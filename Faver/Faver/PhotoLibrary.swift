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

    var toReviewCount: Int { filtered.reduce(0) { $0 + $1.count } }

    var reviewedFraction: Double {
        guard totalAssets > 0 else { return 0 }
        return Double(totalAssets - toReviewCount) / Double(totalAssets)
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
            // Phase 1 — enumerate assets off the main thread (no property access).
            let (total, allAssets): (Int, [PHAsset]) = await Task.detached(priority: .userInitiated) {
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                let result = PHAsset.fetchAssets(with: options)
                var assets: [PHAsset] = []
                assets.reserveCapacity(result.count)
                result.enumerateObjects { asset, _, _ in assets.append(asset) }
                return (result.count, assets)
            }.value

            // Phase 2 — clustering on @MainActor (PHAsset property access is @MainActor in iOS 26).
            loadProgress = 0.88
            let built: [PhotoCluster]
            switch mode {
            case .smart:
                built = buildSmartClusters(from: allAssets, reviewedIDs: reviewedIDs, sensitivity: sensitivity)
            case .fixed:
                built = buildClusters(from: allAssets, reviewedIDs: reviewedIDs, gapThreshold: gap.threshold)
            }

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
