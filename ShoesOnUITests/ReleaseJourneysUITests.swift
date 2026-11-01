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
        // The answer can sit below the visible cards (always on the unfolded
        // Duo's shorter pane); scroll to it as a person would.
        let answer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "About 45 minutes")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        // The pager keeps the other pages' scroll views in the tree, so
        // swipe the one that holds the answer.
        let page = app.scrollViews.containing(NSPredicate(format: "label BEGINSWITH %@", "About 45 minutes")).firstMatch
        var scrolls = 0
        // On the Duo the card can sit under the button bar, where it still
        // reads as hittable; scroll until the page itself shows all of it.
        let bar = app.buttons["Continue"].firstMatch
        func covered() -> Bool { !page.frame.contains(answer.frame) || answer.frame.maxY > bar.frame.minY }
        // Drag on a card in plain view: low in the pane the drag would start
        // on the button bar and scroll nothing.
        let cards = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "About", "An hour"))
        func handle() -> XCUIElement {
            cards.allElementsBoundByIndex.first { $0.frame.minY > page.frame.minY && $0.frame.maxY < bar.frame.minY } ?? page
        }
        while covered() && scrolls < 6 {
            QA.swipe(handle(), .up)
            scrolls += 1
        }
        answer.tap()
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
            QA.swipe(app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch, .up)
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

    /// Core loop: run the routine, finish a step, and the run is still on
    /// that next step after the app is killed and reopened.
    func testCoreLoopRunAdvancesAndSurvivesRelaunch() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.time")
        QA.launch(app, arguments: ["-SeedScreenshotData", "-FixedNow", "06:20"])
        home("home", in: app)
        start(in: app).tap()
        let first = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Step 1 of")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        QA.checkpoint(app, "run-step-1")
        tap("Done", in: app)
        let second = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Step 2 of")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 10), "Done moves the run to step 2")
        QA.checkpoint(app, "run-step-2")
        // Reopen without the seed, which would replace the saved run.
        app.launchArguments.removeAll { $0 == "-SeedScreenshotData" }
        QA.relaunch(app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Step 2 of")).firstMatch
            .waitForExistence(timeout: 20), "the run resumes on step 2")
        QA.checkpoint(app, "run-after-relaunch")
        tap("End routine", in: app)
        tap("End without leaving", in: app)
        home("home-after-run", in: app)
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
