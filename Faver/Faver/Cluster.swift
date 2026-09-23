import CoreLocation
import Photos

// MARK: - ClusterGap

nonisolated enum ClusterGap: String, CaseIterable {
    case narrow, medium, broad

    var threshold: TimeInterval {
        switch self {
        case .narrow: return 3600
        case .medium: return 3 * 3600
        case .broad:  return 8 * 3600
        }
    }

    var label: String {
        switch self {
        case .narrow: return "Narrow"
        case .medium: return "Medium"
        case .broad:  return "Broad"
        }
    }

    var description: String {
        switch self {
        case .narrow: return "~1 hour"
        case .medium: return "~3 hours"
        case .broad:  return "~8 hours"
        }
    }
}

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

/// Photos belong to the same burst when the camera says so, or when they were taken
/// within `window` of each other. The camera's own burst identifier only covers real
/// burst mode; the time rule catches the far more common case of pressing the shutter
/// four times in a row because the first one might be blurry.
nonisolated func groupIntoUnits(_ assets: [PHAsset], window: TimeInterval = 3) -> [ReviewUnit] {
    guard !assets.isEmpty else { return [] }

    var units: [[PHAsset]] = []
    var current: [PHAsset] = [assets[0]]

    for i in 1..<assets.count {
        let prev = assets[i - 1]
        let curr = assets[i]

        let sameCameraBurst: Bool = {
            guard let a = prev.burstIdentifier, let b = curr.burstIdentifier else { return false }
            return a == b
        }()

        let closeInTime: Bool = {
            guard let a = prev.creationDate, let b = curr.creationDate else { return false }
            return b.timeIntervalSince(a) <= window
        }()

        // A video is always its own item. Grouping one with the stills around it would
        // hide it behind a photo, and it takes its own kind of attention to judge.
        let groupable = prev.mediaType == .image && curr.mediaType == .image

        if groupable && (sameCameraBurst || closeInTime) {
            current.append(curr)
        } else {
            units.append(current)
            current = [curr]
        }
    }
    units.append(current)

    return units.compactMap { group in
        guard let first = group.first else { return nil }
        return ReviewUnit(id: first.localIdentifier, assets: group)
    }
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

// MARK: - ClusterMode

nonisolated enum ClusterMode: String, CaseIterable {
    case smart, fixed

    var label: String {
        switch self {
        case .smart: return "Smart"
        case .fixed: return "Fixed"
        }
    }
}

// MARK: - Clustering

/// What one clustering pass produced.
nonisolated struct ClusterResult: @unchecked Sendable {
    let clusters: [PhotoCluster]
    /// Photos marked as reviewed inside a window that was never finished. Under the
    /// current rules that cannot happen: a moment is marked whole, at the end, or not at
    /// all. A mixed window is therefore left over from the builds that recorded progress
    /// photo by photo, and those photos are owed back. See LibraryService.load().
    let strandedIDs: [String]
}

nonisolated func strandedIDs(in groups: [[PHAsset]], reviewedIDs: Set<String>) -> [String] {
    groups.flatMap { group -> [String] in
        let seen = group.filter { reviewedIDs.contains($0.localIdentifier) }
        guard !seen.isEmpty, seen.count < group.count else { return [] }
        return seen.map { $0.localIdentifier }
    }
}

/// Turns one time window into a cluster, or nothing if there is no reason to show it.
///
/// A window is skipped when it was already curated before Faver ever saw it: someone
/// favorited in there, and not a single photo in the window has been through the app.
/// That library was tidied by hand, and re-reviewing it wastes the user's time.
///
/// Once Faver *has* been in a window, the favorites in it are the user's own, made
/// here. Skipping then would hide every photo they had not reached yet — favorite the
/// third photo of two hundred and the remaining hundred and ninety-seven would vanish
/// with no way back in. A complete pass over the library is the whole point, so the
/// window stays.
nonisolated private func makeCluster(from group: [PHAsset], reviewedIDs: Set<String>) -> PhotoCluster? {
    let seenHere = group.contains { reviewedIDs.contains($0.localIdentifier) }
    let curatedElsewhere = !seenHere && group.contains { $0.isFavorite }
    guard !curatedElsewhere else { return nil }

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

/// Groups ALL photos by time window, then filters each group to only what still needs reviewing.
nonisolated func buildClusters(
    from allAssets: [PHAsset],
    reviewedIDs: Set<String>,
    gapThreshold: TimeInterval = 3 * 3600
) -> ClusterResult {
    guard !allAssets.isEmpty else { return ClusterResult(clusters: [], strandedIDs: []) }

    var groups: [[PHAsset]] = []
    var currentGroup: [PHAsset] = [allAssets[0]]

    for i in 1..<allAssets.count {
        let prev = allAssets[i - 1]
        let curr = allAssets[i]
        if let prevDate = prev.creationDate,
           let currDate = curr.creationDate,
           currDate.timeIntervalSince(prevDate) > gapThreshold {
            groups.append(currentGroup)
            currentGroup = [curr]
        } else {
            currentGroup.append(curr)
        }
    }
    if !currentGroup.isEmpty { groups.append(currentGroup) }

    return ClusterResult(
        clusters: groups.compactMap { makeCluster(from: $0, reviewedIDs: reviewedIDs) },
        strandedIDs: strandedIDs(in: groups, reviewedIDs: reviewedIDs)
    )
}

/// Smart clustering: three-tier boundary detection.
///
/// **Tier 1 — day gap (hard rule, always splits)**
/// If there are ≥ 24 hours between consecutive photos, at least one full calendar
/// day had no photos. That stretch is always its own set, regardless of anything else.
///
/// **Tier 2 — time gap (adaptive)**
/// Burst gaps (< 60 s) are excluded so rapid-fire shooting doesn't skew the
/// calculation. The 90th percentile of the remaining pauses is the threshold
/// (min 30 min, max 18 h — within-day only, since tier 1 handles overnight gaps).
///
/// **Tier 3 — location change**
/// If you've paused ≥ 5 min AND the next geotagged photo is > 1 km away, that's
/// a venue change — even if the time gap wouldn't have triggered tier 2. This
/// keeps "beach morning / fair afternoon / home evening" as three sets on the
/// same day. Photos without GPS fall back to tier 2 only.
nonisolated func buildSmartClusters(
    from allAssets: [PHAsset],
    reviewedIDs: Set<String>,
    sensitivity: SmartSensitivity = .balanced
) -> ClusterResult {
    guard !allAssets.isEmpty else { return ClusterResult(clusters: [], strandedIDs: []) }
    guard allAssets.count >= 2 else {
        return buildClusters(from: allAssets, reviewedIDs: reviewedIDs, gapThreshold: 3600)
    }

    // Compute adaptive within-day threshold from meaningful (≥ 60 s) gaps
    var meaningfulGaps: [TimeInterval] = []
    for i in 1..<allAssets.count {
        guard let prev = allAssets[i - 1].creationDate,
              let curr = allAssets[i].creationDate else { continue }
        let gap = curr.timeIntervalSince(prev)
        if gap >= 60 { meaningfulGaps.append(gap) }
    }

    let timeThreshold: TimeInterval
    if meaningfulGaps.isEmpty {
        timeThreshold = 18 * 3600
    } else {
        let sorted = meaningfulGaps.sorted()
        let p90 = sorted[Int(Double(sorted.count - 1) * 0.90)]
        // Cap at 18 h: tier 1 handles anything ≥ 24 h, so within-day logic
        // only needs to cover the range up to a single long day.
        timeThreshold = max(1800, min(p90, 18 * 3600))
    }

    let dayGap: TimeInterval = 24 * 3600
    let locationThreshold = sensitivity.locationThreshold
    let minTimeForLocationSplit = sensitivity.minPauseTime

    var groups: [[PHAsset]] = []
    var currentGroup: [PHAsset] = [allAssets[0]]

    for i in 1..<allAssets.count {
        let prev = allAssets[i - 1]
        let curr = allAssets[i]

        guard let prevDate = prev.creationDate,
              let currDate = curr.creationDate else {
            currentGroup.append(curr)
            continue
        }

        let timeGap = currDate.timeIntervalSince(prevDate)
        var isBoundary = false

        if timeGap >= dayGap {
            // Tier 1: full-day gap → isolated stretch, always split
            isBoundary = true
        } else if timeGap >= timeThreshold {
            // Tier 2: long within-day pause
            isBoundary = true
        } else if timeGap >= minTimeForLocationSplit,
                  let prevLoc = prev.location,
                  let currLoc = curr.location,
                  prevLoc.distance(from: currLoc) > locationThreshold {
            // Tier 3: paused + moved to a different venue
            isBoundary = true
        }

        if isBoundary {
            groups.append(currentGroup)
            currentGroup = [curr]
        } else {
            currentGroup.append(curr)
        }
    }
    if !currentGroup.isEmpty { groups.append(currentGroup) }

    return ClusterResult(
        clusters: groups.compactMap { makeCluster(from: $0, reviewedIDs: reviewedIDs) },
        strandedIDs: strandedIDs(in: groups, reviewedIDs: reviewedIDs)
    )
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
