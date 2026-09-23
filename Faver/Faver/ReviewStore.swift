import Foundation

/// Persists which photos have been reviewed (seen) across app sessions.
/// Stored locally on the device using UserDefaults.
/// A photo is "reviewed" the moment it appears on screen — regardless of whether it was favorited.
class ReviewStore {
    static let shared = ReviewStore()

    private let key = "reviewedPhotoIDs"
    /// In-memory set, loaded once at init. Fast O(1) reads for the clustering pipeline.
    private(set) var reviewedIDs: Set<String>

    private init() {
        reviewedIDs = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

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

    /// Forgets everything the app has seen. Nothing in the photo library is touched —
    /// favorites already made stay made. This only puts the queue back to full, which
    /// is the one way out of a moment swiped through by accident.
    func reset() {
        reviewedIDs = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}
