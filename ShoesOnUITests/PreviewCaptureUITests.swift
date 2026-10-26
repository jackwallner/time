import XCTest

@MainActor
final class PreviewCaptureUITests: XCTestCase {
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-DemoPro"]
        app.launch()
        return app
    }

    func testPreviewWalkthrough() {
        installAlertDismisser()
        var app = launch(["-SeedScreenshotData", "-FixedNow", "06:50"])
        let start = app.buttons.matching(NSPredicate(format: "label IN %@", ["Start now", "Start early", "Practice run"])).firstMatch
        _ = start.waitForExistence(timeout: 20)
        print("PREVIEW-MARK home")
        pause(4)
        gentleScroll(app)
        pause(2.5)
        gentleScroll(app, up: false)
        pause(1)
        app.terminate()

        print("PREVIEW-MARK run")
        app = launch(["-SeedScreenshotData", "-Screen", "run", "-FixedNow", "07:45"])
        _ = app.buttons["Done"].waitForExistence(timeout: 15)
        pause(4)
        tapIfPresent(app.buttons["Done"])
        pause(3.5)
        app.terminate()

        print("PREVIEW-MARK leaving")
        app = launch(["-SeedScreenshotData", "-Screen", "leaving", "-FixedNow", "08:10"])
        _ = app.buttons["I'm out the door"].waitForExistence(timeout: 15)
        pause(4)
        app.terminate()

        print("PREVIEW-MARK summary")
        app = launch(["-SeedScreenshotData", "-Screen", "summary", "-FixedNow", "08:14"])
        _ = app.staticTexts["2 min early."].waitForExistence(timeout: 15)
        pause(4)
        gentleScroll(app)
        pause(3)
    }
}
