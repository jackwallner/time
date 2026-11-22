package com.jackwallner.time

import com.jackwallner.time.data.MemoryStateFile
import com.jackwallner.time.data.RoutineStore
import com.jackwallner.time.model.PaceAnswer
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS `StoreTests` "Done tied to its step" (iOS commit ce74592). */
class StepGuardTests {
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

    private fun makeStore(): RoutineStore {
        val store = RoutineStore(MemoryStateFile(), zone = { zone }, clock = { date(21, 6) })
        store.save(routine)
        store.setPace(PaceAnswer.ON_THE_DOT)
        return store
    }

    @Test fun aSecondDoneWithinASecondDoesNotFinishTheNextStep() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        val shower = date(21, 7, 58)
        store.completeStep(shower)
        store.completeStep(shower.plusMillis(400))
        assertEquals(1, store.activeRun?.stepIndex)
        assertNull(store.activeRun?.steps?.get(1)?.actualSeconds)
    }

    @Test fun aSecondSkipWithinASecondDoesNotSkipTheNextStep() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        val shower = date(21, 7, 58)
        store.skipStep(shower)
        store.skipStep(shower.plusMillis(400))
        assertEquals(false, store.activeRun?.steps?.get(1)?.skipped)
        assertEquals(1, store.activeRun?.stepIndex)
    }

    @Test fun aDoneForAFinishedStepChangesNothing() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        val showerStarted = store.activeRun!!.stepStartedAt
        store.completeStep(date(21, 7, 58), stepStartedAt = showerStarted)
        assertEquals(1, store.activeRun?.stepIndex)
        store.completeStep(date(21, 8, 1), stepStartedAt = showerStarted)
        assertEquals(1, store.activeRun?.stepIndex)
        store.completeStep(date(21, 8, 2), stepStartedAt = store.activeRun!!.stepStartedAt)
        assertEquals(true, store.activeRun?.isLeaving)
    }
}
