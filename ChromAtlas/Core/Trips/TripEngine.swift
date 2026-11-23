import Foundation

/// Reconstructs home base, trips, stops, legs, counters and badges from geotagged assets.
enum TripEngine {
    struct Config {
        var awayRadiusKm = 50.0          // PRD: > 50 km from home base counts as away
        var tripBreakHours = 72.0        // gap between away photos that ends a trip
        var homeReturnHours = 18.0       // time spent back home that ends a trip
        var dbscanEpsKm = 30.0
        var dbscanEpsHours = 36.0
        var dbscanMinPts = 2
        var layoverHours = 3.0           // PRD: < 3 h single-point stops are layovers
        var layoverDistinctKm = 2.0
        var flightMinKm = 100.0          // PRD: > 100 km within 12 h → flight
        var flightMaxHours = 12.0
        var flightAlwaysKm = 700.0       // long hops are flights even with a photo gap
    }

    static func analyze(_ assets: [AssetRecord], config: Config = Config()) -> TripAnalysis {
        let geo = assets.filter { $0.location != nil }.sorted { $0.timestamp < $1.timestamp }
        guard !geo.isEmpty else { return .empty }

        var result = TripAnalysis()
        let home = detectHome(geo)
        result.home = home

        // 1. Split into trips: runs of "away" photos.
        let away: [Bool] = geo.map { GeoMath.distanceKm($0.location!, home.location) > config.awayRadiusKm }
        var tripRuns: [[AssetRecord]] = []
        var current: [AssetRecord] = []
        var homeSince: TimeInterval?
        for (i, a) in geo.enumerated() {
            if away[i] {
                if let last = current.last {
                    let gap = (a.timestamp - last.timestamp) / 3600
                    let homeSpan = homeSince.map { (a.timestamp - $0) / 3600 } ?? 0
                    if gap > config.tripBreakHours || homeSpan > config.homeReturnHours {
                        tripRuns.append(current); current = []
                    }
                }
                current.append(a)
                homeSince = nil
            } else if !current.isEmpty, homeSince == nil {
                homeSince = a.timestamp
            }
        }
        if !current.isEmpty { tripRuns.append(current) }

        // 2. Each trip → stops (DBSCAN) → legs.
        var stopID = 0, legID = 0
        for (tIdx, run) in tripRuns.enumerated() {
            let tripID = tIdx + 1
            var stops: [Stop] = []
            for cluster in spatioTemporalDBSCAN(run, config: config) {
                let pts = cluster.map { $0.location! }
                let loc = GeoMath.centroid(pts)
                let start = cluster.first!.date, end = cluster.last!.date
                let spanH = end.timeIntervalSince(start) / 3600
                let distinct = distinctLocationCount(pts, thresholdKm: config.layoverDistinctKm)
                stopID += 1
                stops.append(Stop(
                    id: stopID, tripID: tripID, location: loc,
                    city: GeoDatabase.shared.nearestCity(to: loc),
                    start: start, end: end, assetIDs: cluster.map(\.id),
                    isLayover: spanH < config.layoverHours && distinct < 2 && cluster.count < 12))
            }
            stops.sort { $0.start < $1.start }
            // A trip made only of layovers (e.g. a single airport photo) is noise.
            if stops.allSatisfy(\.isLayover) && stops.count < 2 { continue }

            var legs: [Leg] = []
            let homeLabel = home.city?.name ?? "Home"
            func addLeg(_ a: GeoPoint, _ aLabel: String, _ dep: Date, _ b: GeoPoint, _ bLabel: String, _ arr: Date, homeLeg: Bool) {
                let d = GeoMath.distanceKm(a, b)
                guard d > 5 else { return }
                let hours = arr.timeIntervalSince(dep) / 3600
                let isFlight: Bool
                if homeLeg { isFlight = d > 300 }
                else { isFlight = d > config.flightAlwaysKm || (d > config.flightMinKm && hours <= config.flightMaxHours) }
                legID += 1
                legs.append(Leg(id: legID, tripID: tripID, from: a, to: b, fromLabel: aLabel, toLabel: bLabel,
                                departure: dep, arrival: arr, kind: isFlight ? .flight : .ground, distanceKm: d))
            }
            if let first = stops.first {
                addLeg(home.location, homeLabel, first.start, first.location, first.city?.name ?? "—", first.start, homeLeg: true)
            }
            for (a, b) in zip(stops, stops.dropFirst()) {
                addLeg(a.location, a.city?.name ?? "—", a.end, b.location, b.city?.name ?? "—", b.start, homeLeg: false)
            }
            if let last = stops.last {
                addLeg(last.location, last.city?.name ?? "—", last.end, home.location, homeLabel, last.end, homeLeg: true)
            }

            let ids = run.map(\.id)
            let (hue, chroma) = dominantHue(run)
            let trip = Trip(id: tripID, start: run.first!.date, end: run.last!.date, stops: stops, legs: legs,
                            title: title(for: stops, homeCountry: home.countryCode, start: run.first!.date),
                            assetIDs: ids, dominantHue: hue, dominantChroma: chroma)
            result.trips.append(trip)
            for id in ids { result.assetTrip[id] = tripID }
        }

        // 3. Counters.
        var countries: [String] = []
        var cities: [Int] = []
        if let hc = home.countryCode { countries.append(hc) }
        if let hcity = home.city?.id { cities.append(hcity) }
        for s in result.allStops where !s.isLayover {
            if let c = s.countryCode, !countries.contains(c) { countries.append(c) }
            if let ci = s.city?.id, !cities.contains(ci) { cities.append(ci) }
        }
        // Count every distinct non-layover city photographed (not just stop centroids).
        let layoverIDs = Set(result.allStops.filter(\.isLayover).flatMap(\.assetIDs))
        for a in geo where !layoverIDs.contains(a.id) {
            if let ci = a.cityID, !cities.contains(ci) { cities.append(ci) }
            if let cc = a.countryCode, !countries.contains(cc) { countries.append(cc) }
        }
        result.countriesVisited = countries
        result.citiesVisited = cities
        result.kilometersTraveled = result.allLegs.reduce(0) { $0 + $1.distanceKm }
        result.passportsStamped = countries.filter { $0 != home.countryCode }.count
        result.badges = badges(countries: Set(countries), km: result.kilometersTraveled, stops: result.allStops)
        return result
    }

