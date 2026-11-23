import XCTest
@testable import ChromAtlas

final class ColorTests: XCTestCase {
    func testOKLabRoundTrip() {
        for (r, g, b) in [(1.0, 0.0, 0.0), (0.2, 0.6, 0.9), (0.95, 0.75, 0.3), (0.5, 0.5, 0.5)] {
            let lab = OKLab(r: r, g: g, b: b)
            let back = lab.rgb
            XCTAssertEqual(back.r, r, accuracy: 0.002)
            XCTAssertEqual(back.g, g, accuracy: 0.002)
            XCTAssertEqual(back.b, b, accuracy: 0.002)
        }
        XCTAssertEqual(OKLab(r: 1, g: 1, b: 1).L, 1, accuracy: 0.001)
        XCTAssertLessThan(OKLab(r: 0.5, g: 0.5, b: 0.5).chroma, 0.001)
    }

    func testKMeansFindsSmallAccent() {
        // 88% dark navy, 12% neon red: the accent must survive as its own centroid.
        let navy = ColorExtractor.labFloat(r: Float(OKLab.linearize(0.05)), g: Float(OKLab.linearize(0.07)), b: Float(OKLab.linearize(0.15)))
        let red = ColorExtractor.labFloat(r: 1, g: Float(OKLab.linearize(0.1)), b: Float(OKLab.linearize(0.2)))
        let grey = ColorExtractor.labFloat(r: 0.2, g: 0.2, b: 0.2)
        let pts = Array(repeating: navy, count: 700) + Array(repeating: red, count: 120) + Array(repeating: grey, count: 180)
        let clusters = ColorExtractor.kMeans(pts, k: 3)
        XCTAssertEqual(clusters.count, 3)
        XCTAssertEqual(clusters.map(\.weight).reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertTrue(clusters.contains { $0.lab.chroma > 0.15 && abs($0.weight - 0.12) < 0.01 })
    }

    func testZoneNames() {
        XCTAssertEqual(ChromaticZone.name(hue: 62, chroma: 0.14), "Golden Hour / Warm Amber")
        XCTAssertTrue(ChromaticZone.name(hue: 62, chroma: 0.01).hasPrefix("Monochrome"))
    }
}

final class GeoTests: XCTestCase {
    func testHaversine() {
        let dubai = GeoPoint(lat: 25.2048, lon: 55.2708), london = GeoPoint(lat: 51.5074, lon: -0.1278)
        XCTAssertEqual(GeoMath.distanceKm(dubai, london), 5_470, accuracy: 30)
    }

    func testReverseGeocodeOffline() {
        let c = GeoDatabase.shared.nearestCity(to: GeoPoint(lat: 41.89, lon: 12.49))
        XCTAssertEqual(c?.name, "Rome")
        XCTAssertEqual(c?.countryCode, "IT")
        XCTAssertNil(GeoDatabase.shared.nearestCity(to: GeoPoint(lat: -40, lon: -120)), "mid-Pacific should not resolve")
    }

    func testGreatCircleEndpoints() {
        let a = GeoPoint(lat: 25, lon: 55), b = GeoPoint(lat: 35.7, lon: 139.7)
        let pts = GeoMath.greatCircle(a, b, segments: 20)
        XCTAssertEqual(GeoMath.point(from: pts.first!).lat, a.lat, accuracy: 1e-6)
        XCTAssertEqual(GeoMath.point(from: pts.last!).lon, b.lon, accuracy: 1e-6)
    }
}

final class SolarTests: XCTestCase {
    func testElevationAndPhases() {
        let iso = ISO8601DateFormatter()
        let dubai = GeoPoint(lat: 25.2, lon: 55.27)
        // Dubai solar noon on the June solstice ≈ 08:20 UTC, sun nearly overhead.
        XCTAssertGreaterThan(SolarCalculator.elevationDegrees(date: iso.date(from: "2024-06-21T08:20:00Z")!, location: dubai), 85)
        XCTAssertEqual(SolarCalculator.phase(date: iso.date(from: "2024-06-21T20:00:00Z")!, location: dubai), .night)
        // ~10 minutes after sunset (≈ 15:12 UTC) → golden/blue boundary region.
        let e = SolarCalculator.elevationDegrees(date: iso.date(from: "2024-06-21T15:05:00Z")!, location: dubai)
        XCTAssertEqual(SolarCalculator.phase(forElevation: e), .goldenHour)
    }

    func testSeasonsFlipSouth() {
        let july = ISO8601DateFormatter().date(from: "2024-07-15T12:00:00Z")!
        XCTAssertEqual(Season.of(date: july, latitude: 48), .summer)
        XCTAssertEqual(Season.of(date: july, latitude: -33), .winter)
    }
}

final class TripEngineTests: XCTestCase {
    private func rec(_ id: String, _ t: TimeInterval, _ lat: Double, _ lon: Double) -> AssetRecord {
        AssetRecord.make(id: id, date: Date(timeIntervalSince1970: t), location: GeoPoint(lat: lat, lon: lon), colors: [])
    }

