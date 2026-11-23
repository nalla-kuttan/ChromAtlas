import SwiftUI
import UIKit

/// Radial OKLCh wheel: hue around the circumference, saturation (chroma) from the neutral centre outward.
struct ColorWheelView: View {
    @Environment(AppModel.self) private var model
    var diameter: CGFloat

    @State private var lastZone: Int?
    @State private var lastDenseBin: Int?
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)

    var body: some View {
        let r = diameter / 2
        ZStack {
            Image(uiImage: WheelImage.shared.image)
                .resizable()
                .interpolation(.high)
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .saturation(model.filter.color == nil ? 0.85 : 1)

            // Density of the photos matching the current time/geo filters.
            Canvas { ctx, size in
                let res = model.result
                guard res.maxDensity > 0 else { return }
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for s in 0..<QueryEngine.satBins {
                    for h in 0..<QueryEngine.hueBins {
                        let v = res.density[s * QueryEngine.hueBins + h] / res.maxDensity
                        guard v > 0.002 else { continue }
                        let rr = (Double(s) + 0.5) / Double(QueryEngine.satBins) * Double(r) * 0.94
                        let a = (Double(h) * 10 + 5) * .pi / 180
                        let p = CGPoint(x: c.x + rr * cos(a), y: c.y - rr * sin(a))
                        let dot = 2.2 + 6.5 * sqrt(Double(v))
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot)),
                                 with: .color(.black.opacity(0.18 + 0.5 * Double(v))))
                        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot)),
                                   with: .color(.white.opacity(0.25 + 0.6 * Double(v))), lineWidth: 0.8)
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)

            // Monochrome dead zone
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: diameter * ColorSelection.deadZone * 2, height: diameter * ColorSelection.deadZone * 2)

            if let sel = model.filter.color {
                selectionMarks(sel, r: r)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in update(at: g.location, r: r) }
        )
        .onAppear { light.prepare(); soft.prepare() }
        // VoiceOver sees two native sliders: hue and saturation.
        .accessibilityRepresentation {
            VStack {
                Slider(value: hueBinding, in: 0...345, step: 15) { Text("Color wheel hue") }
                    .accessibilityValue(model.filter.color == nil ? "All colors" : model.colorCallout)
                Slider(value: saturationBinding, in: 0...1, step: 0.1) { Text("Color wheel saturation") }
                    .accessibilityValue(model.filter.color.map { $0.isNeutral ? "Neutral" : "\(Int(($0.saturation * 100).rounded())) percent" } ?? "Any")
            }
        }
    }

    private var hueBinding: Binding<Double> {
        Binding(
            get: { model.filter.color?.hue ?? 60 },
            set: { hue in
                let sat = model.filter.color.map { $0.isNeutral ? 0.6 : $0.saturation } ?? 0.6
                model.filter.color = ColorSelection(hue: hue, saturation: sat)
            })
    }

    private var saturationBinding: Binding<Double> {
        Binding(
            get: { model.filter.color?.saturation ?? 0 },
            set: { sat in model.filter.color = ColorSelection(hue: model.filter.color?.hue ?? 60, saturation: sat) })
    }

    @ViewBuilder
    private func selectionMarks(_ sel: ColorSelection, r: CGFloat) -> some View {
        let harmony = model.filter.effectiveHarmony
        let rad = CGFloat(sel.saturation) * r
        if harmony == .analogous {
            Circle()
                .trim(from: 0, to: 96.0 / 360)
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: rad * 2, height: rad * 2)
                .rotationEffect(.degrees(-(sel.hue + 48)))
        }
        if harmony == .complementary {
            let h2 = sel.hue + 180
            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .background(Circle().fill(OKLab(L: 0.72, chroma: sel.targetChroma, hueDegrees: h2).color))
                .frame(width: 18, height: 18)
                .offset(puckOffset(h2, rad))
            Path { p in
                p.move(to: CGPoint(x: r + puckOffset(sel.hue, rad).width, y: r + puckOffset(sel.hue, rad).height))
                p.addLine(to: CGPoint(x: r + puckOffset(h2, rad).width, y: r + puckOffset(h2, rad).height))
            }
            .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(width: r * 2, height: r * 2)
        }
        Circle()
            .strokeBorder(.white, lineWidth: 3)
            .background(Circle().fill(sel.isNeutral ? Color.gray : OKLab(L: 0.72, chroma: sel.targetChroma, hueDegrees: sel.hue).color))
            .frame(width: 26, height: 26)
            .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
            .offset(puckOffset(sel.hue, rad))
    }

    private func puckOffset(_ hue: Double, _ rad: CGFloat) -> CGSize {
        let a = hue * .pi / 180
        return CGSize(width: rad * cos(a), height: -rad * sin(a))
    }

    private func update(at p: CGPoint, r: CGFloat) {
        let dx = Double(p.x - r), dy = Double(r - p.y)
        let sat = min(1, (dx * dx + dy * dy).squareRoot() / Double(r))
        var hue = atan2(dy, dx) * 180 / .pi
        if hue < 0 { hue += 360 }
        let sel = ColorSelection(hue: hue, saturation: sat)
        model.filter.color = sel

        // Haptic detents: crossing a named hue boundary, and entering a dense photo cluster.
        let zone = sel.isNeutral ? -1 : ChromaticZone.zoneIndex(hue: hue)
        if zone != lastZone {
            if lastZone != nil { light.impactOccurred(intensity: 0.8) }
            lastZone = zone
        }
        let res = model.result
        let sb = min(QueryEngine.satBins - 1, Int(sat * Double(QueryEngine.satBins)))
        let bin = sb * QueryEngine.hueBins + Int(hue / 10) % QueryEngine.hueBins
        if res.maxDensity > 0, res.density[bin] / res.maxDensity > 0.55 {
            if bin != lastDenseBin { soft.impactOccurred(intensity: 1); lastDenseBin = bin }
        } else {
            lastDenseBin = nil
        }
    }
}

