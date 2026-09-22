import Foundation

/// Where a step's realistic time came from, so the UI can say it honestly.
enum EstimateSource: Hashable, Sendable {
    /// No runs yet: the guess scaled by the personal pace.
    case pace
    /// Learned from this many timed runs of the step.
    case learned(runs: Int)
}

struct StepEstimate: Hashable, Sendable {
    var guessMinutes: Int
    var minutes: Int
    var source: EstimateSource
}

/// Turns the user's guesses into the times they will really need.
///
/// Three things are learned, each blended with a prior so one odd morning
/// cannot swing the plan:
/// - the pace: how far this person's guesses run over, seeded by onboarding;
/// - each step's own real duration, once it has been timed;
/// - the start delay: how long after the get-ready alert they actually begin.
struct Calibration: Sendable {
    /// Onboarding answer, as a multiplier on guesses.
    var basePace: Double
    var stepHistory: [StepRecord]
    var departures: [DepartureRecord]

    /// Pseudo-samples the onboarding answer is worth against real step timings.
    static let pacePriorWeight = 6.0
    /// Pseudo-samples a step's paced guess is worth against its own timings.
    static let stepPriorWeight = 2.0
    /// Timed runs of a step that still count. Habits change; old mornings fade.
    static let stepWindow = 8
    static let paceWindow = 40
    static let startDelayWindow = 10
    static let maxStartDelayMinutes = 20.0
    static let paceRange = 0.8...3.0

    /// The person's pace: real time over guessed time, across recent steps.
    var pace: Double {
        let ratios = stepHistory
            .sorted { $0.date > $1.date }
            .prefix(Self.paceWindow)
            .map { min(max($0.ratio, 0.5), 3.0) }
        let blended = (Self.pacePriorWeight * basePace + ratios.reduce(0, +))
            / (Self.pacePriorWeight + Double(ratios.count))
        return min(max(blended, Self.paceRange.lowerBound), Self.paceRange.upperBound)
    }

    /// How many timed steps the pace is built on.
    var pacedStepCount: Int { min(stepHistory.count, Self.paceWindow) }

    func estimate(for step: RoutineStep) -> StepEstimate {
        let prior = Double(max(step.guessMinutes, 1)) * pace
        let timed = stepHistory
            .filter { $0.stepID == step.id }
            .sorted { $0.date > $1.date }
            .prefix(Self.stepWindow)
            .map { $0.actualSeconds / 60 }
        guard !timed.isEmpty else {
            return StepEstimate(guessMinutes: step.guessMinutes, minutes: Self.roundUp(prior), source: .pace)
        }
        // A slow-side percentile, not the mean: planning on the average means
        // being late on half of all mornings.
        let learned = Self.percentile(timed, 0.7)
        let n = Double(timed.count)
        let blended = (Self.stepPriorWeight * prior + n * learned) / (Self.stepPriorWeight + n)
        return StepEstimate(
            guessMinutes: step.guessMinutes,
            minutes: Self.roundUp(blended),
            source: .learned(runs: timed.count)
        )
    }

    /// Minutes of head start for the gap between the alert and actually
    /// starting. Zero until there is evidence of one.
    var startDelayMinutes: Int {
        let delays = departures
            .sorted { $0.left > $1.left }
            .compactMap(\.startDelaySeconds)
            .prefix(Self.startDelayWindow)
            .map { min(max($0 / 60, 0), Self.maxStartDelayMinutes) }
        guard !delays.isEmpty else { return 0 }
        let median = Self.percentile(Array(delays), 0.5)
        let n = Double(delays.count)
        return Int((n * median / (n + 2)).rounded())
    }

    static func roundUp(_ minutes: Double) -> Int {
        max(1, Int((minutes - 0.05).rounded(.up)))
    }

    /// Linear-interpolated percentile of a non-empty sample.
    static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}
