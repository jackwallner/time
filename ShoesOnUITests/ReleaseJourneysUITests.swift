import XCTest

@MainActor
final class ReleaseJourneysUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func test1SetupToOfferAndHome() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.time")
        QA.launch(app, arguments: ["-ResetState"])
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        checkpoint("welcome", button: "Continue", in: app)
        tap("Continue", in: app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "About 45 minutes")).firstMatch.tap()
        checkpoint("pace", button: "Continue", in: app)
        tap("Continue", in: app)
        XCTAssertTrue(app.staticTexts["When do you need to walk out the door?"].waitForExistence(timeout: 10))
        QA.checkpoint(app, "leave-time")
        tap("Continue", in: app)
        XCTAssertTrue(app.staticTexts["What happens before you leave?"].waitForExistence(timeout: 10))
        QA.checkpoint(app, "steps")
        tap("Continue", in: app)
        XCTAssertTrue(app.staticTexts["It really takes"].waitForExistence(timeout: 10))
        QA.checkpoint(app, "reveal")
        tap("Continue", in: app)
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 30))
        if allow.exists { allow.tap() }
        QA.checkpoint(app, "onboarding-offer", paywall: true)
        tap("Get Started", in: app)
        home("first-home", in: app)
    }

    func test2SettingsUpgradeRunAndReturn() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.time")
        QA.launch(app, arguments: ["-SeedScreenshotData", "-FixedNow", "06:20"])
        home("home", in: app)
        tap("Settings", in: app)
        checkpoint("settings", button: "Done", in: app)
        let pro = app.buttons["Try Shoes On Pro"].firstMatch
        var tries = 0
        while !(pro.exists && pro.isHittable) && tries < 6 {
            app.swipeUp()
            tries += 1
        }
        pro.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15))
        QA.checkpoint(app, "upgrade", paywall: true)
        tap("Close", in: app)
        tap("Done", in: app)
        home("home-after-upgrade", in: app)
        start(in: app).tap()
        checkpoint("run", button: "Done", in: app)
        tap("End routine", in: app)
        tap("End without leaving", in: app)
        home("home-after-run", in: app)
        QA.interrupt(app)
        home("home-after-background", in: app)
        QA.relaunch(app)
        home("home-after-relaunch", in: app)
    }

    private func start(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Start now", "Start early", "Practice run"])).firstMatch
    }

    private func tap(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
    }

    private func checkpoint(_ name: String, button label: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons[label].firstMatch.waitForExistence(timeout: 15))
        QA.checkpoint(app, name)
    }

    private func home(_ name: String, in app: XCUIApplication) {
        XCTAssertTrue(start(in: app).waitForExistence(timeout: 20))
        QA.checkpoint(app, name)
    }
}