    func testHomeTripAndLayover() {
        var assets: [AssetRecord] = []
        let day = 86400.0
        let t0 = 1_600_000_000.0
        // Home (Dubai) across 14 months.
        for m in 0..<14 { for k in 0..<5 { assets.append(rec("h\(m)-\(k)", t0 + Double(m) * 30 * day + Double(k) * 3600, 25.2, 55.27)) } }
        // Trip: 1-photo Istanbul layover, then Paris (2 days), then Rome (2 days).
        let trip = t0 + 200 * day
        assets.append(rec("ist", trip, 41.26, 28.74))
        for k in 0..<10 { assets.append(rec("par\(k)", trip + 8 * 3600 + Double(k) * 4 * 3600, 48.86, 2.35)) }
        for k in 0..<10 { assets.append(rec("rom\(k)", trip + 3 * day + Double(k) * 4 * 3600, 41.90, 12.50)) }

        let a = TripEngine.analyze(assets)
        XCTAssertEqual(a.home?.city?.name, "Dubai")
        XCTAssertEqual(a.trips.count, 1)
        let t = a.trips[0]
        XCTAssertEqual(t.stops.filter(\.isLayover).count, 1)
        XCTAssertEqual(Set(t.countries), ["FR", "IT"])
        XCTAssertFalse(a.countriesVisited.contains("TR"), "layover must not unlock a country")
        XCTAssertTrue(t.legs.contains { $0.kind == .flight })
        XCTAssertEqual(t.title, "2021 – Europe Circuit")
        XCTAssertEqual(a.passportsStamped, 2)
    }
}

final class QueryEngineTests: XCTestCase {
    func testColorAndHarmonyMatching() {
        let amber = ColorCluster(lab: OKLab(L: 0.65, chroma: 0.14, hueDegrees: 62), weight: 0.6)
        let teal = ColorCluster(lab: OKLab(L: 0.6, chroma: 0.12, hueDegrees: 200), weight: 0.6)
        let neon = ColorCluster(lab: OKLab(L: 0.65, chroma: 0.22, hueDegrees: 20), weight: 0.08)
        let dark = ColorCluster(lab: OKLab(L: 0.12, chroma: 0.02, hueDegrees: 260), weight: 0.92)
        let now = Date()
        let assets = [
            AssetRecord.make(id: "a", date: now, location: nil, colors: [amber]),
            AssetRecord.make(id: "t", date: now, location: nil, colors: [teal]),
            AssetRecord.make(id: "n", date: now, location: nil, colors: [dark, neon]),
        ]
        let q = QueryEngine(assets)
        var f = FilterState()
        f.color = ColorSelection(hue: 62, saturation: 0.47)
        XCTAssertEqual(q.run(f).matches, [0])

        f.harmony = .complementary
        f.color = ColorSelection(hue: 20, saturation: 0.45)
        XCTAssertTrue(q.run(f).matches.contains(1), "teal is complementary to the orange-red pick")

        f.harmony = .single
        f.color = ColorSelection(hue: 20, saturation: 0.73)
        XCTAssertEqual(q.run(f).matches, [2], "8% neon accent in a dark frame stays discoverable")

        f.color = nil
        f.luminance = 0...0.3
        XCTAssertEqual(q.run(f).matches, [2])
    }

    func testLatencyBudget() {
        var rng = DemoLibrary.RNG(state: 1)
        let assets: [AssetRecord] = (0..<100_000).map { i in
            let c = (0..<3).map { _ in ColorCluster(lab: OKLab(L: rng.unit(), chroma: rng.range(0...0.3), hueDegrees: rng.range(0...360)), weight: 0.33) }
            return AssetRecord(id: "\(i)", timestamp: Double(i) * 1000, location: nil, countryCode: nil, cityID: nil, tripID: nil,
                               season: .summer, solarPhase: .daylight, colors: c)
        }
        let q = QueryEngine(assets)
        var f = FilterState()
        f.color = ColorSelection(hue: 120, saturation: 0.5)
        _ = q.run(f)
        let r = q.run(f)
        print("100k query: \(r.elapsedMs) ms, \(r.matches.count) matches")
        #if DEBUG
        XCTAssertLessThan(r.elapsedMs, 120, "unoptimized build; the < 16 ms budget is checked in Release")
        #else
        XCTAssertLessThan(r.elapsedMs, 16, "PRD: < 16 ms for 100k assets")
        #endif
    }
}