/// The wheel bitmap, rendered once in OKLCh.
final class WheelImage {
    static let shared = WheelImage()
    let image: UIImage

    private init() {
        let side = 360
        var px = [UInt8](repeating: 0, count: side * side * 4)
        let r = Double(side) / 2
        for y in 0..<side {
            for x in 0..<side {
                let dx = Double(x) + 0.5 - r, dy = r - (Double(y) + 0.5)
                let d = (dx * dx + dy * dy).squareRoot() / r
                guard d <= 1.0 else { continue }
                var hue = atan2(dy, dx) * 180 / .pi
                if hue < 0 { hue += 360 }
                let c = OKLab(L: 0.74 - 0.06 * d, chroma: d * ColorSelection.maxChroma * 0.75, hueDegrees: hue).rgb
                let i = (y * side + x) * 4
                px[i] = UInt8(c.r * 255); px[i + 1] = UInt8(c.g * 255); px[i + 2] = UInt8(c.b * 255); px[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        image = UIImage(cgImage: cg)
    }
}

/// Vertical luminance range slider adjacent to the wheel.
struct LuminanceSlider: View {
    @Environment(AppModel.self) private var model
    var height: CGFloat
    @State private var dragging: Bool?   // true = upper thumb

    var body: some View {
        let lum = model.filter.luminance
        let hue = model.filter.color?.hue ?? 60
        let chroma = min(0.05, model.filter.color?.targetChroma ?? 0)
        let y = { (l: Double) -> CGFloat in CGFloat(1 - l) * height }
        ZStack(alignment: .top) {
            LinearGradient(stops: stride(from: 1.0, through: 0, by: -0.125).map {
                .init(color: OKLab(L: $0, chroma: chroma, hueDegrees: hue).color, location: 1 - $0)
            }, startPoint: .top, endPoint: .bottom)
            .frame(width: 14, height: height)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke))

            Capsule().strokeBorder(Theme.amber, lineWidth: 2)
                .frame(width: 22, height: max(14, y(lum.lowerBound) - y(lum.upperBound)))
                .offset(y: y(lum.upperBound))
            thumb.offset(y: y(lum.upperBound) - 6)
            thumb.offset(y: y(lum.lowerBound) - 6)
        }
        .frame(width: Theme.minTap, height: height)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let l = min(max(1 - Double(g.location.y / height), 0), 1)
                    if dragging == nil {
                        dragging = abs(l - lum.upperBound) < abs(l - lum.lowerBound)
                    }
                    var r = model.filter.luminance
                    if dragging == true { r = min(r.lowerBound, l - 0.05)...max(l, r.lowerBound + 0.05) }
                    else { r = min(l, r.upperBound - 0.05)...max(r.upperBound, l + 0.05) }
                    let lo = max(0, r.lowerBound), hi = min(1, r.upperBound)
                    model.filter.luminance = lo...hi
                }
                .onEnded { _ in dragging = nil }
        )
        // VoiceOver sees two native sliders, one per end of the range.
        .accessibilityRepresentation {
            VStack {
                Slider(value: lowerBinding, in: 0...0.95, step: 0.05) { Text("Minimum brightness") }
                Slider(value: upperBinding, in: 0.05...1, step: 0.05) { Text("Maximum brightness") }
            }
        }
    }

    private var lowerBinding: Binding<Double> {
        Binding(
            get: { model.filter.luminance.lowerBound },
            set: { lo in
                let hi = model.filter.luminance.upperBound
                model.filter.luminance = min(lo, hi - 0.05)...hi
            })
    }

    private var upperBinding: Binding<Double> {
        Binding(
            get: { model.filter.luminance.upperBound },
            set: { hi in
                let lo = model.filter.luminance.lowerBound
                model.filter.luminance = lo...max(hi, lo + 0.05)
            })
    }

    private var thumb: some View {
        Capsule().fill(.white).frame(width: 26, height: 12)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }
}

