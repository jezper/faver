import Foundation
import Testing

@testable import Faver

/// What the app remembers between sessions.
///
/// Three separate ideas that have been confused with each other at least once each, at
/// real cost: what has been reviewed, where the user stopped, and where Faver has been.

private func scratchStore() -> (ReviewStore, UserDefaults) {
    let name = "faver.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (ReviewStore(defaults: defaults), defaults)
}

@Suite("Reviewed state")
struct ReviewedTests {

    @Test("Marking a photo reviewed sticks")
    func mark() {
        let (store, _) = scratchStore()
        store.markReviewed("a")
        #expect(store.isReviewed("a"))
        #expect(!store.isReviewed("b"))
    }

    @Test("Marking the same photo twice changes nothing")
    func markTwice() {
        let (store, _) = scratchStore()
        store.markReviewed("a")
        store.markReviewed("a")
        #expect(store.reviewedIDs == ["a"])
    }

    @Test("Unmarking puts photos back in the queue")
    func unmark() {
        let (store, _) = scratchStore()
        store.markReviewed("a")
        store.markReviewed("b")
        store.unmark(["a"])
        #expect(!store.isReviewed("a"))
        #expect(store.isReviewed("b"))
    }

    @Test("Unmarking nothing is harmless")
    func unmarkEmpty() {
        let (store, _) = scratchStore()
        store.markReviewed("a")
        store.unmark([])
        #expect(store.isReviewed("a"))
    }
}

@Suite("Where the user stopped")
struct StopTests {

    @Test("A stop is remembered")
    func setAndRead() {
        let (store, _) = scratchStore()
        store.setStop("b", within: ["a", "b", "c"])
        #expect(store.isStop("b"))
        #expect(!store.isStop("a"))
    }

    @Test("Moving through a moment leaves only one stop behind")
    func stopMoves() {
        let (store, _) = scratchStore()
        let moment = ["a", "b", "c"]
        store.setStop("a", within: moment)
        store.setStop("b", within: moment)
        store.setStop("c", within: moment)
        #expect(store.isStop("c"))
        #expect(!store.isStop("a"))
        #expect(!store.isStop("b"))
    }

    @Test("Two moments each keep their own stop")
    func stopsAreIndependent() {
        let (store, _) = scratchStore()
        store.setStop("a2", within: ["a1", "a2"])
        store.setStop("b1", within: ["b1", "b2"])
        #expect(store.isStop("a2"))
        #expect(store.isStop("b1"))
    }

    @Test("Finishing a moment clears its stop and no one else's")
    func clearStops() {
        let (store, _) = scratchStore()
        store.setStop("a2", within: ["a1", "a2"])
        store.setStop("b1", within: ["b1", "b2"])
        store.clearStops(within: ["a1", "a2"])
        #expect(!store.isStop("a2"))
        #expect(store.isStop("b1"))
    }

    @Test("A stop survives the moment being regrouped")
    func stopSurvivesRegrouping() {
        // Stops are keyed to the photo, never to the moment, because moments are worked
        // out from the grouping settings and change identity the instant one is touched.
        let (store, _) = scratchStore()
        store.setStop("photo42", within: ["photo41", "photo42", "photo43"])
        // The same photo now sits in a completely differently shaped moment.
        #expect(store.isStop("photo42"))
    }
}

@Suite("Where Faver has been")
struct VisitedTests {

    @Test("Visiting is recorded")
    func markVisited() {
        let (store, _) = scratchStore()
        store.markVisited(["a", "b"])
        #expect(store.visitedIDs == ["a", "b"])
    }

    @Test("Visiting finishes nothing")
    func visitingIsNotReviewing() {
        // The whole point. Opening a moment must not spend any of it.
        let (store, _) = scratchStore()
        store.markVisited(["a", "b"])
        #expect(!store.isReviewed("a"))
        #expect(store.reviewedIDs.isEmpty)
    }

    @Test("Visiting the same photos again changes nothing")
    func visitTwice() {
        let (store, _) = scratchStore()
        store.markVisited(["a"])
        store.markVisited(["a"])
        #expect(store.visitedIDs == ["a"])
    }
}

@Suite("Across sessions")
struct PersistenceTests {

    @Test("Everything is still there next launch")
    func roundTrip() async throws {
        let name = "faver.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!

        let first = ReviewStore(defaults: defaults)
        first.markReviewed("reviewed1")
        first.setStop("stopped1", within: ["stopped1", "stopped2"])
        first.markVisited(["visited1"])

        // Writes are handed to a background queue so the app never waits on them.
        try await Task.sleep(for: .milliseconds(300))

        let second = ReviewStore(defaults: defaults)
        #expect(second.isReviewed("reviewed1"))
        #expect(second.isStop("stopped1"))
        #expect(second.visitedIDs.contains("visited1"))
    }
}
