import Foundation

/// Deterministic synthetic camera roll so the atlas can be explored without a real library
/// (e.g. in the Simulator). Every record goes through the same geo/solar/season pipeline as
/// real photos; only the colour centroids are synthesized instead of extracted.
enum DemoLibrary {
    struct RNG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
        mutating func range(_ r: ClosedRange<Double>) -> Double { r.lowerBound + unit() * (r.upperBound - r.lowerBound) }
        mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.count)) }
        mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] }
    }

    /// Lightness, chroma, hue — the look of a place in daylight, plus its after-dark accents.
    struct Mood {
        let day: [(Double, Double, Double)]
        let neon: [Double]
    }

    static let moods: [String: Mood] = [
        "desert":        Mood(day: [(0.78, 0.09, 75), (0.70, 0.11, 60), (0.82, 0.05, 240), (0.55, 0.08, 50)], neon: [60, 330]),
        "skyline":       Mood(day: [(0.80, 0.07, 235), (0.62, 0.03, 250), (0.85, 0.02, 90), (0.72, 0.08, 75)], neon: [200, 320, 60]),
        "sakura":        Mood(day: [(0.86, 0.06, 355), (0.80, 0.09, 350), (0.65, 0.07, 140), (0.82, 0.04, 240)], neon: [340, 300]),
        "neon":          Mood(day: [(0.60, 0.02, 250), (0.72, 0.04, 230), (0.55, 0.03, 60), (0.80, 0.02, 90)], neon: [0, 330, 200, 300]),
        "temple":        Mood(day: [(0.55, 0.17, 30), (0.58, 0.09, 140), (0.78, 0.04, 80), (0.40, 0.05, 50)], neon: [60]),
        "mediterranean": Mood(day: [(0.62, 0.13, 245), (0.88, 0.03, 90), (0.66, 0.11, 225), (0.72, 0.10, 55)], neon: [60, 30]),
        "tuscan":        Mood(day: [(0.66, 0.12, 50), (0.58, 0.10, 135), (0.76, 0.08, 80), (0.80, 0.05, 240)], neon: [60]),
        "parisian":      Mood(day: [(0.76, 0.03, 85), (0.70, 0.05, 240), (0.52, 0.04, 70), (0.64, 0.08, 140)], neon: [60, 20]),
        "canal":         Mood(day: [(0.52, 0.09, 40), (0.68, 0.05, 230), (0.48, 0.06, 150), (0.78, 0.04, 90)], neon: [30, 60]),
        "gaudi":         Mood(day: [(0.70, 0.13, 200), (0.74, 0.12, 80), (0.64, 0.14, 30), (0.82, 0.06, 240)], neon: [330, 60]),
        "oasis":         Mood(day: [(0.74, 0.09, 70), (0.55, 0.12, 145), (0.68, 0.10, 195), (0.82, 0.05, 240)], neon: [60]),
        "glacier":       Mood(day: [(0.80, 0.08, 220), (0.90, 0.02, 230), (0.40, 0.03, 250), (0.62, 0.10, 205)], neon: [150, 160]),
        "fjord":         Mood(day: [(0.52, 0.10, 150), (0.62, 0.07, 230), (0.85, 0.02, 240), (0.45, 0.05, 140)], neon: [150, 290]),
        "jungle":        Mood(day: [(0.55, 0.15, 140), (0.62, 0.13, 125), (0.78, 0.05, 230), (0.50, 0.06, 60)], neon: [60, 30]),
        "lantern":       Mood(day: [(0.70, 0.12, 80), (0.58, 0.14, 40), (0.64, 0.10, 195), (0.45, 0.08, 140)], neon: [60, 40, 0]),
        "bay":           Mood(day: [(0.64, 0.10, 175), (0.55, 0.11, 150), (0.82, 0.04, 230), (0.40, 0.04, 200)], neon: [200]),
        "metropolis":    Mood(day: [(0.58, 0.03, 250), (0.74, 0.04, 70), (0.66, 0.06, 240), (0.40, 0.02, 60)], neon: [60, 0, 200]),
        "fiesta":        Mood(day: [(0.62, 0.17, 345), (0.72, 0.13, 90), (0.60, 0.13, 195), (0.66, 0.15, 40)], neon: [330, 60]),
        "cenote":        Mood(day: [(0.66, 0.12, 190), (0.58, 0.13, 145), (0.88, 0.04, 90), (0.72, 0.08, 230)], neon: [60]),
        "bluecity":      Mood(day: [(0.62, 0.14, 250), (0.72, 0.10, 240), (0.88, 0.03, 90), (0.55, 0.12, 30)], neon: [60, 250]),
        "dunes":         Mood(day: [(0.68, 0.13, 55), (0.62, 0.15, 45), (0.80, 0.06, 240), (0.45, 0.10, 40)], neon: [60]),
        "foliage":       Mood(day: [(0.60, 0.16, 40), (0.70, 0.14, 70), (0.55, 0.15, 25), (0.78, 0.04, 240)], neon: [330, 200]),
        "snow":          Mood(day: [(0.93, 0.01, 240), (0.86, 0.03, 235), (0.45, 0.04, 150), (0.66, 0.08, 240)], neon: [60]),
        "beach":         Mood(day: [(0.70, 0.12, 205), (0.86, 0.05, 85), (0.60, 0.12, 225), (0.55, 0.12, 145)], neon: [330, 60]),
    ]

    struct Stay { let city: String; let days: Int; let mood: String }
    struct DemoTrip { let start: String; let stays: [Stay]; var layover: String? = nil }

    static let trips: [DemoTrip] = [
        DemoTrip(start: "2018-04-02", stays: [Stay(city: "Tokyo", days: 4, mood: "neon"), Stay(city: "Hakone", days: 1, mood: "sakura"),
                                              Stay(city: "Kyoto", days: 3, mood: "temple"), Stay(city: "Osaka", days: 2, mood: "neon")]),
        DemoTrip(start: "2018-11-15", stays: [Stay(city: "Abu Dhabi", days: 2, mood: "skyline")]),
        DemoTrip(start: "2019-06-14", stays: [Stay(city: "Paris", days: 4, mood: "parisian"), Stay(city: "Amsterdam", days: 3, mood: "canal"),
                                              Stay(city: "Florence", days: 3, mood: "tuscan"), Stay(city: "Rome", days: 3, mood: "tuscan"),
                                              Stay(city: "Barcelona", days: 3, mood: "gaudi")], layover: "Istanbul"),
        DemoTrip(start: "2020-12-18", stays: [Stay(city: "Muscat", days: 2, mood: "mediterranean"), Stay(city: "Nizwa", days: 2, mood: "oasis")]),
        DemoTrip(start: "2021-02-11", stays: [Stay(city: "Doha", days: 3, mood: "skyline")]),
        DemoTrip(start: "2021-11-05", stays: [Stay(city: "Riyadh", days: 2, mood: "desert"), Stay(city: "AlUla", days: 3, mood: "dunes")]),
        DemoTrip(start: "2022-01-20", stays: [Stay(city: "Manama", days: 2, mood: "skyline")]),
        DemoTrip(start: "2022-09-02", stays: [Stay(city: "Reykjavik", days: 2, mood: "glacier"), Stay(city: "Vik", days: 2, mood: "fjord"),
                                              Stay(city: "Jokulsarlon", days: 1, mood: "glacier"), Stay(city: "Oslo", days: 2, mood: "fjord"),
                                              Stay(city: "Bergen", days: 3, mood: "fjord")]),
        DemoTrip(start: "2023-03-10", stays: [Stay(city: "Bangkok", days: 3, mood: "lantern"), Stay(city: "Chiang Mai", days: 3, mood: "jungle"),
                                              Stay(city: "Hanoi", days: 2, mood: "lantern"), Stay(city: "Ha Long", days: 2, mood: "bay"),
                                              Stay(city: "Hoi An", days: 3, mood: "lantern")]),
        DemoTrip(start: "2024-07-01", stays: [Stay(city: "New York", days: 4, mood: "metropolis"), Stay(city: "Mexico City", days: 3, mood: "fiesta"),
                                              Stay(city: "Oaxaca", days: 3, mood: "fiesta"), Stay(city: "Tulum", days: 4, mood: "cenote")]),
        DemoTrip(start: "2025-04-10", stays: [Stay(city: "Marrakesh", days: 3, mood: "desert"), Stay(city: "Merzouga", days: 2, mood: "dunes"),
                                              Stay(city: "Fes", days: 1, mood: "oasis"), Stay(city: "Chefchaouen", days: 2, mood: "bluecity")]),
        DemoTrip(start: "2025-10-24", stays: [Stay(city: "Seoul", days: 4, mood: "foliage"), Stay(city: "Busan", days: 2, mood: "beach"),
                                              Stay(city: "Taipei", days: 3, mood: "neon")]),
        DemoTrip(start: "2026-02-06", stays: [Stay(city: "Zurich", days: 2, mood: "snow"), Stay(city: "Zermatt", days: 3, mood: "snow"),
                                              Stay(city: "Innsbruck", days: 2, mood: "snow"), Stay(city: "Vienna", days: 2, mood: "parisian")]),
        DemoTrip(start: "2026-08-08", stays: [Stay(city: "Sydney", days: 4, mood: "beach"), Stay(city: "Queenstown", days: 3, mood: "fjord")]),
    ]

    static let homeCity = "Dubai"

    static func generate() -> [AssetRecord] {
        var rng = RNG(state: 0xC0FFEE)
        let geo = GeoDatabase.shared
        let byName = Dictionary(geo.allCities.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        guard let home = byName[homeCity] else { return [] }
        var out: [AssetRecord] = []
        var n = 0

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")

        func shoot(_ city: City, mood moodName: String, dayStart: Date, hour: Double, spreadKm: Double) {
            let lonShift = city.location.lon / 15
            let utc = dayStart.addingTimeInterval((hour - lonShift) * 3600)
            let dLat = rng.range(-1...1) * spreadKm / 111
            let dLon = rng.range(-1...1) * spreadKm / (111 * max(0.2, cos(city.location.lat * .pi / 180)))
            let loc = GeoPoint(lat: city.location.lat + dLat, lon: city.location.lon + dLon)
            let colors = synthesizeColors(mood: moods[moodName]!, date: utc, location: loc, rng: &rng)
            n += 1
            out.append(AssetRecord.make(id: "demo:\(n)", date: utc, location: loc, colors: colors))
        }

        func randomHour() -> Double {
            // Skewed toward late afternoon and evening, where the light gets interesting.
            let r = rng.unit()
            if r < 0.45 { return rng.range(8...16.5) }
            if r < 0.80 { return rng.range(16.5...20.5) }
            if r < 0.93 { return rng.range(20.5...23.6) }
            return rng.range(5.3...8)
        }

        // Trips.
        var tripDays = Set<String>()
        for trip in trips {
            guard var day = fmt.date(from: trip.start) else { continue }
            if let lay = trip.layover, let c = byName[lay] {
                shoot(c, mood: "metropolis", dayStart: day, hour: 6.2, spreadKm: 0.3)
            }
            for stay in trip.stays {
                guard let c = byName[stay.city] else { continue }
                for _ in 0..<stay.days {
                    tripDays.insert(fmt.string(from: day))
                    let shots = rng.int(14...34)
                    for _ in 0..<shots { shoot(c, mood: stay.mood, dayStart: day, hour: randomHour(), spreadKm: 6) }
                    day = day.addingTimeInterval(86400)
                }
            }
        }

        // Everyday life at home, 2018 → Oct 2026.
        var day = fmt.date(from: "2018-01-03")!
        let endHome = fmt.date(from: "2026-10-30")!
        while day < endHome {
            if !tripDays.contains(fmt.string(from: day)) {
                let shots = rng.unit() < 0.55 ? rng.int(1...4) : 0
                for _ in 0..<shots {
                    let moodName = rng.unit() < 0.5 ? "skyline" : "desert"
                    if rng.unit() < 0.04 {
                        // A few edited/imported images without GPS.
                        n += 1
                        let colors = synthesizeColors(mood: moods[moodName]!, date: day, location: nil, rng: &rng)
                        out.append(AssetRecord.make(id: "demo:\(n)", date: day.addingTimeInterval(12 * 3600), location: nil, colors: colors))
                    } else {
                        shoot(home, mood: moodName, dayStart: day, hour: randomHour(), spreadKm: 14)
                    }
                }
            }
            day = day.addingTimeInterval(86400)
        }
        return out.sorted { $0.timestamp < $1.timestamp }
    }

    /// Picks three palette colours and shifts them by the real solar phase at that moment.
    static func synthesizeColors(mood: Mood, date: Date, location: GeoPoint?, rng: inout RNG) -> [ColorCluster] {
        let phase = location.map { SolarCalculator.phase(date: date, location: $0) } ?? .daylight
        var picks = mood.day.shuffledDeterministic(&rng).prefix(3).map { $0 }
        func jitter(_ c: (Double, Double, Double)) -> OKLab {
            OKLab(L: min(0.97, max(0.04, c.0 + rng.range(-0.06...0.06))),
                  chroma: max(0, c.1 + rng.range(-0.025...0.025)),
                  hueDegrees: c.2 + rng.range(-9...9))
        }
        let w1 = rng.range(0.45...0.68)
        let w2 = (1 - w1) * rng.range(0.55...0.78)
        var weights = [w1, w2, 1 - w1 - w2]

        switch phase {
        case .daylight:
            break
        case .goldenHour:
            picks[0] = (rng.range(0.58...0.70), rng.range(0.11...0.16), rng.range(50...72))
            picks[1] = (picks[1].0 * 0.82, picks[1].1, picks[1].2 * 0.7 + 60 * 0.3)
            if rng.unit() < 0.5 { picks[2] = (0.45, 0.10, 35) }
        case .blueHour:
            picks[0] = (rng.range(0.28...0.38), rng.range(0.07...0.11), rng.range(252...272))
            picks[1] = (picks[1].0 * 0.5, picks[1].1 * 0.6, picks[1].2)
            picks[2] = (0.62, 0.12, rng.pick([60.0, 70.0] + mood.neon))
            weights = [0.6, 0.3, 0.1]
        case .night:
            picks[0] = (rng.range(0.10...0.18), 0.02, 260)
            picks[1] = (rng.range(0.22...0.30), 0.04, rng.pick([250.0, 60.0]))
            picks[2] = (rng.range(0.60...0.70), rng.range(0.18...0.24), rng.pick(mood.neon))
            let accent = rng.range(0.07...0.14)
            weights = [0.72 - accent / 2, 0.28 - accent / 2, accent]
        }
        return zip(picks, weights)
            .map { ColorCluster(lab: jitter($0.0), weight: $0.1) }
            .sorted { $0.weight > $1.weight }
    }
}

private extension Array {
    func shuffledDeterministic(_ rng: inout DemoLibrary.RNG) -> [Element] {
        var a = self
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            a.swapAt(i, j)
        }
        return a
    }
}
