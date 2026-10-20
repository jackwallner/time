package com.jackwallner.time.model

import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlin.math.ceil

/** One alert Shoes On wants delivered. */
data class PlannedAlert(
    val id: String,
    val kind: Kind,
    val fireAt: Instant,
    val title: String,
    val body: String,
    /** The routine a get-ready alert starts when tapped. */
    val routineID: UUID? = null,
    /** The departure a get-ready alert is for, so it can be skipped from the alert itself. */
    val leaveAt: Instant? = null,
) {
    enum class Kind {
        GET_READY,
        /** The get-ready alert went unanswered: here is what starting now costs. */
        START_NUDGE,
        LEAVE_SOON,
        LEAVE_NOW,
        WRAP_UP,
        OVERRUN,
    }
}

data class AlertPreferences(
    val startAlerts: Boolean = true,
    val leaveAlerts: Boolean = true,
    val stepNudges: Boolean = true,
)

/**
 * Decides every alert from the routines, the history and the run. Pure, so
 * the schedule can be tested without AlarmManager.
 */
object NotificationPlan {
    /** iOS keeps 64 pending requests; the same rolling window keeps both apps alike. */
    const val SCHEDULED_LIMIT = 56
    const val HORIZON_DAYS = 10
    const val LEAVE_SOON_MINUTES = 10
    const val OVERRUN_GRACE_MINUTES = 5
    /** Minutes after an unanswered get-ready alert to follow up. */
    val startNudgeMinutes = listOf(5, 12)
    /** Steps at least this long get a heads-up before their time is up. */
    const val HEADS_UP_STEP_MINUTES = 6
    const val HEADS_UP_MINUTES = 2

    fun alerts(
        routines: List<Routine>,
        calibration: Calibration,
        departures: List<DepartureRecord>,
        activeRun: ActiveRun?,
        preferences: AlertPreferences,
        now: Instant,
        zone: ZoneId,
    ): List<PlannedAlert> =
        runAlerts(activeRun, preferences, now) +
            scheduledAlerts(routines, calibration, departures, activeRun, preferences, now, zone)

    /**
     * Get-ready and leave alerts for upcoming scheduled departures, nearest
     * first, skipping the one being run and any already left for.
     */
    fun scheduledAlerts(
        routines: List<Routine>,
        calibration: Calibration,
        departures: List<DepartureRecord>,
        activeRun: ActiveRun?,
        preferences: AlertPreferences,
        now: Instant,
        zone: ZoneId,
    ): List<PlannedAlert> {
        if (!preferences.startAlerts && !preferences.leaveAlerts) return emptyList()
        val alerts = mutableListOf<PlannedAlert>()
        val today = now.day(zone)
        for (routine in routines) {
            for (offset in 0L..HORIZON_DAYS.toLong()) {
                val day = today.plusDays(offset)
                if (!routine.departs(day)) continue
                val leaveAt = routine.leaveTime(day, zone)
                if (leaveAt <= now) continue
                if (activeRun != null && activeRun.routineID == routine.id && activeRun.leaveAt == leaveAt) continue
                if (departures.any { it.routineID == routine.id && it.target == leaveAt }) continue
                val plan = Planner.plan(routine, leaveAt, calibration)
                val key = "${routine.id.toString().uppercase()}.${leaveAt.epochSecond}"
                if (preferences.startAlerts) {
                    // Nudges are kept even after the alert itself has fired,
                    // so opening the app then does not cancel them.
                    alerts += startNudges(key, routine, plan, now)
                }
                if (preferences.startAlerts && plan.alertAt > now) {
                    alerts += PlannedAlert(
                        id = "ready.$key",
                        kind = PlannedAlert.Kind.GET_READY,
                        fireAt = plan.alertAt,
                        title = "Time to get ready",
                        body = "Start now to leave at ${Format.time(leaveAt)}. ${routine.name} really takes ${Format.duration(plan.realMinutes)}.",
                        routineID = routine.id,
                        leaveAt = leaveAt,
                    )
                }
                if (preferences.leaveAlerts) alerts += leaveAlerts(key, routine.name, leaveAt, now)
            }
        }
        return alerts.sortedBy { it.fireAt }.take(SCHEDULED_LIMIT)
    }

