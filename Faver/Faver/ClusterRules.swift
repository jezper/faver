import CoreLocation
import Foundation

/// The rules that decide what a moment is, what counts as a burst, and which windows are
/// worth showing — with no Photos framework in sight.
///
/// They used to read PHAsset directly, which cannot be constructed outside the Photos
/// framework and therefore cannot be written a test for. These are the rules that have
/// broken twice and quietly cost real work each time: windows vanishing because someone
/// favorited in them, progress being spent before it was earned. They are worth being
/// able to prove.
///
/// `Snap` is everything the rules actually read from a photo. Cluster.swift maps PHAssets
/// to these once and slices the real assets by the answers.

// MARK: - Snap

struct Snap: Equatable, Sendable {
    let id: String
    let date: Date?
    let latitude: Double?
    let longitude: Double?
    let isFavorite: Bool
    let isVideo: Bool
    let burstID: String?

    init(
        id: String,
        date: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isFavorite: Bool = false,
        isVideo: Bool = false,
        burstID: String? = nil
    ) {
        self.id = id
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.isFavorite = isFavorite
        self.isVideo = isVideo
        self.burstID = burstID
    }

    var location: CLLocation? {
        guard let latitude, let longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Time threshold

/// A day without photos always separates two moments, so within-day logic never needs to
/// reach past a single long day.
let dayGap: TimeInterval = 24 * 3600
private let minimumThreshold: TimeInterval = 30 * 60
private let maximumThreshold: TimeInterval = 18 * 3600

/// How long a pause has to be, in this particular library, before it reads as a break.
///
/// Taken from the 90th percentile of the gaps, so a library of daily snapshots and a
/// library of three holidays a year each get a threshold that suits them. Gaps under a
/// minute are left out: rapid-fire shooting would otherwise drag the typical pause down
/// towards nothing and split every moment into fragments.
nonisolated func adaptiveTimeThreshold(_ snaps: [Snap]) -> TimeInterval {
    var gaps: [TimeInterval] = []
    for i in 1..<max(snaps.count, 1) {
        guard let previous = snaps[i - 1].date, let current = snaps[i].date else { continue }
        let gap = current.timeIntervalSince(previous)
        if gap >= 60 { gaps.append(gap) }
    }
    guard !gaps.isEmpty else { return maximumThreshold }
    let sorted = gaps.sorted()
    let p90 = sorted[Int(Double(sorted.count - 1) * 0.90)]
    return max(minimumThreshold, min(p90, maximumThreshold))
}

// MARK: - Window boundaries

/// The indices that begin a new moment. Three tiers, in order of authority:
///
/// 1. A gap of a full day or more. Always splits, whatever else is true.
/// 2. A pause longer than this library's typical one.
/// 3. A change of place: paused a while *and* moved a real distance, both photos
///    knowing where they were. This is what keeps "beach morning, fair afternoon,
///    home evening" as three moments on one day.
nonisolated func windowBoundaries(_ snaps: [Snap], sensitivity: SmartSensitivity) -> Set<Int> {
    guard snaps.count >= 2 else { return [] }

    let timeThreshold = adaptiveTimeThreshold(snaps)
    var boundaries: Set<Int> = []

    for i in 1..<snaps.count {
        let previous = snaps[i - 1]
        let current = snaps[i]

        guard let previousDate = previous.date, let currentDate = current.date else { continue }
        let gap = currentDate.timeIntervalSince(previousDate)

        if gap >= dayGap {
            boundaries.insert(i)
        } else if gap >= timeThreshold {
            boundaries.insert(i)
        } else if gap >= sensitivity.minPauseTime,
                  let from = previous.location,
                  let to = current.location,
                  from.distance(from: to) > sensitivity.locationThreshold {
            boundaries.insert(i)
        }
    }
    return boundaries
}

// MARK: - Worth showing

/// Whether this window was curated before Faver ever saw it.
///
/// Someone favorited in here, and Faver has never been inside — not reviewed, not even
/// opened. That is a library tidied by hand, and asking the user to redo it wastes their
/// time.
///
/// The visited half is not optional. Nothing is marked reviewed until a moment is
/// finished, so without it, favoriting one photo and leaving makes a window that Faver is
/// actively working on look exactly like somebody else's finished work, and it disappears
/// with every unseen photo in it.
nonisolated func isPreCurated(_ window: [Snap], reviewed: Set<String>, visited: Set<String>) -> Bool {
    let seenHere = window.contains { reviewed.contains($0.id) || visited.contains($0.id) }
    guard !seenHere else { return false }
    return window.contains { $0.isFavorite }
}

/// Photos marked reviewed inside a window that was never finished.
///
/// Under the whole-moment rule this cannot happen: a moment is marked all at once, at the
/// end, or not at all. A mixed window is left over from the builds that spent progress
/// photo by photo, and those photos are owed back.
nonisolated func strandedInWindow(_ window: [Snap], reviewed: Set<String>) -> [String] {
    let seen = window.filter { reviewed.contains($0.id) }
    guard !seen.isEmpty, seen.count < window.count else { return [] }
    return seen.map(\.id)
}

// MARK: - Bursts

/// Runs of photos that belong together as one thing to decide about.
///
/// The camera's own burst identifier only covers real burst mode. The time rule catches
/// the far more common case: pressing the shutter four times in a row because the first
/// one might be blurry.
///
/// A video is always alone. Folding one in would hide it behind a still, and it takes a
/// different kind of attention to judge.
nonisolated func burstRuns(_ snaps: [Snap], window: TimeInterval = 3) -> [Range<Int>] {
    guard !snaps.isEmpty else { return [] }

    var runs: [Range<Int>] = []
    var start = 0

    for i in 1..<snaps.count {
        let previous = snaps[i - 1]
        let current = snaps[i]

        let sameCameraBurst: Bool = {
            guard let a = previous.burstID, let b = current.burstID else { return false }
            return a == b
        }()

        let closeInTime: Bool = {
            guard let a = previous.date, let b = current.date else { return false }
            return b.timeIntervalSince(a) <= window
        }()

        let groupable = !previous.isVideo && !current.isVideo

        if !(groupable && (sameCameraBurst || closeInTime)) {
            runs.append(start..<i)
            start = i
        }
    }
    runs.append(start..<snaps.count)
    return runs
}

// MARK: - Progress

/// How far through the library the user is.
///
/// Deliberately takes the whole library and everything still queued, never the filtered
/// view: setting photos aside with the size filter is not the same as having reviewed
/// them, and counting it would quietly inflate the number.
nonisolated func progressFraction(total: Int, remaining: Int) -> Double {
    guard total > 0 else { return 0 }
    return Double(total - remaining) / Double(total)
}
