import Foundation
import Testing

@testable import Faver

/// The rules that decide what a moment is.
///
/// Every test here stands for something that has actually gone wrong, or for a promise
/// the app makes out loud. They run in milliseconds and should run on every build.

// MARK: - Helpers

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

private func at(_ minutes: Double) -> Date { epoch.addingTimeInterval(minutes * 60) }

private func snap(
    _ id: String,
    _ minutes: Double,
    favorite: Bool = false,
    video: Bool = false,
    burst: String? = nil,
    lat: Double? = nil,
    lon: Double? = nil
) -> Snap {
    Snap(id: id, date: at(minutes), latitude: lat, longitude: lon,
         isFavorite: favorite, isVideo: video, burstID: burst)
}

// MARK: - When a moment ends

@Suite("Moment boundaries")
struct BoundaryTests {

    @Test("A day without photos always ends a moment")
    func dayGapAlwaysSplits() {
        // Even though the two are in the same place, and nothing else suggests a break.
        let snaps = [
            snap("a", 0, lat: 59.33, lon: 18.07),
            snap("b", 25 * 60, lat: 59.33, lon: 18.07)
        ]
        #expect(windowBoundaries(snaps, sensitivity: .balanced) == [1])
    }

    @Test("A long pause ends a moment")
    func longPauseSplits() {
        var snaps = (0..<20).map { snap("morning\($0)", Double($0) * 2) }
        snaps.append(snap("evening", 600))
        #expect(windowBoundaries(snaps, sensitivity: .balanced).contains(20))
    }

    @Test("Photos taken back to back stay in one moment")
    func rapidPhotosStayTogether() {
        let snaps = (0..<10).map { snap("p\($0)", Double($0) * 0.05) }
        #expect(windowBoundaries(snaps, sensitivity: .balanced).isEmpty)
    }

    @Test("Moving to a different place ends a moment, even on the same afternoon")
    func venueChangeSplits() {
        // Stockholm, then a twenty minute pause, then somewhere 40 km away.
        let snaps = [
            snap("beach1", 0, lat: 59.33, lon: 18.07),
            snap("beach2", 1, lat: 59.33, lon: 18.07),
            snap("fair1", 21, lat: 59.60, lon: 17.90),
            snap("fair2", 22, lat: 59.60, lon: 17.90)
        ]
        #expect(windowBoundaries(snaps, sensitivity: .balanced).contains(2))
    }

    @Test("Moving without pausing does not end a moment")
    func movingWhileShootingDoesNotSplit() {
        // Out of a car window: far apart, no pause. One moment.
        let snaps = [
            snap("a", 0, lat: 59.33, lon: 18.07),
            snap("b", 0.5, lat: 59.60, lon: 17.90)
        ]
        #expect(windowBoundaries(snaps, sensitivity: .balanced).isEmpty)
    }

    @Test("A pause with no location on either photo does not end a moment by place")
    func noLocationNoVenueSplit() {
        let snaps = [snap("a", 0), snap("b", 21)]
        #expect(windowBoundaries(snaps, sensitivity: .balanced).isEmpty)
    }

    @Test("Looser sensitivity needs a bigger move before it counts as a new place")
    func sensitivityChangesTheVenueRule() {
        // 2 km apart, after a five minute pause.
        let snaps = [
            snap("a", 0, lat: 59.330, lon: 18.070),
            snap("b", 6, lat: 59.348, lon: 18.070)
        ]
        #expect(windowBoundaries(snaps, sensitivity: .tight).contains(1))
        #expect(!windowBoundaries(snaps, sensitivity: .loose).contains(1))
    }

    @Test("Photos with no date never split a moment, and never crash")
    func missingDatesAreSurvivable() {
        let snaps = [
            Snap(id: "a"),
            snap("b", 5),
            Snap(id: "c")
        ]
        #expect(windowBoundaries(snaps, sensitivity: .balanced).isEmpty)
    }

    @Test("One photo has no boundaries")
    func singlePhoto() {
        #expect(windowBoundaries([snap("a", 0)], sensitivity: .balanced).isEmpty)
    }
}

// MARK: - How long a pause has to be

@Suite("Adaptive pause threshold")
struct ThresholdTests {

    @Test("Never shorter than half an hour, however fidgety the library")
    func clampedBelow() {
        let snaps = (0..<50).map { snap("p\($0)", Double($0) * 1.5) }   // 90 second gaps
        #expect(adaptiveTimeThreshold(snaps) == 30 * 60)
    }

    @Test("Never longer than a long day, however sparse the library")
    func clampedAbove() {
        let snaps = (0..<10).map { snap("p\($0)", Double($0) * 60 * 40) }  // 40 hour gaps
        #expect(adaptiveTimeThreshold(snaps) == 18 * 3600)
    }

    @Test("Burst gaps are left out of the calculation")
    func burstsDoNotDragTheThresholdDown() {
        // Ten photos a second apart, then pauses of an hour. Were the one-second gaps
        // counted, the typical pause would collapse and every hour-long gap would split.
        var snaps = (0..<10).map { snap("burst\($0)", Double($0) / 60) }
        for i in 0..<10 { snaps.append(snap("later\(i)", Double(60 + i * 60))) }
        #expect(adaptiveTimeThreshold(snaps) > 30 * 60)
    }

    @Test("A library with nothing to go on falls back to a long day")
    func noGaps() {
        #expect(adaptiveTimeThreshold([snap("a", 0)]) == 18 * 3600)
        #expect(adaptiveTimeThreshold([]) == 18 * 3600)
    }
}

// MARK: - Which moments are worth showing

@Suite("Pre-curated moments")
struct PreCuratedTests {

