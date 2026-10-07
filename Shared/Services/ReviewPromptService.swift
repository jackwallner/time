import Foundation

/// When to ask for a rating: a genuinely good moment (walking out on time, for
/// the third time or more), at most once per cooldown. The ask is Apple's own
/// prompt with no question in front of it; guideline 5.6.1 rejects a gate that
/// sends only happy answers to the App Store. Feedback lives in Settings.
@MainActor
final class ReviewPromptService {
    static let shared = ReviewPromptService()

    static let minimumOnTimeDepartures = 3
    static let cooldownDays = 90

    private let defaults = AppGroup.defaults
    private static let lastAskedKey = "reviewLastAskedAt"
    private var askedThisSession = false

    private init() {}

    /// True when an on-time departure has earned the prompt; records the ask.
    func shouldAskAfterOnTimeDeparture(onTimeCount: Int) -> Bool {
        guard isEligible(onTimeCount: onTimeCount) else { return false }
        askedThisSession = true
        defaults.set(Date.now, forKey: Self.lastAskedKey)
        return true
    }

    func isEligible(onTimeCount: Int) -> Bool {
        guard !ScreenshotConfig.isEnabled, !askedThisSession else { return false }
        guard onTimeCount >= Self.minimumOnTimeDepartures else { return false }
        if let last = defaults.object(forKey: Self.lastAskedKey) as? Date {
            guard Date.now.timeIntervalSince(last) / 86_400 >= Double(Self.cooldownDays) else { return false }
        }
        return true
    }
}
