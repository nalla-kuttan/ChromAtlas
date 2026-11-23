import Foundation
import simd

struct GeoPoint: Hashable, Codable, Sendable {
    var lat: Double
    var lon: Double
}

enum GeoMath {
    static let earthRadiusKm = 6371.0088

    /// Great-circle distance in kilometers (haversine).
    static func distanceKm(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let φ1 = a.lat * .pi / 180, φ2 = b.lat * .pi / 180
        let dφ = φ2 - φ1
        let dλ = (b.lon - a.lon) * .pi / 180
        let h = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * earthRadiusKm * asin(min(1, h.squareRoot()))
    }

    /// Unit vector on the sphere. Convention: +Y = north pole, lon 0 faces +Z.
    static func unitVector(_ p: GeoPoint) -> SIMD3<Double> {
        let φ = p.lat * .pi / 180, λ = p.lon * .pi / 180
        return SIMD3(cos(φ) * sin(λ), sin(φ), cos(φ) * cos(λ))
    }

    static func point(from v: SIMD3<Double>) -> GeoPoint {
        let n = simd_normalize(v)
        return GeoPoint(lat: asin(n.y) * 180 / .pi, lon: atan2(n.x, n.z) * 180 / .pi)
    }

    /// Points along the great circle from a to b (slerp), inclusive of both ends.
    static func greatCircle(_ a: GeoPoint, _ b: GeoPoint, segments: Int) -> [SIMD3<Double>] {
        let va = unitVector(a), vb = unitVector(b)
        let ω = acos(min(1, max(-1, simd_dot(va, vb))))
        guard ω > 1e-6 else { return [va, vb] }
        let sinω = sin(ω)
        return (0...segments).map { i in
            let t = Double(i) / Double(segments)
            return (sin((1 - t) * ω) / sinω) * va + (sin(t * ω) / sinω) * vb
        }
    }

    /// Mean of points on the sphere.
    static func centroid(_ pts: [GeoPoint]) -> GeoPoint {
        guard !pts.isEmpty else { return GeoPoint(lat: 0, lon: 0) }
        let sum = pts.reduce(SIMD3<Double>.zero) { $0 + unitVector($1) }
        return point(from: sum)
    }

    /// Degrees of latitude/longitude spanning `km` around a latitude (for bounding-box queries).
    static func degreeSpan(km: Double, atLat lat: Double) -> (dLat: Double, dLon: Double) {
        let dLat = km / 111.32
        let dLon = km / max(1, 111.32 * cos(lat * .pi / 180))
        return (dLat, min(dLon, 180))
    }
}
