import Photos
import PhotosUI
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        @Bindable var model = model
        Group {
            if hSize == .regular && vSize == .regular {
                // iPad and large windows have room for everything on one screen.
                GeometryReader { geo in WideLayout(size: geo.size) }
                    .background(Theme.background.ignoresSafeArea())
            } else {
                PhoneTabs()
            }
        }
        .overlay(alignment: .top) { IndexingBanner().padding(.top, 4) }
        .overlay {
            if model.assets.isEmpty && !model.isIndexing { OnboardingCard() }
        }
        .foregroundStyle(Theme.textPrimary)
        .sheet(item: $model.selectedAsset) { AssetDetailView(record: $0).presentationDetents([.large]) }
        .sheet(isPresented: $model.showShare) { ShareCardSheet() }
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $model.showMap) { MapModeView() }
    }
}

/// iPhone: the globe and the color wheel each get a full screen. They share one filter.
struct PhoneTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView(selection: Bindable(model).tab) {
            Tab("Atlas", systemImage: "globe.europe.africa.fill", value: AppTab.atlas) { AtlasTab() }
            Tab("Palette", systemImage: "paintpalette.fill", value: AppTab.palette) { PaletteTab() }
        }
        .tint(Theme.amber)
    }
}

// MARK: - Shared sections

struct GlobeSection: View {
    @Environment(AppModel.self) private var model
    var compactHUD = false

    var body: some View {
        // The globe alone sizes this section; the controls float in an overlay so large text
        // can never push the timeline below out of the layout.
        GlobeView().globeAccessibility()
            .background {
                RadialGradient(colors: [Color(red: 0.07, green: 0.14, blue: 0.28).opacity(0.55), .clear],
                               center: .center, startRadius: 30, endRadius: 360)
                    .accessibilityHidden(true)
            }
            .overlay { controls }
        .clipped()
    }

