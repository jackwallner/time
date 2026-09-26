import Foundation

struct RunStep: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var guessMinutes: Int
    /// The realistic minutes the plan gave this step when the run began.
    var plannedMinutes: Int
    var actualSeconds: TimeInterval?
    var skipped: Bool = false

    var plannedSeconds: TimeInterval { TimeInterval(plannedMinutes * 60) }
}

/// Whether the morning is on schedule, measured against the leave time.
enum RunStatus: Hashable, Sendable {
    case ahead(minutes: Int)
    case onTrack
    case behind(minutes: Int)

    /// A minute of slack either way reads as on track; the plan has minute
    /// resolution and anything finer is noise.
    init(slipSeconds: TimeInterval) {
        if slipSeconds <= -120 {
            self = .ahead(minutes: Int((-slipSeconds / 60).rounded(.down)))
        } else if slipSeconds <= 60 {
            self = .onTrack
        } else {
            self = .behind(minutes: Int((slipSeconds / 60).rounded(.up)))
        }
    }

    var label: String {
        switch self {
        case .ahead(let minutes): "\(minutes) min to spare"
        case .onTrack: "On track"
        case .behind(let minutes): "\(minutes) min behind"
        }
    }

    var isBehind: Bool {
        if case .behind = self { return true }
        return false
    }
}

/// A routine in progress. Pure value: the store persists it and every surface
/// (app, Live Activity, Watch) derives the same answers from it.
struct ActiveRun: Codable, Hashable, Sendable {
    var routineID: UUID
    var routineName: String
    var leaveAt: Date
    var startedAt: Date
    /// When the get-ready alert was due for this departure, if one was.
    var alertAt: Date?
    var steps: [RunStep]
    var stepIndex: Int
    var stepStartedAt: Date

    init(plan: DeparturePlan, routineName: String, startedAt: Date, alertAt: Date?) {
        routineID = plan.routineID
        self.routineName = routineName
        leaveAt = plan.leaveAt
        self.startedAt = startedAt
        self.alertAt = alertAt
        steps = plan.steps.map {
            RunStep(
                id: $0.step.id,
                name: $0.step.name,
                guessMinutes: $0.estimate.guessMinutes,
                plannedMinutes: $0.estimate.minutes
            )
        }
        stepIndex = 0
        stepStartedAt = startedAt
    }

    /// All steps are done; the only thing left is walking out.
    var isLeaving: Bool { stepIndex >= steps.count }

    var currentStep: RunStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }

    /// The next step still to do, passing over any dropped to catch up.
    var nextStep: RunStep? { upcomingSteps.first }

    /// "Step 2 of 4", counting only steps done or still on the plan.
    var planStepNumber: Int { steps.prefix(stepIndex + 1).filter { !$0.skipped }.count }
    var planStepCount: Int { steps.filter { !$0.skipped }.count }

    /// Steps after the current one that are still on the plan.
    var upcomingSteps: [RunStep] {
        guard stepIndex + 1 < steps.count else { return [] }
        return steps[(stepIndex + 1)...].filter { !$0.skipped }
    }

    /// When the current step should wrap up to stay on plan.
    var stepEndsAt: Date {
        guard let currentStep else { return leaveAt }
        return stepStartedAt.addingTimeInterval(currentStep.plannedSeconds)
    }

    /// Planned seconds still to come after the current step.
    var remainingAfterCurrentSeconds: TimeInterval {
        upcomingSteps.reduce(0) { $0 + $1.plannedSeconds }
    }

    /// When the user will be ready to leave if every remaining step takes its
    /// planned time and the current one ends on schedule, or now if it is
    /// already running over.
    func projectedReadyAt(now: Date) -> Date {
        RunProjection.projectedReadyAt(
            now: now,
            isLeaving: isLeaving,
            stepEndsAt: stepEndsAt,
            remainingAfterCurrentSeconds: remainingAfterCurrentSeconds
        )
    }

    func slipSeconds(now: Date) -> TimeInterval {
        projectedReadyAt(now: now).timeIntervalSince(leaveAt)
    }

    func status(now: Date) -> RunStatus {
        RunStatus(slipSeconds: slipSeconds(now: now))
    }

    /// Marks the current step finished and returns what it took.
    mutating func completeCurrentStep(at now: Date) -> RunStep? {
        guard steps.indices.contains(stepIndex) else { return nil }
        steps[stepIndex].actualSeconds = max(0, now.timeIntervalSince(stepStartedAt))
        let finished = steps[stepIndex]
        advance(from: now)
        return finished
    }

    /// Moves past the current step without timing it, so a skipped breakfast
    /// does not teach the app that breakfast takes no time.
    mutating func skipCurrentStep(at now: Date) {
        guard steps.indices.contains(stepIndex) else { return }
        steps[stepIndex].skipped = true
        advance(from: now)
    }

    /// Takes a step that has not started off today's plan, to win its time
    /// back. Like a skip, it teaches nothing about how long the step takes.
    mutating func dropUpcomingStep(id: UUID) {
        guard let index = steps.firstIndex(where: { $0.id == id }), index > stepIndex else { return }
        steps[index].skipped = true
    }

    /// Moves to the next step still on the plan, or to leaving.
    private mutating func advance(from now: Date) {
        stepIndex += 1
        while stepIndex < steps.count, steps[stepIndex].skipped { stepIndex += 1 }
        stepStartedAt = now
    }

    /// When the run is behind, the one step to drop that best wins the time
    /// back: the shortest that covers the slip, else the longest. Never the
    /// last step, which is usually the walk out itself.
    func catchUpSuggestion(now: Date) -> RunStep? {
        guard case .behind(let minutes) = status(now: now), minutes >= 2 else { return nil }
        let candidates = upcomingSteps.dropLast()
        guard !candidates.isEmpty else { return nil }
        let covering = candidates.filter { $0.plannedMinutes >= minutes }
        return covering.min { $0.plannedMinutes < $1.plannedMinutes }
            ?? candidates.max { $0.plannedMinutes < $1.plannedMinutes }
    }

    /// A run nobody closed: hours past its leave time, the user long gone.
    /// Kept this long so a late morning can still be finished honestly.
    static let abandonAfter: TimeInterval = 3 * 3600

    func isAbandoned(now: Date) -> Bool {
        now.timeIntervalSince(leaveAt) > Self.abandonAfter
    }

    /// Seconds between the alert and the start, when the start answered it.
    /// A start more than an hour after the alert was not a response to it.
    var startDelaySeconds: TimeInterval? {
        guard let alertAt else { return nil }
        let delay = startedAt.timeIntervalSince(alertAt)
        guard delay < 3600 else { return nil }
        return max(0, delay)
    }
}

/// The projection shared with the Watch, which only receives the summary numbers.
enum RunProjection {
    static func projectedReadyAt(
        now: Date,
        isLeaving: Bool,
        stepEndsAt: Date,
        remainingAfterCurrentSeconds: TimeInterval
    ) -> Date {
        guard !isLeaving else { return now }
        return max(now, stepEndsAt).addingTimeInterval(remainingAfterCurrentSeconds)
    }
}
