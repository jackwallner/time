import XCTest

/// The skeptical free user: what is paid, what a lapse takes away, restore,
/// cancel and the ways out. Observations go to a notes attachment instead of
/// assertions, so a missing element becomes a note and a screenshot, not a
/// dead test. Tests run in name order and share one simulator install: P1
/// denies notifications (the system asks only once), P3 ends with Pro off.
@MainActor
final class SubscriptionAuditUITests: XCTestCase {
    private var notes: [String] = []
    private let bundleID = "com.jackwallner.time"

    override func setUp() {
        continueAfterFailure = true
        notes = []
    }

    override func tearDown() {
        let attachment = XCTAttachment(string: notes.joined(separator: "\n"))
        attachment.name = "notes"
        attachment.lifetime = .keepAlways
        add(attachment)
        super.tearDown()
    }

    // MARK: - P1: first run with notifications denied, the offer, the ways out

    func testP1_firstRunOfferRestoreAndExits() {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        QA.launch(app, arguments: ["-ResetState"])
        tap(app.buttons["Continue"], "welcome Continue", timeout: 30)
        tap(button(app, startingWith: "About 45 minutes"), "pace answer")
        tap(app.buttons["Continue"], "pace Continue")
        _ = app.staticTexts["When do you need to walk out the door?"].waitForExistence(timeout: 10)
        tap(app.buttons["Continue"], "leave Continue")
        _ = app.staticTexts["What happens before you leave?"].waitForExistence(timeout: 10)
        tap(app.buttons["Continue"], "steps Continue")
        _ = app.staticTexts["It really takes"].waitForExistence(timeout: 10)
        tap(app.buttons["Continue"], "reveal Continue")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch
        if deny.waitForExistence(timeout: 10) {
            shot("p1-01-permission-prompt")
            deny.tap()
        } else {
            note("no notification prompt appeared")
        }

        guard app.buttons["Get Started"].waitForExistence(timeout: 30) else {
            note("the offer page never showed")
            shot("p1-02-no-offer")
            return
        }
        sleep(2)
        shot("p1-02-offer-denied", tree: app)

        app.swipeUp()
        sleep(1)
        shot("p1-03-offer-scrolled", tree: app)

        if tap(app.buttons["Restore"], "offer Restore") {
            sleep(3)
            shot("p1-04-offer-after-restore")
        }

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 15)
        sleep(1)
        shot("p1-05-offer-after-background")

        app.terminate()
        app.launchArguments = []
        app.launch()
        let resumed = app.buttons["Get Started"].waitForExistence(timeout: 30)
        note("after kill and relaunch the offer is \(resumed ? "shown again" : "NOT shown")")
        sleep(2)
        shot("p1-06-offer-after-relaunch", tree: app)

        tap(app.buttons["Get Started"], "Get Started")
        guard startButton(app).waitForExistence(timeout: 20) else {
            note("Home never showed after Get Started")
            shot("p1-07-no-home")
            return
        }
        sleep(2)
        shot("p1-07-home-free", tree: app)

