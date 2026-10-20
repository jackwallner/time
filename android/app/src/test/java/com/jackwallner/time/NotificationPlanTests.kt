package com.jackwallner.time

import com.jackwallner.time.model.ActiveRun
import com.jackwallner.time.model.AlertPreferences
import com.jackwallner.time.model.Calibration
import com.jackwallner.time.model.DayChange
import com.jackwallner.time.model.DepartureRecord
import com.jackwallner.time.model.Format
import com.jackwallner.time.model.NotificationPlan
import com.jackwallner.time.model.PlannedAlert.Kind
import com.jackwallner.time.model.Planner
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import com.jackwallner.time.model.day
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** One for one with iOS `NotificationPlanTests`. */
class NotificationPlanTests {
    private val zone = ZoneId.of("America/Los_Angeles")

    @Before fun setUp() {
        Format.zone = zone
    }

    private fun date(day: Int, hour: Int, minute: Int): Instant = LocalDateTime.of(2026, 9, day, hour, minute).atZone(zone).toInstant()
    private fun day(day: Int): LocalDate = LocalDate.of(2026, 9, day)

    private val routine = Routine(
        name = "Weekday mornings",
        leaveHour = 8,
        leaveMinute = 15,
        weekdays = setOf(2, 3, 4, 5, 6),
        steps = listOf(RoutineStep(name = "Shower", guessMinutes = 20), RoutineStep(name = "Shoes", guessMinutes = 10)),
    )
    private val calibration = Calibration(1.5, emptyList(), emptyList())

    private fun alerts(departures: List<DepartureRecord> = emptyList(), run: ActiveRun? = null, now: Instant) =
        NotificationPlan.alerts(listOf(routine), calibration, departures, run, AlertPreferences(), now, zone)

    private fun scheduled(routines: List<Routine>, now: Instant, calibration: Calibration = this.calibration) =
        NotificationPlan.scheduledAlerts(routines, calibration, emptyList(), null, AlertPreferences(), now, zone)

    private fun Instant.isOn(day: Int) = day(zone) == day(day)

    @Test fun getReadyAlertFiresAtThePacedStart() {
        // Monday 21 September, early.
        val result = alerts(now = date(21, 5, 0))
        val first = result.first { it.kind == Kind.GET_READY }
        assertEquals(date(21, 7, 30), first.fireAt)
        assertEquals(routine.id, first.routineID)
        assertTrue(result.any { it.kind == Kind.LEAVE_SOON && it.fireAt == date(21, 8, 5) })
        assertTrue(result.any { it.kind == Kind.LEAVE_NOW && it.fireAt == date(21, 8, 15) })
    }

    @Test fun weekendsGetNoAlerts() {
        val result = alerts(now = date(19, 5, 0))
        assertFalse(result.any { it.fireAt.isOn(19) })
        assertFalse(result.any { it.fireAt.isOn(20) })
    }

    @Test fun aDepartureAlreadyMadeIsNotAlertedAgain() {
        val left = DepartureRecord(routineID = routine.id, target = date(21, 8, 15), left = date(21, 8, 0), startDelaySeconds = null)
        assertFalse(alerts(listOf(left), now = date(21, 8, 1)).any { it.fireAt.isOn(21) })
    }

    @Test fun runningStepGetsAWrapUpAndAnOverrunNudge() {
        val now = date(21, 7, 30)
        val plan = Planner.plan(routine, date(21, 8, 15), calibration)
        val run = ActiveRun.start(plan, routine.name, now, null)
        val result = alerts(run = run, now = now)
        // A thirty minute shower gets its heads-up two minutes before the end.
        val wrap = result.first { it.kind == Kind.WRAP_UP }
        assertEquals(date(21, 7, 58), wrap.fireAt)
        assertEquals("2 min left: Shower", wrap.title)
        val over = result.first { it.kind == Kind.OVERRUN }
        assertEquals(date(21, 8, 5), over.fireAt)
        assertTrue(over.body, over.body.startsWith("5 min behind"))
        // The scheduled get-ready for the same departure is replaced by the run.
        assertFalse(result.any { it.kind == Kind.GET_READY && it.fireAt.isOn(21) })
    }

