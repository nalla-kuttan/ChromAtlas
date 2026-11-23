import Foundation

/// Persists the asset index in SQLite inside the app sandbox (schema per PRD §5).
final class AssetStore: @unchecked Sendable {
    private let db: SQLiteDB

    init(filename: String = "atlas.sqlite") throws {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var url = dir.appendingPathComponent(filename)
        db = try SQLiteDB(path: url.path)
        // Never back up the index to iCloud: it is derived data.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        try migrate()
    }

    /// In-memory store for tests.
    init(inMemory: Bool) throws {
        db = try SQLiteDB(path: ":memory:")
        try migrate()
    }

    private func migrate() throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS asset_index (
                local_identifier TEXT PRIMARY KEY,
                creation_timestamp REAL NOT NULL,
                latitude REAL,
                longitude REAL,
                country_code TEXT,
                city_id INTEGER,
                trip_id INTEGER,
                season_code INTEGER,
                solar_phase INTEGER,
                oklab_l1 REAL, oklab_a1 REAL, oklab_b1 REAL, weight1 REAL,
                oklab_l2 REAL, oklab_a2 REAL, oklab_b2 REAL, weight2 REAL,
                oklab_l3 REAL, oklab_a3 REAL, oklab_b3 REAL, weight3 REAL
            );
            CREATE INDEX IF NOT EXISTS idx_color_l1 ON asset_index(oklab_l1, oklab_a1, oklab_b1);
            CREATE INDEX IF NOT EXISTS idx_trip_time ON asset_index(trip_id, creation_timestamp);
            """)
    }

    func loadAll() throws -> [AssetRecord] {
        var out: [AssetRecord] = []
        let q = try db.prepare("SELECT * FROM asset_index ORDER BY creation_timestamp")
        try q.forEach { r in
            var colors: [ColorCluster] = []
            for k in 0..<3 {
                let base = Int32(9 + k * 4)
                if let L = r.optionalDouble(base), let w = r.optionalDouble(base + 3), w > 0 {
                    colors.append(ColorCluster(lab: OKLab(L: L, a: r.double(base + 1), b: r.double(base + 2)), weight: w))
                }
            }
            let loc: GeoPoint? = {
                guard let lat = r.optionalDouble(2), let lon = r.optionalDouble(3) else { return nil }
                return GeoPoint(lat: lat, lon: lon)
            }()
            out.append(AssetRecord(
                id: r.string(0), timestamp: r.double(1), location: loc,
                countryCode: r.optionalString(4), cityID: r.optionalInt(5), tripID: r.optionalInt(6),
                season: Season(rawValue: r.optionalInt(7) ?? 0) ?? .spring,
                solarPhase: r.optionalInt(8).flatMap(SolarPhase.init(rawValue:)),
                colors: colors))
        }
        return out
    }

    func allIdentifiers() throws -> Set<String> {
        var ids = Set<String>()
        try db.prepare("SELECT local_identifier FROM asset_index").forEach { ids.insert($0.string(0)) }
        return ids
    }

    func upsert(_ records: [AssetRecord]) throws {
        guard !records.isEmpty else { return }
        let stmt = try db.prepare("INSERT OR REPLACE INTO asset_index VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
        try db.transaction {
            for r in records {
                var v: [Any?] = [r.id, r.timestamp, r.location?.lat, r.location?.lon, r.countryCode, r.cityID, r.tripID,
                                 r.season.rawValue, r.solarPhase?.rawValue]
                for k in 0..<3 {
                    if k < r.colors.count {
                        let c = r.colors[k]
                        v += [c.lab.L, c.lab.a, c.lab.b, c.weight]
                    } else {
                        v += [nil, nil, nil, nil]
                    }
                }
                try stmt.bind(v).run()
            }
        }
    }

    func delete(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let stmt = try db.prepare("DELETE FROM asset_index WHERE local_identifier = ?")
        try db.transaction { for id in ids { try stmt.bind([id]).run() } }
    }

    func updateTrips(_ mapping: [String: Int?]) throws {
        let stmt = try db.prepare("UPDATE asset_index SET trip_id = ? WHERE local_identifier = ?")
        try db.transaction {
            for (id, trip) in mapping { try stmt.bind([trip, id]).run() }
        }
    }

    func deleteAll(demoOnly: Bool) throws {
        try db.execute(demoOnly ? "DELETE FROM asset_index WHERE local_identifier LIKE 'demo:%';" : "DELETE FROM asset_index;")
    }
}
