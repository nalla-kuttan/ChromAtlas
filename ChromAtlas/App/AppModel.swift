import Foundation
import Observation
import SwiftUI

enum LibrarySource: String { case none, library, demo }
enum ArcColorMode: String, CaseIterable, Identifiable {
    case chronological = "Chronology"
    case palette = "Active Palette"
    var id: String { rawValue }
}

enum Chapter: Identifiable, Hashable {
    case trip(Trip)
    case year(Int, ClosedRange<TimeInterval>)
    case aesthetic(name: String, hue: Double, saturation: Double)

    var id: String {
        switch self {
        case .trip(let t): return "trip-\(t.id)"
        case .year(let y, _): return "year-\(y)"
        case .aesthetic(let n, _, _): return "aes-\(n)"
        }
    }
}

@MainActor
enum AppTab: Hashable { case atlas, palette }

@Observable
final class AppModel {
    // MARK: Data
    private(set) var assets: [AssetRecord] = []
    private(set) var analysis: TripAnalysis = .empty
    private(set) var result = QueryEngine.Result()
    private(set) var chapters: [Chapter] = []
    private(set) var monthlyDensity: [(month: Date, count: Int)] = []
    private(set) var dateSpan: ClosedRange<TimeInterval> = 0...1
    private(set) var dataVersion = 0
    private(set) var resultVersion = 0
    private(set) var cityCounts: [Int: Int] = [:]

    // MARK: Filter
    var filter = FilterState() { didSet { if filter != oldValue { scheduleQuery() } } }
    var arcColorMode: ArcColorMode = .chronological

    // MARK: UI state
    private(set) var source: LibrarySource
    private(set) var isIndexing = false
    private(set) var progress: LibraryIndexer.Progress?
    private(set) var lastError: String?
    /// True after the user declined photo access; onboarding then offers Settings instead of a request iOS won't show again.
    private(set) var photoAccessDenied = false
    var focus: GeoPoint?
    var focusToken = 0
    var selectedAsset: AssetRecord?
    var showMap = false
    var showShare = false
    var showSettings = false
    /// Selected iPhone tab. Both tabs share one filter, so a color picked in Palette also narrows the globe.
    var tab: AppTab = .atlas

    @ObservationIgnored private var engine = QueryEngine()
    @ObservationIgnored private var store: AssetStore?
    @ObservationIgnored private var indexer: LibraryIndexer?
    @ObservationIgnored private var observer: LibraryChangeObserver?
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    @ObservationIgnored private var lastQueryAt: CFAbsoluteTime = 0
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var lastRebuildAt: CFAbsoluteTime = 0
    @ObservationIgnored private var pendingRebuild: Task<Void, Never>?

    init() {
        source = LibrarySource(rawValue: UserDefaults.standard.string(forKey: "source") ?? "") ?? .none
        do { store = try AssetStore() } catch {
            print("AssetStore failed to open: \(error)")
            lastError = "ChromAtlas couldn't open its on-device index. Delete the index in Settings, or reinstall the app if this keeps happening."
        }
    }

    func bootstrap() async {
        _ = GeoDatabase.shared
        refreshPhotoAccess()
        if let stored = try? store?.loadAll(), !stored.isEmpty {
            assets = stored
            rebuild(analyze: true)
        }
        switch source {
        case .library where LibraryIndexer.isAuthorized: startIndexing()
        case .demo where assets.isEmpty: loadDemo()
        default: break
        }
    }

    // MARK: Sources

    func connectLibrary() async {
        guard await LibraryIndexer.requestAuthorization() else {
            photoAccessDenied = true
            lastError = Self.accessDeniedMessage
            return
        }
        photoAccessDenied = false
        lastError = nil
        if source == .demo { try? store?.deleteAll(demoOnly: true); assets.removeAll { $0.isDemo } }
        setSource(.library)
        rebuild(analyze: true)
        startIndexing()
    }

    private static let accessDeniedMessage = "Photo access is off. Turn it on in Settings to index your library, or explore the demo atlas."

    /// Re-reads photo authorization, e.g. when returning from the Settings app.
    func refreshPhotoAccess() {
        photoAccessDenied = LibraryIndexer.isDenied
        if photoAccessDenied, lastError == nil { lastError = Self.accessDeniedMessage }
        if !photoAccessDenied, lastError == Self.accessDeniedMessage { lastError = nil }
    }

    func loadDemo() {
        indexer?.cancel()
        isIndexing = false
        try? store?.deleteAll(demoOnly: false)
        let demo = DemoLibrary.generate()
        assets = demo
        try? store?.upsert(demo)
        setSource(.demo)
        filter = FilterState()
        rebuild(analyze: true)
    }

    func resetIndex() {
        indexer?.cancel()
        isIndexing = false
        try? store?.deleteAll(demoOnly: false)
        assets = []
        analysis = .empty
        filter = FilterState()
        setSource(.none)
        rebuild(analyze: false)
    }

    private func setSource(_ s: LibrarySource) {
        source = s
        UserDefaults.standard.set(s.rawValue, forKey: "source")
    }