struct HarmonyPicker: View {
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .footnote) private var capsuleWidth: CGFloat = 38
    @ScaledMetric(relativeTo: .footnote) private var capsuleHeight: CGFloat = 32
    var body: some View {
        HStack(spacing: 4) {
            ForEach(HarmonyMode.allCases) { mode in
                let on = model.filter.effectiveHarmony == mode
                Button {
                    if mode == .monochrome {
                        model.filter.color = ColorSelection(hue: model.filter.color?.hue ?? 0, saturation: 0)
                    } else if model.filter.color?.isNeutral ?? true {
                        model.filter.color = ColorSelection(hue: model.filter.color?.hue ?? 60, saturation: 0.55)
                    }
                    model.filter.harmony = mode == .monochrome ? model.filter.harmony : mode
                } label: {
                    Image(systemName: mode.symbol)
                        .font(Theme.rounded(.footnote))
                        .frame(width: capsuleWidth, height: capsuleHeight)
                        .foregroundStyle(on ? Color.black.opacity(0.85) : Theme.textSecondary)
                        .background(on ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(Theme.surface), in: Capsule())
                        .tapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.rawValue) harmony")
                .accessibilitySelected(on)
                .accessibilityShowsLargeContentViewer { Label(mode.rawValue, systemImage: mode.symbol) }
                .sensoryFeedback(.selection, trigger: on)
            }
        }
    }
}

struct WheelCallout: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.filter.color.map { $0.isNeutral ? Color.gray : OKLab(L: 0.74, chroma: $0.targetChroma, hueDegrees: $0.hue).color } ?? Color.white.opacity(0.3))
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            Text(model.colorCallout)
                .font(Theme.rounded(.footnote))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .contentTransition(.interpolate)
            Text("· \(model.result.matches.count)")
                .font(Theme.mono(.caption, .medium))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
                .accessibilityLabel("\(model.result.matches.count) photos")
            if model.filter.hasColorFilter {
                Button {
                    withAnimation(.snappy) {
                        model.filter.color = nil
                        model.filter.luminance = 0...1
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                        .frame(width: Theme.minTap, height: Theme.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The 44 pt hit area overhangs the pill instead of making it taller.
                .padding(.vertical, -12)
                .padding(.trailing, -14)
                .accessibilityLabel("Clear color filter")
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassPanel(radius: 20)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
