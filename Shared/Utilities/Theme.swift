import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Every colour and radius in one place. The app is deliberately quiet: paper
/// and ink, with colour reserved for whether the morning is on schedule.
enum Theme {
    #if os(watchOS)
    static let background = Color.black
    static let surface = Color(white: 0.12)
    static let ink = Color.white
    static let secondary = Color(white: 0.68)
    static let inkInverse = Color.black
    #else
    static let background = Color(light: .init(0.972, 0.965, 0.945), dark: .init(0.055, 0.058, 0.062))
    static let surface = Color(light: .init(1, 1, 1), dark: .init(0.105, 0.110, 0.118))
    static let ink = Color(light: .init(0.090, 0.098, 0.110), dark: .init(0.960, 0.955, 0.940))
    static let secondary = Color(light: .init(0.42, 0.43, 0.45), dark: .init(0.62, 0.63, 0.65))
    static let hairline = Color(light: .init(0.88, 0.87, 0.84), dark: .init(0.20, 0.21, 0.22))
    /// Text and glyphs drawn on an ink-filled button.
    static let inkInverse = Color(light: .init(0.980, 0.975, 0.960), dark: .init(0.070, 0.074, 0.080))
    #endif

    static let onTrack = Color(red: 0.13, green: 0.62, blue: 0.43)
    static let behind = Color(red: 0.93, green: 0.55, blue: 0.13)
    static let late = Color(red: 0.86, green: 0.27, blue: 0.22)

    static let radius: CGFloat = 20
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
