package com.jackwallner.time

import com.jackwallner.time.data.MemoryStateFile
import com.jackwallner.time.data.RoutineStore
import com.jackwallner.time.model.DayChange
import com.jackwallner.time.model.Format
import com.jackwallner.time.model.NextDepartureSnapshot
import com.jackwallner.time.model.PaceAnswer
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import com.jackwallner.time.model.WidgetPhase
import com.jackwallner.time.model.WidgetRun
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** The next-start widget: which phase it draws, when it redraws, what it lists. */
class WidgetPhaseTests {
    private val zone = ZoneId.of("America/Los_Angeles")

    private val routine = Routine(
        name = "Weekday mornings",
        leaveHour = 8,
        leaveMinute = 15,
        weekdays = setOf(2, 3, 4, 5, 6),
        steps = listOf(RoutineStep(name = "Shower", guessMinutes = 10), RoutineStep(name = "Shoes", guessMinutes = 5)),
    )

    /** The 21st of September 2026 is a Monday. */
    private fun date(day: Int, hour: Int, minute: Int = 0): Instant = LocalDateTime.of(2026, 9, day, hour, minute).atZone(zone).toInstant()

    private val monday = NextDepartureSnapshot("Weekday mornings", alertAt = date(21, 8), leaveAt = date(21, 8, 15))
    private val tuesday = NextDepartureSnapshot("Weekday mornings", alertAt = date(22, 8), leaveAt = date(22, 8, 15))

    @Before fun setUp() {
        Format.zone = zone
        Format.timeFormatter = DateTimeFormatter.ofPattern("H:mm")
    }

    private fun makeStore(): RoutineStore {
        val store = RoutineStore(MemoryStateFile(), zone = { zone }, clock = { date(21, 6) })
        store.save(routine)
        store.setPace(PaceAnswer.ON_THE_DOT)
        return store
    }

    @Test fun moreThanAnHourOutShowsTheStartTime() {
        val phase = WidgetPhase.at(date(21, 6), listOf(monday, tuesday), null)
        assertEquals(WidgetPhase.Later(monday), phase)
        assertEquals("Start at", phase.smallLabel)
        assertEquals("8:00", phase.headline)
        assertEquals("Out the door 8:15", phase.footer(date(21, 6)))
    }

    @Test fun theLastHourCountsDown() {
        assertEquals(WidgetPhase.Countdown(monday), WidgetPhase.at(date(21, 7), listOf(monday), null))
        assertEquals(WidgetPhase.Countdown(monday), WidgetPhase.at(date(21, 7, 59), listOf(monday), null))
        assertEquals("Start in", WidgetPhase.Countdown(monday).smallLabel)
    }

    @Test fun pastTheStartItSaysStartNowInRed() {
        val phase = WidgetPhase.at(date(21, 8, 5), listOf(monday, tuesday), null)
        assertEquals(WidgetPhase.Overdue(monday), phase)
        assertTrue(phase.isUrgent)
        assertEquals("Start now", phase.headline)
        assertEquals("Late to start", phase.smallLabel)
    }

    @Test fun afterTheLeaveTimeItMovesToTheNextDay() {
        val phase = WidgetPhase.at(date(21, 8, 15), listOf(monday, tuesday), null)
        assertEquals(WidgetPhase.Later(tuesday), phase)
        assertEquals("Tomorrow, out 8:15", phase.footer(date(21, 8, 15)))
    }

    @Test fun aRunShowsItsStepUntilHalfAnHourAfterLeaving() {
        val run = WidgetRun("Weekday mornings", date(21, 8, 15), "Shower", isLeaving = false)
        assertEquals("Shower", WidgetPhase.at(date(21, 8, 40), listOf(tuesday), run).headline)
        assertEquals("Head out", WidgetPhase.at(date(21, 8, 10), emptyList(), run.copy(isLeaving = true)).headline)
        assertEquals(WidgetPhase.Later(tuesday), WidgetPhase.at(date(21, 8, 45), listOf(tuesday), run))
    }

    @Test fun nothingSetSaysSo() {
        val phase = WidgetPhase.at(date(21, 6), emptyList(), null)
        assertEquals(WidgetPhase.None, phase)
        assertEquals("Set one in the app", phase.footer(date(21, 6)))
    }

    @Test fun itRedrawsAtEveryPhaseChangeAndAtMidnight() {
        val departures = listOf(monday, tuesday)
        assertEquals(date(21, 7), WidgetPhase.nextChange(date(21, 6), departures, null))
        assertEquals(date(21, 8), WidgetPhase.nextChange(date(21, 7), departures, null))
        assertEquals(date(21, 8, 15), WidgetPhase.nextChange(date(21, 8), departures, null))
        assertEquals(date(22, 0), WidgetPhase.nextChange(date(21, 8, 15), departures, null))
    }

    @Test fun upcomingDeparturesHonourSkipsAndOneOffTimes() {
        val store = makeStore()
        store.setChange(DayChange(LocalDate.of(2026, 9, 22), null), LocalDate.of(2026, 9, 22), routine.id)
        store.setChange(DayChange(LocalDate.of(2026, 9, 23), 9 * 60), LocalDate.of(2026, 9, 23), routine.id)
        val leaves = store.upcomingDepartures(date(21, 6)).map { it.plan.leaveAt }
        assertEquals(date(21, 8, 15), leaves[0])
        assertEquals(date(23, 9), leaves[1])
        assertEquals(date(24, 8, 15), leaves[2])
        assertTrue(leaves.zipWithNext().all { (a, b) -> a < b })
    }

    @Test fun upcomingDeparturesLeaveOutTheRunAndDeparturesMade() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 55))
        assertEquals(date(22, 8, 15), store.widgetDepartures(date(21, 7, 56)).first().leaveAt)
        assertEquals("Shower", store.widgetRun?.stepName)
        store.finishRun(date(21, 8, 10))
        assertEquals(date(22, 8, 15), store.widgetDepartures(date(21, 8, 11)).first().leaveAt)
        assertEquals(null, store.widgetRun)
    }

    @Test fun theWidgetAlertTimeIncludesTheHeadStart() {
        val store = makeStore()
        val next = store.widgetDepartures(date(21, 6)).first()
        val plan = store.nextPlan(routine, date(21, 6))!!
        assertEquals(plan.alertAt, next.alertAt)
        assertEquals(plan.leaveAt, next.leaveAt)
    }
}
