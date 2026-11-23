import SceneKit
import UIKit
import simd

/// Builds and updates the dark obsidian globe, its great-circle flight arcs and city pins.
@MainActor
final class GlobeScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    /// Everything that rotates with the Earth hangs off this node.
    let earth = SCNNode()
    private let arcsNode = SCNNode()
    private let pinsNode = SCNNode()
    private let homeNode = SCNNode()

    private(set) var yaw: Float = 0
    private(set) var pitch: Float = 0.35
    private(set) var distance: Float = 3.8

    static let landTexture: UIImage = renderLandTexture(width: 2048, height: 1024)

    init() {
        scene.background.contents = UIColor.clear
        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.05
        camera.zFar = 50
        camera.wantsHDR = true
        camera.bloomIntensity = 0.55
        camera.bloomThreshold = 0.7
        camera.bloomBlurRadius = 6
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, distance)
        scene.rootNode.addChildNode(cameraNode)

        let sphere = SCNNode(geometry: GlobeScene.makeSphere(segments: 96))
        let m = SCNMaterial()
        m.diffuse.contents = GlobeScene.landTexture
        m.lightingModel = .lambert
        m.emission.contents = GlobeScene.landTexture
        m.emission.intensity = 0.55
        sphere.geometry?.materials = [m]
        earth.addChildNode(sphere)

        // Atmosphere: back-face fresnel shell.
        let atmo = SCNSphere(radius: 1.06)
        atmo.segmentCount = 72
        let am = SCNMaterial()
        am.lightingModel = .constant
        am.diffuse.contents = UIColor.black
        am.blendMode = .add
        am.writesToDepthBuffer = false
        am.cullMode = .front
        am.shaderModifiers = [.fragment: """
            #pragma transparent
            #pragma body
            float d = abs(dot(normalize(_surface.normal), normalize(_surface.view)));
            float rim = pow(clamp(d / 0.34, 0.0, 1.0), 2.2);
            _output.color = float4(0.20, 0.55, 1.0, 1.0) * rim * 0.75;
            """]
        atmo.materials = [am]
        let atmoNode = SCNNode(geometry: atmo)
        scene.rootNode.addChildNode(atmoNode)

        earth.addChildNode(arcsNode)
        earth.addChildNode(pinsNode)
        earth.addChildNode(homeNode)
        scene.rootNode.addChildNode(earth)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 260
        ambient.light!.color = UIColor(red: 0.55, green: 0.62, blue: 0.8, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 900
        key.light!.color = UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1)
        key.eulerAngles = SCNVector3(-0.5, -0.7, 0)
        scene.rootNode.addChildNode(key)

        addReferenceLights()
        applyOrientation(animated: false)
    }

    // MARK: Camera

    func rotate(dYaw: Float, dPitch: Float) {
        yaw += dYaw
        pitch = min(max(pitch + dPitch, -1.35), 1.35)
        applyOrientation(animated: false)
    }

    func zoom(scale: Float) {
        distance = min(max(distance / scale, 1.45), 6)
        cameraNode.position = SCNVector3(0, 0, distance)
    }

    func setZoom(_ d: Float, animated: Bool) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.9 : 0
        distance = d
        cameraNode.position = SCNVector3(0, 0, d)
        SCNTransaction.commit()
    }

    /// Spins the globe so `p` faces the camera.
    func focus(on p: GeoPoint, animated: Bool) {
        var target = Float(-p.lon * .pi / 180)
        // Take the short way round.
        while target - yaw > .pi { target -= 2 * .pi }
        while target - yaw < -.pi { target += 2 * .pi }
        yaw = target
        pitch = Float(p.lat * .pi / 180)
        applyOrientation(animated: animated)
    }

    private func applyOrientation(animated: Bool) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.9 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let q = simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        earth.simdOrientation = q
        SCNTransaction.commit()
    }

    // MARK: Content

    struct Content {
        var legs: [Leg]
        var legColors: [Int: (UIColor, UIColor)]
        var dimmedLegs: Set<Int>
        var pins: [(city: City, count: Int, highlighted: Bool, color: UIColor)]
        var home: GeoPoint?
    }

    func update(_ c: Content) {
        arcsNode.childNodes.forEach { $0.removeFromParentNode() }
        pinsNode.childNodes.forEach { $0.removeFromParentNode() }
        homeNode.childNodes.forEach { $0.removeFromParentNode() }

        for leg in c.legs {
            let (c0, c1) = c.legColors[leg.id] ?? (.cyan, .orange)
            let dim = c.dimmedLegs.contains(leg.id)
            let node = SCNNode(geometry: GlobeScene.makeArc(leg, from: c0, to: c1, alpha: dim ? 0.18 : 1))
            node.renderingOrder = 10
            arcsNode.addChildNode(node)
        }

        let maxCount = max(1, c.pins.map(\.count).max() ?? 1)
        for pin in c.pins {
            let v = GeoMath.unitVector(pin.city.location)
            let scale = 0.006 + 0.010 * sqrt(Double(pin.count) / Double(maxCount))
            let geo = SCNSphere(radius: scale * (pin.highlighted ? 1.25 : 0.8))
            geo.segmentCount = 12
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = pin.highlighted ? pin.color : pin.color.withAlphaComponent(0.25)
            m.emission.contents = pin.highlighted ? pin.color : UIColor.black
            geo.materials = [m]
            let node = SCNNode(geometry: geo)
            node.simdPosition = SIMD3<Float>(v * 1.004)
            node.name = "city:\(pin.city.id)"
            pinsNode.addChildNode(node)

            if pin.highlighted {
                let halo = SCNPlane(width: scale * 6, height: scale * 6)
                let hm = SCNMaterial()
                hm.lightingModel = .constant
                hm.diffuse.contents = GlobeScene.haloImage
                hm.multiply.contents = pin.color
                hm.blendMode = .add
                hm.writesToDepthBuffer = false
                hm.isDoubleSided = true
                halo.materials = [hm]
                let h = SCNNode(geometry: halo)
                h.simdPosition = SIMD3<Float>(v * 1.006)
                h.simdOrientation = simd_quatf(from: SIMD3(0, 0, 1), to: simd_normalize(SIMD3<Float>(v)))
                pinsNode.addChildNode(h)
            }
        }

        if let home = c.home {
            let v = GeoMath.unitVector(home)
            let ring = SCNTorus(ringRadius: 0.022, pipeRadius: 0.0025)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = UIColor.white
            m.emission.contents = UIColor.white
            ring.materials = [m]
            let n = SCNNode(geometry: ring)
            n.simdPosition = SIMD3<Float>(v * 1.004)
            n.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(SIMD3<Float>(v)))
            n.name = "home"
            homeNode.addChildNode(n)
        }
    }

    private func addReferenceLights() {
        // Faint city lights for every bundled city: a hint of geography on the night side.
        let cities = GeoDatabase.shared.allCities
        guard !cities.isEmpty else { return }
        var verts: [SCNVector3] = []
        for c in cities {
            let v = GeoMath.unitVector(c.location) * 1.0015
            verts.append(SCNVector3(Float(v.x), Float(v.y), Float(v.z)))
        }
        let src = SCNGeometrySource(vertices: verts)
        let el = SCNGeometryElement(indices: Array(0..<Int32(verts.count)), primitiveType: .point)
        el.pointSize = 2.5
        el.minimumPointScreenSpaceRadius = 1
        el.maximumPointScreenSpaceRadius = 2.5
        let g = SCNGeometry(sources: [src], elements: [el])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(red: 1, green: 0.78, blue: 0.45, alpha: 0.35)
        m.blendMode = .add
        g.materials = [m]
        earth.addChildNode(SCNNode(geometry: g))
    }

    // MARK: Geometry builders

    /// UV sphere using the same lat/lon convention as `GeoMath.unitVector`, so the texture lines up exactly.
    static func makeSphere(segments: Int) -> SCNGeometry {
        let rings = segments / 2
        var verts: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = []
        for r in 0...rings {
            let lat = 90 - 180 * Double(r) / Double(rings)
            for s in 0...segments {
                let lon = -180 + 360 * Double(s) / Double(segments)
                let v = GeoMath.unitVector(GeoPoint(lat: lat, lon: lon))
                let p = SCNVector3(Float(v.x), Float(v.y), Float(v.z))
                verts.append(p); normals.append(p)
                uvs.append(CGPoint(x: Double(s) / Double(segments), y: Double(r) / Double(rings)))
            }
        }
        var idx: [Int32] = []
        let stride = segments + 1
        for r in 0..<rings {
            for s in 0..<segments {
                let a = Int32(r * stride + s), b = Int32((r + 1) * stride + s)
                idx += [a, b, a + 1, a + 1, b, b + 1]   // counter-clockwise from outside
            }
        }
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uvs)],
            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    /// A lifted great-circle tube with a per-vertex colour gradient.
    static func makeArc(_ leg: Leg, from c0: UIColor, to c1: UIColor, alpha: CGFloat) -> SCNGeometry {
        let segs = max(12, min(96, Int(leg.distanceKm / 80)))
        let path = GeoMath.greatCircle(leg.from, leg.to, segments: segs)
        let isFlight = leg.kind == .flight
        let lift = isFlight ? min(0.16, 0.012 + leg.distanceKm / 20000 * 0.45) : 0.003
        let radius: Double = isFlight ? 0.0030 : 0.0024
        let sides = 5

        var pts: [SIMD3<Double>] = []
        for (i, v) in path.enumerated() {
            let t = Double(i) / Double(path.count - 1)
            pts.append(simd_normalize(v) * (1.003 + lift * sin(.pi * t)))
        }
        var verts: [SCNVector3] = [], colors: [SIMD4<Float>] = []
        func rgba(_ c: UIColor) -> SIMD4<Double> {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return SIMD4(Double(r), Double(g), Double(b), 1)
        }
        let k0 = rgba(c0), k1 = rgba(c1)
        for i in pts.indices {
            let p = pts[i]
            let tangent = simd_normalize(pts[min(i + 1, pts.count - 1)] - pts[max(i - 1, 0)])
            let up = simd_normalize(p)
            let side = simd_normalize(simd_cross(tangent, up))
            let up2 = simd_cross(side, tangent)
            let t = Double(i) / Double(pts.count - 1)
            let col = k0 + (k1 - k0) * t
            // Fade the very ends so arcs feel like light trails.
            let fade = min(1, min(t, 1 - t) * 8 + 0.35) * Double(alpha)
            for s in 0..<sides {
                let a = 2 * Double.pi * Double(s) / Double(sides)
                let q = p + (side * cos(a) + up2 * sin(a)) * radius
                verts.append(SCNVector3(Float(q.x), Float(q.y), Float(q.z)))
                colors.append(SIMD4<Float>(Float(col.x * fade), Float(col.y * fade), Float(col.z * fade), Float(fade)))
            }
        }
        var idx: [Int32] = []
        for i in 0..<(pts.count - 1) {
            for s in 0..<sides {
                let a = Int32(i * sides + s), b = Int32(i * sides + (s + 1) % sides)
                let c = a + Int32(sides), d = b + Int32(sides)
                idx += [a, c, b, b, c, d]
            }
        }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSrc = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count,
                                         usesFloatComponents: true, componentsPerVector: 4,
                                         bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                         dataStride: MemoryLayout<SIMD4<Float>>.stride)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), colorSrc],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.white
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        g.materials = [m]
        return g
    }

    static let haloImage: UIImage = {
        let size = CGSize(width: 64, height: 64)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                             endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
    }()

    /// Equirectangular obsidian/slate land texture with a faint graticule.
    static func renderLandTexture(width: Int, height: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            func pt(_ lat: Double, _ lon: Double) -> CGPoint {
                CGPoint(x: (lon + 180) / 360 * Double(width), y: (90 - lat) / 180 * Double(height))
            }
            UIColor(red: 0.035, green: 0.05, blue: 0.085, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Graticule
            cg.setStrokeColor(UIColor(red: 0.25, green: 0.4, blue: 0.6, alpha: 0.18).cgColor)
            cg.setLineWidth(1)
            for lat in stride(from: -75.0, through: 75, by: 15) {
                cg.move(to: pt(lat, -180)); cg.addLine(to: pt(lat, 180))
            }
            for lon in stride(from: -180.0, through: 180, by: 15) {
                cg.move(to: pt(85, lon)); cg.addLine(to: pt(-85, lon))
            }
            cg.strokePath()

            func path(_ ring: WorldOutlines.Ring) -> CGPath {
                let p = CGMutablePath()
                for (i, c) in ring.enumerated() {
                    i == 0 ? p.move(to: pt(c.0, c.1)) : p.addLine(to: pt(c.0, c.1))
                }
                p.closeSubpath()
                return p
            }
            let land = UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1)
            let coast = UIColor(red: 0.36, green: 0.48, blue: 0.62, alpha: 0.9)
            for ring in WorldOutlines.land {
                cg.addPath(path(ring)); cg.setFillColor(land.cgColor); cg.fillPath()
            }
            let ocean = UIColor(red: 0.035, green: 0.05, blue: 0.085, alpha: 1)
            for ring in WorldOutlines.water {
                cg.addPath(path(ring)); cg.setFillColor(ocean.cgColor); cg.fillPath()
            }
            cg.setStrokeColor(coast.cgColor)
            cg.setLineWidth(1.6)
            cg.setLineJoin(.round)
            for ring in WorldOutlines.land + WorldOutlines.water {
                cg.addPath(path(ring)); cg.strokePath()
            }
        }
    }

    /// Offscreen render for share cards.
    func snapshot(size: CGSize) -> UIImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }
}
