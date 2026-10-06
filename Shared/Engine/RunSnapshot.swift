import Foundation

/// The numbers the Live Activity and the Watch need to draw a run and keep its
/// status live between updates. Both derive status from these alone, with the
/// same `RunProjection`, so they can never disagree with the phone.
struct RunSnapshot: Codable, Hashable, Sendable {
    var routineName: String
    var leaveAt: Date
    var stepName: String?
    var nextStepName: String?
    var stepIndex: Int
    var stepCount: Int
    var stepStartedAt: Date
    var stepEndsAt: Date
    var remainingAfterCurrentSeconds: TimeInterval
    var isLeaving: Bool

    init(run: ActiveRun) {
        routineName = run.routineName
        leaveAt = run.leaveAt
        stepName = run.currentStep?.name
        nextStepName = run.nextStep?.name
        // Positions among the steps still on the plan, for "Step 2 of 4".
        stepIndex = run.planStepNumber - 1
        stepCount = run.planStepCount
        stepStartedAt = run.stepStartedAt
        stepEndsAt = run.stepEndsAt
        remainingAfterCurrentSeconds = run.remainingAfterCurrentSeconds
        isLeaving = run.isLeaving
    }

    func status(now: Date) -> RunStatus {
        let ready = RunProjection.projectedReadyAt(
            now: now,
            isLeaving: isLeaving,
            stepEndsAt: stepEndsAt,
            remainingAfterCurrentSeconds: remainingAfterCurrentSeconds
        )
        return RunStatus(slipSeconds: ready.timeIntervalSince(leaveAt))
    }
}

/// The next departure, for the idle Watch screen.
struct NextDepartureSnapshot: Codable, Hashable, Sendable {
    var routineName: String
    var alertAt: Date
    var leaveAt: Date
}

/// What the Home Screen and Lock Screen widgets draw between launches: the
/// next few departures, soonest first, and the run if one is going.
struct WidgetSnapshot: Codable, Hashable, Sendable {
    var departures: [NextDepartureSnapshot]
    var run: RunSnapshot?

    static let defaultsKey = "widget.snapshot"
    static let kind = "NextDeparture"
    /// Set on the Watch when the phone says Pro is off; the complication
    /// then shows a lock instead of the plan.
    static let lockedKey = "widget.locked"
}

/// Everything the phone sends the Watch.
struct WatchPayload: Codable, Hashable, Sendable {
    var isPro: Bool
    var run: RunSnapshot?
    var next: NextDepartureSnapshot?
    /// The departures after `next` too, so the Watch and its complication
    /// stay right after one passes while the phone sends nothing. Optional
    /// because older phones never sent it.
    var upcoming: [NextDepartureSnapshot]?
    var sentAt: Date

    /// The first departure not yet left for at `now`.
    func nextDeparture(now: Date) -> NextDepartureSnapshot? {
        (upcoming ?? [next].compactMap { $0 }).first { $0.leaveAt > now }
    }

    /// What the Watch complication draws.
    var widgetSnapshot: WidgetSnapshot {
        WidgetSnapshot(departures: upcoming ?? [next].compactMap { $0 }, run: run)
    }
}

/// Things the Watch can ask the phone to do.
enum WatchCommand: String, Codable, Sendable {
    case start
    case completeStep
    case skipStep
    case leave
}
