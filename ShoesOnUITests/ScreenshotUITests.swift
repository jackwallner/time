import XCTest

/// Renders each surface from seeded data under StoreKit Testing, so the real
/// paywall prices show, and attaches a screenshot per surface. Also walks the
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

    /// One render per product for the App Review screenshots: each has to show
    /// its own billed amount.
    func testPaywallShowsEachPlanPrice() {
        for (plan, billed) in [("yearly", "Free for 7 days, then $9.99 per year"), ("monthly", "Free for 7 days, then $1.99 per month")] {
            let app = launch(["-PaywallSnapshot", plan])
            XCTAssertTrue(app.staticTexts[billed].waitForExistence(timeout: 10), plan)
            XCTAssertTrue(app.buttons["Start 7-day free trial"].exists)
            capture(app, "paywall-\(plan)")
            app.terminate()
        }
    }

    func testOnboardingPages() {
        for page in 0...5 {
            let app = launch(["-OnboardingPage", "\(page)"])
            XCTAssertTrue(app.buttons[page == 5 ? "Start 7-day free trial" : "Continue"].waitForExistence(timeout: 10))
            if page == 5 {
                XCTAssertTrue(app.buttons["Get Started"].exists)
            }
            capture(app, "onboarding-\(page)")
            app.terminate()
        }
    }

    /// The fleet contract: the primary button sits in the same frame on every
    /// onboarding page, trial page included.
    func testOnboardingButtonNeverMoves() {
        var frames: [CGRect] = []
        for page in [0, 4, 5] {
            let app = launch(["-OnboardingPage", "\(page)"])
            let button = app.buttons[page == 5 ? "Start 7-day free trial" : "Continue"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            frames.append(button.frame)
            app.terminate()
        }
        XCTAssertEqual(Set(frames.map { "\($0)" }).count, 1, "\(frames)")
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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Step 4 of 5")).firstMatch.exists)
        capture(app, "run-next")
    }

    func testLeavingAndSummary() {
        let app = launch(["-SeedScreenshotData", "-Screen", "leaving"])
        XCTAssertTrue(app.buttons["I'm out the door"].waitForExistence(timeout: 10))
        capture(app, "leaving")
        app.buttons["I'm out the door"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.terminate()
        let summary = launch(["-SeedScreenshotData", "-Screen", "summary"])
        XCTAssertTrue(summary.staticTexts["2 min early."].waitForExistence(timeout: 10))
        sleep(2)
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
