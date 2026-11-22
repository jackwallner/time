package com.jackwallner.time

import com.jackwallner.time.data.MemoryStateFile
import com.jackwallner.time.data.RoutineStore
import com.jackwallner.time.model.Calibration
import com.jackwallner.time.model.PaceAnswer
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import com.jackwallner.time.model.StepRecord
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `StoreTests` for forgotten runs, try-outs, a lapsed Pro and a Done tied
 * to its step (iOS commits 0e5af2d, ce74592, d2ccbc7).
 */
class StoreRobustnessTests {
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

    private fun makeStore(file: MemoryStateFile = MemoryStateFile(), now: Instant = date(21, 6)): RoutineStore {
        val store = RoutineStore(file, zone = { zone }, clock = { now })
        store.save(routine)
        store.setPace(PaceAnswer.ON_THE_DOT)
        return store
    }

    // MARK: A forgotten run

    /**
     * Start 7:50, Shower done at 8:00, walk out without a tap, then clear the
     * run at 10:30. Tuesday's plan must not grow by the hours it sat open.
     */
    @Test fun aStepLeftRunningForHoursDoesNotTakeOverItsPlan() {
        val store = makeStore()
        val before = store.plan(routine, date(22, 8, 15)).alertAt
        store.startRun(routine.id, date(21, 7, 50))
        store.completeStep(date(21, 8))
        store.completeStep(date(21, 10, 30))
        store.cancelRun()
        val shoes = store.calibration.estimate(routine.steps[1])
        assertTrue("Shoes (guess 5) is now planned at ${shoes.minutes} min", shoes.minutes <= 6)
        val after = store.plan(routine, date(22, 8, 15)).alertAt
        assertEquals("Tuesday's alert moved from $before to $after", 0.0, after.epochSecond.toDouble() - before.epochSecond, 60.0)
    }

    /** A timing already stored from an older build is bounded too. */
    @Test fun oneHugeTimingIsBoundedInThePlan() {
        val step = routine.steps[1]
        val calibration = Calibration(1.0, listOf(StepRecord(step.id, routine.id, 5, 24 * 3600.0, date(21, 8))), emptyList())
        assertTrue(calibration.estimate(step).minutes <= 15)
    }

    @Test fun aRealLongStepStillTeaches() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        store.completeStep(date(21, 8, 10))
        assertEquals(20 * 60.0, store.state.stepHistory.last().actualSeconds, 0.001)
        assertTrue(store.calibration.estimate(routine.steps[0]).minutes > 10)
    }

    // MARK: A run left open overnight

    @Test fun aRunLeftOpenOvernightDoesNotBlockTheNextMorning() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        store.startNextRun(date(22, 7, 55))
        assertEquals(date(22, 8, 15), store.activeRun?.leaveAt)

        val other = makeStore()
        other.startRun(routine.id, date(21, 7, 50))
        other.startRunFromAlert(routine.id, date(22, 8, 15), date(22, 8))
        assertEquals(date(22, 8, 15), other.activeRun?.leaveAt)
    }

    @Test fun aDoneOnYesterdaysRunClosesItWithoutTimingAStep() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        store.completeStep(date(22, 7, 50))
        assertNull(store.activeRun)
        assertTrue(store.state.stepHistory.isEmpty())
        assertNull(store.finishRun(date(22, 7, 51)))
        assertTrue(store.state.departures.isEmpty())
    }

    @Test fun anAbandonedRunIsGoneAtLaunch() {
        val file = MemoryStateFile()
        makeStore(file).startRun(routine.id, date(21, 7, 50))
        assertNotNull(RoutineStore(file, zone = { zone }, clock = { date(21, 9) }).activeRun)
        assertNull(RoutineStore(file, zone = { zone }, clock = { date(22, 7) }).activeRun)
    }

    // MARK: A try-out

    @Test fun aTryOutFarUnderTheGuessTeachesNothing() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 21))
        val started = store.activeRun?.stepStartedAt ?: date(21, 21)
        // 20 s on a 10 minute shower is poking at the app, not a timing.
        store.completeStep(started.plusSeconds(20))
        assertTrue(store.state.stepHistory.isEmpty())
        assertFalse(RoutineStore.isTiming(149.0, 10))
        assertTrue(RoutineStore.isTiming(150.0, 10))
        assertTrue(RoutineStore.isTiming(15.0, 1))
    }
}
