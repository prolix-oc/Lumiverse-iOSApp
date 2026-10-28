import XCTest

final class ControlsGestureTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "chat.lumiverse.native-regression-host")
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Page menus: 0"].waitForExistence(timeout: 10))
    }

    func testTwoFingerHoldCancelsPageLongPressBeforeOpeningControls() {
        // XCTest's slow, tiny pinch holds two contacts inside the 18 pt slop.
        app.webViews.buttons["Message target"].pinch(withScale: 1.05, velocity: 0.025)
        let controls = app.alerts["App controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 3))
        controls.buttons["Cancel"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Page menus: 0"].exists,
            "The native hold must cancel JS before its 500 ms context menu timer")
        XCTAssertFalse(app.webViews.staticTexts["Touch cancels: 0"].exists,
            "The wrapper must deliver touchcancel to the frontend")
        app.webViews.buttons["Tap target"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Page clicks: 1"].exists)
    }

    func testSingleFingerTapLongPressAndScrollingStillReachThePage() {
        app.webViews.buttons["Tap target"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Page clicks: 1"].exists)
        app.webViews.buttons["Message target"].press(forDuration: 0.8)
        XCTAssertFalse(app.alerts["App controls"].exists)
        XCTAssertFalse(app.webViews.staticTexts["Page menus: 0"].exists)
        app.webViews.firstMatch.swipeUp()
        XCTAssertFalse(app.webViews.staticTexts["Page scroll: 0"].exists)
    }

    func testQuickPinchPreservesNativeZoomWithoutOpeningControls() {
        // XCTest's scale/velocity trajectory must finish before the hold's
        // 650 ms threshold; its slower pinches intentionally open controls.
        app.webViews.buttons["Message target"].pinch(withScale: 2, velocity: 20)
        XCTAssertFalse(app.alerts["App controls"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.webViews.staticTexts["Page zoom: 1"].exists,
            "Native pinch zoom must still work alongside touch ownership")
        XCTAssertTrue(app.webViews.staticTexts["Page menus: 0"].exists)
    }
}
