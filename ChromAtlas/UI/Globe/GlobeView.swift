import SceneKit
import SwiftUI

/// Chronology gradient for arcs: cool cyan (oldest) → warm amber (newest), interpolated in OKLab.
enum ArcPalette {
    static let cool = OKLab(L: 0.82, chroma: 0.13, hueDegrees: 210)
    static let warm = OKLab(L: 0.80, chroma: 0.16, hueDegrees: 62)

    static func chronological(_ t: Double) -> UIColor {
        let t = min(max(t, 0), 1)
        return OKLab(L: cool.L + (warm.L - cool.L) * t, a: cool.a + (warm.a - cool.a) * t, b: cool.b + (warm.b - cool.b) * t).uiColor
    }

    static func hue(_ h: Double) -> UIColor { OKLab(L: 0.80, chroma: 0.17, hueDegrees: h).uiColor }
}

struct GlobeView: View {
    @Environment(AppModel.self) private var model
    var interactive = true
    var initialDistance: Float = 3.8

    var body: some View {
        // Reading these here registers Observation dependencies so the SceneKit view refreshes.
        GlobeCanvas(model: model, interactive: interactive, initialDistance: initialDistance,
                    token: "\(model.dataVersion)-\(model.resultVersion)-\(model.arcColorMode.rawValue)-\(model.focusToken)")
    }
}

struct GlobeCanvas: UIViewRepresentable {
    let model: AppModel
    var interactive: Bool
    var initialDistance: Float
    var token: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.globe.scene
        view.pointOfView = context.coordinator.globe.cameraNode
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.isPlaying = true
        context.coordinator.globe.setZoom(initialDistance, animated: false)
        context.coordinator.onTapCity = { [model] id in model.selectCity(id) }
        if interactive {
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:))))
            view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        }
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        let signature = "\(model.dataVersion)-\(model.resultVersion)-\(model.arcColorMode.rawValue)"
        if signature != c.lastSignature {
            c.lastSignature = signature
            c.globe.update(model.globeContent())
            if !c.didInitialFocus, let home = model.analysis.home {
                c.didInitialFocus = true
                c.globe.focus(on: GeoPoint(lat: home.location.lat - 12, lon: home.location.lon), animated: false)
            }
        }
        if model.focusToken != c.lastFocusToken, let f = model.focus {
            c.lastFocusToken = model.focusToken
            // With Reduce Motion on, jump straight to the place instead of spinning the globe there.
            c.globe.focus(on: f, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        let globe = GlobeScene()
        weak var view: SCNView?
        var lastSignature = ""
        var lastFocusToken = 0
        var didInitialFocus = false
        var onTapCity: ((Int) -> Void)?
        private var lastPan: CGPoint = .zero

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let p = g.translation(in: g.view)
            if g.state == .began { lastPan = .zero }
            let dx = Float(p.x - lastPan.x), dy = Float(p.y - lastPan.y)
            lastPan = p
            let k = 0.0045 * globe.distance / 3.2
            globe.rotate(dYaw: dx * k, dPitch: dy * k)
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            globe.zoom(scale: Float(g.scale))
            g.scale = 1
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let view else { return }
            let hits = view.hitTest(g.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            for h in hits {
                if let name = h.node.name, name.hasPrefix("city:"), let id = Int(name.dropFirst(5)) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onTapCity?(id)
                    return
                }
            }
            // Tolerant fallback: nearest pin to the tap on screen.
            var best: (Int, CGFloat)?
            let loc = g.location(in: view)
            for h in view.scene?.rootNode.childNodes(passingTest: { n, _ in n.name?.hasPrefix("city:") == true }) ?? [] {
                let p = view.projectPoint(h.worldPosition)
                guard p.z < 1 else { continue }
                // Skip pins on the far hemisphere.
                let world = h.simdWorldPosition
                if simd_dot(world, globe.cameraNode.simdWorldPosition - world) < 0 { continue }
                let d = hypot(CGFloat(p.x) - loc.x, CGFloat(p.y) - loc.y)
                if d < 22, d < (best?.1 ?? .infinity), let id = Int(h.name!.dropFirst(5)) { best = (id, d) }
            }
            if let (id, _) = best {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onTapCity?(id)
            }
        }
    }
}

extension AppModel {
    func globeContent() -> GlobeScene.Content {
        let model = self
        let span = model.dateSpan
        let legs = model.analysis.allLegs
        let f = model.filter
        var colors: [Int: (UIColor, UIColor)] = [:]
        for leg in legs {
            switch model.arcColorMode {
            case .chronological:
                let len = max(1, span.upperBound - span.lowerBound)
                let t0 = (leg.departure.timeIntervalSince1970 - span.lowerBound) / len
                colors[leg.id] = (ArcPalette.chronological(t0 - 0.03), ArcPalette.chronological(t0 + 0.03))
            case .palette:
                if let sel = f.color, !sel.isNeutral {
                    let h2 = f.effectiveHarmony == .complementary ? sel.hue + 180 : sel.hue
                    colors[leg.id] = (ArcPalette.hue(sel.hue), ArcPalette.hue(h2))
                } else if let sel = f.color, sel.isNeutral {
                    colors[leg.id] = (.white, UIColor(white: 0.7, alpha: 1))
                } else {
                    colors[leg.id] = (ArcPalette.chronological(0), ArcPalette.chronological(1))
                }
            }
        }
        let filtering = !f.isEmpty
        let matchTrips = model.result.matchingTrips
        let dimmed = filtering ? Set(legs.filter { !matchTrips.contains($0.tripID) }.map(\.id)) : []

        let pinColor: UIColor = {
            if let sel = f.color, !sel.isNeutral { return OKLab(L: 0.82, chroma: max(0.1, sel.targetChroma), hueDegrees: sel.hue).uiColor }
            return ArcPalette.warm.uiColor
        }()
        let matchCities = model.result.matchingCities
        var pins: [(City, Int, Bool, UIColor)] = []
        for (id, count) in model.cityCounts {
            guard let city = GeoDatabase.shared.city(id: id) else { continue }
            pins.append((city, count, !filtering || matchCities.contains(id), pinColor))
        }
        return GlobeScene.Content(legs: legs, legColors: colors, dimmedLegs: dimmed,
                                  pins: pins.map { (city: $0.0, count: $0.1, highlighted: $0.2, color: $0.3) },
                                  home: model.analysis.home?.location)
    }

}
