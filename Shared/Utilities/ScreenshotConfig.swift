import Foundation

/// Screenshot mode, driven by launch arguments so App Store captures and UI
/// tests can open any surface with seeded data. Always false in Release.
enum ScreenshotConfig {
    #if DEBUG
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-SeedScreenshotData") || args.contains("-PaywallSnapshot")
    }

    static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func has(_ flag: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }
    #else
    static let isEnabled = false
    static func value(after flag: String) -> String? { nil }
    static func has(_ flag: String) -> Bool { false }
    #endif
}
