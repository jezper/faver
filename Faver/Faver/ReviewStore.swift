import Foundation

/// Persists review state across app sessions, locally, in UserDefaults.
///
/// Two separate ideas, deliberately kept apart:
///
/// **Reviewed** is a property of a whole moment, and is only ever set by the explicit
/// last step at the end of one. Swiping past a photo does not spend it. This is what
/// keeps a moment whole: open it, look at two photos, leave, and it is exactly as it was.
///
/// **A stop** is the photo the user was on when they last left a moment, so the next
/// visit opens there.
///
/// Both are recorded against photo ids, never against moment ids. Moments are not
/// stored — they are worked out from the grouping settings every time the library
/// loads — so a moment's identity changes the instant someone moves the sensitivity
/// slider. Anything keyed to it would quietly point at nothing. Photo ids never move.
class ReviewStore {
    static let shared = ReviewStore()

    private let key = "reviewedPhotoIDs"
    private let stopsKey = "stoppedAtPhotoIDs"
    private let visitedKey = "visitedPhotoIDs"

    /// In-memory set, loaded once at init. Fast O(1) reads for the clustering pipeline.
    private(set) var reviewedIDs: Set<String>
    /// Photos the user was looking at when they left the moment containing them.
    private var stoppedAtIDs: Set<String>
    /// Photos in moments the user has opened. Not progress — opening a moment finishes
    /// nothing. It only records that Faver has been in here, which is what tells a
    /// library curated by hand years ago apart from one being curated in Faver now.
    private(set) var visitedIDs: Set<String>

    private let defaults: UserDefaults

    /// Takes its storage so a test can hand it a scratch suite instead of the real one.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reviewedIDs = Set(defaults.stringArray(forKey: key) ?? [])
        stoppedAtIDs = Set(defaults.stringArray(forKey: stopsKey) ?? [])
        visitedIDs = Set(defaults.stringArray(forKey: visitedKey) ?? [])
    }

    // MARK: - Visited

    func markVisited(_ ids: [String]) {
        let new = Set(ids).subtracting(visitedIDs)
        guard !new.isEmpty else { return }
        visitedIDs.formUnion(new)
        let snapshot = visitedIDs
        DispatchQueue.global(qos: .utility).async {
            self.defaults.set(Array(snapshot), forKey: self.visitedKey)
        }
    }

    // MARK: - Where the user stopped

    func isStop(_ assetID: String) -> Bool {
        stoppedAtIDs.contains(assetID)
    }

    /// Moves the stop inside one moment. `within` is every photo of that moment, so the
    /// previous stop is cleared however the moment happens to be grouped today.
    func setStop(_ assetID: String, within momentAssetIDs: [String]) {
        let others = Set(momentAssetIDs).subtracting([assetID])
        guard !stoppedAtIDs.contains(assetID) || !stoppedAtIDs.isDisjoint(with: others) else { return }
        stoppedAtIDs.subtract(others)
        stoppedAtIDs.insert(assetID)
        persistStops()
    }

    func clearStops(within momentAssetIDs: [String]) {
        let ids = Set(momentAssetIDs)
        guard !stoppedAtIDs.isDisjoint(with: ids) else { return }
        stoppedAtIDs.subtract(ids)
        persistStops()
    }

    private func persistStops() {
        let snapshot = stoppedAtIDs
        DispatchQueue.global(qos: .utility).async {
            self.defaults.set(Array(snapshot), forKey: self.stopsKey)
        }
    }

    // MARK: - Reviewed

    func markReviewed(_ id: String) {
        guard !reviewedIDs.contains(id) else { return }
        reviewedIDs.insert(id)
        let snapshot = reviewedIDs
        DispatchQueue.global(qos: .utility).async {
            self.defaults.set(Array(snapshot), forKey: self.key)
        }
    }

    func isReviewed(_ id: String) -> Bool {
        reviewedIDs.contains(id)
    }

    /// Puts photos back in the queue. Nothing in the photo library is touched; favorites
    /// already made stay made.
    func unmark(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        reviewedIDs.subtract(ids)
        let snapshot = reviewedIDs
        DispatchQueue.global(qos: .utility).async {
            self.defaults.set(Array(snapshot), forKey: self.key)
        }
    }
}
