package com.jackwallner.time.model

import java.time.Instant
import java.util.UUID
import kotlin.math.ceil
import kotlin.math.floor

data class RunStep(
    val id: UUID,
    val name: String,
    val guessMinutes: Int,
    /** The realistic minutes the plan gave this step when the run began. */
    val plannedMinutes: Int,
    val actualSeconds: Double? = null,
    val skipped: Boolean = false,
) {
    val plannedSeconds: Double get() = (plannedMinutes * 60).toDouble()
}

/** Whether the morning is on schedule, measured against the leave time. */
sealed interface RunStatus {
    data class Ahead(val minutes: Int) : RunStatus
    data object OnTrack : RunStatus
    data class Behind(val minutes: Int) : RunStatus

    val label: String
        get() = when (this) {
            is Ahead -> "$minutes min to spare"
            OnTrack -> "On track"
            is Behind -> "$minutes min behind"
        }

    val isBehind: Boolean get() = this is Behind

    companion object {
        /**
         * A minute of slack either way reads as on track; the plan has minute
         * resolution and anything finer is noise.
         */
        fun of(slipSeconds: Double): RunStatus = when {
            slipSeconds <= -120 -> Ahead(floor(-slipSeconds / 60).toInt())
            slipSeconds <= 60 -> OnTrack
            else -> Behind(ceil(slipSeconds / 60).toInt())
        }
    }
}

/**
 * A routine in progress. Pure value: the store persists it and every surface
 * (app, run notification) derives the same answers from it.
 */
data class ActiveRun(
    val routineID: UUID,
    val routineName: String,
    val leaveAt: Instant,
    val startedAt: Instant,
    /** When the get-ready alert was due for this departure, if one was. */
    val alertAt: Instant?,
    val steps: List<RunStep>,
    val stepIndex: Int,
    val stepStartedAt: Instant,
    /**
     * Started long before any departure, to try the routine out: planned from
     * the moment it began, its step times still teach, and it records no
     * departure.
     */
    val isPractice: Boolean = false,
) {
    /** All steps are done; the only thing left is walking out. */
    val isLeaving: Boolean get() = stepIndex >= steps.size

    val currentStep: RunStep? get() = steps.getOrNull(stepIndex)

    /** The next step still to do, passing over any dropped to catch up. */
    val nextStep: RunStep? get() = upcomingSteps.firstOrNull()

    /** "Step 2 of 4", counting only steps done or still on the plan. */
    val planStepNumber: Int get() = steps.take(stepIndex + 1).count { !it.skipped }
    val planStepCount: Int get() = steps.count { !it.skipped }

    /** Steps after the current one that are still on the plan. */
    val upcomingSteps: List<RunStep>
        get() = if (stepIndex + 1 >= steps.size) emptyList() else steps.drop(stepIndex + 1).filter { !it.skipped }

    /** When the current step should wrap up to stay on plan. */
    val stepEndsAt: Instant
        get() {
            val step = currentStep ?: return leaveAt
            return stepStartedAt.plusSeconds(step.plannedSeconds)
        }

    /** Planned seconds still to come after the current step. */
    val remainingAfterCurrentSeconds: Double get() = upcomingSteps.sumOf { it.plannedSeconds }

    fun projectedReadyAt(now: Instant): Instant =
        RunProjection.projectedReadyAt(now, isLeaving, stepEndsAt, remainingAfterCurrentSeconds)

    fun slipSeconds(now: Instant): Double = projectedReadyAt(now).secondsSince(leaveAt)

    fun status(now: Instant): RunStatus = RunStatus.of(slipSeconds(now))

    /** Marks the current step finished; returns the new run and what the step took. */
    fun completingCurrentStep(now: Instant): Pair<ActiveRun, RunStep?> {
        val step = currentStep ?: return this to null
        val finished = step.copy(actualSeconds = maxOf(0.0, now.secondsSince(stepStartedAt)))
        val updated = copy(steps = steps.replacing(stepIndex, finished)).advancing(now)
        return updated to finished
    }

    /**
     * Moves past the current step without timing it, so a skipped breakfast
     * does not teach the app that breakfast takes no time.
     */
    fun skippingCurrentStep(now: Instant): ActiveRun {
        val step = currentStep ?: return this
        return copy(steps = steps.replacing(stepIndex, step.copy(skipped = true))).advancing(now)
    }

    /** Takes a step that has not started off today's plan, to win its time back. */
    fun droppingUpcomingStep(id: UUID): ActiveRun {
        val index = steps.indexOfFirst { it.id == id }
        if (index <= stepIndex) return this
        return copy(steps = steps.replacing(index, steps[index].copy(skipped = true)))
    }

    /** Moves to the next step still on the plan, or to leaving. */
    private fun advancing(now: Instant): ActiveRun {
        var index = stepIndex + 1
        while (index < steps.size && steps[index].skipped) index++
        return copy(stepIndex = index, stepStartedAt = now)
    }

    /**
     * When the run is behind, the one step to drop that best wins the time
     * back: the shortest that covers the slip, else the longest. Never the
     * last step, which is usually the walk out itself.
     */
    fun catchUpSuggestion(now: Instant): RunStep? {
        val status = status(now)
        if (status !is RunStatus.Behind || status.minutes < 2) return null
        val candidates = upcomingSteps.dropLast(1)
        if (candidates.isEmpty()) return null
        return candidates.filter { it.plannedMinutes >= status.minutes }.minByOrNull { it.plannedMinutes }
            ?: candidates.maxByOrNull { it.plannedMinutes }
    }

    fun isAbandoned(now: Instant): Boolean = now.secondsSince(leaveAt) > ABANDON_AFTER_SECONDS

    /**
     * Seconds between the alert and the start, when the start answered it. A
     * start more than an hour after the alert was not a response to it.
     */
    val startDelaySeconds: Double?
        get() {
            val alert = alertAt ?: return null
            val delay = startedAt.secondsSince(alert)
            if (delay >= 3600) return null
            return maxOf(0.0, delay)
        }

    companion object {
        /** A run nobody closed: hours past its leave time, the user long gone. */
        const val ABANDON_AFTER_SECONDS = 3 * 3600.0

        fun start(plan: DeparturePlan, routineName: String, startedAt: Instant, alertAt: Instant?, isPractice: Boolean = false) =
            ActiveRun(
                routineID = plan.routineID,
                routineName = routineName,
                leaveAt = plan.leaveAt,
                startedAt = startedAt,
                alertAt = alertAt,
                steps = plan.steps.map { RunStep(it.step.id, it.step.name, it.estimate.guessMinutes, it.estimate.minutes) },
                stepIndex = 0,
                stepStartedAt = startedAt,
                isPractice = isPractice,
            )
    }
}

