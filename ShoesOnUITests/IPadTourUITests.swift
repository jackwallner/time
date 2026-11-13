import XCTest

/// iPad frames of every main surface in portrait and landscape, for a person
/// to look at. Skips itself on iPhone. gh-sim cannot rotate a simulator, so the
/// rotation happens here and the frames come back as the run's attachments:
/// `gh-sim test --scheme ShoesOn --only ShoesOnUITests/IPadTourUITests
/// --device "iPad Pro 13-inch (M5)"`. Landscape frames come back as a portrait
/// buffer turned a quarter clockwise; turn them upright with `sips -r 270`.
@MainActor
final class IPadTourUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
    }

    private func launch(_ arguments: [String], landscape: Bool) -> XCUIApplication {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String, _ landscape: Bool) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "\(name)-\(landscape ? "land" : "port")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tour(_ name: String, _ arguments: [String], after: ((XCUIApplication) -> Void)? = nil) {
        for landscape in [false, true] {
            let app = launch(arguments, landscape: landscape)
            sleep(6)
            after?(app)
            attach(app, name, landscape)
            app.terminate()
        }
    }

    private let seeded = ["-SeedScreenshotData", "-FixedNow", "06:20"]

    func testHome() { tour("home", seeded) }
    func testOnboardingWelcome() { tour("onboarding-0", ["-OnboardingPage", "0"]) }
    func testOnboardingLeaveTime() { tour("onboarding-2", ["-OnboardingPage", "2"]) }
    func testOnboardingSteps() { tour("onboarding-3", ["-OnboardingPage", "3"]) }
    func testOnboardingReveal() { tour("onboarding-4", ["-OnboardingPage", "4"]) }
    func testOnboardingOffer() { tour("onboarding-5", ["-OnboardingPage", "5"]) }
    func testPaywall() { tour("paywall", ["-PaywallSnapshot", "yearly", "-DemoPro"]) }
    func testRunScreen() { tour("run", ["-SeedScreenshotData", "-DemoPro", "-Screen", "run", "-FixedNow", "07:45"]) }
    func testSummary() { tour("summary", ["-SeedScreenshotData", "-DemoPro", "-Screen", "summary", "-FixedNow", "08:14"]) }

    func testSettings() {
        tour("settings", seeded + ["-DemoPro"]) { app in
            app.buttons["Settings"].firstMatch.tap()
            sleep(2)
        }
    }

    func testRoutineEditor() {
        tour("editor", seeded + ["-DemoPro"]) { app in
            app.buttons["Edit"].firstMatch.tap()
            sleep(2)
        }
    }
}
