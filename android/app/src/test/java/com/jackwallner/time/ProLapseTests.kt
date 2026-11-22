package com.jackwallner.time

import com.jackwallner.time.data.MemoryStateFile
import com.jackwallner.time.data.RoutineStore
import com.jackwallner.time.model.AlertPreferences
import com.jackwallner.time.model.PaceAnswer
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `StoreTests` "Pro lapsed": a lapsed trial keeps one routine (iOS commit 0e5af2d). */
class ProLapseTests {
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

    private fun makeStoreWithTwoRoutines(isPro: Boolean): Pair<RoutineStore, Routine> {
        val store = RoutineStore(MemoryStateFile(), zone = { zone }, clock = { date(21, 6) })
        store.save(routine)
        store.setPace(PaceAnswer.ON_THE_DOT)
        val gym = Routine(name = "Gym", leaveHour = 7, leaveMinute = 0, weekdays = setOf(2, 3, 4, 5, 6), steps = listOf(RoutineStep(name = "Bag", guessMinutes = 5)))
        store.save(gym)
        store.hasPro = { isPro }
        return store to gym
    }

    @Test fun withoutProOnlyTheFirstRoutineAlertsAndRuns() {
        val (store, gym) = makeStoreWithTwoRoutines(isPro = false)
        assertEquals(listOf(routine.id), store.activeRoutines.map { it.id })
        assertTrue(store.isLocked(gym.id))
        assertEquals(routine.id, store.selectedRoutine?.id)
        assertFalse(store.upcomingDepartures(date(21, 6)).any { it.routine.id == gym.id })
        assertEquals(routine.id, store.nextDeparture(date(21, 6))?.routine?.id)
        assertFalse(store.alerts(AlertPreferences(), date(21, 6)).any { it.routineID == gym.id })
        store.startRun(gym.id, date(21, 6, 50))
        assertNull(store.activeRun)
        store.startRun(routine.id, date(21, 7, 50))
        assertEquals(routine.id, store.activeRun?.routineID)
    }

    @Test fun proBringsEveryRoutineBack() {
        val (store, gym) = makeStoreWithTwoRoutines(isPro = true)
        assertEquals(2, store.activeRoutines.size)
        assertFalse(store.isLocked(gym.id))
        assertEquals(gym.id, store.selectedRoutine?.id)
        assertEquals(gym.id, store.nextDeparture(date(21, 6))?.routine?.id)
    }
}
