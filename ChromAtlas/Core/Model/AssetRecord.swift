import Foundation

/// One indexed photo. Mirrors a row of `asset_index`.
struct AssetRecord: Identifiable, Hashable, Sendable {
    let id: String                 // PHAsset.localIdentifier, or "demo:<n>" for the demo atlas
    var timestamp: TimeInterval
    var location: GeoPoint?
    var countryCode: String?
    var cityID: Int?
    var tripID: Int?
    var season: Season
    var solarPhase: SolarPhase?    // nil when the photo has no GPS
    var colors: [ColorCluster]     // up to three, heaviest first

    var date: Date { Date(timeIntervalSince1970: timestamp) }
    var isDemo: Bool { id.hasPrefix("demo:") }

    var dominant: OKLab { colors.first?.lab ?? OKLab(L: 0.5, a: 0, b: 0) }

    var city: City? { cityID.flatMap { GeoDatabase.shared.city(id: $0) } }

    /// City-level label only — never street-level coordinates.
    var placeLabel: String? {
        if let c = city { return c.label }
        if let cc = countryCode { return Countries.info(cc).name }
        return nil
    }

    var shortPlaceLabel: String? {
        if let c = city { return "\(c.name), \(c.countryCode)" }
        return countryCode
    }

    /// Builds a record, resolving geography, season and solar phase offline.
    static func make(id: String, date: Date, location: GeoPoint?, colors: [ColorCluster]) -> AssetRecord {
        var city: City?
        if let loc = location { city = GeoDatabase.shared.nearestCity(to: loc) }
        return AssetRecord(
            id: id,
            timestamp: date.timeIntervalSince1970,
            location: location,
            countryCode: city?.countryCode,
            cityID: city?.id,
            tripID: nil,
            season: Season.of(date: date, latitude: location?.lat),
            solarPhase: location.map { SolarCalculator.phase(date: date, location: $0) },
            colors: Array(colors.prefix(3))
        )
    }
}
