package com.jackwallner.time

import android.content.Intent
import com.jackwallner.time.data.FinishedRun
import com.jackwallner.time.data.PersistedState
import com.jackwallner.time.model.ActiveRun
import com.jackwallner.time.model.Calibration
import com.jackwallner.time.model.DayChange
import com.jackwallner.time.model.DepartureRecord
import com.jackwallner.time.model.PaceAnswer
import com.jackwallner.time.model.Planner
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import com.jackwallner.time.model.StepRecord
import com.jackwallner.time.model.day
import com.jackwallner.time.model.iosWeekday
import com.jackwallner.time.model.plusSeconds
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID

/**
 * Debug-only launch extras, the Android twin of the iOS launch arguments:
 * `reset`, `seed` (twelve weekday mornings), `screen` run|leaving|summary,
 * `seedDayChanges`, `onboardingPage` N, `paywall` yearly|monthly, `demoPro`,
 * `free`, `fixedNow` HH:mm, `appearance` light|dark.
 * Pass them with `adb shell am start -n ... --ez seed true --es screen run`.
 */
object DebugLaunchOptions {
    fun apply(intent: Intent?, graph: AppGraph) {
        intent ?: return
        intent.getStringExtra("fixedNow")?.let { value ->
            val parts = value.split(":").mapNotNull(String::toIntOrNull)
            if (parts.size == 2) {
                val zone = ZoneId.systemDefault()
                val target = Instant.now().day(zone).atTime(LocalTime.of(parts[0], parts[1])).atZone(zone).toInstant()
                AppClock.offsetMillis = target.toEpochMilli() - System.currentTimeMillis()
            }
        }
        if (intent.getBooleanExtra("demoPro", false)) graph.purchases.setLocalOverride(true)
        if (intent.getBooleanExtra("free", false)) graph.purchases.setLocalOverride(false)
        if (intent.getBooleanExtra("reset", false)) {
            graph.settings.completeSetup(false)
            graph.store.replaceState(PersistedState())
        }
        if (intent.getBooleanExtra("seed", false)) {
            graph.settings.completeSetup(true)
            graph.store.replaceState(
                ScreenshotFixtures.state(intent.getStringExtra("screen"), intent.getBooleanExtra("seedDayChanges", false), AppClock.now()),
            )
            graph.propagate()
        }
    }

    fun onboardingPage(intent: Intent?): Int? = intent?.takeIf { it.hasExtra("onboardingPage") }?.getIntExtra("onboardingPage", 0)

    fun paywallSnapshot(intent: Intent?): String? = intent?.getStringExtra("paywall")

    fun appearance(intent: Intent?): String? = intent?.getStringExtra("appearance")

    fun isScreenshot(intent: Intent?): Boolean = intent?.getBooleanExtra("seed", false) == true || intent?.hasExtra("paywall") == true
}

/** Seeded state for screenshots and UI tests, the same mornings as iOS `ScreenshotFixtures`. */
object ScreenshotFixtures {
    val routineID: UUID = UUID.fromString("5A0E5A0E-0000-4000-8000-000000000001")

    private data class Seed(val name: String, val guess: Int, val real: Double)

    private val steps = listOf(
        Seed("Shower", 10, 15.5),
        Seed("Get dressed", 10, 13.0),
        Seed("Breakfast", 15, 19.0),
        Seed("Pack bag and lunch", 5, 9.0),
        Seed("Shoes, keys, out", 5, 7.0),
    )

    val routine: Routine
        get() = Routine(
            id = routineID,
            name = "Weekday mornings",
            leaveHour = 8,
            leaveMinute = 15,
            weekdays = setOf(2, 3, 4, 5, 6),
            steps = steps.mapIndexed { index, step ->
                RoutineStep(UUID.fromString(String.format("5A0E5A0E-0000-4000-8000-%012d", index + 10)), step.name, step.guess)
            },
        )

