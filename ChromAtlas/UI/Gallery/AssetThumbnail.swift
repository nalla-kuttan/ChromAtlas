import Photos
import SwiftUI

/// Loads PhotoKit thumbnails on-device only (no iCloud downloads); renders demo assets procedurally.
@MainActor
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()
    /// PHAsset handles resolved in batches, so scrolling doesn't run one library fetch per cell.
    private var assets: [String: PHAsset] = [:]

    init() { cache.countLimit = 600 }

    /// Resolves many identifiers with a single PhotoKit fetch. Call when the visible result set changes.
    func prefetch(_ records: [AssetRecord]) {
        let missing = records.lazy.filter { !$0.isDemo && self.assets[$0.id] == nil }.map(\.id)
        guard !missing.isEmpty else { return }
        let found = PHAsset.fetchAssets(withLocalIdentifiers: Array(missing), options: nil)
        found.enumerateObjects { asset, _, _ in self.assets[asset.localIdentifier] = asset }
    }

    func image(for record: AssetRecord, side: CGFloat) async -> UIImage? {
        let key = "\(record.id)#\(Int(side))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let img: UIImage?
        let scale = UIScreen.main.scale
        if record.isDemo {
            // Procedural artwork is drawn off the main thread so scrolling stays smooth.
            img = await Task.detached(priority: .userInitiated) { DemoArtwork.render(record, side: side, scale: scale) }.value
        } else {
            img = await request(record.id, side: side, scale: scale)
        }
        if let img { cache.setObject(img, forKey: key) }
        return img
    }

    private func request(_ id: String, side: CGFloat, scale: CGFloat) async -> UIImage? {
        let asset: PHAsset
        if let known = assets[id] {
            asset = known
        } else {
            guard let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
            assets[id] = fetched
            asset = fetched
        }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = false
        return await withCheckedContinuation { cont in
            manager.requestImage(for: asset, targetSize: CGSize(width: side * scale, height: side * scale),
                                 contentMode: .aspectFill, options: opts) { img, _ in
                cont.resume(returning: img)
            }
        }
    }
}

/// Paints a small abstract "scene" from a demo record's three OKLab centroids.
enum DemoArtwork {
    static func render(_ r: AssetRecord, side: CGFloat, scale: CGFloat) -> UIImage {
        let size = CGSize(width: side, height: side)
        let colors = r.colors.map(\.lab.uiColor)
        let c0 = colors.first ?? .gray, c1 = colors.count > 1 ? colors[1] : c0, c2 = colors.count > 2 ? colors[2] : c1
        let w0 = r.colors.first?.weight ?? 0.6
        // FNV-1a of the id: unlike hashValue, it's the same on every launch, so each demo photo keeps its look.
        var seed: UInt64 = r.id.utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 }
        func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 40) / CGFloat(1 << 24) }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            // Sky → ground split weighted by the dominant share.
            let horizon = side * (1 - CGFloat(w0)) * 0.9 + side * 0.08
            let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c1.cgColor, c1.withAlphaComponent(0.9).cgColor, c0.cgColor] as CFArray, locations: [0, 0.6, 1])!
            cg.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: horizon + side * 0.1), options: [.drawsAfterEndLocation])
            // Ground / skyline silhouette in the dominant colour.
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: side))
            var x: CGFloat = 0
            while x < side {
                let h = horizon + (rnd() - 0.5) * side * 0.22
                path.addLine(to: CGPoint(x: x, y: h))
                x += side * (0.08 + rnd() * 0.16)
                path.addLine(to: CGPoint(x: x, y: h))
            }
            path.addLine(to: CGPoint(x: side, y: side))
            path.close()
            c0.setFill(); path.fill()
            // Accent: sun, lamp or neon sign.
            let ar = side * (0.08 + CGFloat(r.colors.last?.weight ?? 0.1) * 0.5)
            let ac = CGPoint(x: side * (0.2 + rnd() * 0.6), y: side * (0.15 + rnd() * 0.35))
            let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c2.cgColor, c2.withAlphaComponent(0).cgColor] as CFArray, locations: [0.35, 1])!
            cg.drawRadialGradient(glow, startCenter: ac, startRadius: 0, endCenter: ac, endRadius: ar * 2.2, options: [])
            // Film grain-ish vignette.
            let vig = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.35).cgColor] as CFArray, locations: [0.55, 1])!
            cg.drawRadialGradient(vig, startCenter: CGPoint(x: side / 2, y: side / 2), startRadius: 0,
                                  endCenter: CGPoint(x: side / 2, y: side / 2), endRadius: side * 0.75, options: [])
        }
    }
}

struct AssetThumbnail: View {
    let record: AssetRecord
    var side: CGFloat
    var showBadges = true
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(record.dominant.color.opacity(0.6))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: side, height: side).clipped()
                    .transition(.opacity)
            }
            if showBadges {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                HStack(spacing: 4) {
                    Circle().fill(record.dominant.color)
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                        .frame(width: 8, height: 8)
                    if let place = record.city?.name {
                        Text(place).font(Theme.rounded(.caption2))
                            .foregroundStyle(.white).lineLimit(1)
                    }
                }
                .padding(5)
                .dynamicTypeSize(...DynamicTypeSize.large)   // a caption on an ~85 pt tile; the full place is in the VoiceOver label
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: record.id) {
            image = await ThumbnailLoader.shared.image(for: record, side: side)
        }
        .accessibilityElement()
        .accessibilityLabel("\(record.placeLabel ?? "Photo without location"), \(record.date.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityAddTraits(.isImage)
    }
}
