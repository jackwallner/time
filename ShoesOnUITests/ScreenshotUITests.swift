import XCTest

/// Renders each surface from seeded data under StoreKit Testing, so the real
/// paywall price shows, and attaches a screenshot per surface. Also walks the
/// run: Done advances the step.
final class ScreenshotUITests: XCTestCase {
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

    func testPaywallShowsTheLocalizedPrice() {
        let app = launch(["-PaywallSnapshot"])
        XCTAssertTrue(app.staticTexts["$14.99 once. No subscription."].waitForExistence(timeout: 10))
        capture(app, "paywall")
    }

    func testOnboardingPages() {
        for page in 0...5 {
            let app = launch(["-OnboardingPage", "\(page)"])
            XCTAssertTrue(app.buttons[page == 5 ? "Unlock Pro" : "Continue"].waitForExistence(timeout: 10))
            if page == 5 {
                XCTAssertTrue(app.staticTexts["$14.99, one-time purchase. No subscription."].waitForExistence(timeout: 10))
            }
            capture(app, "onboarding-\(page)")
            app.terminate()
        }
    }

    func testHome() {
        let app = launch(["-SeedScreenshotData"])
        XCTAssertTrue(app.buttons["Start now"].waitForExistence(timeout: 10))
        capture(app, "home")
        app.swipeUp()
        capture(app, "home-scrolled")
    }

    func testRunAdvancesOnDone() {
        let app = launch(["-SeedScreenshotData", "-Screen", "run"])
        XCTAssertTrue(app.staticTexts["Breakfast"].waitForExistence(timeout: 10))
        capture(app, "run")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Pack bag and lunch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Step 4 of 5"].exists)
    }

    func testLeavingAndSummary() {
        let app = launch(["-SeedScreenshotData", "-Screen", "leaving"])
        XCTAssertTrue(app.buttons["I'm out the door"].waitForExistence(timeout: 10))
        capture(app, "leaving")
        app.buttons["I'm out the door"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        capture(app, "summary-live")
        app.terminate()
        let summary = launch(["-SeedScreenshotData", "-Screen", "summary"])
        XCTAssertTrue(summary.staticTexts["2 min early."].waitForExistence(timeout: 10))
        capture(summary, "summary")
    }

    func testSettingsAndEditor() {
        let app = launch(["-SeedScreenshotData"])
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture(app, "settings")
        app.buttons["Done"].tap()
        app.buttons["Edit"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit routine"].waitForExistence(timeout: 5))
        capture(app, "editor")
    }
}