    // MARK: Indexing

    func startIndexing() {
        guard let store, !isIndexing else { return }
        isIndexing = true
        let indexer = LibraryIndexer(store: store)
        self.indexer = indexer
        if observer == nil {
            observer = LibraryChangeObserver { [weak self] in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    self?.startIndexing()
                }
            }
        }
        Task.detached(priority: .userInitiated) {
            await indexer.run { records, removed, progress in
                Task { @MainActor [weak self] in self?.ingest(records, removed: removed, progress: progress) }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isIndexing = false
                self.progress = nil
                self.rebuild(analyze: true)
            }
        }
    }

    func appDidEnterBackground() {
        if source == .library { LibraryIndexer.scheduleBackgroundTask() }
    }

    private func ingest(_ records: [AssetRecord], removed: [String], progress: LibraryIndexer.Progress) {
        self.progress = progress.total > 0 ? progress : nil
        if !removed.isEmpty {
            let gone = Set(removed)
            assets.removeAll { gone.contains($0.id) }
        }
        guard !records.isEmpty || !removed.isEmpty else { return }
        assets.append(contentsOf: records)
        // Progressive population: rebuild immediately for the first batch, then at most every 0.6 s.
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastRebuildAt > 0.6 {
            rebuild(analyze: true)
        } else if pendingRebuild == nil {
            pendingRebuild = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                self.pendingRebuild = nil
                self.rebuild(analyze: true)
            }
        }
    }

    // MARK: Derived data

    private func rebuild(analyze: Bool) {
        lastRebuildAt = CFAbsoluteTimeGetCurrent()
        assets.sort { $0.timestamp < $1.timestamp }
        engine = QueryEngine(assets)
        dataVersion += 1
        computeTimeline()
        runQuery()
        guard analyze else { return }
        analysisTask?.cancel()
        let snapshot = assets
        analysisTask = Task.detached(priority: .utility) {
            let a = TripEngine.analyze(snapshot)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in self?.apply(analysis: a) }
        }
    }

    private func apply(analysis a: TripAnalysis) {
        analysis = a
        var changed: [String: Int?] = [:]
        for i in assets.indices {
            let t = a.assetTrip[assets[i].id]
            if assets[i].tripID != t { assets[i].tripID = t; changed[assets[i].id] = t }
        }
        if !changed.isEmpty {
            try? store?.updateTrips(changed)
            engine = QueryEngine(assets)
        }
        dataVersion += 1
        computeChapters()
        runQuery()
    }

    private func computeTimeline() {
        guard let first = assets.first?.timestamp, let last = assets.last?.timestamp else {
            dateSpan = 0...1; monthlyDensity = []; cityCounts = [:]; return
        }
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: cal.dateComponents([.year], from: Date(timeIntervalSince1970: first)))!
        var endComps = cal.dateComponents([.year], from: Date(timeIntervalSince1970: last))
        endComps.year! += 1
        let end = cal.date(from: endComps)!
        dateSpan = start.timeIntervalSince1970...end.timeIntervalSince1970

        var perCity: [Int: Int] = [:]
        for a in assets { if let c = a.cityID { perCity[c, default: 0] += 1 } }
        cityCounts = perCity

        var counts: [Int: Int] = [:]
        for a in assets {
            let c = cal.dateComponents([.year, .month], from: a.date)
            counts[c.year! * 12 + c.month! - 1, default: 0] += 1
        }
        var out: [(Date, Int)] = []
        var m = start
        while m < end {
            let c = cal.dateComponents([.year, .month], from: m)
            out.append((m, counts[c.year! * 12 + c.month! - 1] ?? 0))
            m = cal.date(byAdding: .month, value: 1, to: m)!
        }
        monthlyDensity = out
    }

    private func computeChapters() {
        var out: [Chapter] = analysis.trips
            .filter { $0.stops.filter { !$0.isLayover }.count >= 1 }
            .map { Chapter.trip($0) }

        // Aesthetic clusters: the heaviest hue zones across the whole library.
        var zoneWeight = [Double](repeating: 0, count: ChromaticZone.zones.count)
        var zoneChroma = [Double](repeating: 0, count: ChromaticZone.zones.count)
        for a in assets {
            for c in a.colors where c.lab.chroma > 0.06 {
                let z = ChromaticZone.zoneIndex(hue: c.lab.hueDegrees)
                zoneWeight[z] += c.weight * c.lab.chroma
                zoneChroma[z] += c.weight * c.lab.chroma * c.lab.chroma
            }
        }
        let top = zoneWeight.indices.sorted { zoneWeight[$0] > zoneWeight[$1] }.prefix(4).filter { zoneWeight[$0] > 0 }
        for z in top {
            let zone = ChromaticZone.zones[z]
            let hue = (zone.start + zone.end) / 2
            let chroma = zoneChroma[z] / max(zoneWeight[z], 1e-9)
            out.append(.aesthetic(name: zone.name, hue: hue, saturation: min(1, chroma / ColorSelection.maxChroma)))
        }

        let cal = Calendar(identifier: .gregorian)
        let years = Set(assets.map { cal.component(.year, from: $0.date) }).sorted()
        for y in years {
            let s = cal.date(from: DateComponents(year: y, month: 1, day: 1))!.timeIntervalSince1970
            let e = cal.date(from: DateComponents(year: y + 1, month: 1, day: 1))!.timeIntervalSince1970 - 1
            out.append(.year(y, s...e))
        }
        chapters = out
    }

    // MARK: Querying

    private func scheduleQuery() {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastQueryAt >= 0.032 {
            runQuery()
        } else if queryTask == nil {
            queryTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 32_000_000)
                self.queryTask = nil
                self.runQuery()
            }
        }
    }

    private func runQuery() {
        lastQueryAt = CFAbsoluteTimeGetCurrent()
        result = engine.run(filter)
        resultVersion += 1
    }

    func asset(at index: Int32) -> AssetRecord { assets[Int(index)] }

    var matchedAssets: [AssetRecord] { result.matches.map { assets[Int($0)] } }

    // MARK: Actions

    func apply(_ chapter: Chapter) {
        switch chapter {
        case .trip(let t):
            if filter.tripID == t.id { filter.tripID = nil; return }
            filter.tripID = t.id
            filter.timeRange = nil
            focusGlobe(on: t.center)
        case .year(_, let range):
            filter.tripID = nil
            filter.timeRange = filter.timeRange == range ? nil : range
        case .aesthetic(_, let hue, let sat):
            let sel = ColorSelection(hue: hue, saturation: max(sat, 0.3))
            filter.color = filter.color == sel ? nil : sel
        }
    }

    func isActive(_ chapter: Chapter) -> Bool {
        switch chapter {
        case .trip(let t): return filter.tripID == t.id
        case .year(_, let r): return filter.timeRange == r
        case .aesthetic(_, let h, let s): return filter.color == ColorSelection(hue: h, saturation: max(s, 0.3))
        }
    }

    func focusGlobe(on p: GeoPoint) {
        focus = p
        focusToken += 1
    }

    func selectCity(_ id: Int) {
        if filter.cityID == id { filter.cityID = nil; return }
        filter.cityID = id
        if let c = GeoDatabase.shared.city(id: id) { focusGlobe(on: c.location) }
    }

    func clearAllFilters() { filter = FilterState() }

    /// Visible label for the active colour selection (wheel callout pill).
    var colorCallout: String {
        guard let c = filter.color else {
            if filter.luminance != 0...1 { return luminanceLabel }
            return "All Colors"
        }
        if c.isNeutral {
            let mid = (filter.luminance.lowerBound + filter.luminance.upperBound) / 2
            return ChromaticZone.name(hue: c.hue, chroma: 0, lightness: filter.luminance == 0...1 ? nil : mid)
        }
        let base = ChromaticZone.name(hue: c.hue, chroma: c.targetChroma)
        switch filter.effectiveHarmony {
        case .complementary:
            let other = ChromaticZone.shortName(hue: c.hue + 180, chroma: c.targetChroma)
            return "\(ChromaticZone.shortName(hue: c.hue, chroma: c.targetChroma)) + \(other)"
        case .analogous: return "\(base) · Analogous"
        default: return base
        }
    }

    private var luminanceLabel: String {
        let l = filter.luminance
        if l.upperBound <= 0.4 { return "Low-Key Shadows" }
        if l.lowerBound >= 0.65 { return "High-Key / Pastel" }
        return "Luminance \(Int(l.lowerBound * 100))–\(Int(l.upperBound * 100))"
    }
}

