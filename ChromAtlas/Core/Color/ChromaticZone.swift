import Foundation

/// Human-readable names for regions of the OKLCh wheel, used for the wheel callout
/// and for naming aesthetic chapters on the timeline.
enum ChromaticZone {
    struct Zone {
        let name: String
        let start: Double   // OKLCh hue degrees, inclusive
        let end: Double     // exclusive; may wrap past 360
    }

    /// Major hue boundaries (fire a haptic detent when crossed).
    static let zones: [Zone] = [
        Zone(name: "Crimson / Neon Red", start: 0, end: 40),
        Zone(name: "Golden Hour / Warm Amber", start: 40, end: 85),
        Zone(name: "Desert Sand / Ochre", start: 85, end: 115),
        Zone(name: "Spring Lime / Chartreuse", start: 115, end: 135),
        Zone(name: "Emerald / Forest", start: 135, end: 175),
        Zone(name: "Lagoon / Teal", start: 175, end: 215),
        Zone(name: "Glacier / Sky Blue", start: 215, end: 250),
        Zone(name: "Blue Hour / Indigo", start: 250, end: 290),
        Zone(name: "Ultraviolet / Purple", start: 290, end: 325),
        Zone(name: "Neon Magenta / Rose", start: 325, end: 360),
    ]

    static func zoneIndex(hue: Double) -> Int {
        let h = hue.truncatingRemainder(dividingBy: 360)
        let hh = h < 0 ? h + 360 : h
        return zones.firstIndex { hh >= $0.start && hh < $0.end } ?? 0
    }

    /// Name for a full color selection (hue + saturation + luminance context).
    static func name(hue: Double, chroma: Double, lightness: Double? = nil) -> String {
        if chroma < 0.035 {
            if let l = lightness {
                if l < 0.3 { return "Monochrome / Low-Key Shadow" }
                if l > 0.8 { return "Monochrome / High-Key Pastel" }
            }
            return "Monochrome / Neutral"
        }
        let zone = zones[zoneIndex(hue: hue)]
        if let l = lightness, l < 0.3 {
            return zone.name.replacingOccurrences(of: " / ", with: " / Deep ")
        }
        return zone.name
    }

    static func shortName(hue: Double, chroma: Double) -> String {
        if chroma < 0.035 { return "Monochrome" }
        return String(zones[zoneIndex(hue: hue)].name.split(separator: "/").last ?? "").trimmingCharacters(in: .whitespaces)
    }
}
