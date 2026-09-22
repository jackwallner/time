import Foundation

/// One thing that happens before leaving, with the user's own guess of how long
/// it takes. The guess is never overwritten: the gap between it and the real
/// time is the point of the app.
struct RoutineStep: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var guessMinutes: Int

    init(id: UUID = UUID(), name: String, guessMinutes: Int) {
        self.id = id
        self.name = name
        self.guessMinutes = guessMinutes
    }
}

/// A departure the user makes on a schedule: when they walk out the door, on
/// which days, and the steps that come before it.
struct Routine: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var leaveHour: Int
    var leaveMinute: Int
    /// `Calendar` weekdays, 1 = Sunday through 7 = Saturday.
    var weekdays: Set<Int>
    var steps: [RoutineStep]

    init(
        id: UUID = UUID(),
        name: String,
        leaveHour: Int,
        leaveMinute: Int,
        weekdays: Set<Int>,
        steps: [RoutineStep]
    ) {
        self.id = id
        self.name = name
        self.leaveHour = leaveHour
        self.leaveMinute = leaveMinute
        self.weekdays = weekdays
        self.steps = steps
    }

    var guessTotalMinutes: Int { steps.reduce(0) { $0 + $1.guessMinutes } }

    /// The leave time on the given day, in the calendar's time zone.
    func leaveTime(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: leaveHour, minute: leaveMinute, second: 0, of: day) ?? day
    }

    /// The next scheduled departure strictly after `now`, on an enabled weekday.
    func nextScheduledLeave(after now: Date, calendar: Calendar = .current) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            guard weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            let leave = leaveTime(on: day, calendar: calendar)
            if leave > now { return leave }
        }
        return nil
    }

    /// The leave time a run started now aims for: today's if it is still ahead,
    /// otherwise tomorrow's. Weekdays are ignored so the routine can be run on
    /// any day by hand.
    func leaveTimeForRunStarted(at now: Date, calendar: Calendar = .current) -> Date {
        let today = leaveTime(on: now, calendar: calendar)
        if today > now { return today }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return leaveTime(on: tomorrow, calendar: calendar)
    }
}

/// How long a step really took, captured when the user taps Done.
struct StepRecord: Codable, Hashable, Sendable {
    var stepID: UUID
    var routineID: UUID
    var guessMinutes: Int
    var actualSeconds: TimeInterval
    var date: Date

    var ratio: Double {
        guard guessMinutes > 0 else { return 1 }
        return actualSeconds / Double(guessMinutes * 60)
    }
}

/// One finished run: when the user actually walked out, against when they meant to.
struct DepartureRecord: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var routineID: UUID
    var target: Date
    var left: Date
    /// Seconds between the get-ready alert and the moment the run was started.
    /// Nil when the run was not a response to an alert.
    var startDelaySeconds: TimeInterval?

    init(
        id: UUID = UUID(),
        routineID: UUID,
        target: Date,
        left: Date,
        startDelaySeconds: TimeInterval?
    ) {
        self.id = id
        self.routineID = routineID
        self.target = target
        self.left = left
        self.startDelaySeconds = startDelaySeconds
    }

    /// Positive when late, negative when early.
    var lateSeconds: TimeInterval { left.timeIntervalSince(target) }

    /// A minute of grace, so leaving at 8:15:40 for 8:15 still counts.
    var wasOnTime: Bool { lateSeconds <= 60 }
}

/// The answer to the onboarding question "when getting ready feels like an
/// hour, it usually takes…". It seeds the pace multiplier until real runs
/// replace it.
enum PaceAnswer: String, Codable, CaseIterable, Identifiable, Sendable {
    case onTheDot
    case quarterOver
    case halfOver
    case doubleOver

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .onTheDot: 1.0
        case .quarterOver: 1.25
        case .halfOver: 1.5
        case .doubleOver: 2.0
        }
    }

    var title: String {
        switch self {
        case .onTheDot: "About an hour"
        case .quarterOver: "An hour and 15 minutes"
        case .halfOver: "An hour and a half"
        case .doubleOver: "Closer to two hours"
        }
    }

    var detail: String {
        switch self {
        case .onTheDot: "My guesses are usually right"
        case .quarterOver: "I run a little behind"
        case .halfOver: "I'm often 20 to 30 minutes late"
        case .doubleOver: "I'm late more often than not"
        }
    }
}
