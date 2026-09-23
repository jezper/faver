import CoreLocation
import Photos

// MARK: - PhotoCluster

/// Unchecked Sendable on purpose. PHAsset is a read-only snapshot whose properties are
/// fixed when it is fetched, and the Photos framework hands the same instance to every
/// thread that asks. That makes it safe to read off the main actor, which is what lets
/// clustering run without freezing the app.
nonisolated struct PhotoCluster: Identifiable, @unchecked Sendable {
    let id: String
    /// Every photo in the time window, reviewed or not. What the archive shows.
    let allAssets: [PHAsset]
    let assetsToReview: [PHAsset]
    /// `assetsToReview` folded into burst sets. Computed once when the cluster is built,
    /// off the main actor, rather than on every render of the review screen.
    let units: [ReviewUnit]
    let totalInWindow: Int
    let anchorDate: Date?
    let firstLocationAsset: PHAsset?

    var count: Int { assetsToReview.count }

    /// A moment is reviewed once it has been through the last step, which marks all of
    /// it at once. There is no half-reviewed moment.
    var isReviewed: Bool { assetsToReview.isEmpty }

    var reviewedPercent: Int {
        guard totalInWindow > 0 else { return 0 }
        let done = totalInWindow - assetsToReview.count
        return Int((Double(done) / Double(totalInWindow)) * 100)
    }

    /// E.g. "Thursday afternoon"
    var title: String {
        guard let date = anchorDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return "\(formatter.string(from: date)) \(timeOfDay(for: date))"
    }

    /// E.g. "Jan 7, 2010"
    var dateLabel: String {
        guard let date = anchorDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func timeOfDay(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default:      return "night"
        }
    }
}

// MARK: - ReviewUnit

/// One position in the review pager: a single photo, or a burst of photos taken within
/// a few seconds of each other.
///
/// Twelve near-identical shots of the same thing used to cost twelve swipes and twelve
/// full-size image loads, which is exactly where reviewing stops feeling like looking at
/// your life and starts feeling like a chore. A burst is one thing to decide about, so
/// it occupies one horizontal position and opens downwards.
nonisolated struct ReviewUnit: Identifiable, @unchecked Sendable {
    let id: String
    let assets: [PHAsset]

    var isBurst: Bool { assets.count > 1 }
}


// MARK: - Grouping structures

nonisolated struct MonthSection: Identifiable {
    let id: String         // "2010-01"
    let title: String      // "January 2010"
    let clusters: [PhotoCluster]
}

nonisolated struct YearSummary: Identifiable {
    let id: Int            // year number
    let year: Int
    let clusterCount: Int
    let toReviewCount: Int
}

// MARK: - SmartSensitivity

/// Controls how aggressively Smart mode splits photos into separate sets.
/// Expressed in human terms, not algorithm parameters.
nonisolated enum SmartSensitivity: String, CaseIterable {
    case tight, balanced, loose

    var label: String {
        switch self {
        case .tight:    return "Tight"
        case .balanced: return "Balanced"
        case .loose:    return "Loose"
        }
    }

    var description: String {
        switch self {
        case .tight:    return "Smaller sets. Best when your moments are close together in time or space."
        case .balanced: return "Works well for most libraries."
        case .loose:    return "Larger sets. Best for wide venues — beaches, ski mountains, festivals."
        }
    }

    /// How far you need to move (from your last photo) before it counts as a new place.
    var locationThreshold: CLLocationDistance {
        switch self {
        case .tight:    return 1500   // 1.5 km
        case .balanced: return 3000   // 3 km
        case .loose:    return 5000   // 5 km
        }
    }

    /// How long you need to have paused before a location change triggers a split.
    var minPauseTime: TimeInterval {
        switch self {
        case .tight:    return 120   // 2 min
        case .balanced: return 180   // 3 min
        case .loose:    return 480   // 8 min
        }
    }
}

// MARK: - MinSetSize

