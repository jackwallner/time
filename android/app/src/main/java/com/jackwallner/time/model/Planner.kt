package com.jackwallner.time.model

import java.time.Instant
import java.util.UUID
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** Where a step's realistic time came from, so the UI can say it honestly. */
sealed interface EstimateSource {
    /** No runs yet: the guess scaled by the personal pace. */
    data object Pace : EstimateSource

    /** Learned from this many timed runs of the step. */
    data class Learned(val runs: Int) : EstimateSource
}

data class StepEstimate(val guessMinutes: Int, val minutes: Int, val source: EstimateSource)

/**
 * Turns the user's guesses into the times they will really need.
 *
 * Three things are learned, each blended with a prior so one odd morning
 * cannot swing the plan: the pace, each step's own real duration, and the
 * start delay after the get-ready alert.
 */
data class Calibration(
    /** Onboarding answer, as a multiplier on guesses. */
    val basePace: Double,
    val stepHistory: List<StepRecord>,
    val departures: List<DepartureRecord>,
) {
    /** The person's pace: real time over guessed time, across recent steps. */
    val pace: Double by lazy {
        val ratios = stepHistory
            .sortedByDescending { it.date }
            .take(PACE_WINDOW)
            .map { min(max(it.ratio, 0.5), 3.0) }
        val blended = (PACE_PRIOR_WEIGHT * basePace + ratios.sum()) / (PACE_PRIOR_WEIGHT + ratios.size)
        min(max(blended, PACE_MIN), PACE_MAX)
    }

    /** How many timed steps the pace is built on. */
    val pacedStepCount: Int get() = min(stepHistory.size, PACE_WINDOW)

    fun estimate(step: RoutineStep): StepEstimate {
        val prior = max(step.guessMinutes, 1).toDouble() * pace
        val timed = stepHistory
            .filter { it.stepID == step.id }
            .sortedByDescending { it.date }
            .take(STEP_WINDOW)
            .map { it.actualSeconds / 60 }
        if (timed.isEmpty()) return StepEstimate(step.guessMinutes, roundUp(prior), EstimateSource.Pace)
        // A slow-side percentile, not the mean: planning on the average means
        // being late on half of all mornings.
        val learned = percentile(timed, 0.7)
        val n = timed.size.toDouble()
        val blended = (STEP_PRIOR_WEIGHT * prior + n * learned) / (STEP_PRIOR_WEIGHT + n)
        return StepEstimate(step.guessMinutes, roundUp(blended), EstimateSource.Learned(timed.size))
    }

    /** Minutes of head start for the gap between the alert and actually starting. */
    val startDelayMinutes: Int
        get() {
            val delays = departures
                .sortedByDescending { it.left }
                .mapNotNull { it.startDelaySeconds }
                .take(START_DELAY_WINDOW)
                .map { min(max(it / 60, 0.0), MAX_START_DELAY_MINUTES) }
            if (delays.isEmpty()) return 0
            val median = percentile(delays, 0.5)
            val n = delays.size.toDouble()
            return roundHalfAway(n * median / (n + 2)).toInt()
        }

    companion object {
        /** Pseudo-samples the onboarding answer is worth against real step timings. */
        const val PACE_PRIOR_WEIGHT = 6.0
        /** Pseudo-samples a step's paced guess is worth against its own timings. */
        const val STEP_PRIOR_WEIGHT = 2.0
        const val STEP_WINDOW = 8
        const val PACE_WINDOW = 40
        const val START_DELAY_WINDOW = 10
        const val MAX_START_DELAY_MINUTES = 20.0
        const val PACE_MIN = 0.8
        const val PACE_MAX = 3.0

        fun roundUp(minutes: Double): Int = max(1, ceil(minutes - 0.05).toInt())

        /** Linear-interpolated percentile of a non-empty sample. */
        fun percentile(values: List<Double>, p: Double): Double {
            val sorted = values.sorted()
            if (sorted.size <= 1) return sorted.firstOrNull() ?: 0.0
            val position = p * (sorted.size - 1)
            val lower = floor(position).toInt()
            val upper = min(lower + 1, sorted.size - 1)
            val fraction = position - lower
            return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
        }
    }
}

data class PlannedStep(
    val step: RoutineStep,
    val estimate: StepEstimate,
    val startsAt: Instant,
    val endsAt: Instant,
) {
    val id: UUID get() = step.id
}

/** A routine laid out backward from the leave time. */
data class DeparturePlan(
    val routineID: UUID,
    val leaveAt: Instant,
    val steps: List<PlannedStep>,
    /** Extra lead for the gap between the alert and actually starting. */
    val headStartMinutes: Int,
) {
    val guessMinutes: Int get() = steps.sumOf { it.estimate.guessMinutes }
    val realMinutes: Int get() = steps.sumOf { it.estimate.minutes }

    /** When the first step has to begin. */
    val getReadyAt: Instant get() = steps.firstOrNull()?.startsAt ?: leaveAt

    /** When the get-ready alert fires: the first step, less the head start. */
    val alertAt: Instant get() = getReadyAt.plusMinutes(-headStartMinutes)

    /** Minutes the guess alone would have made the user late by. */
    val hiddenMinutes: Int get() = realMinutes + headStartMinutes - guessMinutes
}

object Planner {
    fun plan(routine: Routine, leaveAt: Instant, calibration: Calibration): DeparturePlan {
        var cursor = leaveAt
        val planned = mutableListOf<PlannedStep>()
        for (step in routine.steps.asReversed()) {
            val estimate = calibration.estimate(step)
            val start = cursor.plusMinutes(-estimate.minutes)
            planned += PlannedStep(step, estimate, start, cursor)
            cursor = start
        }
        return DeparturePlan(routine.id, leaveAt, planned.asReversed().toList(), calibration.startDelayMinutes)
    }
}