private fun <T> List<T>.replacing(index: Int, value: T): List<T> = toMutableList().also { it[index] = value }

/** The projection shared with every surface that only receives the summary numbers. */
object RunProjection {
    fun projectedReadyAt(now: Instant, isLeaving: Boolean, stepEndsAt: Instant, remainingAfterCurrentSeconds: Double): Instant {
        if (isLeaving) return now
        return maxOf(now, stepEndsAt).plusSeconds(remainingAfterCurrentSeconds)
    }
}

/**
 * The numbers the run notification needs to draw a run and keep its status
 * honest between updates, derived with the same `RunProjection`.
 */
data class RunSnapshot(
    val routineName: String,
    val leaveAt: Instant,
    val stepName: String?,
    val nextStepName: String?,
    val stepIndex: Int,
    val stepCount: Int,
    val stepStartedAt: Instant,
    val stepEndsAt: Instant,
    val remainingAfterCurrentSeconds: Double,
    val isLeaving: Boolean,
) {
    fun status(now: Instant): RunStatus {
        val ready = RunProjection.projectedReadyAt(now, isLeaving, stepEndsAt, remainingAfterCurrentSeconds)
        return RunStatus.of(ready.secondsSince(leaveAt))
    }

    companion object {
        fun of(run: ActiveRun) = RunSnapshot(
            routineName = run.routineName,
            leaveAt = run.leaveAt,
            stepName = run.currentStep?.name,
            nextStepName = run.nextStep?.name,
            stepIndex = run.planStepNumber - 1,
            stepCount = run.planStepCount,
            stepStartedAt = run.stepStartedAt,
            stepEndsAt = run.stepEndsAt,
            remainingAfterCurrentSeconds = run.remainingAfterCurrentSeconds,
            isLeaving = run.isLeaving,
        )
    }
}