/// Filter that hides clusters smaller than a given total-photo threshold.
/// Uses `totalInWindow` (all photos in the time window, not just unreviewed)
/// so a 100-photo vacation still shows even if 60 are already reviewed.
nonisolated enum MinSetSize: Int, CaseIterable {
    case all        = 1
    case moments    = 5
    case events     = 20
    case adventures = 50

    var label: String {
        switch self {
        case .all:        return "All"
        case .moments:    return "5+"
        case .events:     return "20+"
        case .adventures: return "50+"
        }
    }

    var description: String {
        switch self {
        case .all:        return "Show every set, including quick snapshots."
        case .moments:    return "Hide sets with fewer than 5 photos — good for filtering out accidental shots."
        case .events:     return "Focus on proper outings, parties, and events (20+ photos)."
        case .adventures: return "Prioritise big trips and multi-day adventures (50+ photos)."
        }
    }
}

// MARK: - Clustering

/// What one clustering pass produced.
nonisolated struct ClusterResult: @unchecked Sendable {
    let clusters: [PhotoCluster]
    /// See `strandedInWindow` in ClusterRules.swift.
    let strandedIDs: [String]
}

nonisolated private func snap(_ asset: PHAsset) -> Snap {
    Snap(
        id: asset.localIdentifier,
        date: asset.creationDate,
        latitude: asset.location?.coordinate.latitude,
        longitude: asset.location?.coordinate.longitude,
        isFavorite: asset.isFavorite,
        isVideo: asset.mediaType == .video,
        burstID: asset.burstIdentifier
    )
}

/// Turns one time window into a cluster, or nothing if there is no reason to show it.
/// The decision itself lives in `isPreCurated`; this only carries the assets.
nonisolated private func makeCluster(
    from group: [PHAsset],
    snaps: [Snap],
    reviewedIDs: Set<String>,
    visitedIDs: Set<String>
) -> PhotoCluster? {
    guard !isPreCurated(snaps, reviewed: reviewedIDs, visited: visitedIDs) else { return nil }

    // Finished moments are kept rather than dropped, so they can be found again in the
    // archive and gone back into. They are filtered out of the queue, not out of memory.
    let toReview = group.filter { !reviewedIDs.contains($0.localIdentifier) }

    return PhotoCluster(
        id: group.first?.localIdentifier ?? UUID().uuidString,
        allAssets: group,
        assetsToReview: toReview,
        units: groupIntoUnits(toReview),
        totalInWindow: group.count,
        anchorDate: group.first?.creationDate,
        firstLocationAsset: group.first(where: { $0.location != nil })
    )
}

/// Splits assets into windows at the given boundaries and builds a cluster from each.
nonisolated private func assemble(
    _ assets: [PHAsset],
    snaps: [Snap],
    boundaries: Set<Int>,
    reviewedIDs: Set<String>,
    visitedIDs: Set<String>
) -> ClusterResult {
    var clusters: [PhotoCluster] = []
    var stranded: [String] = []

    var start = 0
    var cut = boundaries.sorted()
    cut.append(assets.count)

    for end in cut where end > start {
        let group = Array(assets[start..<end])
        let groupSnaps = Array(snaps[start..<end])
        if let cluster = makeCluster(
            from: group,
            snaps: groupSnaps,
            reviewedIDs: reviewedIDs,
            visitedIDs: visitedIDs
        ) {
            clusters.append(cluster)
        }
        stranded.append(contentsOf: strandedInWindow(groupSnaps, reviewed: reviewedIDs))
        start = end
    }

    return ClusterResult(clusters: clusters, strandedIDs: stranded)
}

