import Foundation

enum AppGroup {
    static let identifier = "group.com.jackwallner.time"
    static let subsystem = "com.jackwallner.time"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) { return url }
        // Unsigned simulator builds have no App Group; the fallback folder
        // does not exist until something makes it.
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}
