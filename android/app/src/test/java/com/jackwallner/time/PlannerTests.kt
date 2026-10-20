package com.jackwallner.time

import com.jackwallner.time.model.Calibration
import com.jackwallner.time.model.DepartureRecord
import com.jackwallner.time.model.EstimateSource
import com.jackwallner.time.model.Planner
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import com.jackwallner.time.model.StepRecord
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** One for one with iOS `PlannerTests`. */
class PlannerTests {
    private val zone = ZoneId.of("America/Los_Angeles")

    private fun date(day: Int, hour: Int, minute: Int): Instant = LocalDateTime.of(2026, 9, day, hour, minute).atZone(zone).toInstant()

    private fun routine(steps: List<Pair<String, Int>> = listOf("Shower" to 10, "Dress" to 10, "Breakfast" to 15, "Shoes" to 5)) = Routine(
        name = "Weekday mornings",
        leaveHour = 8,
        leaveMinute = 15,
        weekdays = setOf(2, 3, 4, 5, 6),
        steps = steps.map { RoutineStep(name = it.first, guessMinutes = it.second) },
    )

    private fun calibration(pace: Double, history: List<StepRecord> = emptyList(), departures: List<DepartureRecord> = emptyList()) =
        Calibration(pace, history, departures)

    @Test fun eachStepRoundsUpToAWholeMinute() {
        val plan = Planner.plan(routine(listOf("Shoes" to 5)), date(22, 8, 15), calibration(1.5))
        assertEquals(8, plan.realMinutes)
    }

    @Test fun guessesAreTrustedAtAnHonestPace() {
        val plan = Planner.plan(routine(), date(22, 8, 15), calibration(1.0))
        assertEquals(40, plan.guessMinutes)
        assertEquals(40, plan.realMinutes)
        assertEquals(date(22, 7, 35), plan.getReadyAt)
        assertEquals(date(22, 7, 35), plan.alertAt)
    }

    /** Someone who underestimates by half is told to start that much earlier. */
    @Test fun halfOverPaceStartsTwentyMinutesEarlierOnAFortyMinuteRoutine() {
        val plan = Planner.plan(routine(listOf("Shower" to 10, "Dress" to 10, "Breakfast" to 14, "Shoes" to 6)), date(22, 8, 15), calibration(1.5))
        assertEquals(60, plan.realMinutes)
        assertEquals(20, plan.hiddenMinutes)
        assertEquals(date(22, 7, 15), plan.getReadyAt)
    }

    @Test fun stepsAreLaidOutBackwardFromTheLeaveTime() {
        val plan = Planner.plan(routine(listOf("A" to 10, "B" to 20)), date(22, 8, 0), calibration(1.0))
        assertEquals(listOf("A", "B"), plan.steps.map { it.step.name })
        assertEquals(date(22, 7, 30), plan.steps[0].startsAt)
        assertEquals(date(22, 7, 40), plan.steps[0].endsAt)
        assertEquals(date(22, 8, 0), plan.steps[1].endsAt)
    }

    @Test fun timedStepsReplaceTheGuess() {
        val routine = routine(listOf("Shower" to 10))
        val step = routine.steps[0]
        val history = (0 until 8).map { StepRecord(step.id, routine.id, 10, 18 * 60.0, date(10 + it, 7, 0)) }
        val estimate = calibration(1.0, history).estimate(step)
        assertEquals(EstimateSource.Learned(8), estimate.source)
        // Eight timings of 18 against a paced prior worth two: pulled most of the way.
        assertTrue(estimate.minutes in 16..18)
    }

    @Test fun oneOddMorningDoesNotSwingAStep() {
        val routine = routine(listOf("Shower" to 10))
        val step = routine.steps[0]
        val history = listOf(StepRecord(step.id, routine.id, 10, 45 * 60.0, date(21, 7, 0)))
        assertTrue(calibration(1.0, history).estimate(step).minutes < 25)
    }

    @Test fun paceLearnsFromEveryStepAndAppliesToNewOnes() {
        val routine = routine(listOf("Shower" to 10, "New thing" to 10))
        val shower = routine.steps[0]
        val history = (0 until 30).map { StepRecord(shower.id, routine.id, 10, 20 * 60.0, date(1, 7, 0).plusSeconds(it * 86_400L)) }
        val calibration = calibration(1.0, history)
        assertTrue(calibration.pace > 1.7)
        val untimed = calibration.estimate(routine.steps[1])
        assertEquals(EstimateSource.Pace, untimed.source)
        assertTrue(untimed.minutes >= 18)
    }

    @Test fun paceStaysWithinBounds() {
        val routine = routine(listOf("Shower" to 1))
        val history = (0 until 40).map { StepRecord(routine.steps[0].id, routine.id, 1, 3600.0, date(1, 7, 0).plusSeconds(it * 3600L)) }
        assertTrue(calibration(2.0, history).pace <= 3.0)
    }

    @Test fun startDelayBecomesAHeadStart() {
        val routine = routine()
        val departures = (0 until 6).map { DepartureRecord(routineID = routine.id, target = date(10 + it, 8, 15), left = date(10 + it, 8, 15), startDelaySeconds = 8 * 60.0) }
        val calibration = calibration(1.0, departures = departures)
        // Median 8, blended with two pseudo-samples of zero: 6.
        assertEquals(6, calibration.startDelayMinutes)
        assertEquals(date(22, 7, 29), Planner.plan(routine, date(22, 8, 15), calibration).alertAt)
    }

    @Test fun startDelayIsCapped() {
        val routine = routine()
        val departures = (0 until 10).map { DepartureRecord(routineID = routine.id, target = date(10 + it, 8, 15), left = date(10 + it, 8, 15), startDelaySeconds = 50 * 60.0) }
        assertTrue(calibration(1.0, departures = departures).startDelayMinutes <= 20)
    }

    @Test fun nextScheduledLeaveSkipsDaysOff() {
        // Saturday 19 September 2026, after the leave time: next is Monday.
        assertEquals(date(21, 8, 15), routine().nextScheduledLeave(date(19, 9, 0), zone))
    }

    @Test fun manualRunAimsForTodayOrTomorrow() {
        val routine = routine()
        assertEquals(date(19, 8, 15), routine.leaveTimeForRunStarted(date(19, 7, 0), zone))
        assertEquals(date(20, 8, 15), routine.leaveTimeForRunStarted(date(19, 9, 0), zone))
    }
}