/// Plain time-window grouping. Only reached for libraries too small for the smart rules
/// to have anything to work with.
nonisolated func buildClusters(
    from allAssets: [PHAsset],
    reviewedIDs: Set<String>,
    visitedIDs: Set<String> = [],
    gapThreshold: TimeInterval = 3 * 3600
) -> ClusterResult {
    guard !allAssets.isEmpty else { return ClusterResult(clusters: [], strandedIDs: []) }
    let snaps = allAssets.map(snap)

    var boundaries: Set<Int> = []
    for i in 1..<max(snaps.count, 1) {
        guard let previous = snaps[i - 1].date, let current = snaps[i].date else { continue }
        if current.timeIntervalSince(previous) > gapThreshold { boundaries.insert(i) }
    }
    return assemble(allAssets, snaps: snaps, boundaries: boundaries,
                    reviewedIDs: reviewedIDs, visitedIDs: visitedIDs)
}

/// Smart clustering. The rules themselves are in ClusterRules.swift, where they can be
/// tested without a photo library.
nonisolated func buildSmartClusters(
    from allAssets: [PHAsset],
    reviewedIDs: Set<String>,
    visitedIDs: Set<String> = [],
    sensitivity: SmartSensitivity = .balanced
) -> ClusterResult {
    guard !allAssets.isEmpty else { return ClusterResult(clusters: [], strandedIDs: []) }
    guard allAssets.count >= 2 else {
        return buildClusters(from: allAssets, reviewedIDs: reviewedIDs,
                             visitedIDs: visitedIDs, gapThreshold: 3600)
    }
    let snaps = allAssets.map(snap)
    let boundaries = windowBoundaries(snaps, sensitivity: sensitivity)
    return assemble(allAssets, snaps: snaps, boundaries: boundaries,
                    reviewedIDs: reviewedIDs, visitedIDs: visitedIDs)
}

/// Folds a moment's photos into the positions the review pager pages through.
nonisolated func groupIntoUnits(_ assets: [PHAsset], window: TimeInterval = 3) -> [ReviewUnit] {
    guard !assets.isEmpty else { return [] }
    return burstRuns(assets.map(snap), window: window).compactMap { range in
        let group = Array(assets[range])
        guard let first = group.first else { return nil }
        return ReviewUnit(id: first.localIdentifier, assets: group)
    }
}

// MARK: - Grouping helpers

/// Groups clusters by year, newest first
nonisolated func yearSummaries(from clusters: [PhotoCluster]) -> [YearSummary] {
    let calendar = Calendar.current
    var map: [Int: (Int, Int)] = [:]  // year → (clusterCount, photoCount)
    for cluster in clusters {
        let year = calendar.component(.year, from: cluster.anchorDate ?? Date())
        let existing = map[year] ?? (0, 0)
        map[year] = (existing.0 + 1, existing.1 + cluster.count)
    }
    return map
        .map { year, data in YearSummary(id: year, year: year, clusterCount: data.0, toReviewCount: data.1) }
        .sorted { $0.year > $1.year }
}

/// Groups clusters into month sections, newest first
nonisolated func groupByMonth(_ clusters: [PhotoCluster]) -> [MonthSection] {
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"

    // Preserve insertion order using an array + index map
    var sections: [(key: String, title: String, clusters: [PhotoCluster])] = []
    var indexMap: [String: Int] = [:]

    for cluster in clusters {
        let date = cluster.anchorDate ?? Date()
        let comps = calendar.dateComponents([.year, .month], from: date)
        let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        let title = formatter.string(from: calendar.date(from: comps) ?? date)

        if let idx = indexMap[key] {
            sections[idx].clusters.append(cluster)
        } else {
            indexMap[key] = sections.count
            sections.append((key, title, [cluster]))
        }
    }

    // Reverse so newest month is first
    return sections
        .reversed()
        .map { MonthSection(id: $0.key, title: $0.title, clusters: $0.clusters) }
}

/// Returns clusters for a specific year
nonisolated func clusters(for year: Int, in all: [PhotoCluster]) -> [PhotoCluster] {
    let calendar = Calendar.current
    return all.filter {
        calendar.component(.year, from: $0.anchorDate ?? Date()) == year
    }
}
