import Foundation

struct City: Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let countryCode: String
    let admin1: String
    let location: GeoPoint
    let population: Int

    var country: CountryInfo { Countries.info(countryCode) }
    var label: String { "\(name), \(country.name)" }
}

/// Offline reverse geocoder backed by an SQLite R*Tree.
///
/// If the app bundle contains `geo.sqlite` (built by `Scripts/build_geodb.py` from GeoNames
/// `cities15000`), it is used directly. Otherwise a database is built on first launch
/// from the bundled `cities_seed.csv`.
final class GeoDatabase: @unchecked Sendable {
    static let shared = GeoDatabase()

    private var db: SQLiteDB?
    private var cities: [Int: City] = [:]
    private var cache: [Int64: Int] = [:]   // quantized coordinate → city id (or -1)
    private let lock = NSLock()

    /// Beyond this distance a coordinate is considered "unresolved" (e.g. open ocean).
    static let maxResolveKm = 350.0

    private init() {
        do { try open() } catch { print("GeoDatabase failed: \(error)") }
    }

    var cityCount: Int { cities.count }

    private func open() throws {
        let fm = FileManager.default
        if let bundled = Bundle.main.path(forResource: "geo", ofType: "sqlite") {
            db = try SQLiteDB(path: bundled, readOnly: true)
        } else {
            let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let path = dir.appendingPathComponent("geo_seed_v1.sqlite").path
            let exists = fm.fileExists(atPath: path)
            db = try SQLiteDB(path: path)
            if !exists { try buildFromSeed() }
        }
        try loadCities()
    }

    private func buildFromSeed() throws {
        guard let db, let url = Bundle.main.url(forResource: "cities_seed", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        try db.execute("""
            CREATE TABLE IF NOT EXISTS cities (
                id INTEGER PRIMARY KEY, name TEXT NOT NULL, country_code TEXT NOT NULL,
                admin1 TEXT, latitude REAL NOT NULL, longitude REAL NOT NULL, population INTEGER);
            CREATE VIRTUAL TABLE IF NOT EXISTS city_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);
            """)
        let insCity = try db.prepare("INSERT INTO cities VALUES (?,?,?,?,?,?,?)")
        let insTree = try db.prepare("INSERT INTO city_rtree VALUES (?,?,?,?,?)")
        try db.transaction {
            for (i, line) in text.split(separator: "\n").enumerated() where i > 0 {
                let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                guard f.count >= 6, let lat = Double(f[3]), let lon = Double(f[4]) else { continue }
                try insCity.bind([i, f[0], f[1], f[2], lat, lon, Int(f[5]) ?? 0]).run()
                try insTree.bind([i, lat, lat, lon, lon]).run()
            }
        }
    }

    private func loadCities() throws {
        guard let db else { return }
        let q = try db.prepare("SELECT id, name, country_code, admin1, latitude, longitude, population FROM cities")
        try q.forEach { r in
            let c = City(id: r.int(0), name: r.string(1), countryCode: r.string(2), admin1: r.string(3),
                         location: GeoPoint(lat: r.double(4), lon: r.double(5)), population: r.int(6))
            cities[c.id] = c
        }
    }

    func city(id: Int) -> City? { cities[id] }

    /// Nearest city to a coordinate, searching the R*Tree with expanding bounding boxes.
    func nearestCity(to p: GeoPoint) -> City? {
        let key = Int64((p.lat * 50).rounded()) &* 100_000 &+ Int64((p.lon * 50).rounded())
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit >= 0 ? cities[hit] : nil }
        lock.unlock()

        var result: City?
        for radius in [40.0, 120.0, GeoDatabase.maxResolveKm] {
            if let c = query(p, radiusKm: radius) { result = c; break }
        }
        lock.lock(); cache[key] = result?.id ?? -1; lock.unlock()
        return result
    }

    private func query(_ p: GeoPoint, radiusKm: Double) -> City? {
        guard let db else { return nil }
        let span = GeoMath.degreeSpan(km: radiusKm, atLat: p.lat)
        var best: City?
        var bestScore = Double.greatestFiniteMagnitude
        do {
            let q = try db.prepare("SELECT id FROM city_rtree WHERE min_lat >= ? AND max_lat <= ? AND min_lon >= ? AND max_lon <= ?")
            q.bind([p.lat - span.dLat, p.lat + span.dLat, p.lon - span.dLon, p.lon + span.dLon])
            try q.forEach { r in
                guard let c = cities[r.int(0)] else { return }
                let d = GeoMath.distanceKm(p, c.location)
                guard d <= radiusKm else { return }
                // Slight bias toward larger cities so suburbs resolve to the metro they belong to.
                let score = d / (1 + 0.08 * log10(Double(max(c.population, 1000)) / 1000))
                if score < bestScore { bestScore = score; best = c }
            }
        } catch {
            return nil
        }
        return best
    }

    /// Cities for drawing faint reference lights on the globe.
    var allCities: [City] { Array(cities.values) }
}
