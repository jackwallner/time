import XCTest

/// The whole first session, end to end: setup from the first page, the
/// Home it lands on, a practice run, and the way back. Attaches a screenshot
/// at every stop, so a run of this test is also a visual walkthrough.
@MainActor
final class FlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFirstSessionFromSetupToPracticeRun() {
        let app = XCUIApplication()
        app.launchArguments = ["-ResetState"]
        app.launch()

        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        capture(app, "01-welcome")
        next.tap()
        XCTAssertTrue(app.staticTexts["About 30 minutes"].waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "Continue waits for an answer")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "About 45 minutes")).firstMatch.tap()
        capture(app, "02-pace")
        next.tap()
        XCTAssertTrue(app.staticTexts["When do you need to walk out the door?"].waitForExistence(timeout: 5))
        capture(app, "03-leave")
        next.tap()
        XCTAssertTrue(app.staticTexts["What happens before you leave?"].waitForExistence(timeout: 5))
        capture(app, "04-steps")
        next.tap()
        XCTAssertTrue(app.staticTexts["It really takes"].waitForExistence(timeout: 5))
        capture(app, "05-reveal")

        // The notification prompt comes up between the reveal and the offer.
        next.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let free = app.buttons["Get Started"]
        XCTAssertTrue(free.waitForExistence(timeout: 30))
        if allow.exists { allow.tap() }
        capture(app, "06-offer")
        free.tap()

        // Home: the plan from the answers just given, with nothing learned yet.
        let start = app.buttons.matching(NSPredicate(format: "label IN %@", ["Start now", "Start early", "Practice run"])).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["The real plan"].exists)
        capture(app, "07-home")

        // A run comes up over Home, moves on at Done and Skip, and ends
        // cleanly back on Home.
        start.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Step 1 of 6")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "08-run")
        sleep(1)
        done.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Step 2 of 6")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Undo Wake up and bathroom done"].exists)
        capture(app, "09-run-step-2")
        sleep(6)
        app.buttons["Skip this step"].tap()
        // A skipped step leaves the plan, so the count drops with it.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Step 2 of 5")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Get dressed"].exists)
        app.buttons["End routine"].tap()
        app.buttons["End without leaving"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(done.exists)
        capture(app, "10-home-after")
    }
}