    private var controls: some View {
        VStack {
            // Stats sit side by side when they fit, and stack (without badges) when text is large or the column is narrow.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    TelemetryHUD()
                    Spacer(minLength: 0)
                    DistanceBadgeHUD(compact: compactHUD)
                }
                VStack(alignment: .leading, spacing: 6) {
                    TelemetryHUD()
                    DistanceBadgeHUD(compact: true, alignment: .leading, showsBadges: false)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Menu {
                    Picker("Arc color", selection: Bindable(model).arcColorMode) {
                        ForEach(ArcColorMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label(model.arcColorMode.rawValue, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(Theme.rounded(.caption))
                        .lineLimit(1)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .glassPanel(radius: 18)
                        .tapTarget()
                }
                .accessibilityLabel("Arc color")
                .accessibilityValue(model.arcColorMode.rawValue)
                Spacer(minLength: 0)
                iconButton("arrow.up.left.and.arrow.down.right", "Open full-screen map") { model.showMap = true }
                iconButton("square.and.arrow.up", "Share card") { model.showShare = true }
                iconButton("gearshape", "Settings") { model.showSettings = true }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // Chrome floating over the globe stops growing at xxxLarge so the globe stays visible;
        // the icon buttons offer the Large Content Viewer beyond that.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(Theme.rounded(.subheadline))
                .frame(width: Theme.minTap, height: Theme.minTap)
                .glassPanel(radius: Theme.minTap / 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
    }
}

/// VoiceOver access to the 3D globe: a summary, plus one custom action per visited city.
private struct GlobeAccessibility: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        let cities = model.cityCounts
            .compactMap { id, count in GeoDatabase.shared.city(id: id).map { (city: $0, count: count) } }
            .sorted { $0.count > $1.count }
        let selected = model.filter.cityID.flatMap { GeoDatabase.shared.city(id: $0) }
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Travel globe")
            .accessibilityValue(selected.map { "Showing \($0.label)" }
                ?? "\(model.analysis.countriesVisited.count) countries, \(cities.count) cities")
            .accessibilityHint(cities.isEmpty ? "" : "Swipe up or down to choose a city.")
            .accessibilityActions {
                if selected != nil {
                    Button("Show all cities") { model.filter.cityID = nil }
                }
                ForEach(cities, id: \.city.id) { entry in
                    Button("\(entry.city.label), \(entry.count) photos") { model.selectCity(entry.city.id) }
                }
            }
    }
}

extension View {
    func globeAccessibility() -> some View { modifier(GlobeAccessibility()) }
}

struct ChronologySection: View {
    /// On iPhone the wheel lives in its own tab, so the chips show a link to any active color filter.
    var showsColorChip = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Caps sit at the call site so the views' @ScaledMetric sizes are capped too.
            TimelineScrubber().dynamicTypeSize(...DynamicTypeSize.accessibility2).padding(.horizontal, 16)
            ChapterChips(showsColorChip: showsColorChip)
        }
        .padding(.vertical, 8)
    }
}

struct WheelCluster: View {
    var diameter: CGFloat
    var body: some View {
        VStack(spacing: 10) {
            WheelCallout()
            HStack(alignment: .center, spacing: 8) {
                ColorWheelView(diameter: diameter)
                LuminanceSlider(height: diameter * 0.92)
            }
            HarmonyPicker().dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
}

// MARK: - Layouts

/// Atlas tab: where and when. Globe and timeline stay put; the matching photos scroll beneath.
struct AtlasTab: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if size.width > size.height {
                HStack(spacing: 0) {
                    GlobeSection(compactHUD: true).frame(width: size.width * 0.55)
                    VStack(spacing: 0) {
                        ChronologySection(showsColorChip: true)
                        Divider().overlay(Theme.stroke)
                        ResultsGrid(width: size.width * 0.45)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    GlobeSection(compactHUD: true).frame(height: size.height * 0.46)
                    ChronologySection(showsColorChip: true)
                    Divider().overlay(Theme.stroke)
                    ResultsGrid(width: size.width)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

/// Palette tab: search by color and light. The wheel sits outside the scroll view,
/// so dragging on it never fights with scrolling the photos.
struct PaletteTab: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if size.width > size.height {
                HStack(spacing: 0) {
                    WheelCluster(diameter: max(120, min(180, size.height - 130)))
                        .frame(width: size.width * 0.45)
                        .frame(maxHeight: .infinity)
                    VStack(spacing: 8) {
                        EnvironmentPills().padding(.top, 8)
                        AtlasFilterNote()
                        Divider().overlay(Theme.stroke)
                        ResultsGrid(width: size.width * 0.55)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        WheelCluster(diameter: max(140, min(210, size.width * 0.52, size.height * 0.32)))
                        EnvironmentPills()
                        AtlasFilterNote()
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    Divider().overlay(Theme.stroke)
                    ResultsGrid(width: size.width)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

/// The filtered photos, shown under both tabs.
struct ResultsGrid: View {
    let width: CGFloat
    var body: some View {
        ScrollView(showsIndicators: false) {
            PhotoGridContent(width: width - 24, columns: 4, spacing: 3)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }
    }
}

/// On the Palette tab, says when a time or place chosen in Atlas is also narrowing the results.
struct AtlasFilterNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let summary {
            HStack(spacing: 4) {
                Button { model.tab = .atlas } label: {
                    Label(summary, systemImage: "globe.europe.africa")
                        .font(Theme.rounded(.footnote))
                        .lineLimit(1)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: Theme.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Also filtered by \(summary)")
                .accessibilityHint("Opens the Atlas tab.")
                Button {
                    withAnimation(.snappy) {
                        var f = model.filter
                        f.timeRange = nil; f.tripID = nil; f.cityID = nil; f.countryCode = nil
                        model.filter = f
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                        .frame(width: Theme.minTap, height: Theme.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear time and place filters")
            }
            .padding(.horizontal, 16)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    private var summary: String? {
        let parts = model.timePlaceDescriptions
        return parts.isEmpty ? nil : "Also: " + parts.joined(separator: " · ")
    }
}

/// iPad (and large windows): three stacked tiers, grids flanking the wheel.
struct WideLayout: View {
    let size: CGSize
    var body: some View {
        VStack(spacing: 0) {
            GlobeSection().frame(height: size.height * 0.44)
            ChronologySection()
            HStack(alignment: .top, spacing: 18) {
                PhotoGrid(lane: 0, laneCount: 2, columns: size.width > 1100 ? 4 : 3)
                VStack(spacing: 14) {
                    WheelCluster(diameter: min(250, size.height * 0.26))
                    EnvironmentPills().frame(width: 360)
                }
                .frame(width: 360)
                PhotoGrid(lane: 1, laneCount: 2, columns: size.width > 1100 ? 4 : 3)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
    }
}

// MARK: - Indexing & onboarding

struct IndexingBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if model.isIndexing, let p = model.progress, p.total > 0 {
            HStack(spacing: 8) {
                ProgressView(value: Double(p.processed), total: Double(p.total))
                    .progressViewStyle(.linear).tint(Theme.amber).frame(width: 90)
                    .accessibilityHidden(true)
                Text("Indexing \(p.processed.formatted()) / \(p.total.formatted())")
                    .font(Theme.mono(.caption))
                Text("· \(Int(p.photosPerSecond))/s").font(Theme.mono(.caption, .medium)).foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("\(Int(p.photosPerSecond)) photos per second")
                if p.thermalThrottled {
                    Image(systemName: "thermometer.high").foregroundStyle(.orange).accessibilityLabel("Slowed down to keep the device cool")
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glassPanel(radius: 18)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children: .combine)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
    }
}

struct OnboardingCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.system(.largeTitle))
                        .foregroundStyle(LinearGradient(colors: [Theme.cyan, Theme.amber], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .accessibilityHidden(true)
                    Text("Your camera roll, as an atlas of places and light.")
                        .font(Theme.rounded(.title2, .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("ChromAtlas reads each photo's date, GPS and colors to rebuild your trips and let you search by mood. Everything is analyzed on this device. Nothing is uploaded, and there's no account.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    if let err = model.lastError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if model.photoAccessDenied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Label("Open Settings", systemImage: "gear")
                                .font(Theme.rounded(.callout))
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Theme.amber, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            Task { await model.connectLibrary() }
                        } label: {
                            Label("Index My Library", systemImage: "photo.stack")
                                .font(Theme.rounded(.callout))
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Theme.amber, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        withAnimation { model.loadDemo() }
                    } label: {
                        Text("Explore the Demo Atlas")
                            .font(Theme.rounded(.subheadline))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(22)
                .frame(maxWidth: 420)
                .glassPanel(radius: 22)
                .padding(20)
                // Centred when it fits; scrolls when large text makes it taller than the screen.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Source", value: sourceLabel)
                    LabeledContent("Indexed photos", value: model.assets.count.formatted())
                    LabeledContent("Geotagged", value: model.assets.filter { $0.location != nil }.count.formatted())
                    LabeledContent("Offline city database", value: "\(GeoDatabase.shared.cityCount.formatted()) cities")
                    if model.source != .library {
                        Button("Index My Library") { Task { await model.connectLibrary(); dismiss() } }
                    } else {
                        Button("Re-scan Library") { model.startIndexing() }.disabled(model.isIndexing)
                        if LibraryIndexer.isLimited {
                            Button("Manage Selected Photos") { LimitedLibraryPicker.present() }
                        }
                    }
                    Button("Load Demo Atlas") { model.loadDemo(); dismiss() }
                } header: {
                    Text("Library")
                } footer: {
                    if model.source == .library && LibraryIndexer.isLimited {
                        Text("ChromAtlas can see only the photos you selected. New selections are indexed automatically.")
                    }
                }
                Section("Globe") {
                    Picker("Arc color", selection: $model.arcColorMode) {
                        ForEach(ArcColorMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if let home = model.analysis.home {
                        LabeledContent("Home base", value: home.city?.label ?? "Unknown")
                    }
                    LabeledContent("Trips detected", value: "\(model.analysis.trips.count)")
                }
                Section("Badges") {
                    ForEach(model.analysis.badges) { b in
                        HStack {
                            Label(b.title, systemImage: b.symbol).foregroundStyle(b.unlocked ? Theme.amber : Theme.textSecondary)
                            Spacer()
                            Text(b.unlocked ? "Unlocked" : "\(min(b.progress, b.goal).formatted()) / \(b.goal.formatted())")
                                .font(Theme.mono(.footnote, .medium)).foregroundStyle(Theme.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    LabeledContent("Last query", value: String(format: "%.2f ms", model.result.elapsedMs))
                    LabeledContent("Network access", value: "None")
                } header: { Text("Privacy & Performance") } footer: {
                    Text("ChromAtlas makes no network requests. Thumbnails are read from the on-device library only; iCloud originals are never downloaded. The index lives in the app sandbox and is excluded from backups.")
                }
                Section {
                    Button("Delete Index", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete the on-device index?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete Index", role: .destructive) { model.resetIndex(); dismiss() }
            } message: {
                Text("Your photos are not touched. Colors, places and trips will be rebuilt the next time you index.")
            }
        }
    }

    private var sourceLabel: String {
        switch model.source {
        case .none: return "Not connected"
        case .library: return LibraryIndexer.isLimited ? "Selected Photos" : "Photo Library"
        case .demo: return "Demo Atlas"
        }
    }
}

/// Presents the system picker that lets a limited-access user change which photos ChromAtlas can read.
enum LimitedLibraryPicker {
    @MainActor static func present() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}
