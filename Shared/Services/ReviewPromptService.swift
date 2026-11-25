import Foundation

/// When Shoes On may put Apple's own rating prompt on screen.
///
/// No question goes in front of it: an "Enjoying Shoes On?" step that sent
/// only the yeses to a rating is review gating under App Review 5.6.1. The
/// job is to ask early and often enough inside Apple's limits (three showings
/// a year, Apple's call each time): from the second launch on, at a good
/// morning (`isGoodMoment`), at most once every 30 days. A call Apple
/// swallows costs nothing. Feedback lives in Settings and never ends the asks.
@MainActor
final class ReviewPromptService {
    static let shared = ReviewPromptService()

    /// Not in the first session: a second launch is the only tenure gate.
    static let minimumLaunchCount = 2
    /// Days between calls. Paces the asks, not the answers.
    static let cooldownDays = 30
    /// A summary opened this long after walking out is a relaunch, not the
    /// moment itself.
    static let freshMomentSeconds: TimeInterval = 30 * 60

    private let defaults: UserDefaults
    private var recordedLaunch = false

    private enum Keys {
        /// Kept from 1.0.3, so an install asked then keeps its cooldown.
        static let lastAsked = "reviewLastAskedAt"
        static let launchCount = "review.launchCount"
        static let openedWriteReview = "review.openedWriteReview"
    }

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    var launchCount: Int { max(defaults.integer(forKey: Keys.launchCount), 0) }

    /// Once per process, when the app first comes on screen. A background
    /// launch for a Watch tap or an alert action is not a session.
    func recordLaunch() {
        guard !recordedLaunch else { return }
        recordedLaunch = true
        defaults.set(launchCount + 1, forKey: Keys.launchCount)
    }

    /// The good mornings: walking out on time for a real departure, or
    /// finishing a practice run with every step done. Seen on the summary
    /// right after, not on a summary reopened later.
    static func isGoodMoment(_ finished: FinishedRun, now: Date) -> Bool {
        guard now.timeIntervalSince(finished.departure.left) < freshMomentSeconds else { return false }
        if finished.run.isPracticeRun {
            return !finished.run.steps.isEmpty && finished.run.steps.allSatisfy { !$0.skipped && $0.actualSeconds != nil }
        }
        return finished.departure.wasOnTime
    }

    /// Whether a good moment right now may call `requestReview()`.
    func shouldRequestReview(now: Date = .now) -> Bool {
        guard !ScreenshotConfig.isEnabled else { return false }
        guard !defaults.bool(forKey: Keys.openedWriteReview) else { return false }
        guard launchCount >= Self.minimumLaunchCount else { return false }
        // A stamp from a clock that ran ahead is no evidence of an ask, and
        // would hold the cooldown shut for as long.
        guard let last = defaults.object(forKey: Keys.lastAsked) as? Date, last <= now else { return true }
        return now.timeIntervalSince(last) >= TimeInterval(Self.cooldownDays) * 86_400
    }

    /// Stamped when the call is made: Apple may show nothing, and there is
    /// no answer to wait for.
    func markAsked(now: Date = .now) {
        defaults.set(now, forKey: Keys.lastAsked)
    }

    /// Settings, Rate Shoes On. The one thing that ends the asks.
    func markOpenedWriteReview(now: Date = .now) {
        defaults.set(true, forKey: Keys.openedWriteReview)
        markAsked(now: now)
    }
}