    /**
     * Follow-ups to an unanswered get-ready alert, each saying honestly when
     * starting right then gets them out the door.
     */
    fun startNudges(key: String, routine: Routine, plan: DeparturePlan, now: Instant): List<PlannedAlert> {
        val cutoff = plan.leaveAt.plusMinutes(-LEAVE_SOON_MINUTES)
        return startNudgeMinutes.mapIndexedNotNull { index, minutes ->
            val fireAt = plan.alertAt.plusMinutes(minutes)
            if (fireAt <= now || fireAt >= cutoff) return@mapIndexedNotNull null
            val out = fireAt.plusMinutes(plan.realMinutes)
            val lateMinutes = ceil(out.secondsSince(plan.leaveAt) / 60).toInt()
            val body = if (lateMinutes <= 1) {
                "Start now and you still leave on time at ${Format.time(plan.leaveAt)}."
            } else {
                "Starting now puts you out the door at ${Format.time(out)}, $lateMinutes min late."
            }
            PlannedAlert(
                id = "nudge$index.$key",
                kind = PlannedAlert.Kind.START_NUDGE,
                fireAt = fireAt,
                title = "Not started yet?",
                body = body,
                routineID = routine.id,
                leaveAt = plan.leaveAt,
            )
        }
    }

    /**
     * Alerts for the run in progress: a heads-up before a long step's time is
     * up, a nudge if it is still going a few minutes after, and the leave
     * alerts for this departure.
     */
    fun runAlerts(run: ActiveRun?, preferences: AlertPreferences, now: Instant): List<PlannedAlert> {
        if (run == null) return emptyList()
        val alerts = mutableListOf<PlannedAlert>()
        val leave = Format.time(run.leaveAt)
        val step = run.currentStep
        if (preferences.stepNudges && step != null) {
            val next = run.nextStep?.name ?: "shoes on and out the door"
            val headsUp = step.plannedMinutes >= HEADS_UP_STEP_MINUTES
            val wrapAt = run.stepEndsAt.plusMinutes(if (headsUp) -HEADS_UP_MINUTES else 0)
            if (wrapAt > now) {
                alerts += PlannedAlert(
                    id = "run.wrap.${run.stepIndex}",
                    kind = PlannedAlert.Kind.WRAP_UP,
                    fireAt = wrapAt,
                    title = if (headsUp) "$HEADS_UP_MINUTES min left: ${step.name}" else "Wrap up: ${step.name}",
                    body = "Next: $next. Leave at $leave.",
                )
            }
            val overrunAt = run.stepEndsAt.plusMinutes(OVERRUN_GRACE_MINUTES)
            if (overrunAt > now) {
                val status = RunStatus.of(run.projectedReadyAt(overrunAt).secondsSince(run.leaveAt))
                alerts += PlannedAlert(
                    id = "run.over.${run.stepIndex}",
                    kind = PlannedAlert.Kind.OVERRUN,
                    fireAt = overrunAt,
                    title = "Still on ${step.name}?",
                    body = "${status.label}. Leave at $leave.",
                )
            }
        }
        if (preferences.leaveAlerts && !run.isPractice) alerts += leaveAlerts("run", run.routineName, run.leaveAt, now)
        return alerts
    }

    private fun leaveAlerts(key: String, routineName: String, leaveAt: Instant, now: Instant): List<PlannedAlert> {
        val alerts = mutableListOf<PlannedAlert>()
        val soon = leaveAt.plusMinutes(-LEAVE_SOON_MINUTES)
        if (soon > now) {
            alerts += PlannedAlert(
                id = "soon.$key",
                kind = PlannedAlert.Kind.LEAVE_SOON,
                fireAt = soon,
                title = "Leave in $LEAVE_SOON_MINUTES minutes",
                body = "Shoes on by ${Format.time(leaveAt)}.",
            )
        }
        if (leaveAt <= now) return alerts
        alerts += PlannedAlert(
            id = "leave.$key",
            kind = PlannedAlert.Kind.LEAVE_NOW,
            fireAt = leaveAt,
            title = "Time to go",
            body = "Head out now for $routineName.",
        )
        return alerts
    }
}
