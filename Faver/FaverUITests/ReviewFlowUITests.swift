import XCTest

/// End-to-end tests against a real photo library in the simulator.
///
/// Slow, and not meant for every build. They exist because the bugs that have cost the
/// most were not in the rules but in the screens: a finished moment that stayed on the
/// home screen, a photo spent by merely opening a moment, a moment that vanished because
/// one photo in it was favorited. None of those are visible to a unit test.
///
/// The library is seeded by scripts/uitest.sh before these run: three moments, one of
/// which contains a burst. Run them with ./scripts/uitest.sh.
///
/// **Not yet confirmed green, for a reason outside the tests.** `simctl privacy grant
/// photos` reports success and then writes a *denied* value into the simulator's
/// permission database, so the app never sees the library and every test waits out its
/// timeout on a welcome screen. uitest.sh sets the value directly now, which is the fix,
/// but it could not be run to completion: Xcode's licence agreement was reset by the
/// macOS 27 upgrade and blocks simctl until somebody with the password accepts it.
///
///     sudo xcodebuild -license accept
final class ReviewFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// A picture of whatever the app was actually showing when a test gave up. Without it
    /// every failure looks the same from the log, and diagnosing one means driving the
    /// simulator by hand.
    override func tearDown() {
        guard (testRun?.failureCount ?? 0) > 0 else { return }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "screen-at-failure"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Helpers

    /// Matched on identity rather than element type. SwiftUI decides for itself whether a
    /// combined, button-flavoured element surfaces as a button or a plain container, and
    /// that is not worth a test knowing.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var firstCard: XCUIElement { element("moment-card") }

    /// Takes the system's photo access question, whatever this iOS version calls the
    /// button and wherever it puts it.
    ///
    /// Since iOS 14 this sheet is drawn by PhotosUI inside the app's own process, not by
    /// the home screen, so looking only at springboard finds nothing and the test sits
    /// there until it times out. Both are checked, repeatedly, because the sheet takes a
    /// moment to arrive.
    private func answerPhotoAccess() {
        let titles = ["Allow Full Access", "Allow Access to All Photos", "Allow"]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(25)

        while Date() < deadline {
            for host in [app!, springboard] {
                for title in titles {
                    let button = host.buttons[title]
                    if button.exists && button.isHittable {
                        button.tap()
                        return
                    }
                }
            }
            usleep(400_000)
        }
    }

    private func waitForHome() {
        // Belt and braces: uitest.sh grants photo access before the app is launched, but
        // if that ever stops working the app lands on the welcome screen instead, and a
        // test that just times out says nothing useful about why.
        let start = app.buttons["Find my moments"]
        if start.waitForExistence(timeout: 15) {
            start.tap()
            answerPhotoAccess()
        }
        XCTAssertTrue(
            firstCard.waitForExistence(timeout: 60),
            "The home screen never showed a moment. Is the simulator's photo library seeded, and access granted?"
        )
    }

    /// Swipes to the end of a moment and finishes it.
    private func finishOpenMoment() {
        let finish = element("finish-moment")
        for _ in 0..<40 {
            if finish.exists && finish.isHittable { break }
            app.swipeLeft()
        }
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "Never reached the end of the moment.")
        finish.tap()
    }

    // MARK: - The home screen tells the truth

    func testHomeShowsAMomentAndProgress() {
        waitForHome()
        XCTAssertTrue(element("progress").waitForExistence(timeout: 10), "No progress shown on the home screen.")
    }

    /// The bug from build 8: the card was identified by its position in the row, so the
    /// moment that slid into a finished one's place inherited its photos and looked like
    /// the moment that had just been finished.
    func testFinishedMomentLeavesTheHomeScreen() {
        waitForHome()
        let before = firstCard.label
        XCTAssertFalse(before.isEmpty, "The moment card has no accessibility label.")

        firstCard.tap()
        finishOpenMoment()

        waitForHome()
        let after = firstCard.label
        XCTAssertNotEqual(after, before, "The finished moment is still on the home screen.")
    }

    /// The bug found on build 3: opening a moment marked its first photo as seen, so
    /// pressing Done without looking at anything quietly spent a photo.
    func testOpeningAndLeavingAMomentCostsNothing() {
        waitForHome()
        let before = firstCard.label

        firstCard.tap()
        let done = element("done")
        XCTAssertTrue(done.waitForExistence(timeout: 10), "No way out of the review screen.")
        done.tap()

        waitForHome()
        XCTAssertEqual(firstCard.label, before, "Opening a moment and leaving changed it.")
    }

    /// The regression that shipped twice: favoriting one photo made the whole moment,
    /// including every photo not yet reached, disappear.
    func testFavoritingDoesNotHideTheMoment() {
        waitForHome()
        let before = firstCard.label

        firstCard.tap()
        let favorite = element("favorite")
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        favorite.tap()
        element("done").tap()

        waitForHome()
        XCTAssertEqual(
            firstCard.label, before,
            "Favoriting a photo removed the moment it was in, along with everything unseen in it."
        )
    }

    /// Progress is per photo, so it has to survive the app being closed and reopened.
    func testProgressSurvivesRelaunch() {
        waitForHome()
        let before = firstCard.label

        firstCard.tap()
        finishOpenMoment()
        waitForHome()

        app.terminate()
        app.launch()
        waitForHome()

        XCTAssertNotEqual(firstCard.label, before, "A finished moment came back after relaunch.")
    }

    // MARK: - The archive

    func testFinishedMomentIsFoundInTheArchive() {
        waitForHome()
        firstCard.tap()
        finishOpenMoment()
        waitForHome()

        element("browse-all").tap()

        let scope = element("browse-scope")
        XCTAssertTrue(scope.waitForExistence(timeout: 10), "No archive control in Browse.")
        scope.buttons["Reviewed"].tap()

        XCTAssertTrue(
            element("moment-row").waitForExistence(timeout: 10),
            "A finished moment is not in the archive."
        )
    }
}