    @Test fun shortStepsGetAWrapUpWhenTimeIsUp() {
        val short = Routine(name = "Quick", leaveHour = 8, leaveMinute = 15, weekdays = setOf(2), steps = listOf(RoutineStep(name = "Shoes", guessMinutes = 3)))
        val plan = Planner.plan(short, date(21, 8, 15), Calibration(1.0, emptyList(), emptyList()))
        val run = ActiveRun.start(plan, short.name, date(21, 8, 12), null)
        val wrap = NotificationPlan.runAlerts(run, AlertPreferences(), date(21, 8, 12)).first { it.kind == Kind.WRAP_UP }
        assertEquals(date(21, 8, 15), wrap.fireAt)
        assertEquals("Wrap up: Shoes", wrap.title)
    }

    @Test fun anUnansweredAlertIsFollowedUpWithWhatStartingNowCosts() {
        // Paced plan: 30 + 15 = 45 min, so start 7:30 for 8:15.
        val nudges = alerts(now = date(21, 5, 0)).filter { it.kind == Kind.START_NUDGE && it.fireAt.isOn(21) }
        assertEquals(listOf(date(21, 7, 35), date(21, 7, 42)), nudges.map { it.fireAt })
        assertEquals(routine.id, nudges[0].routineID)
        assertEquals(date(21, 8, 15), nudges[0].leaveAt)
        assertTrue(nudges[0].body, nudges[0].body.contains("5 min late"))
        assertTrue(nudges[1].body, nudges[1].body.contains("12 min late"))
    }

    @Test fun nudgesSurviveTheAppOpeningAfterTheAlert() {
        val result = alerts(now = date(21, 7, 33))
        assertFalse(result.any { it.kind == Kind.GET_READY && it.fireAt.isOn(21) })
        assertTrue(result.any { it.kind == Kind.START_NUDGE && it.fireAt == date(21, 7, 35) })
    }

    @Test fun startingTheRunCancelsTheNudges() {
        val plan = Planner.plan(routine, date(21, 8, 15), calibration)
        val run = ActiveRun.start(plan, routine.name, date(21, 7, 31), date(21, 7, 30))
        assertFalse(alerts(run = run, now = date(21, 7, 31)).any { it.kind == Kind.START_NUDGE && it.fireAt.isOn(21) })
    }

    @Test fun aSkippedDayGetsNoAlertsAndTheNextDayIsUntouched() {
        val skipping = routine.settingChange(DayChange(day(22), null), day(22))
        val result = scheduled(listOf(skipping), date(21, 9, 0))
        assertFalse(result.any { it.fireAt.isOn(22) })
        assertTrue(result.any { it.kind == Kind.GET_READY && it.fireAt == date(23, 7, 30) })
    }

    @Test fun aOneOffTimeMovesThatDayOnlyAndCanAddAWeekend() {
        val changed = routine
            .settingChange(DayChange(day(22), 7 * 60), day(22))
            // Saturday the 26th, not a routine day, gets a one-off at 10:40.
            .settingChange(DayChange(day(26), 10 * 60 + 40), day(26))
        val ready = scheduled(listOf(changed), date(21, 9, 0)).filter { it.kind == Kind.GET_READY }.map { it.fireAt }
        assertTrue(date(22, 6, 15) in ready)
        assertTrue(date(23, 7, 30) in ready)
        assertTrue(date(26, 9, 55) in ready)
        assertFalse(date(22, 7, 30) in ready)
    }

    @Test fun scheduleStaysUnderTheSystemLimit() {
        val many = (0 until 8).map { Routine(name = "R$it", leaveHour = 8, leaveMinute = it, weekdays = (1..7).toSet(), steps = listOf(RoutineStep(name = "S", guessMinutes = 5))) }
        val result = scheduled(many, date(21, 5, 0), Calibration(1.0, emptyList(), emptyList()))
        assertTrue(result.size <= NotificationPlan.SCHEDULED_LIMIT)
        assertEquals(result.map { it.fireAt }.sorted(), result.map { it.fireAt })
    }

    @Test fun copyHasNoDashes() {
        val plan = Planner.plan(routine, date(21, 8, 15), calibration)
        val run = ActiveRun.start(plan, routine.name, date(21, 7, 30), null)
        for (alert in alerts(run = run, now = date(21, 5, 0)) + alerts(now = date(21, 5, 0))) {
            assertFalse(alert.title + alert.body, (alert.title + alert.body).contains("—"))
            assertFalse(alert.title + alert.body, (alert.title + alert.body).contains("–"))
        }
    }
}
