import Foundation

/// What RevenueCat can change without a release, read from the current
/// offering's metadata, so a running Experiment's variant is what gets read.
/// Every variant ships in the binary; a missing or unknown value is the
/// control, which is exactly what 1.0.3 shipped. Keys a switch reads must be
/// set the same on every offering, or an Experiment arm would flip them as a
/// side effect.
///
/// DEBUG builds can pin any key for captures: `-time.rc.<key> <value>`.
enum RemoteConfig {
    /// The value for `key`, or `fallback` when it is missing, not a string,
    /// or not one of the shipped variants.
    static func value<T: RawRepresentable>(_ key: String, in metadata: [String: Any]?, default fallback: T) -> T
    where T.RawValue == String {
        #if DEBUG
        if let pinned = launchOverride(key).flatMap(T.init(rawValue:)) { return pinned }
        #endif
        guard let raw = metadata?[key] as? String else { return fallback }
        return T(rawValue: raw) ?? fallback
    }

    /// On unless the metadata says "off".
    static func isOn(_ remoteSwitch: RemoteSwitch, in metadata: [String: Any]?) -> Bool {
        #if DEBUG
        if let pinned = launchOverride(remoteSwitch.rawValue) { return pinned != "off" }
        #endif
        return (metadata?[remoteSwitch.rawValue] as? String) != "off"
    }

    #if DEBUG
    private static func launchOverride(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-time.rc.\(key)"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    #endif
}

/// The trial button's wording, tested through offering metadata `trial_cta`.
/// Onboarding and the paywall both use sentence case.
enum TrialCTA: String, CaseIterable, Sendable {
    static let metadataKey = "trial_cta"

    /// Control: "Start 7-day free trial", as 1.0.3 shipped.
    case sevenDay = "seven_day"
    case my
    case your

    enum Surface: Sendable {
        case onboarding, paywall
    }

    static func from(metadata: [String: Any]?) -> TrialCTA {
        RemoteConfig.value(metadataKey, in: metadata, default: .sevenDay)
    }

    var title: String {
        switch self {
        case .sevenDay: "Start 7-day free trial"
        case .my: "Start my free trial"
        case .your: "Start your free trial"
        }
    }

    /// An Apple Account that already had its free week is charged on day
    /// one, so its button promises no trial (3.1.2). Each surface keeps the
    /// wording it shipped with.
    func title(_ surface: Surface, trialEligible: Bool) -> String {
        guard !trialEligible else { return title }
        switch surface {
        case .onboarding: return "Continue with Pro"
        case .paywall: return "Subscribe"
        }
    }
}

/// Remote off switches, for what is worth pausing without a release.
enum RemoteSwitch: String, CaseIterable, Sendable {
    /// Apple's rating prompt after a good morning.
    case ratingPrompt = "rating_prompt"
}
