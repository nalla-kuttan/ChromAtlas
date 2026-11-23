import SwiftUI

/// Exportable dark-mode summary card. Rendered to a fresh bitmap, so it carries no EXIF/GPS —
/// places appear at city level only.
struct ShareCardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var gridCount = 9
    @State private var globeImage: UIImage?
    @State private var photos: [UIImage] = []
    @State private var rendered: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let rendered {
                        Image(uiImage: rendered).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
                            .accessibilityLabel("Share card preview: \(cardTitle)")
                    } else {
                        ProgressView("Rendering card…").frame(height: 400)
                    }
                    Picker("Photos", selection: $gridCount) {
                        Text("4 photos").tag(4)
                        Text("9 photos").tag(9)
                    }
                    .pickerStyle(.segmented)

                    Label("Rendered on device. Street-level GPS and all photo metadata are stripped — only city names appear.",
                          systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)

                    if let rendered {
                        ShareLink(item: Image(uiImage: rendered), preview: SharePreview("ChromAtlas", image: Image(uiImage: rendered))) {
                            Label("Share Card", systemImage: "square.and.arrow.up")
                                .font(Theme.rounded(.callout))
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Theme.amber, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.black)
                        }
                    }
                }
                .padding(18)
            }
            .background(Theme.background)
            .navigationTitle("Share Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task(id: gridCount) { await build() }
        }
    }

    private func build() async {
        if globeImage == nil {
            let g = GlobeScene()
            g.update(model.globeContent())
            let trip = model.filter.tripID.flatMap { id in model.analysis.trips.first { $0.id == id } }
            if let center = trip?.center ?? model.analysis.home?.location {
                g.focus(on: GeoPoint(lat: center.lat - 8, lon: center.lon), animated: false)
            }
            g.setZoom(3.0, animated: false)
            globeImage = g.snapshot(size: CGSize(width: 900, height: 900))
        }
        var imgs: [UIImage] = []
        for idx in model.result.matches.prefix(gridCount) {
            if let img = await ThumbnailLoader.shared.image(for: model.asset(at: idx), side: 360) { imgs.append(img) }
        }
        photos = imgs
        let card = ShareCard(analysis: model.analysis, title: cardTitle, palette: paletteColor,
                             globe: globeImage, photos: photos, columns: gridCount == 4 ? 2 : 3)
        let r = ImageRenderer(content: card)
        r.scale = 1
        rendered = r.uiImage
    }

    private var cardTitle: String {
        if let t = model.filter.tripID, let trip = model.analysis.trips.first(where: { $0.id == t }) { return trip.title }
        if model.filter.color != nil { return model.colorCallout }
        return "My Atlas"
    }

    private var paletteColor: Color? {
        guard let c = model.filter.color, !c.isNeutral else { return nil }
        return OKLab(L: 0.75, chroma: c.targetChroma, hueDegrees: c.hue).color
    }
}

struct ShareCard: View {
    let analysis: TripAnalysis
    let title: String
    let palette: Color?
    let globe: UIImage?
    let photos: [UIImage]
    let columns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            HStack {
                // Brand lockup (vector asset, Branding/logo/kit/master/lockup-horizontal-on-dark.svg, cropped tight).
                Image("LogoLockup").resizable().scaledToFit()
                    .frame(height: 44)
                    .accessibilityLabel("ChromAtlas")
                Spacer(minLength: 24)
                Text(title).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(palette ?? Theme.amber)
                    .lineLimit(1)
            }
            HStack(alignment: .center, spacing: 40) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(red: 0.1, green: 0.25, blue: 0.5).opacity(0.5), .clear], center: .center, startRadius: 100, endRadius: 260))
                    if let globe { Image(uiImage: globe).resizable().scaledToFit() }
                }
                .frame(width: 440, height: 440)
                VStack(alignment: .leading, spacing: 26) {
                    stat(DistanceBadgeHUD.km(analysis.kilometersTraveled), "kilometers traveled")
                    stat("\(analysis.countriesVisited.count)", "countries")
                    stat("\(analysis.citiesVisited.count)", "cities")
                    let badges = analysis.badges.filter(\.unlocked).prefix(3)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(badges)) { b in
                            Label(b.title, systemImage: b.symbol)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.amber)
                        }
                    }
                }
            }
            let side = (1080 - 120 - CGFloat(columns - 1) * 14) / CGFloat(columns)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: 14), count: columns), spacing: 14) {
                ForEach(Array(photos.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: side, height: side * (columns == 2 ? 0.62 : 1)).clipped()
                        .overlay(palette.map { $0.opacity(0.22).blendMode(.softLight) })
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
            Spacer(minLength: 0)
            Text("Indexed privately on device · no cloud, no accounts")
                .font(.system(size: 18, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(60)
        .frame(width: 1080, height: 1350, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.09), Color(red: 0.02, green: 0.02, blue: 0.035)],
                           startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.large)   // fixed-size export bitmap: independent of the reader's text size
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
            Text(l.uppercased()).font(.system(size: 17, weight: .semibold)).tracking(2).foregroundStyle(.white.opacity(0.5))
        }
    }
}
