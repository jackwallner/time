import XCTest
@testable import ShoesOn

/// The offering-metadata reader and the trial button's wording test.
final class RemoteConfigTests: XCTestCase {
    func testMissingNonStringAndUnknownValuesAreTheControl() {
        XCTAssertEqual(TrialCTA.from(metadata: nil), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: [:]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": 3]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": ["my"]]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "ours"]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["other": "my"]), .sevenDay)
    }

    func testEachKnownValueIsItsArm() {
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "seven_day"]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "my"]), .my)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "your"]), .your)
        XCTAssertEqual(TrialCTA.metadataKey, "trial_cta")
    }

    /// The control is 1.0.3's button on both surfaces, character for character.
    func testControlIsTheShippedCopyOnBothSurfaces() {
        XCTAssertEqual(TrialCTA.sevenDay.title(.onboarding, trialEligible: true), "Start 7-day free trial")
        XCTAssertEqual(TrialCTA.sevenDay.title(.paywall, trialEligible: true), "Start 7-day free trial")
    }

    func testEachArmsTitlePerSurface() {
        for surface in [TrialCTA.Surface.onboarding, .paywall] {
            XCTAssertEqual(TrialCTA.my.title(surface, trialEligible: true), "Start my free trial")
            XCTAssertEqual(TrialCTA.your.title(surface, trialEligible: true), "Start your free trial")
        }
    }

    /// No arm promises a trial to an account that already used one (3.1.2).
    func testIneligibleWordingIsUnchangedInEveryArm() {
        for arm in TrialCTA.allCases {
            XCTAssertEqual(arm.title(.onboarding, trialEligible: false), "Continue with Pro")
            XCTAssertEqual(arm.title(.paywall, trialEligible: false), "Subscribe")
        }
    }

    func testSwitchIsOnUnlessOff() {
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: nil))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: [:]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "on"]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": false]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "OFF"]))
        XCTAssertFalse(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "off"]))
        XCTAssertEqual(RemoteSwitch.ratingPrompt.rawValue, "rating_prompt")
    }

    func testCopyHasNoDashes() {
        for arm in TrialCTA.allCases {
            for title in [arm.title(.onboarding, trialEligible: true), arm.title(.paywall, trialEligible: true)] {
                XCTAssertFalse(title.contains("\u{2014}") || title.contains("\u{2013}"), title)
            }
        }
    }
}