        guard tap(button(app, startingWith: "Routine,"), "routine menu") else { return }
        sleep(1)
        shot("p1-08-routine-menu-free", tree: app)
        let newRoutine = button(app, startingWith: "New routine")
        note("free menu item: \(newRoutine.exists ? newRoutine.label : "none")")
        guard tap(newRoutine, "New routine (Pro)") else { return }
        guard app.buttons["Close"].waitForExistence(timeout: 15) else {
            note("no paywall after New routine (Pro)")
            shot("p1-09-no-paywall")
            return
        }
        sleep(2)
        shot("p1-09-paywall-from-new-routine", tree: app)
        tap(app.buttons["Close"], "paywall Close")
        sleep(1)
        shot("p1-10-home-after-close")
    }

    // MARK: - P2: a free user in Settings: restore, the paywall, the exits

    func testP2_settingsRestoreAndPaywallExits() {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        QA.launch(app, arguments: ["-SeedScreenshotData", "-FixedNow", "06:20"])
        guard startButton(app).waitForExistence(timeout: 30) else {
            note("Home never showed")
            shot("p2-00-no-home")
            return
        }
        sleep(1)
        shot("p2-00-home-seeded-free")
        tap(app.buttons["Settings"], "Settings")
        guard app.buttons["Done"].waitForExistence(timeout: 10) else {
            note("Settings never showed")
            shot("p2-00-no-settings")
            return
        }
        let pro = app.buttons["Try Shoes On Pro"].firstMatch
        reveal(pro, in: app)
        sleep(1)
        shot("p2-01-settings-pro-section", tree: app)

        if tap(app.buttons["Restore purchase"].firstMatch, "Restore purchase") {
            if app.alerts.firstMatch.waitForExistence(timeout: 8) {
                note("restore alert: \(app.alerts.firstMatch.label)")
                shot("p2-02-restore-alert", tree: app)
                app.alerts.buttons["OK"].tap()
            } else {
                note("restore from Settings showed no alert")
                shot("p2-02-restore-no-alert")
            }
        }

        reveal(pro, in: app)
        guard tap(pro, "Try Shoes On Pro"), app.buttons["Close"].waitForExistence(timeout: 15) else {
            note("the paywall never showed from Settings")
            shot("p2-03-no-paywall")
            return
        }
        sleep(3)
        shot("p2-03-paywall-yearly", tree: app)
        QA.checkpoint(app, "paywall-settings", observe: 2, paywall: true)

        tap(button(app, startingWith: "Monthly"), "Monthly plan")
        sleep(1)
        shot("p2-04-paywall-monthly", tree: app)

        app.swipeUp()
        sleep(1)
        shot("p2-05-paywall-bottom", tree: app)

        if tap(app.buttons["Restore"], "paywall Restore") {
            sleep(3)
            shot("p2-06-paywall-after-restore")
        }

        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        from.press(forDuration: 0.1, thenDragTo: to)
        sleep(2)
        let dismissed = !app.buttons["Close"].exists
        note("swiping the paywall down dismisses it: \(dismissed)")
        shot("p2-07-after-swipe-down", tree: app)
        if !dismissed { tap(app.buttons["Close"], "paywall Close") }

        let forget = app.buttons["Forget my real times"]
        reveal(forget, in: app)
        if tap(forget, "Forget my real times") {
            sleep(1)
            shot("p2-08-forget-dialog", tree: app)
            tap(app.buttons["Cancel"], "Cancel forget")
        }

        tap(app.buttons["Done"], "Settings Done")
        sleep(1)
        shot("p2-09-home-after-settings")
    }

    // MARK: - P3: Pro lapses: what stays, what locks, what the user is told

    func testP3_lapsedProLocksRoutines() {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        QA.launch(app, arguments: ["-SeedScreenshotData", "-DemoPro", "-FixedNow", "06:20"])
        guard startButton(app).waitForExistence(timeout: 30) else {
            note("Home never showed")
            shot("p3-00-no-home")
            return
        }
        guard tap(button(app, startingWith: "Routine,"), "routine menu") else { return }
        sleep(1)
        shot("p3-01-menu-pro", tree: app)
        tap(button(app, startingWith: "New routine"), "New routine")
        let field = app.textFields.element(boundBy: 0)
        if field.waitForExistence(timeout: 10) {
            field.tap()
            field.typeText("Gym")
        } else {
            note("MISSING routine name field")
        }
        shot("p3-02-new-routine-editor")
        tap(app.buttons["Save"], "Save")
        let selected = app.buttons["Routine, Gym"].waitForExistence(timeout: 10)
        note("after saving, Gym is the selected routine: \(selected)")
        sleep(2)
        shot("p3-03-home-gym-selected-pro", tree: app)

        tap(app.buttons["Settings"], "Settings")
        _ = app.buttons["Done"].waitForExistence(timeout: 10)
        sleep(1)
        let manage = app.buttons["Manage subscription"]
        reveal(manage, in: app, tries: 3)
        shot("p3-04-settings-pro-active", tree: app)

        let proSwitch = app.switches["Pro"]
        reveal(proSwitch, in: app)
        shot("p3-05-debug-switch")
        tap(proSwitch, "Pro switch")
        sleep(1)
        for _ in 0..<8 { app.swipeDown() }
        sleep(1)
        shot("p3-06-settings-lapsed", tree: app)
        tap(app.buttons["Done"], "Settings Done")

        sleep(2)
        shot("p3-07-home-lapsed", tree: app)

        guard tap(button(app, startingWith: "Routine,"), "routine menu") else { return }
        sleep(1)
        shot("p3-08-menu-lapsed", tree: app)
        let gym = button(app, startingWith: "Gym")
        note("locked routine menu item label: \(gym.exists ? gym.label : "none")")
        if tap(gym, "Gym menu item"), app.buttons["Close"].waitForExistence(timeout: 15) {
            sleep(2)
            shot("p3-09-paywall-from-lock", tree: app)
            tap(app.buttons["Close"], "paywall Close")
        } else {
            note("tapping the locked routine showed no paywall")
            shot("p3-09-no-paywall")
        }

        sleep(1)
        tap(app.buttons["Edit"], "Edit")
        let delete = app.buttons["Delete routine"]
        reveal(delete, in: app)
        shot("p3-10-editor-delete", tree: app)
        if tap(delete, "Delete routine") {
            sleep(1)
            shot("p3-11-delete-dialog", tree: app)
            tap(app.buttons["Delete"], "Delete")
            sleep(2)
            shot("p3-12-home-after-delete", tree: app)
        }
    }

    // MARK: - P4: the cancel path while Pro is active

    func testP4_manageSubscriptionSheet() {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        QA.launch(app, arguments: ["-SeedScreenshotData", "-DemoPro", "-FixedNow", "06:20"])
        guard startButton(app).waitForExistence(timeout: 30) else {
            note("Home never showed")
            shot("p4-00-no-home")
            return
        }
        tap(app.buttons["Settings"], "Settings")
        _ = app.buttons["Done"].waitForExistence(timeout: 10)
        sleep(1)
        let manage = app.buttons["Manage subscription"]
        reveal(manage, in: app, tries: 3)
        shot("p4-01-settings-pro-active", tree: app)
        if tap(manage, "Manage subscription") {
            sleep(6)
            shot("p4-02-after-manage-tap", tree: app)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            note("springboard buttons after the tap: \(springboard.buttons.allElementsBoundByIndex.map(\.label))")
        }
    }

    // MARK: - Helpers

    private func note(_ text: String) {
        notes.append(text)
        print("AUDIT: \(text)")
    }

    private func shot(_ name: String, tree app: XCUIApplication? = nil) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let app else { return }
        let dump = XCTAttachment(string: app.debugDescription)
        dump.name = "\(name)-tree"
        dump.lifetime = .keepAlways
        add(dump)
    }

    @discardableResult
    private func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 10) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            note("MISSING \(what)")
            return false
        }
        element.tap()
        return true
    }

    private func button(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func startButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Start now", "Start early", "Practice run"])).firstMatch
    }

    /// Scrolls a lazy Form or ScrollView until the element can be tapped.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, tries: Int = 8) {
        var count = 0
        while !(element.exists && element.isHittable) && count < tries {
            app.swipeUp()
            count += 1
        }
    }
}