    fun state(screen: String?, seedDayChanges: Boolean, now: Instant): PersistedState {
        val zone = ZoneId.systemDefault()
        var routine = routine
        val history = mutableListOf<StepRecord>()
        val departures = mutableListOf<DepartureRecord>()
        val wobble = listOf(0.9, 1.1, 1.0, 1.2, 0.95, 1.05, 0.85, 1.15, 1.0, 0.9, 1.1, 1.0)
        val lateness = listOf(-3.0, 0.5, 11.0, -1.0, 0.0, 6.0, -2.0, 0.2, -4.0, 1.0, 0.0, -2.0)
        val today = now.day(zone)
        val pastWeekdays = (1L..30L).map { today.minusDays(it) }.filter { it.iosWeekday() in routine.weekdays }
        wobble.forEachIndexed { day, factor ->
            val date = pastWeekdays[day]
            val at = date.atTime(7, 30).atZone(zone).toInstant()
            routine.steps.forEachIndexed { index, step ->
                history += StepRecord(step.id, routine.id, step.guessMinutes, steps[index].real * factor * 60, at)
            }
            val target = routine.leaveTime(date, zone)
            departures += DepartureRecord(routineID = routine.id, target = target, left = target.plusSeconds(lateness[day] * 60), startDelaySeconds = (3 + day % 4) * 60.0)
        }
        if (seedDayChanges) {
            // The next routine day skipped, and a one-off on the coming Saturday.
            val upcoming = (1L..7L).map { today.plusDays(it) }
            upcoming.firstOrNull { it.iosWeekday() in routine.weekdays }?.let { routine = routine.settingChange(DayChange(it, null), it) }
            upcoming.firstOrNull { it.iosWeekday() == 7 }?.let { routine = routine.settingChange(DayChange(it, 10 * 60 + 40), it) }
        }
        var state = PersistedState(
            routines = listOf(routine),
            selectedRoutineID = routine.id,
            pace = PaceAnswer.HALF_OVER,
            stepHistory = history,
            departures = departures,
        )
        val calibration = Calibration(state.pace.multiplier, history, departures)
        state = when (screen) {
            "run" -> state.copy(activeRun = midRun(routine, calibration, now))
            "leaving" -> {
                val run = midRun(routine, calibration, now)
                state.copy(activeRun = run.copy(stepIndex = run.steps.size, leaveAt = now.plusSeconds(4 * 60 + 20L)))
            }
            "summary" -> {
                val took = listOf(14.0, 12.0, 17.0, 8.0, 6.0)
                val base = midRun(routine, calibration, now)
                val run = base.copy(
                    steps = base.steps.mapIndexed { i, s -> s.copy(actualSeconds = took[i] * 60) },
                    stepIndex = base.steps.size,
                    leaveAt = routine.leaveTime(now.day(zone), zone),
                )
                val departure = DepartureRecord(routineID = routine.id, target = run.leaveAt, left = run.leaveAt.plusSeconds(-120L), startDelaySeconds = 180.0)
                state.copy(lastFinished = FinishedRun(run, departure))
            }
            else -> state
        }
        return state
    }

    /** Two steps done, breakfast running a little long, three minutes behind. */
    private fun midRun(routine: Routine, calibration: Calibration, now: Instant): ActiveRun {
        val plan = Planner.plan(routine, now.plusSeconds(3600L), calibration)
        var run = ActiveRun.start(plan, routine.name, now.plusSeconds(-30 * 60L), null)
        run = run.copy(
            steps = run.steps.mapIndexed { i, s ->
                when (i) {
                    0 -> s.copy(actualSeconds = 16 * 60.0)
                    1 -> s.copy(actualSeconds = 13 * 60.0)
                    else -> s
                }
            },
            stepIndex = 2,
            stepStartedAt = now.plusSeconds(-(11 * 60 + 25L)),
        )
        val ready = run.projectedReadyAt(now)
        return run.copy(leaveAt = ready.plusSeconds(-3 * 60L))
    }
}
