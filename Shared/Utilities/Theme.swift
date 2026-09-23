import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Every colour and radius in one place. Paper and ink at rest; colour only
/// where it carries meaning (on track, behind, late), and a dark, immersive
/// surface while a routine runs.
enum Theme {
    #if os(watchOS)
    static let background = Color.black
    static let surface = Color(white: 0.12)
    static let ink = Color.white
    static let secondary = Color(white: 0.68)
    static let inkInverse = Color.black
    #else
    static let background = Color(light: .init(0.965, 0.961, 0.945), dark: .init(0.043, 0.047, 0.055))
    static let surface = Color(light: .init(1, 1, 1), dark: .init(0.098, 0.106, 0.118))
    static let raised = Color(light: .init(0.935, 0.930, 0.912), dark: .init(0.150, 0.158, 0.172))
    static let ink = Color(light: .init(0.071, 0.078, 0.090), dark: .init(0.965, 0.961, 0.945))
    static let secondary = Color(light: .init(0.43, 0.44, 0.46), dark: .init(0.60, 0.62, 0.65))
    static let hairline = Color(light: .init(0.878, 0.870, 0.847), dark: .init(0.190, 0.200, 0.215))
    /// Text and glyphs drawn on an ink-filled control.
    static let inkInverse = Color(light: .init(0.980, 0.975, 0.960), dark: .init(0.060, 0.065, 0.075))
    /// The run screen's canvas, always dark.
    static let night = Color(red: 0.035, green: 0.040, blue: 0.050)
    #endif

    static let onTrack = Color(red: 0.16, green: 0.78, blue: 0.52)
    static let behind = Color(red: 1.00, green: 0.62, blue: 0.20)
    static let late = Color(red: 1.00, green: 0.36, blue: 0.33)
    /// The time your guesses leave out.
    static let gap = Color(red: 1.00, green: 0.62, blue: 0.20)

    static let radius: CGFloat = 28
    static let margin: CGFloat = 20

    static func color(for status: RunStatus) -> Color {
        switch status {
        case .ahead, .onTrack: onTrack
        case .behind(let minutes): minutes >= 5 ? late : behind
        }
    }
}

#if canImport(UIKit) && !os(watchOS)
extension Color {
    struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    init(light: RGB, dark: RGB) {
        self.init(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: 1)
        })
    }
}
#endif
