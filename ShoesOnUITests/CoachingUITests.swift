import XCTest

/// The coaching moves a late morning needs: skip or move a day, and cut a
/// later step when the run falls behind.
final class CoachingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testBehindRunOffersACutThatCatchesUp() {
        let app = launch(["-SeedScreenshotData", "-Screen", "run"])
        let cut = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Skip Pack bag and lunch today")).firstMatch
        XCTAssertTrue(cut.waitForExistence(timeout: 10))
        cut.tap()
        XCTAssertTrue(app.staticTexts["Then Shoes, keys, out"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Step 3 of 4")).firstMatch.exists)
        capture(app, "run-after-cut")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Shoes, keys, out"].waitForExistence(timeout: 5))
    }

    func testSkippingTheNextDepartureFromHomeAndUndoing() {
        let app = launch(["-SeedScreenshotData", "-FixedNow", "06:20"])
        let menu = app.buttons["Change a day"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let skip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Skip ")).firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(app.staticTexts["Skipped"].waitForExistence(timeout: 5))
        capture(app, "home-skipped")
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["Skipped"].waitForNonExistence(timeout: 5))
    }

    func testSkippingADayFromTheSheet() {
        let app = launch(["-SeedScreenshotData", "-OpenDayChange", "-FixedNow", "06:20"])
        XCTAssertTrue(app.navigationBars["Just this once"].waitForExistence(timeout: 10))
        let skip = app.buttons["Skip it"]
        if skip.exists {
            skip.tap()
            XCTAssertTrue(app.staticTexts["No alerts tomorrow."].waitForExistence(timeout: 5))
            capture(app, "sheet-skip")
            app.buttons["Save"].tap()
            XCTAssertTrue(app.staticTexts["Skipped"].waitForExistence(timeout: 5))
        } else {
            // Tomorrow is not a routine day: only a one-off time is offered.
            XCTAssertTrue(app.buttons["Save"].exists)
        }
    }
}