// MARK: - Filter descriptions

extension AppModel {
    /// The trip or years, and the city or country, currently narrowing results ("2018 – Japan Circuit", "Lisbon, Portugal").
    var timePlaceDescriptions: [String] {
        var parts: [String] = []
        if let id = filter.tripID, let trip = analysis.trips.first(where: { $0.id == id }) {
            parts.append(trip.title)
        } else if let r = filter.timeRange {
            let cal = Calendar.current
            let y0 = cal.component(.year, from: Date(timeIntervalSince1970: r.lowerBound))
            let y1 = cal.component(.year, from: Date(timeIntervalSince1970: r.upperBound))
            parts.append(y0 == y1 ? String(y0) : "\(y0)–\(y1)")
        }
        if let id = filter.cityID, let city = GeoDatabase.shared.city(id: id) {
            parts.append(city.label)
        } else if let code = filter.countryCode {
            parts.append(Countries.info(code).name)
        }
        return parts
    }

    /// Every active filter in words, for empty states ("Warm Amber", "Winter", "2018 – Japan Circuit").
    var activeFilterDescriptions: [String] {
        var parts: [String] = []
        if filter.hasColorFilter { parts.append(colorCallout) }
        parts += Season.allCases.filter { filter.seasons.contains($0) }.map(\.label)
        parts += SolarPhase.allCases.filter { filter.phases.contains($0) }.map(\.label)
        return parts + timePlaceDescriptions
    }
}

