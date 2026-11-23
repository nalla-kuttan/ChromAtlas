import Foundation
import SwiftUI

/// A color in Björn Ottosson's OKLab perceptual space.
/// L ∈ [0, 1], a/b roughly ∈ [-0.4, 0.4].
struct OKLab: Hashable, Codable, Sendable {
    var L: Double
    var a: Double
    var b: Double

    /// Chroma (distance from the neutral axis).
    var chroma: Double { (a * a + b * b).squareRoot() }

    /// Hue angle in degrees, 0..<360 (OKLCh convention).
    var hueDegrees: Double {
        let h = atan2(b, a) * 180 / .pi
        return h < 0 ? h + 360 : h
    }

    init(L: Double, a: Double, b: Double) {
        self.L = L; self.a = a; self.b = b
    }

    /// Builds from OKLCh (lightness, chroma, hue in degrees).
    init(L: Double, chroma: Double, hueDegrees: Double) {
        let h = hueDegrees * .pi / 180
        self.init(L: L, a: chroma * cos(h), b: chroma * sin(h))
    }

    /// Builds from gamma-encoded sRGB components in 0...1.
    init(r: Double, g: Double, b: Double) {
        let lr = OKLab.linearize(r), lg = OKLab.linearize(g), lb = OKLab.linearize(b)
        let l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
        let m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
        let s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        self.L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        self.a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        self.b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    }

    /// Gamma-encoded sRGB, clamped to gamut.
    var rgb: (r: Double, g: Double, b: Double) {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return (OKLab.delinearize(r), OKLab.delinearize(g), OKLab.delinearize(bb))
    }

    var color: Color {
        let c = rgb
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    var uiColor: UIColor {
        let c = rgb
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    func distanceSquared(to o: OKLab) -> Double {
        let dl = L - o.L, da = a - o.a, db = b - o.b
        return dl * dl + da * da + db * db
    }

    @inline(__always) static func linearize(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    @inline(__always) static func delinearize(_ c: Double) -> Double {
        let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(max(c, 0), 1 / 2.4) - 0.055
        return min(max(v, 0), 1)
    }
}

/// Fast lookup from 8-bit sRGB channel to linear value.
enum SRGBLUT {
    static let table: [Float] = (0..<256).map { Float(OKLab.linearize(Double($0) / 255)) }
}
