import Foundation

enum AppGroup {
    static let identifier = "group.com.jackwallner.time"
    static let subsystem = "com.jackwallner.time"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// The shared container, or Application Support when the build has no
    /// App Group (an unsigned simulator build). That folder does not exist on
    /// a fresh install, so it is made here, or every save would fail.
    static var containerURL: URL {
        if let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return shared
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }
}
