import XCTest

/// A tired person pulled away mid-task who comes back minutes or hours later
/// and expects Shoes On to be where they left it. Each test attaches
/// screenshots and label dumps. Its expectations say what that person would
/// reasonably expect, so a failed expectation is an audit finding; a failure
/// that starts with SETUP means the script lost its footing, not the app.
/// Relaunches drop the seed arguments (a seed would replace what was saved).
@MainActor
final class InterruptedUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: - Helpers

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// Kills the app and opens it again with the given arguments, none by
    /// default, so only what it saved carries over.
    private func killAndReturn(_ app: XCUIApplication, arguments: [String] = []) {
        app.terminate()
        app.launchArguments = arguments
        app.launch()
    }

    private func background(_ app: XCUIApplication, seconds: UInt32 = 3) {
        XCUIDevice.shared.press(.home)
        sleep(seconds)
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 15)
        sleep(1)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ text: String, _ name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Every label on screen, attached for the report; returns the text ones.
    @discardableResult
    private func dump(_ app: XCUIApplication, _ name: String) -> [String] {
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
        let buttons = app.buttons.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
        note((texts.map { "text: \($0)" } + buttons.map { "button: \($0)" }).joined(separator: "\n"), "\(name).labels")
        return texts
    }

    private func require(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 20) -> Bool {
        if element.waitForExistence(timeout: timeout) { return true }
        XCTFail("SETUP: \(what) did not appear")
        return false
    }

    private func homeStart(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Start now", "Start early", "Practice run"])).firstMatch
    }

    /// Setup from the first page to the steps page, with a custom step typed
    /// into its field (not yet added).
    private func walkSetup(_ app: XCUIApplication, customStep: String) -> Bool {
        let next = app.buttons["Continue"]
        guard require(next, "welcome page", timeout: 30) else { return false }
        next.tap()
        guard require(app.staticTexts["About 30 minutes"], "pace page", timeout: 10) else { return false }
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "About 45 minutes")).firstMatch.tap()
        next.tap()
        guard require(app.staticTexts["When do you need to walk out the door?"], "leave page", timeout: 10) else { return false }
        next.tap()
        guard require(app.staticTexts["What happens before you leave?"], "steps page", timeout: 10) else { return false }
        let field = app.textFields["Add your own step"]
        app.swipeUp()
        guard require(field, "custom step field", timeout: 5) else { return false }
        field.tap()
        field.typeText(customStep)
        return true
    }

    // MARK: - Tests (alphabetical is run order, most telling first)

    /// A tapped get-ready alert or the Lock Screen Start control begins a run
    /// while the routine editor is open with typed changes. `-StartRunAfter`
    /// calls the same `startNextRun` those do, 45 seconds after launch.
    func test1_RunStartingWhileEditingKeepsTheTypedChanges() {
        let app = launch(["-SeedScreenshotData", "-StartRunAfter", "45"])
        guard require(app.buttons["Edit"], "Home Edit button") else { return }
        app.buttons["Edit"].tap()
        let name = app.textFields["Name, like Weekday mornings"]
        guard require(name, "editor name field", timeout: 10) else { return }
        name.tap()
        name.typeText(" for the dentist")
        if app.buttons["End routine"].exists {
            XCTFail("SETUP: the run started before the edit was typed")
            return
        }
        capture(app, "01-editor-typed")
        note("name field value: \((name.value as? String) ?? "nil")", "01-editor-typed.value")
        guard require(app.buttons["End routine"], "the run that starts by itself", timeout: 120) else { return }
        sleep(1)
        capture(app, "02-run-over-the-editor")
        app.buttons["End routine"].tap()
        guard require(app.buttons["End without leaving"], "end confirmation", timeout: 5) else { return }
        app.buttons["End without leaving"].tap()
        guard require(app.buttons["Settings"], "Home after the run", timeout: 15) else { return }
        sleep(1)
        capture(app, "03-after-the-run")
        note(app.debugDescription, "03-after-the-run.tree")
        XCTAssertTrue(
            app.navigationBars["Edit routine"].exists,
            "the editor, and what was typed in it, is still open once the run ends"
        )
    }

    /// Pulled away mid-breakfast for fifty minutes with no history yet (the
    /// first week), then Done on that step and a tap through the rest.
    func test2_OneInterruptedMorningMovesTheNewUsersPlan() {
        overdueScenario(extra: ["-NoHistory"], tag: "newuser")
    }

    /// The same interruption after twelve ordinary mornings of history.
    func test3_OneInterruptedMorningMovesTheTwelveMorningPlan() {
        overdueScenario(extra: [], tag: "twelve")
    }

    private func overdueScenario(extra: [String], tag: String) {
        let seed = ["-SeedScreenshotData"] + extra
        let app = launch(seed)
        guard require(homeStart(app), "Home") else { return }
        sleep(1)
        capture(app, "\(tag)-01-home-before")
        let before = dump(app, "\(tag)-01-home-before").filter { $0.contains("your guess leaves out") }
        killAndReturn(app, arguments: seed + ["-Screen", "overdue"])
        guard require(app.buttons["Done"], "the overdue run") else { return }
        sleep(2)
        capture(app, "\(tag)-02-run-on-return")
        dump(app, "\(tag)-02-run-on-return")
        for step in 1...3 {
            let done = app.buttons["Done"]
            guard done.waitForExistence(timeout: 5) else { break }
            done.tap()
            sleep(1)
            if step == 1 { capture(app, "\(tag)-03-after-first-done") }
        }
        guard require(app.buttons["I'm out the door"], "the leaving face", timeout: 10) else { return }
        capture(app, "\(tag)-04-leaving")
        app.buttons["End routine"].tap()
        guard require(app.buttons["End without leaving"], "end confirmation", timeout: 5) else { return }
        app.buttons["End without leaving"].tap()
        guard require(homeStart(app), "Home after the run", timeout: 15) else { return }
        sleep(1)
        capture(app, "\(tag)-05-home-after")
        let after = dump(app, "\(tag)-05-home-after").filter { $0.contains("your guess leaves out") }
        note("before: \(before)\nafter: \(after)", "\(tag)-plan-gap")
        XCTAssertFalse(before.isEmpty, "SETUP: Home showed no guess gap line before the run")
        XCTAssertEqual(after, before, "one interrupted morning leaves the plan as it was")
    }

    /// Down for a few seconds, then killed, with a run in progress.
    func test4_RunSurvivesBackgroundAndKill() {
        let app = launch(["-SeedScreenshotData", "-Screen", "run"])
        guard require(app.buttons["Done"], "the run") else { return }
        sleep(1)
        capture(app, "01-run-before")
        dump(app, "01-run-before")
        background(app)
        capture(app, "02-run-after-background")
        XCTAssertTrue(app.buttons["Done"].exists, "the run is still on screen after a short interruption")
        killAndReturn(app)
        let back = app.buttons["Done"].waitForExistence(timeout: 20)
        sleep(1)
        capture(app, "03-run-after-kill")
        let after = dump(app, "03-run-after-kill")
        XCTAssertTrue(back, "the run is back after the app was killed and opened again")
        XCTAssertTrue(after.contains("Breakfast"), "the same step is current")
    }

    /// A routine edited and left, put down, then the app killed.
    func test5_EditorDraftAfterBackgroundAndKill() {
        let app = launch(["-SeedScreenshotData"])
        guard require(app.buttons["Edit"], "Home Edit button") else { return }
        app.buttons["Edit"].tap()
        let name = app.textFields["Name, like Weekday mornings"]
        guard require(name, "editor name field", timeout: 10) else { return }
        name.tap()
        name.typeText(" for the dentist")
        let add = app.textFields["Add a step"]
        if add.waitForExistence(timeout: 3) {
            add.tap()
            add.typeText("Find the insurance card")
        }
        capture(app, "01-editor-typed")
        background(app)
        capture(app, "02-editor-after-background")
        XCTAssertTrue(app.navigationBars["Edit routine"].exists, "the editor is still open after a short interruption")
        killAndReturn(app)
        guard require(app.buttons["Edit"], "Home after the kill") else { return }
        sleep(1)
        capture(app, "03-home-after-kill")
        app.buttons["Edit"].tap()
        let again = app.textFields["Name, like Weekday mornings"]
        guard require(again, "editor name field again", timeout: 10) else { return }
        capture(app, "04-editor-reopened")
        let value = (again.value as? String) ?? ""
        note("name after kill: \(value)", "04-editor-reopened.value")
        XCTAssertTrue(value.contains("for the dentist"), "the edit typed before the interruption is still there")
    }

    /// Setup interrupted on the steps page, then the app killed.
    func test6_SetupAnswersAfterKill() {
        let app = launch(["-ResetState"])
        guard walkSetup(app, customStep: "Feed the cat") else { return }
        capture(app, "01-steps-typed")
        app.buttons["Continue"].tap()
        guard require(app.staticTexts["It really takes"], "reveal", timeout: 10) else { return }
        capture(app, "02-reveal")
        background(app)
        capture(app, "03-reveal-after-background")
        XCTAssertTrue(app.staticTexts["It really takes"].exists, "setup is on the same page after a short interruption")
        killAndReturn(app)
        let welcome = app.buttons["Continue"]
        guard require(welcome, "the first page after the kill", timeout: 30) else { return }
        sleep(1)
        capture(app, "04-after-kill")
        let labels = dump(app, "04-after-kill")
        let wherever = app.staticTexts["It really takes"].exists
            || app.staticTexts["What happens before you leave?"].exists
            || app.staticTexts["When do you need to walk out the door?"].exists
            || labels.contains { $0.contains("About 30 minutes") }
        XCTAssertTrue(wherever, "setup reopens on the page it was left on, with the answers given")
    }

    /// A run nobody closed, four hours past its leave time, then the app.
    func test7_RunLeftOpenForHours() {
        let app = launch(["-SeedScreenshotData", "-Screen", "stale"])
        sleep(4)
        capture(app, "01-launch-with-a-stale-run")
        dump(app, "01-launch-with-a-stale-run")
        killAndReturn(app)
        guard require(homeStart(app), "Home after the return") else { return }
        sleep(1)
        capture(app, "02-home-after-return")
        let labels = dump(app, "02-home-after-return")
        let explained = labels.contains {
            $0.range(of: "run|morning", options: [.regularExpression, .caseInsensitive]) != nil
                && $0.range(of: "closed|ended|expired|left open|over", options: [.regularExpression, .caseInsensitive]) != nil
        }
        XCTAssertTrue(explained, "Home says what became of the run that was left open")
    }

    /// The summary of a finished morning, then the app killed.
    func test8_SummarySurvivesKill() {
        // The clock is pinned on both launches: a summary older than 12 hours
        // is dropped on purpose, and the runner's own hour is not the test's.
        let app = launch(["-SeedScreenshotData", "-Screen", "summary", "-FixedNow", "08:14"])
        guard require(app.buttons["Done"], "the summary") else { return }
        sleep(1)
        capture(app, "01-summary")
        killAndReturn(app, arguments: ["-FixedNow", "08:20"])
        let back = app.buttons["Done"].waitForExistence(timeout: 20)
        sleep(1)
        capture(app, "02-summary-after-kill")
        XCTAssertTrue(back, "the summary of the morning is still there after the kill")
        if back {
            app.buttons["Done"].tap()
            XCTAssertTrue(homeStart(app).waitForExistence(timeout: 15), "Done on the summary lands on Home")
            capture(app, "03-home-after-summary")
        }
    }

    /// Killed on the Pro offer, which the routine was saved before.
    func test9_KillOnTheOfferResumesThereWithTheRoutine() {
        let app = launch(["-ResetState"])
        guard walkSetup(app, customStep: "Feed the cat") else { return }
        app.buttons["Continue"].tap()
        guard require(app.staticTexts["It really takes"], "reveal", timeout: 10) else { return }
        app.buttons["Continue"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        guard require(app.buttons["Get Started"], "the offer page", timeout: 30) else { return }
        if allow.exists { allow.tap() }
        capture(app, "01-offer")
        killAndReturn(app)
        let resumed = app.buttons["Get Started"].waitForExistence(timeout: 30)
        sleep(1)
        capture(app, "02-offer-after-kill")
        XCTAssertTrue(resumed, "the app reopens on the offer, not at page one")
        guard resumed else { return }
        app.buttons["Get Started"].tap()
        XCTAssertTrue(homeStart(app).waitForExistence(timeout: 15), "Get Started lands on Home")
        sleep(1)
        capture(app, "03-home")
        let labels = dump(app, "03-home")
        XCTAssertTrue(labels.contains { $0.contains("Feed the cat") }, "the step typed in setup is in the saved plan")
    }

    /// Back at the phone after the get-ready alert went unanswered, and again
    /// after the leave time itself passed.
    func test10_ReturningAfterTheAlertAndAfterTheLeaveTime() {
        let seed = ["-SeedScreenshotData", "-FixedNow", "07:58"]
        let app = launch(seed)
        guard require(homeStart(app), "Home at 07:58") else { return }
        sleep(1)
        capture(app, "01-home-0758")
        dump(app, "01-home-0758")
        killAndReturn(app, arguments: ["-SeedScreenshotData", "-FixedNow", "08:22"])
        guard require(homeStart(app), "Home at 08:22") else { return }
        sleep(1)
        capture(app, "02-home-0822")
        let labels = dump(app, "02-home-0822")
        let today = labels.contains { $0.range(of: "today", options: .caseInsensitive) != nil }
        note("a label mentions today: \(today)", "02-home-0822.today")
        XCTAssertTrue(today, "Home still offers this morning, seven minutes after the leave time")
    }
}
