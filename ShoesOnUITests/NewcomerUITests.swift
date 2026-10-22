import XCTest

/// A first-time user who does not know the app's words and wants one useful
/// result fast. Each test attaches screenshots and records what it measured
/// as an attachment note, so the audit reads evidence, not guesses.
@MainActor
final class NewcomerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "note"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func touchTargets(_ app: XCUIApplication, _ label: String) -> String {
        let element = app.buttons[label].firstMatch
        guard element.exists else { return "\(label): missing" }
        let f = element.frame
        return "\(label): \(Int(f.width))x\(Int(f.height)) hittable=\(element.isHittable)"
    }

    /// Everything accepted as offered: the fewest taps to a first plan, then
    /// a run started and Done tapped at once, as a newcomer unsure what it does.
    func testDefaultsPathAndImmediateDone() {
        let app = launch(["-ResetState"])
        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        capture(app, "n01-welcome")
        var taps = 0
        next.tap(); taps += 1
        XCTAssertFalse(next.isEnabled, "Continue stays off until a pace answer")
        capture(app, "n02-pace-nothing-chosen")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "About 45 minutes")).firstMatch.tap(); taps += 1
        next.tap(); taps += 1
        capture(app, "n03-leave")
        next.tap(); taps += 1
        capture(app, "n04-steps")
        next.tap(); taps += 1
        XCTAssertTrue(app.staticTexts["It really takes"].waitForExistence(timeout: 5))
        capture(app, "n05-reveal")
        next.tap(); taps += 1
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { capture(app, "n06-permission-prompt"); allow.tap() }
        let skip = app.buttons["Get Started"]
        XCTAssertTrue(skip.waitForExistence(timeout: 30))
        capture(app, "n07-offer")
        skip.tap(); taps += 1
        note("taps from launch to Home with every default: \(taps)")

        let start = app.buttons.matching(NSPredicate(format: "label IN %@", ["Start now", "Start early", "Practice run"])).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        capture(app, "n08-home-top")
        note("Home start button label: \(start.label)")
        app.swipeUp()
        capture(app, "n09-home-scrolled")
        app.swipeDown()

        start.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        capture(app, "n10-run-first-step")
        // A newcomer taps Done straight away to see what it does.
        done.tap()
        usleep(900_000)
        let advanced = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Step 2 of 6")).firstMatch.exists
        note("Done tapped right after the run opened advanced the step: \(advanced)")
        capture(app, "n11-run-after-instant-done")
        if !advanced {
            done.tap()
            usleep(900_000)
            let secondAdvanced = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Step 2 of 6")).firstMatch.exists
            note("A second Done tap advanced: \(secondAdvanced)")
        }
        note(touchTargets(app, "Done") + " | " + touchTargets(app, "End routine") + " | " + touchTargets(app, "Skip this step"))
    }

    /// The pace question is the first real decision; check it at large text.
    func testLargeTextOnboarding() {
        for page in [1, 2, 3, 4, 5] {
            let app = launch(["-OnboardingPage", "\(page)", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
            let primary = app.buttons[page == 5 ? "Start 7-day free trial" : "Continue"]
            XCTAssertTrue(primary.waitForExistence(timeout: 10), "page \(page)")
            capture(app, "large-onboarding-\(page)")
            note("page \(page) primary hittable=\(primary.isHittable) frame=\(primary.frame)")
            app.terminate()
        }
    }

    /// Steps page: the stepper buttons a newcomer must use to give a guess.
    func testStepsPageTouchTargets() {
        let app = launch(["-OnboardingPage", "3"])
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
        let minus = app.buttons["minus"].firstMatch
        let plus = app.buttons["plus"].firstMatch
        note("stepper minus frame \(minus.frame), plus frame \(plus.frame)")
        capture(app, "steps-page")
        let field = app.textFields["Add your own step"]
        field.tap()
        field.typeText("Feed the dog")
        capture(app, "steps-page-keyboard")
        note("Continue hittable with keyboard up: \(app.buttons["Continue"].isHittable)")
        app.buttons["Add"].tap()
        capture(app, "steps-page-added")
    }

    /// After setup: the Edit route and the Settings route a newcomer takes
    /// to find out what the words on Home mean.
    func testHomeJargonAndEditRoute() {
        let app = launch(["-SeedScreenshotData"])
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        capture(app, "home-seeded")
        app.buttons["Change a day"].tap()
        capture(app, "home-change-menu")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Skip")).firstMatch.tap()
        capture(app, "home-after-skip")
        app.swipeUp()
        capture(app, "home-after-skip-scrolled")
        app.buttons["Edit"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit routine"].waitForExistence(timeout: 5))
        capture(app, "editor-top")
        app.swipeUp()
        capture(app, "editor-steps")
    }

    /// The leaving face and the summary, for first-run wording.
    func testRunEndAndSummaryWording() {
        let app = launch(["-SeedScreenshotData", "-Screen", "leaving"])
        XCTAssertTrue(app.buttons["I'm out the door"].waitForExistence(timeout: 10))
        capture(app, "leaving")
        app.terminate()
        let summary = launch(["-SeedScreenshotData", "-Screen", "summary", "-FixedNow", "08:14"])
        XCTAssertTrue(summary.buttons["Done"].waitForExistence(timeout: 10))
        sleep(2)
        capture(summary, "summary")
    }
}
