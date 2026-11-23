import Foundation

enum SolarPhase: Int, CaseIterable, Codable, Sendable, Identifiable {
    case daylight = 0, goldenHour = 1, blueHour = 2, night = 3
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .daylight: return "Daylight"
        case .goldenHour: return "Golden Hour"
        case .blueHour: return "Blue Hour"
        case .night: return "Night"
        }
    }
    var symbol: String {
        switch self {
        case .daylight: return "sun.max.fill"
        case .goldenHour: return "sun.horizon.fill"
        case .blueHour: return "moon.haze.fill"
        case .night: return "moon.stars.fill"
        }
    }
}

enum Season: Int, CaseIterable, Codable, Sendable, Identifiable {
    case spring = 0, summer = 1, autumn = 2, winter = 3
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .autumn: return "Autumn"
        case .winter: return "Winter"
        }
    }
    var symbol: String {
        switch self {
        case .spring: return "leaf.fill"
        case .summer: return "sun.max.fill"
        case .autumn: return "wind"
        case .winter: return "snowflake"
        }
    }

    /// Meteorological season; flipped for the southern hemisphere.
    /// Within ±10° of the equator seasons are weak, but we still classify by the calendar.
    static func of(date: Date, latitude: Double?) -> Season {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let month = cal.component(.month, from: date)
        var s: Season
        switch month {
        case 3, 4, 5: s = .spring
        case 6, 7, 8: s = .summer
        case 9, 10, 11: s = .autumn
        default: s = .winter
        }
        if let lat = latitude, lat < 0 {
            s = Season(rawValue: (s.rawValue + 2) % 4)!
        }
        return s
    }
}

/// NOAA-style solar position approximation, accurate to a fraction of a degree — plenty for
/// classifying golden hour (−4°…6°), blue hour (−6°…−4°) and night (< −6°).
enum SolarCalculator {
    static func elevationDegrees(date: Date, location: GeoPoint) -> Double {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let n = jd - 2451545.0
        let L = normalize(280.460 + 0.9856474 * n)            // mean longitude
        let g = normalize(357.528 + 0.9856003 * n) * .pi / 180  // mean anomaly
        let λ = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * .pi / 180  // ecliptic longitude
        let ε = (23.439 - 0.0000004 * n) * .pi / 180
        let δ = asin(sin(ε) * sin(λ))                            // declination
        let α = atan2(cos(ε) * sin(λ), cos(λ))                   // right ascension

        let gmst = normalize(280.46061837 + 360.98564736629 * n) // degrees
        let lst = (gmst + location.lon) * .pi / 180
        let H = lst - α                                           // hour angle
        let φ = location.lat * .pi / 180
        let sinAlt = sin(φ) * sin(δ) + cos(φ) * cos(δ) * cos(H)
        return asin(max(-1, min(1, sinAlt))) * 180 / .pi
    }

    static func phase(date: Date, location: GeoPoint) -> SolarPhase {
        phase(forElevation: elevationDegrees(date: date, location: location))
    }

    static func phase(forElevation e: Double) -> SolarPhase {
        if e >= 6 { return .daylight }
        if e >= -4 { return .goldenHour }
        if e >= -6 { return .blueHour }
        return .night
    }

    private static func normalize(_ deg: Double) -> Double {
        let r = deg.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}
