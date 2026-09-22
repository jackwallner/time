import Foundation

/// Small preferences. Routines and history live in `RoutineStore`.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = AppGroup.defaults

    @Published var hasCompletedSetup: Bool {
        didSet { defaults.set(hasCompletedSetup, forKey: Keys.setup) }
    }

    /// The "time to get ready" alert before each scheduled departure.
    @Published var startAlerts: Bool {
        didSet { defaults.set(startAlerts, forKey: Keys.start); changed() }
    }

    /// "Leave in 10 minutes" and "Time to go".
    @Published var leaveAlerts: Bool {
        didSet { defaults.set(leaveAlerts, forKey: Keys.leave); changed() }
    }

    /// During a run: wrap up this step, and a nudge when it runs over.
    @Published var stepNudges: Bool {
        didSet { defaults.set(stepNudges, forKey: Keys.nudges); changed() }
    }

    private enum Keys {
        static let setup = "hasCompletedSetup"
        static let start = "alerts.start"
        static let leave = "alerts.leave"
        static let nudges = "alerts.nudges"
    }

    private init() {
        defaults.register(defaults: [Keys.start: true, Keys.leave: true, Keys.nudges: true])
        hasCompletedSetup = defaults.bool(forKey: Keys.setup)
        startAlerts = defaults.bool(forKey: Keys.start)
        leaveAlerts = defaults.bool(forKey: Keys.leave)
        stepNudges = defaults.bool(forKey: Keys.nudges)
    }

    private func changed() {
        #if os(iOS)
        NotificationService.shared.reschedule(store: RoutineStore.shared)
        #endif
    }
}
