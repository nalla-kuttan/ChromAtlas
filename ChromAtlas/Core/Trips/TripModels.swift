import Foundation

struct HomeBase: Sendable, Hashable {
    let location: GeoPoint
    let city: City?
    var countryCode: String? { city?.countryCode }
}

/// A place the user stayed during a trip: one spatio-temporal DBSCAN cluster.
struct Stop: Identifiable, Sendable, Hashable {
    let id: Int
    let tripID: Int
    let location: GeoPoint
    let city: City?
    let start: Date
    let end: Date
    let assetIDs: [String]
    /// < 3 h at a single point (e.g. an airport transfer). Kept on the route, but unlocks nothing.
    let isLayover: Bool

    var countryCode: String? { city?.countryCode }
}

enum LegKind: String, Sendable { case flight, ground }

struct Leg: Identifiable, Sendable, Hashable {
    let id: Int
    let tripID: Int
    let from: GeoPoint
    let to: GeoPoint
    let fromLabel: String
    let toLabel: String
    let departure: Date
    let arrival: Date
    let kind: LegKind
    let distanceKm: Double
}

struct Trip: Identifiable, Sendable, Hashable {
    let id: Int
    let start: Date
    let end: Date
    let stops: [Stop]
    let legs: [Leg]
    let title: String
    let assetIDs: [String]
    let dominantHue: Double?
    let dominantChroma: Double

    var countries: [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in stops where !s.isLayover { if let c = s.countryCode, seen.insert(c).inserted { out.append(c) } }
        return out
    }
    var distanceKm: Double { legs.reduce(0) { $0 + $1.distanceKm } }
    var center: GeoPoint { GeoMath.centroid(stops.filter { !$0.isLayover }.map(\.location)) }
    var year: Int { Calendar.current.component(.year, from: start) }
}

struct Badge: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let progress: Int
    let goal: Int
    var unlocked: Bool { progress >= goal }
}

struct TripAnalysis: Sendable {
    var home: HomeBase?
    var trips: [Trip] = []
    var countriesVisited: [String] = []
    var citiesVisited: [Int] = []
    var kilometersTraveled: Double = 0
    var passportsStamped: Int = 0
    var badges: [Badge] = []
    var assetTrip: [String: Int] = [:]

    static let empty = TripAnalysis()

    var allLegs: [Leg] { trips.flatMap(\.legs) }
    var allStops: [Stop] { trips.flatMap(\.stops) }
}
