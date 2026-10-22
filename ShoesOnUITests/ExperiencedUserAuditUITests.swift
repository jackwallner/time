import XCTest

/// Persona audit: someone who has run the routine for weeks and now wants
/// accurate, efficient deeper features. Observations are attached as text and
/// screenshots rather than asserted, so a finding never hides behind a red run.
@MainActor
final class ExperiencedUserAuditUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
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

    private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func size(_ element: XCUIElement) -> String {
        let f = element.frame
        return String(format: "%.0fx%.0f at (%.0f, %.0f)", f.width, f.height, f.minX, f.minY)
    }

    func testHomeTouchTargetsAndRecordCard() {
        let app = launch(["-SeedScreenshotData", "-FixedNow", "06:20"])
        XCTAssertTrue(app.buttons["Change a day"].waitForExistence(timeout: 20))
        capture(app, "e01-home-top")
        var lines: [String] = []
        for label in ["Change a day", "Settings", "Routines", "Edit"] {
            let el = app.buttons[label].firstMatch
            lines.append("\(label): \(el.exists ? size(el) : "not found")")
        }
        let start = app.buttons.matching(NSPredicate(format: "label IN %@", ["Start now", "Start early", "Practice run"])).firstMatch
        lines.append("Start button: \(start.exists ? size(start) : "not found")")
        note("e01-touch-target-sizes", lines.joined(separator: "\n"))
        app.swipeUp()
        capture(app, "e02-home-record-card")
        // The lateness strip is one accessibility element: can a user drill
        // into a single morning from it?
        let strip = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'early' OR label CONTAINS[c] 'late' OR label CONTAINS[c] 'on time'")).allElementsBoundByIndex
        note("e02-record-card-elements", strip.map { "\($0.elementType.rawValue): \($0.label)" }.joined(separator: "\n"))
    }

    func testDayPickerReach() {
        let app = launch(["-SeedScreenshotData", "-OpenDayChange", "-FixedNow", "06:20"])
        XCTAssertTrue(app.navigationBars["Just this once"].waitForExistence(timeout: 20))
        let days = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "(Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day.*"))
        note("e03-day-strip", "Selectable days in the sheet: \(days.count)\n" + days.allElementsBoundByIndex.map(\.label).joined(separator: "\n"))
        capture(app, "e03-day-sheet")
        let sizes = days.allElementsBoundByIndex.prefix(2).map { size($0) }.joined(separator: "\n")
        note("e03-day-button-size", sizes)
    }

    func testEditorStepperGranularity() {
        let app = launch(["-SeedScreenshotData"])
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 20))
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit routine"].waitForExistence(timeout: 5))
        capture(app, "e04-editor-top")
        app.swipeUp()
        capture(app, "e05-editor-steps")
        let steppers = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ minutes"))
        guard steppers.count > 0 else {
            note("e05-stepper", "No stepper element found")
            return
        }
        let first = steppers.firstMatch
        var seen = [first.label]
        let plus = first.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        for _ in 0..<4 {
            plus.tap()
            usleep(400_000)
            seen.append(steppers.firstMatch.label)
        }
        note("e05-stepper-sequence", "Stepper \(size(first)); tapping plus walks: \(seen.joined(separator: " -> "))")
        capture(app, "e06-editor-after-plus")
    }

    func testNewRoutineGateAndDefaults() {
        let free = launch(["-SeedScreenshotData"])
        XCTAssertTrue(free.buttons["Routines"].waitForExistence(timeout: 20))
        free.buttons["Routines"].tap()
        usleep(600_000)
        capture(free, "e07-routine-menu-free")
        note("e07-menu-items", free.buttons.allElementsBoundByIndex.map(\.label).joined(separator: "\n"))
        free.terminate()

        let pro = launch(["-SeedScreenshotData", "-DemoPro"])
        XCTAssertTrue(pro.buttons["Routines"].waitForExistence(timeout: 20))
        pro.buttons["Routines"].tap()
        let new = pro.buttons["New routine"]
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        XCTAssertTrue(pro.navigationBars["New routine"].waitForExistence(timeout: 5))
        capture(pro, "e08-new-routine-empty")
        let save = pro.buttons["Save"]
        note("e08-new-routine", "Save enabled with empty name: \(save.isEnabled)\nButtons: \(pro.buttons.allElementsBoundByIndex.map(\.label).joined(separator: " | "))")
    }

    func testRunScreenControlsAndUndoWindow() {
        let app = launch(["-SeedScreenshotData", "-Screen", "run"])
        XCTAssertTrue(app.staticTexts["Breakfast"].waitForExistence(timeout: 20))
        capture(app, "e09-run")
        note("e09-run-buttons", app.buttons.allElementsBoundByIndex.map { "\($0.label) \(size($0))" }.joined(separator: "\n"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Undo Breakfast done"].waitForExistence(timeout: 5))
        usleep(800_000)
        let skipHidden = !app.buttons["Skip this step"].exists
        capture(app, "e10-run-after-done")
        note("e10-skip-during-undo", "Skip this step hidden while Undo is offered: \(skipHidden)")
        // A second Done on the next step replaces the first undo.
        app.buttons["Done"].tap()
        usleep(800_000)
        let firstUndoGone = !app.buttons["Undo Breakfast done"].exists
        capture(app, "e11-run-second-done")
        note("e11-undo-depth", "Undo for the earlier step gone after the next Done: \(firstUndoGone)\nButtons: \(app.buttons.allElementsBoundByIndex.map(\.label).joined(separator: " | "))")
    }

    func testSettingsForgetWipesTheRecord() {
        let app = launch(["-SeedScreenshotData", "-FixedNow", "06:20"])
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 20))
        app.swipeUp()
        capture(app, "e12-home-record-before")
        app.swipeDown()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture(app, "e13-settings")
        let forget = app.buttons["Forget my real times"]
        if !forget.isHittable { app.swipeUp() }
        capture(app, "e14-settings-bottom")
        forget.tap()
        XCTAssertTrue(app.buttons["Forget"].waitForExistence(timeout: 5))
        capture(app, "e15-forget-dialog")
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Plans go back'")).firstMatch
        note("e15-forget-message", "Dialog text: \(message.exists ? message.label : "not found")")
        app.buttons["Forget"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        app.swipeUp()
        capture(app, "e16-home-record-after")
    }
}
