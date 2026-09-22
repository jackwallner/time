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
        stepIndex = run.stepIndex
        stepCount = run.steps.count
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

/// Everything the phone sends the Watch.
struct WatchPayload: Codable, Hashable, Sendable {
    var isPro: Bool
    var run: RunSnapshot?
    var next: NextDepartureSnapshot?
    var sentAt: Date
}

/// Things the Watch can ask the phone to do.
enum WatchCommand: String, Codable, Sendable {
    case start
    case completeStep
    case skipStep
    case leave
}
