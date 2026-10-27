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

    /// The core loop: Done through the morning's steps, out the door, and the
    /// departure it records still counted on Home after a cold relaunch.
    func testCoreLoopRunFinishesAndRecordsTheDeparture() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.time")
        // Seeded mid-run on the real clock: Shower and Get dressed are done,
        // Breakfast is running, so the departure this run records is real.
        let seed = ["-SeedScreenshotData", "-Screen", "run"]
        QA.launch(app, arguments: seed)
        for (number, name) in [(3, "Breakfast"), (4, "Pack bag and lunch"), (5, "Shoes, keys, out")] {
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15))
            XCTAssertTrue(text("Step \(number) of 5", in: app).exists)
            QA.checkpoint(app, "run-step-\(number)")
            tap("Done", in: app)
        }
        tap("I'm out the door", in: app)

        // The summary: how early they left, and each step's real time
        // against its guess.
        let headline = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ min early\\.")).firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 15))
        let early = String(headline.label.dropLast())
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Out the door at ")).firstMatch.exists)
        for (name, guess) in [("Breakfast", 15), ("Pack bag and lunch", 5), ("Shoes, keys, out", 5)] {
            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", name, "guessed \(guess)")).firstMatch
            XCTAssertTrue(row.exists, "summary compares \(name) with its guess")
        }
        QA.checkpoint(app, "run-summary")

        // Off the seed, so a relaunch shows what was saved, not a fresh fixture.
        app.launchArguments.removeAll { seed.contains($0) }
        QA.relaunch(app)
        XCTAssertTrue(app.staticTexts[early + "."].waitForExistence(timeout: 20), "the summary survives a relaunch")
        QA.checkpoint(app, "run-summary-after-relaunch")
        tap("Done", in: app)
        home("home-after-run", in: app)
        XCTAssertTrue(newestDeparture(early, in: app).waitForExistence(timeout: 10), "Home counts the run just finished")

        QA.relaunch(app)
        home("home-after-run-relaunch", in: app)
        XCTAssertTrue(newestDeparture(early, in: app).waitForExistence(timeout: 10), "the departure survives a relaunch")
    }

    /// The record's strip reads oldest to newest, so the run just finished is last.
    private func newestDeparture(_ lateness: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", ", " + lateness)).firstMatch
    }

    private func text(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    private func start(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Start now", "Start early", "Practice run"])).firstMatch
    }

    private func tap(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
    }

    private func checkpoint(_ name: String, button label: String, in app: XCUIApplication, journey: String = #function) {
        XCTAssertTrue(app.buttons[label].firstMatch.waitForExistence(timeout: 15))
        QA.checkpoint(app, name, journey: journey)
    }

    private func home(_ name: String, in app: XCUIApplication, journey: String = #function) {
        XCTAssertTrue(start(in: app).waitForExistence(timeout: 20))
        QA.checkpoint(app, name, journey: journey)
    }
}