    // MARK: - Home base

    /// The ~50 km grid cell photographed in the most distinct months (ties → most photos).
    static func detectHome(_ geo: [AssetRecord]) -> HomeBase {
        struct Cell { var months = Set<Int>(); var count = 0; var pts: [GeoPoint] = [] }
        var cells: [Int: Cell] = [:]
        let cal = Calendar(identifier: .gregorian)
        for a in geo {
            let p = a.location!
            let key = Int((p.lat / 0.45).rounded(.down)) * 10_000 + Int((p.lon / 0.45).rounded(.down))
            let d = cal.dateComponents([.year, .month], from: a.date)
            cells[key, default: Cell()].months.insert(d.year! * 12 + d.month!)
            cells[key]!.count += 1
            if cells[key]!.pts.count < 2000 { cells[key]!.pts.append(p) }
        }
        let best = cells.values.max { a, b in
            a.months.count != b.months.count ? a.months.count < b.months.count : a.count < b.count
        }!
        let loc = GeoMath.centroid(best.pts)
        return HomeBase(location: loc, city: GeoDatabase.shared.nearestCity(to: loc))
    }

    // MARK: - Spatio-temporal DBSCAN

    /// Points are neighbours when within `epsKm` AND `epsHours`. Assets are time-sorted, so
    /// neighbour search only scans a sliding time window (O(n·w)). Noise points become their
    /// own single-asset clusters so they can still be classified as layovers.
    static func spatioTemporalDBSCAN(_ pts: [AssetRecord], config: Config) -> [[AssetRecord]] {
        let n = pts.count
        let epsT = config.dbscanEpsHours * 3600
        func neighbours(_ i: Int) -> [Int] {
            var out: [Int] = []
            var j = i
            while j >= 0, pts[i].timestamp - pts[j].timestamp <= epsT {
                if GeoMath.distanceKm(pts[i].location!, pts[j].location!) <= config.dbscanEpsKm { out.append(j) }
                j -= 1
            }
            j = i + 1
            while j < n, pts[j].timestamp - pts[i].timestamp <= epsT {
                if GeoMath.distanceKm(pts[i].location!, pts[j].location!) <= config.dbscanEpsKm { out.append(j) }
                j += 1
            }
            return out
        }

        var label = [Int](repeating: -2, count: n)   // -2 unvisited, -1 noise
        var clusterCount = 0
        for i in 0..<n where label[i] == -2 {
            let nb = neighbours(i)
            if nb.count < config.dbscanMinPts { label[i] = -1; continue }
            let c = clusterCount; clusterCount += 1
            label[i] = c
            var queue = nb
            var qi = 0
            while qi < queue.count {
                let j = queue[qi]; qi += 1
                if label[j] == -1 { label[j] = c }
                guard label[j] == -2 else { continue }
                label[j] = c
                let nb2 = neighbours(j)
                if nb2.count >= config.dbscanMinPts { queue.append(contentsOf: nb2) }
            }
        }
        var clusters = [[AssetRecord]](repeating: [], count: clusterCount)
        var noise: [[AssetRecord]] = []
        for i in 0..<n {
            if label[i] >= 0 { clusters[label[i]].append(pts[i]) } else { noise.append([pts[i]]) }
        }
        return (clusters + noise).map { $0.sorted { $0.timestamp < $1.timestamp } }
    }

