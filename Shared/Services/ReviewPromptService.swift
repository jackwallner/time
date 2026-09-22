import Foundation

/// The fleet review funnel: wait for a genuinely good moment (walking out on
/// time, for the third time or more), ask whether the app is helping, and only
/// then show Apple's prompt. A "not really" goes to feedback instead.
@MainActor
final class ReviewPromptService: ObservableObject {
    static let shared = ReviewPromptService()

    static let minimumOnTimeDepartures = 3
    static let cooldownDays = 90

    @Published var isPresented = false

    private let defaults = AppGroup.defaults
    private static let lastAskedKey = "reviewLastAskedAt"
    private static let hasRatedKey = "reviewHasRated"
    private var askedThisSession = false

    private init() {}

    /// Called when a summary shows an on-time departure.
    func considerAfterOnTimeDeparture(onTimeCount: Int) {
        guard isEligible(onTimeCount: onTimeCount) else { return }
        askedThisSession = true
        isPresented = true
    }

    func isEligible(onTimeCount: Int) -> Bool {
        guard !ScreenshotConfig.isEnabled, !askedThisSession else { return false }
        guard !defaults.bool(forKey: Self.hasRatedKey) else { return false }
        guard onTimeCount >= Self.minimumOnTimeDepartures else { return false }
        if let last = defaults.object(forKey: Self.lastAskedKey) as? Date {
            guard Date.now.timeIntervalSince(last) / 86_400 >= Double(Self.cooldownDays) else { return false }
        }
        return true
    }

    func markRated() {
        defaults.set(true, forKey: Self.hasRatedKey)
        defaults.set(Date.now, forKey: Self.lastAskedKey)
        isPresented = false
    }

    func markDeferred() {
        defaults.set(Date.now, forKey: Self.lastAskedKey)
        isPresented = false
    }
}
