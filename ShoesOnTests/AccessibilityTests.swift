import SwiftUI
import UIKit
import XCTest
@testable import ShoesOn

@MainActor
final class AccessibilityTests: XCTestCase {
    func testStatusTextHasReadableContrastInLightAndDarkAppearance() {
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: appearance)
            for foreground in [Theme.onTrack, Theme.behind, Theme.late] {
                for background in [Theme.background, Theme.surface] {
                    let values = [foreground, background].map {
                        luminance(UIColor($0).resolvedColor(with: traits))
                    }
                    let contrast = (values.max()! + 0.05) / (values.min()! + 0.05)
                    XCTAssertGreaterThanOrEqual(contrast, 4.5, "Status text in \(appearance)")
                }
            }
        }
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        let channels = [red, green, blue].map {
            $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
        }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
}
