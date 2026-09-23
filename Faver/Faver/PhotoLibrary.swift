import Combine
import Photos
import PhotosUI
import SwiftUI

@MainActor
final class LibraryService: NSObject, ObservableObject {

    @Published var authorizationStatus: PHAuthorizationStatus =
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var clusters: [PhotoCluster] = []
    @Published var totalAssets: Int = 0
    @Published var isLoading: Bool = false
    @Published var loadProgress: Double = 0
    /// Minimum total-photo count a cluster must have to appear in the UI.
    @Published var minSize: Int = max(1, UserDefaults.standard.integer(forKey: "minSetSize"))

    /// Set when the photo library changed under us. Acted on when the app comes back to
    /// the foreground rather than immediately, because Faver's own favorite writes are
    /// changes too — reloading on every one would re-cluster the whole library on every
    /// heart tap.
    private var needsReload = false

    override init() {
        super.init()
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            isLoading = true
            PHPhotoLibrary.shared().register(self)
        }
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - Derived state

    var filtered: [PhotoCluster] {
        minSize <= 1 ? clusters : clusters.filter { $0.totalInWindow >= minSize }
    }

    /// Photos still to review, within whatever the minimum-size filter is showing.
    var toReviewCount: Int { filtered.reduce(0) { $0 + $1.count } }

    /// Moments still to review. Not the same number as `toReviewCount`, which counts
    /// photos — the two were being used interchangeably, and the home screen said
    /// "12,438 moments" when it meant photos.
    var momentCount: Int { filtered.count }

    /// Progress through the whole library, deliberately ignoring the minimum-size
    /// filter. Hiding small sets from view is not the same as having reviewed them,
    /// and counting it as progress would quietly inflate the number.
    var reviewedFraction: Double {
        guard totalAssets > 0 else { return 0 }
        let remaining = clusters.reduce(0) { $0 + $1.count }
        return Double(totalAssets - remaining) / Double(totalAssets)
    }

    /// Top-5 clusters ranked by engagement potential (size × GPS × nostalgia).
    var suggested: [PhotoCluster] {
        Array(filtered.sorted { rank($0) > rank($1) }.prefix(5))
    }

    func yearSections() -> [YearSummary] { yearSummaries(from: filtered) }

    func monthSections(for year: Int) -> [MonthSection] {
        let cal = Calendar.current
        let yearClusters = filtered.filter {
            cal.component(.year, from: $0.anchorDate ?? Date()) == year
        }
        return groupByMonth(yearClusters)
    }

    // MARK: - Access

    func requestAccess() async {
        isLoading = true
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        if status == .authorized || status == .limited {
            PHPhotoLibrary.shared().register(self)
            load()
        } else {
            isLoading = false
        }
    }

    /// True when Faver can only see a hand-picked subset. The promise of a complete pass
    /// over the library quietly means something much smaller here, so the app has to say
    /// so and offer a way to widen it.
    var hasLimitedAccess: Bool { authorizationStatus == .limited }

    func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }

    /// Called when the app comes back to the foreground. Photos taken since it was last
    /// opened, and favorites set in the Photos app, used to need a kill and relaunch.
    func reloadIfNeeded() {
        guard needsReload, !isLoading else { return }
        needsReload = false
        load()
    }

    // MARK: - Load

    func load() {
        isLoading = true
        loadProgress = 0

        // Read all settings eagerly on @MainActor before any async boundary.
        let reviewedIDs = ReviewStore.shared.reviewedIDs
        let modeRaw = UserDefaults.standard.string(forKey: "clusterMode") ?? ClusterMode.smart.rawValue
        let mode = ClusterMode(rawValue: modeRaw) ?? .smart
        let gapRaw = UserDefaults.standard.string(forKey: "clusterGap") ?? ClusterGap.medium.rawValue
        let gap = ClusterGap(rawValue: gapRaw) ?? .medium
        let sensitivityRaw = UserDefaults.standard.string(forKey: "smartSensitivity") ?? SmartSensitivity.balanced.rawValue
        let sensitivity = SmartSensitivity(rawValue: sensitivityRaw) ?? .balanced
        let includeScreenshots = UserDefaults.standard.bool(forKey: "includeScreenshots")

        Task {
            // Fetching and clustering happen in one detached pass. Clustering used to
            // run back on the main actor, reading creationDate, isFavorite and location
            // on every asset in the library, twice — on launch, on every settings
            // change, and after every single moment reviewed. On a large library that
            // is the price of finishing one moment, paid as a frozen screen, while the
            // spinner meant to reassure the user could not even turn.
            let (total, built): (Int, [PhotoCluster]) = await Task.detached(priority: .userInitiated) {
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                // Screenshots are the single biggest source of clutter in a camera roll
                // and nobody wants to be asked whether a screenshot of a receipt is a
                // favourite. Filtered in the fetch rather than afterwards, so they never
                // reach clustering and never count towards progress either.
                if !includeScreenshots {
                    options.predicate = NSPredicate(
                        format: "NOT ((mediaSubtypes & %d) != 0)",
                        PHAssetMediaSubtype.photoScreenshot.rawValue
                    )
                }
                let result = PHAsset.fetchAssets(with: options)
                var assets: [PHAsset] = []
                assets.reserveCapacity(result.count)
                result.enumerateObjects { asset, _, _ in assets.append(asset) }

                switch mode {
                case .smart:
                    return (result.count, buildSmartClusters(from: assets, reviewedIDs: reviewedIDs, sensitivity: sensitivity))
                case .fixed:
                    return (result.count, buildClusters(from: assets, reviewedIDs: reviewedIDs, gapThreshold: gap.threshold))
                }
            }.value

            totalAssets = total
            clusters = built
            loadProgress = 1.0
            isLoading = false
        }
    }

    // MARK: - Mutations

    /// Reports whether the write actually landed. The result used to be discarded, so
    /// the heart filled in whether or not the photo library accepted the change and the
    /// user had no way to know a favourite had been lost.
    func favorite(_ asset: PHAsset, on: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest(for: asset).isFavorite = on
            }, completionHandler: { success, _ in
                continuation.resume(returning: success)
            })
        }
    }

    /// Puts the queue back to full. See ReviewStore.reset().
    func startOver() {
        ReviewStore.shared.reset()
        load()
    }

    func markSeen(_ asset: PHAsset) {
        ReviewStore.shared.markReviewed(asset.localIdentifier)
    }

    // MARK: - Ranking

    private func rank(_ c: PhotoCluster) -> Double {
        var s = Double(c.totalInWindow)
        if c.firstLocationAsset?.location != nil { s *= 1.3 }
        if let d = c.anchorDate {
            let ago = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
            let days = abs(d.timeIntervalSince(ago)) / 86400
            if days < 14 { s *= 2.0 } else if days < 30 { s *= 1.5 }
        }
        return s
    }
}

// MARK: - Photo library changes

extension LibraryService: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            needsReload = true
        }
    }
}
