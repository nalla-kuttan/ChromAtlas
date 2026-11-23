import Foundation

enum HarmonyMode: String, CaseIterable, Identifiable, Sendable {
    case single = "Single Hue"
    case complementary = "Complementary"
    case analogous = "Analogous"
    case monochrome = "Monochrome"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .single: return "circle.fill"
        case .complementary: return "circle.lefthalf.filled"
        case .analogous: return "circle.dotted.circle"
        case .monochrome: return "circle.slash"
        }
    }
}

struct ColorSelection: Equatable, Sendable {
    /// OKLCh hue in degrees.
    var hue: Double
    /// Normalised wheel radius 0…1 (0 = neutral centre).
    var saturation: Double

    static let deadZone = 0.14
    static let maxChroma = 0.30

    var targetChroma: Double { saturation * ColorSelection.maxChroma }
    var isNeutral: Bool { saturation < ColorSelection.deadZone }
}

struct FilterState: Equatable, Sendable {
    var timeRange: ClosedRange<TimeInterval>?
    var color: ColorSelection?
    var harmony: HarmonyMode = .single
    var luminance: ClosedRange<Double> = 0...1
    var seasons: Set<Season> = []
    var phases: Set<SolarPhase> = []
    var countryCode: String?
    var cityID: Int?
    var tripID: Int?

    var effectiveHarmony: HarmonyMode {
        guard let c = color else { return harmony }
        return c.isNeutral ? .monochrome : harmony
    }

    var hasColorFilter: Bool { color != nil || luminance != 0...1 }
    var hasGeoFilter: Bool { countryCode != nil || cityID != nil || tripID != nil }

    var isEmpty: Bool {
        timeRange == nil && color == nil && luminance == 0...1 && seasons.isEmpty && phases.isEmpty && !hasGeoFilter
    }

    /// Hue windows (centre, half-width) implied by the harmony mode.
    var hueWindows: [(Double, Double)] {
        guard let c = color else { return [] }
        switch effectiveHarmony {
        case .single: return [(c.hue, 16)]
        case .complementary: return [(c.hue, 18), ((c.hue + 180).truncatingRemainder(dividingBy: 360), 18)]
        case .analogous: return [(c.hue, 48)]
        case .monochrome: return []
        }
    }
}
