import Combine
import Photos
import SwiftUI

@MainActor
class PhotoLibraryService: ObservableObject {

    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var clusters: [PhotoCluster] = []
    @Published var totalCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var scanProgress: Double = 0

    /// Minimum total-photo count a cluster must have to appear in the UI.
    /// Changing this is instant — no reload needed.
    @Published var minSetSizeMinimum: Int = max(1, UserDefaults.standard.integer(forKey: "minSetSize"))

    init() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            isLoading = true
            // loadAssets() is NOT called here — the view triggers it via .task
            // after the first frame renders, keeping init() instant.
        }
    }

    var toReviewCount: Int { clusters.reduce(0) { $0 + $1.count } }

    /// Clusters visible under the current size filter — used for all display logic.
    var filteredClusters: [PhotoCluster] {
        minSetSizeMinimum <= 1
            ? clusters
            : clusters.filter { $0.totalInWindow >= minSetSizeMinimum }
    }

    /// Clusters grouped into years, newest first — for the home screen
    var years: [YearSummary] { yearSummaries(from: filteredClusters) }

    /// Clusters for a specific year, grouped by month, newest first
    func monthSections(for year: Int) -> [MonthSection] {
        let calendar = Calendar.current
        let yearClusters = filteredClusters.filter {
            calendar.component(.year, from: $0.anchorDate ?? Date()) == year
        }
        return groupByMonth(yearClusters)
    }

    func requestAccess() async {
        // Show loading state immediately — iOS can take 5-10 s to initialise
        // the Photos framework on first authorisation, leaving the welcome screen
        // blank with no feedback. Setting isLoading here gives visual response
        // before the await returns.
        isLoading = true
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        if status == .authorized || status == .limited {
            loadAssets()
        } else {
            isLoading = false
        }
    }

    func loadAssets() {
        isLoading = true
        scanProgress = 0

        // Read all @MainActor-isolated state before crossing any async boundary
        let reviewedIDs = ReviewStore.shared.reviewedIDs
        let modeRaw = UserDefaults.standard.string(forKey: "clusterMode") ?? ClusterMode.smart.rawValue
        let mode = ClusterMode(rawValue: modeRaw) ?? .smart
        let gapRaw = UserDefaults.standard.string(forKey: "clusterGap") ?? ClusterGap.medium.rawValue
        let gap = ClusterGap(rawValue: gapRaw) ?? .medium
        let sensitivityRaw = UserDefaults.standard.string(forKey: "smartSensitivity") ?? SmartSensitivity.balanced.rawValue
        let sensitivity = SmartSensitivity(rawValue: sensitivityRaw) ?? .balanced

        Task {
            // Phase 1: enumerate assets off the main thread (no PHAsset property access here)
            let (total, allAssets): (Int, [PHAsset]) = await Task.detached(priority: .userInitiated) {
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                let result = PHAsset.fetchAssets(with: options)
                var assets: [PHAsset] = []
                assets.reserveCapacity(result.count)
                result.enumerateObjects { asset, _, _ in assets.append(asset) }
                return (result.count, assets)
            }.value

            // Phase 2: clustering — runs on @MainActor because PHAsset property
            // access (creationDate, location, isFavorite) is @MainActor-isolated in iOS 26
            scanProgress = 0.88
            let built: [PhotoCluster]
            switch mode {
            case .smart:
                built = buildSmartClusters(from: allAssets, reviewedIDs: reviewedIDs, sensitivity: sensitivity)
            case .fixed:
                built = buildClusters(from: allAssets, reviewedIDs: reviewedIDs, gapThreshold: gap.threshold)
            }

            totalCount = total
            clusters = built
            scanProgress = 1.0
            isLoading = false
        }
    }

    func toggleFavorite(asset: PHAsset, newValue: Bool) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest(for: asset).isFavorite = newValue
        }, completionHandler: { _, _ in })
    }

    func markReviewed(_ asset: PHAsset) {
        ReviewStore.shared.markReviewed(asset.localIdentifier)
    }

    /// Up to `count` representative assets for the given year — one from each of
    /// the first visible clusters of that year, for the year card collage.
    func sampleAssets(for year: Int, count: Int = 3) -> [PHAsset] {
        let calendar = Calendar.current
        let yearClusters = filteredClusters.filter {
            calendar.component(.year, from: $0.anchorDate ?? Date()) == year
        }
        return yearClusters.prefix(count).compactMap { $0.assetsToReview.first }
    }
}
