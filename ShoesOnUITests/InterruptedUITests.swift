import XCTest

/// A tired user who is pulled away mid-task and comes back later: the app is
/// sent home or killed, then reopened with no launch arguments, as a real
/// return would be. Each test attaches screenshots and the visible text so a
/// run of it is also evidence of what the user finds on return.
@MainActor
final class InterruptedUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
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

    /// Every visible label and button title, so the report can say exactly what
    /// the user sees after the interruption.
    private func note(_ app: XCUIApplication, _ name: String) {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label)
        let buttons = app.buttons.allElementsBoundByIndex.prefix(40).map(\.label)
        let attachment = XCTAttachment(string: "texts: \(texts)\nbuttons: \(buttons)\n")
        attachment.name = name + "-visible"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func sendHomeAndBack(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
    }

    func testRunSurvivesBackgroundAndKill() {
        var app = launch(["-SeedScreenshotData", "-Screen", "run"])
        XCTAssertTrue(app.staticTexts["Breakfast"].waitForExistence(timeout: 15))
        capture(app, "01-run-before")
        sendHomeAndBack(app)
        XCTAssertTrue(app.staticTexts["Breakfast"].waitForExistence(timeout: 10))
        capture(app, "02-run-after-background")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Pack bag and lunch"].waitForExistence(timeout: 5))
        app.terminate()
        app = launch()
        let resumed = app.staticTexts["Pack bag and lunch"].waitForExistence(timeout: 15)
        capture(app, "03-run-after-kill")
        note(app, "03-run-after-kill")
        XCTAssertTrue(resumed, "the run should still be on the step after the one just finished")
    }

    func testSummarySurvivesKill() {
        var app = launch(["-SeedScreenshotData", "-Screen", "leaving"])
        XCTAssertTrue(app.buttons["I'm out the door"].waitForExistence(timeout: 15))
        app.buttons["I'm out the door"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        capture(app, "01-summary")
        app.terminate()
        app = launch()
        let back = app.buttons["Done"].waitForExistence(timeout: 15)
        capture(app, "02-summary-after-kill")
        note(app, "02-summary-after-kill")
        XCTAssertTrue(back, "the summary should wait for the user after a relaunch")
    }

    func testOnboardingAnswersAfterKill() {
        var app = launch(["-ResetState"])
        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        next.tap()
        XCTAssertTrue(app.staticTexts["About 30 minutes"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "About 45 minutes")).firstMatch.tap()
        next.tap()
        XCTAssertTrue(app.staticTexts["When do you need to walk out the door?"].waitForExistence(timeout: 5))
        capture(app, "01-onboarding-leave-page")
        sendHomeAndBack(app)
        XCTAssertTrue(app.staticTexts["When do you need to walk out the door?"].waitForExistence(timeout: 10))
        capture(app, "02-onboarding-after-background")
        app.terminate()
        app = launch()
        _ = app.buttons["Continue"].waitForExistence(timeout: 20)
        sleep(1)
        capture(app, "03-onboarding-after-kill")
        note(app, "03-onboarding-after-kill")
        XCTAssertTrue(
            app.staticTexts["When do you need to walk out the door?"].exists,
            "relaunch lands on the page the user left, not the welcome page"
        )
    }

    func testEditorDraftAfterBackgroundAndKill() {
        var app = launch(["-SeedScreenshotData"])
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 15))
        app.buttons["Edit"].tap()
        let name = app.textFields["Name, like Weekday mornings"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" and school run")
        capture(app, "01-editor-typed")
        sendHomeAndBack(app)
        XCTAssertTrue(app.navigationBars["Edit routine"].waitForExistence(timeout: 10))
        capture(app, "02-editor-after-background")
        app.terminate()
        app = launch()
        _ = app.buttons["Settings"].waitForExistence(timeout: 15)
        capture(app, "03-editor-after-kill")
        note(app, "03-editor-after-kill")
        XCTAssertTrue(
            app.navigationBars["Edit routine"].exists,
            "the editor with its unsaved text is gone after a kill and the edit is lost"
        )
    }

    /// Opened hours after the leave time with the run never closed, as when
    /// the user was pulled away mid-morning.
    func testStaleRunHoursLater() {
        var app = launch(["-SeedScreenshotData", "-Screen", "run", "-FixedNow", "07:30"])
        XCTAssertTrue(app.staticTexts["Breakfast"].waitForExistence(timeout: 15))
        capture(app, "01-run-at-0730")
        app.terminate()
        app = launch(["-FixedNow", "14:30"])
        _ = app.buttons["Settings"].waitForExistence(timeout: 15)
        sleep(2)
        capture(app, "02-after-seven-hours")
        note(app, "02-after-seven-hours")
        XCTAssertFalse(app.buttons["Done"].exists, "a run left open for hours should not still be on screen")
    }

    /// Back at the app a few minutes after the leave time, before leaving.
    func testReturningJustAfterLeaveTime() {
        let app = launch(["-SeedScreenshotData", "-FixedNow", "08:22"])
        let start = app.buttons.matching(NSPredicate(format: "label IN %@", ["Start now", "Start early", "Practice run"])).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        capture(app, "01-home-0822")
        note(app, "01-home-0822")
        start.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        sleep(1)
        capture(app, "02-run-started-0822")
        note(app, "02-run-started-0822")
    }
}
