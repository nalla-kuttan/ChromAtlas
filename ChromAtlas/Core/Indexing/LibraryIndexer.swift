import BackgroundTasks
import CoreLocation
import Foundation
import Photos
import UIKit

/// Incrementally indexes the user's photo library entirely on-device.
///
/// - Recent assets first, so the UI populates within the first couple of seconds.
/// - 64×64 `.fastFormat` thumbnails, never downloaded from iCloud (`isNetworkAccessAllowed = false`).
/// - Worker count throttles with `ProcessInfo.thermalState`.
/// - Screenshots are skipped entirely (they carry neither travel nor mood signal).
final class LibraryIndexer: @unchecked Sendable {
    struct Progress: Sendable {
        var processed: Int
        var total: Int
        var photosPerSecond: Double
        var thermalThrottled: Bool
    }

    static let taskIdentifier = "app.chromatlas.index"
    static let thumbnailSide: CGFloat = 64
    static let chunkSize = 96

    private let store: AssetStore
    private var cancelled = false
    private let lock = NSLock()

    init(store: AssetStore) { self.store = store }

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    static var isAuthorized: Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return s == .authorized || s == .limited
    }

    static var isDenied: Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return s == .denied || s == .restricted
    }

    static var isLimited: Bool { PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited }

    static func requestAuthorization() async -> Bool {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return s == .authorized || s == .limited
    }

    private static func fetchOptions() -> PHFetchOptions {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.predicate = NSPredicate(format: "(mediaSubtypes & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        o.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
        return o
    }

    /// Indexes everything not yet in the store and removes rows whose assets were deleted.
    /// `onBatch` is called with each newly indexed batch and the removed identifiers.
    func run(onBatch: @escaping @Sendable ([AssetRecord], [String], Progress) -> Void) async {
        guard LibraryIndexer.isAuthorized else { return }
        let known = (try? store.allIdentifiers()) ?? []
        let result = PHAsset.fetchAssets(with: .image, options: LibraryIndexer.fetchOptions())

        var current = Set<String>()
        var pending: [PHAsset] = []
        current.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            current.insert(asset.localIdentifier)
            if !known.contains(asset.localIdentifier) { pending.append(asset) }
        }
        let removed = known.filter { !$0.hasPrefix("demo:") && !current.contains($0) }
        if !removed.isEmpty { try? store.delete(ids: Array(removed)) }

        let total = pending.count
        let start = CFAbsoluteTimeGetCurrent()
        var processed = 0
        if total == 0 {
            onBatch([], Array(removed), Progress(processed: 0, total: 0, photosPerSecond: 0, thermalThrottled: false))
            return
        }
        var first = true

        for chunkStart in stride(from: 0, to: total, by: LibraryIndexer.chunkSize) {
            if isCancelled || Task.isCancelled { break }
            let thermal = ProcessInfo.processInfo.thermalState
            if thermal == .critical { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            let workers: Int
            switch thermal {
            case .nominal, .fair: workers = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
            case .serious: workers = 1
            default: workers = 1
            }
            let chunk = Array(pending[chunkStart..<min(total, chunkStart + LibraryIndexer.chunkSize)])
            let records = await LibraryIndexer.process(chunk, workers: workers)
            try? store.upsert(records)
            processed += chunk.count
            let elapsed = max(0.001, CFAbsoluteTimeGetCurrent() - start)
            onBatch(records, first ? Array(removed) : [],
                    Progress(processed: processed, total: total, photosPerSecond: Double(processed) / elapsed,
                             thermalThrottled: thermal == .serious || thermal == .critical))
            first = false
            if thermal == .serious { try? await Task.sleep(nanoseconds: 50_000_000) }
        }
    }

    private static func process(_ assets: [PHAsset], workers: Int) async -> [AssetRecord] {
        await withTaskGroup(of: [AssetRecord].self) { group in
            let slice = max(1, (assets.count + workers - 1) / workers)
            for start in stride(from: 0, to: assets.count, by: slice) {
                let part = Array(assets[start..<min(assets.count, start + slice)])
                group.addTask { part.compactMap(index(_:)) }
            }
            var all: [AssetRecord] = []
            for await r in group { all += r }
            return all
        }
    }

    private static func index(_ asset: PHAsset) -> AssetRecord? {
        let opts = PHImageRequestOptions()
        opts.isSynchronous = true
        opts.deliveryMode = .fastFormat
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = false      // zero-network: never pull originals from iCloud
        opts.version = .current
        var cg: CGImage?
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: thumbnailSide, height: thumbnailSide),
            contentMode: .aspectFill, options: opts
        ) { image, _ in cg = image?.cgImage }

        let colors = cg.map { ColorExtractor.dominantColors(of: $0) } ?? []
        let loc = asset.location.flatMap { l -> GeoPoint? in
            let c = l.coordinate
            guard CLLocationCoordinate2DIsValid(c), !(c.latitude == 0 && c.longitude == 0) else { return nil }
            return GeoPoint(lat: c.latitude, lon: c.longitude)
        }
        return AssetRecord.make(id: asset.localIdentifier, date: asset.creationDate ?? Date(), location: loc, colors: colors)
    }

    // MARK: - Background processing

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGProcessingTask, let store = try? AssetStore() else {
                task.setTaskCompleted(success: false); return
            }
            let indexer = LibraryIndexer(store: store)
            let work = Task {
                await indexer.run { _, _, _ in }
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                indexer.cancel()
                work.cancel()
            }
        }
    }

    static func scheduleBackgroundTask() {
        let req = BGProcessingTaskRequest(identifier: taskIdentifier)
        req.requiresNetworkConnectivity = false
        req.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(req)
    }
}

/// Relays photo-library changes (new photos, deletions) so the index stays incremental.
final class LibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: @Sendable () -> Void
    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        PHPhotoLibrary.shared().register(self)
    }
    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    func photoLibraryDidChange(_ changeInstance: PHChange) { onChange() }
}