    static func distinctLocationCount(_ pts: [GeoPoint], thresholdKm: Double) -> Int {
        var reps: [GeoPoint] = []
        for p in pts where !reps.contains(where: { GeoMath.distanceKm($0, p) < thresholdKm }) {
            reps.append(p)
            if reps.count >= 3 { break }
        }
        return reps.count
    }

    // MARK: - Naming

    static func title(for stops: [Stop], homeCountry: String?, start: Date) -> String {
        let year = Calendar.current.component(.year, from: start)
        let real = stops.filter { !$0.isLayover }
        let countries = Array(NSOrderedSet(array: real.compactMap(\.countryCode))) as! [String]
        let cityNames = Array(NSOrderedSet(array: real.compactMap { $0.city?.name })) as! [String]
        let regions = Array(NSOrderedSet(array: countries.map { Countries.info($0).region.rawValue })) as! [String]
        let name: String
        if cityNames.count <= 1 {
            name = "\(cityNames.first ?? "Weekend") Getaway"
        } else if countries.count == 1 {
            name = "\(Countries.info(countries[0]).name) Circuit"
        } else if regions.count == 1 {
            name = "\(regions[0]) Circuit"
        } else {
            name = regions.prefix(2).joined(separator: " & ")
        }
        return "\(year) – \(name)"
    }

    static func dominantHue(_ assets: [AssetRecord]) -> (Double?, Double) {
        var bins = [Double](repeating: 0, count: 36)
        var chromaSum = 0.0, wSum = 0.0
        for a in assets {
            for c in a.colors where c.lab.chroma > 0.04 {
                bins[Int(c.lab.hueDegrees / 10) % 36] += c.weight * c.lab.chroma
                chromaSum += c.lab.chroma * c.weight; wSum += c.weight
            }
        }
        guard let maxIdx = bins.indices.max(by: { bins[$0] < bins[$1] }), bins[maxIdx] > 0 else { return (nil, 0) }
        return (Double(maxIdx) * 10 + 5, wSum > 0 ? chromaSum / wSum : 0)
    }

    // MARK: - Badges

    static func badges(countries: Set<String>, km: Double, stops: [Stop]) -> [Badge] {
        func count(_ set: Set<String>) -> Int { countries.intersection(set).count }
        let regions = Set(countries.map { Countries.info($0).region })
        let southern = stops.contains { !$0.isLayover && $0.location.lat < 0 }
        return [
            Badge(id: "gcc", title: "GCC Explorer", symbol: "sun.dust.fill", progress: count(Countries.gcc), goal: 3),
            Badge(id: "schengen", title: "Schengen Hopper", symbol: "train.side.front.car", progress: count(Countries.schengen), goal: 4),
            Badge(id: "eastasia", title: "East Asia Circuit", symbol: "building.2.fill", progress: count(Countries.eastAsia), goal: 3),
            Badge(id: "asean", title: "ASEAN Wanderer", symbol: "leaf.fill", progress: count(Countries.asean), goal: 3),
            Badge(id: "nordic", title: "Nordic Lights", symbol: "sparkles", progress: count(Countries.nordic), goal: 2),
            Badge(id: "balkans", title: "Balkan Trail", symbol: "mountain.2.fill", progress: count(Countries.balkans), goal: 3),
            Badge(id: "silk", title: "Silk Road Voyager", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", progress: count(Countries.silkRoad), goal: 3),
            Badge(id: "latam", title: "Latin Loop", symbol: "sun.horizon.fill", progress: count(Countries.latinAmerica), goal: 3),
            Badge(id: "continents", title: "Continental Collector", symbol: "globe.europe.africa.fill", progress: regions.count, goal: 5),
            Badge(id: "globetrotter", title: "Globetrotter", symbol: "airplane", progress: countries.count, goal: 20),
            Badge(id: "equator", title: "Around the World", symbol: "globe", progress: Int(km), goal: 40_075),
            Badge(id: "southern", title: "Southern Cross", symbol: "star.fill", progress: southern ? 1 : 0, goal: 1),
        ]
        .sorted { ($0.unlocked ? 0 : 1, -Double($0.progress) / Double($0.goal)) < ($1.unlocked ? 0 : 1, -Double($1.progress) / Double($1.goal)) }
    }
}
