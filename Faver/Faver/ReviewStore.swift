import Foundation

/// Persists review state across app sessions, locally, in UserDefaults.
///
/// Two separate ideas, deliberately kept apart:
///
/// **Reviewed** is a property of a whole moment, and is only ever set by the explicit
/// last step at the end of one. Swiping past a photo does not spend it. This is what
/// keeps a moment whole: open it, look at two photos, leave, and it is exactly as it was.
///
/// **Position** is where the user stopped inside a moment, so the next visit opens there.
/// Remembering that is what "pick up where you left off" needs, and it needs nothing else.
class ReviewStore {
    static let shared = ReviewStore()

    private let key = "reviewedPhotoIDs"
    private let positionsKey = "momentPositions"

    /// In-memory set, loaded once at init. Fast O(1) reads for the clustering pipeline.
    private(set) var reviewedIDs: Set<String>
    /// Moment id → the id of the photo showing when the user last left it.
    private var positions: [String: String]

    private init() {
        reviewedIDs = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        positions = UserDefaults.standard.dictionary(forKey: positionsKey) as? [String: String] ?? [:]
    }

    // MARK: - Position

    func position(inMoment momentID: String) -> String? {
        positions[momentID]
    }

    func setPosition(_ assetID: String, inMoment momentID: String) {
        guard positions[momentID] != assetID else { return }
        positions[momentID] = assetID
        persistPositions()
    }

    func clearPosition(inMoment momentID: String) {
        guard positions.removeValue(forKey: momentID) != nil else { return }
        persistPositions()
    }

    private func persistPositions() {
        let snapshot = positions
        DispatchQueue.global(qos: .utility).async {
            UserDefaults.standard.set(snapshot, forKey: self.positionsKey)
        }
    }

    // MARK: - Reviewed

    func markReviewed(_ id: String) {
        guard !reviewedIDs.contains(id) else { return }
        reviewedIDs.insert(id)
        let snapshot = reviewedIDs
        DispatchQueue.global(qos: .utility).async {
            UserDefaults.standard.set(Array(snapshot), forKey: self.key)
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
            UserDefaults.standard.set(Array(snapshot), forKey: self.key)
        }
    }
}
