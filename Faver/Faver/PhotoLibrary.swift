import Combine
import Photos
import SwiftUI

@MainActor
final class LibraryService: ObservableObject {

    @Published var authorizationStatus: PHAuthorizationStatus =
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var clusters: [PhotoCluster] = []
    @Published var totalAssets: Int = 0
    @Published var isLoading: Bool = false
    @Published var loadProgress: Double = 0
    /// Minimum total-photo count a cluster must have to appear in the UI.
    @Published var minSize: Int = max(1, UserDefaults.standard.integer(forKey: "minSetSize"))

    init() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            isLoading = true
        }
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
            load()
        } else {
            isLoading = false
        }
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

    func favorite(_ asset: PHAsset, on: Bool) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest(for: asset).isFavorite = on
        }, completionHandler: { _, _ in })
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