    @Test("A favorited moment Faver has never touched was curated by hand, and is skipped")
    func favoriteAndUntouchedIsSkipped() {
        let window = [snap("a", 0, favorite: true), snap("b", 1)]
        #expect(isPreCurated(window, reviewed: [], visited: []))
    }

    @Test("A moment with no favorite is always worth showing")
    func noFavoriteIsKept() {
        let window = [snap("a", 0), snap("b", 1)]
        #expect(!isPreCurated(window, reviewed: [], visited: []))
    }

    @Test("Favoriting inside Faver must never hide the photos not yet reached")
    func visitedMomentIsKept() {
        // The regression that shipped twice. Open a moment of 200, favorite the third
        // photo, leave without finishing. Nothing is marked reviewed under the
        // whole-moment rule, so only "visited" separates this from someone else's
        // finished work. Without it the other 197 vanish with no way back in.
        let window = [snap("a", 0, favorite: true), snap("b", 1), snap("c", 2)]
        #expect(!isPreCurated(window, reviewed: [], visited: ["a"]))
    }

    @Test("A moment Faver has finished part of is kept")
    func reviewedMomentIsKept() {
        let window = [snap("a", 0, favorite: true), snap("b", 1)]
        #expect(!isPreCurated(window, reviewed: ["b"], visited: []))
    }

    @Test("Visiting any photo in the moment is enough")
    func visitingAnyPhotoCounts() {
        let window = [snap("a", 0, favorite: true), snap("b", 1), snap("c", 2)]
        #expect(!isPreCurated(window, reviewed: [], visited: ["c"]))
    }
}

// MARK: - Photos owed back

@Suite("Stranded photos")
struct StrandedTests {

    @Test("Half a moment marked reviewed can only be damage, and is handed back")
    func mixedWindowIsStranded() {
        let window = [snap("a", 0), snap("b", 1), snap("c", 2)]
        #expect(strandedInWindow(window, reviewed: ["a", "b"]).sorted() == ["a", "b"])
    }

    @Test("A properly finished moment is left alone")
    func fullyReviewedIsNotStranded() {
        let window = [snap("a", 0), snap("b", 1)]
        #expect(strandedInWindow(window, reviewed: ["a", "b"]).isEmpty)
    }

    @Test("An untouched moment is left alone")
    func untouchedIsNotStranded() {
        let window = [snap("a", 0), snap("b", 1)]
        #expect(strandedInWindow(window, reviewed: []).isEmpty)
    }
}

// MARK: - Bursts

@Suite("Burst sets")
struct BurstTests {

    @Test("Photos within three seconds are one thing to decide about")
    func closeInTimeGroups() {
        let snaps = [
            Snap(id: "a", date: epoch),
            Snap(id: "b", date: epoch.addingTimeInterval(1)),
            Snap(id: "c", date: epoch.addingTimeInterval(2))
        ]
        #expect(burstRuns(snaps) == [0..<3])
    }

    @Test("Photos further apart than that are separate")
    func farApartDoesNotGroup() {
        let snaps = [
            Snap(id: "a", date: epoch),
            Snap(id: "b", date: epoch.addingTimeInterval(10))
        ]
        #expect(burstRuns(snaps) == [0..<1, 1..<2])
    }

    @Test("The camera's own burst holds together past three seconds")
    func cameraBurstGroups() {
        let snaps = [
            Snap(id: "a", date: epoch, burstID: "B1"),
            Snap(id: "b", date: epoch.addingTimeInterval(9), burstID: "B1")
        ]
        #expect(burstRuns(snaps) == [0..<2])
    }

    @Test("Different bursts a second apart are still one run, by time")
    func differentBurstIDsCloseInTime() {
        let snaps = [
            Snap(id: "a", date: epoch, burstID: "B1"),
            Snap(id: "b", date: epoch.addingTimeInterval(1), burstID: "B2")
        ]
        #expect(burstRuns(snaps) == [0..<2])
    }

    @Test("A video is never folded into a burst")
    func videoStandsAlone() {
        // It would otherwise hide behind a still, and it takes its own kind of attention.
        let snaps = [
            Snap(id: "a", date: epoch),
            Snap(id: "v", date: epoch.addingTimeInterval(1), isVideo: true),
            Snap(id: "b", date: epoch.addingTimeInterval(2))
        ]
        #expect(burstRuns(snaps) == [0..<1, 1..<2, 2..<3])
    }

    @Test("One photo is one position")
    func single() {
        #expect(burstRuns([Snap(id: "a", date: epoch)]) == [0..<1])
    }

    @Test("Nothing in, nothing out")
    func empty() {
        #expect(burstRuns([]).isEmpty)
    }

    @Test("Every photo lands in exactly one position")
    func runsCoverEverythingOnce() {
        let snaps = (0..<30).map { i in
            Snap(id: "p\(i)", date: epoch.addingTimeInterval(Double(i) * Double(i % 5)))
        }
        let covered = burstRuns(snaps).flatMap { Array($0) }
        #expect(covered == Array(0..<30))
    }
}

// MARK: - Progress

@Suite("Progress")
struct ProgressTests {

    @Test("Nothing reviewed is nothing done")
    func none() {
        #expect(progressFraction(total: 100, remaining: 100) == 0)
    }

    @Test("Nothing left is all done")
    func all() {
        #expect(progressFraction(total: 100, remaining: 0) == 1)
    }

    @Test("Half is half")
    func half() {
        #expect(progressFraction(total: 100, remaining: 50) == 0.5)
    }

    @Test("An empty library is not a finished one")
    func emptyLibrary() {
        #expect(progressFraction(total: 0, remaining: 0) == 0)
    }
}
