import Foundation

struct PlannedStep: Hashable, Sendable, Identifiable {
    var step: RoutineStep
    var estimate: StepEstimate
    var startsAt: Date
    var endsAt: Date

    var id: UUID { step.id }
}

/// A routine laid out backward from the leave time.
struct DeparturePlan: Hashable, Sendable {
    var routineID: UUID
    var leaveAt: Date
    var steps: [PlannedStep]
    /// Extra lead for the gap between the alert and actually starting.
    var headStartMinutes: Int

    var guessMinutes: Int { steps.reduce(0) { $0 + $1.estimate.guessMinutes } }
    var realMinutes: Int { steps.reduce(0) { $0 + $1.estimate.minutes } }

    /// When the first step has to begin.
    var getReadyAt: Date { steps.first?.startsAt ?? leaveAt }

    /// When the get-ready alert fires: the first step, less the head start.
    var alertAt: Date { getReadyAt.addingTimeInterval(TimeInterval(-headStartMinutes * 60)) }

    /// Minutes the guess alone would have made the user late by.
    var hiddenMinutes: Int { realMinutes + headStartMinutes - guessMinutes }
}

enum Planner {
    static func plan(_ routine: Routine, leaveAt: Date, calibration: Calibration) -> DeparturePlan {
        var cursor = leaveAt
        var planned: [PlannedStep] = []
        for step in routine.steps.reversed() {
            let estimate = calibration.estimate(for: step)
            let start = cursor.addingTimeInterval(TimeInterval(-estimate.minutes * 60))
            planned.append(PlannedStep(step: step, estimate: estimate, startsAt: start, endsAt: cursor))
            cursor = start
        }
        return DeparturePlan(
            routineID: routine.id,
            leaveAt: leaveAt,
            steps: planned.reversed(),
            headStartMinutes: calibration.startDelayMinutes
        )
    }
}
