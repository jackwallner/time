package com.jackwallner.time

import com.jackwallner.time.data.MemoryStateFile
import com.jackwallner.time.data.RoutineStore
import com.jackwallner.time.data.StateCodec
import com.jackwallner.time.data.StepUndo
import com.jackwallner.time.model.DayChange
import com.jackwallner.time.model.PaceAnswer
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** One for one with iOS `StoreTests`: practice runs, undo, starting from an alert. */
class StoreTests {
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
    private fun day(day: Int) = LocalDate.of(2026, 9, day)

    /** A fresh store with the routine, guesses taken at face value. */
    private fun makeStore(file: MemoryStateFile = MemoryStateFile()): RoutineStore {
        val store = RoutineStore(file, zone = { zone }, clock = { date(21, 6) })
        store.save(routine)
        store.setPace(PaceAnswer.ON_THE_DOT)
        return store
    }

    @Test fun anEveningRunIsPracticeAndLeavesTomorrowAlone() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 21))
        val run = store.activeRun!!
        assertTrue(run.isPractice)
        assertEquals(date(21, 21, 15), run.leaveAt)
        assertNull(run.alertAt)
        store.completeStep(date(21, 21, 8))
        store.completeStep(date(21, 21, 12))
        store.finishRun(date(21, 21, 13))
        assertTrue(store.state.departures.isEmpty())
        assertEquals(2, store.state.stepHistory.size)
        assertEquals(date(22, 8, 15), store.nextPlan(routine, date(21, 21, 14))?.leaveAt)
    }

    @Test fun aRunNearTheStartAimsForTheDeparture() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        assertFalse(store.activeRun!!.isPractice)
        assertEquals(date(21, 8, 15), store.activeRun?.leaveAt)
        store.finishRun(date(21, 8, 14))
        assertEquals(1, store.state.departures.size)
    }

    @Test fun undoPutsTheStepBackAndForgetsItsTiming() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        store.completeStep(date(21, 7, 56))
        assertEquals(1, store.state.stepHistory.size)
        store.undoLastStep()
        assertEquals(0, store.activeRun?.stepIndex)
        assertEquals(date(21, 7, 50), store.activeRun?.stepStartedAt)
        assertNull(store.activeRun?.steps?.get(0)?.actualSeconds)
        assertTrue(store.state.stepHistory.isEmpty())
        assertNull(store.lastStepUndo)
    }

    @Test fun undoingASkipPutsTheStepBack() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        store.skipStep(date(21, 7, 51))
        store.undoLastStep()
        assertEquals(0, store.activeRun?.stepIndex)
        assertEquals(false, store.activeRun?.steps?.get(0)?.skipped)
    }

    @Test fun undoingACatchUpSkipPutsTheStepBack() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        val shoes = routine.steps[1].id
        store.dropUpcomingStep(shoes)
        assertEquals(true, store.activeRun?.steps?.get(1)?.skipped)
        assertEquals(StepUndo.Kind.DROP, store.lastStepUndo?.kind)
        assertEquals("Shoes", store.lastStepUndo?.stepName)
        store.undoLastStep()
        assertEquals(false, store.activeRun?.steps?.get(1)?.skipped)
        assertEquals(0, store.activeRun?.stepIndex)
        assertNull(store.lastStepUndo)
    }

    @Test fun undoDoesNothingOnceTheRunHasMovedOn() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        store.completeStep(date(21, 7, 56))
        store.cancelRun()
        store.undoLastStep()
        assertNull(store.activeRun)
        assertEquals(1, store.state.stepHistory.size)
    }

    @Test fun openingTheAlertStartsThatDeparture() {
        val store = makeStore()
        store.startRunFromAlert(routine.id, date(21, 8, 15), date(21, 7, 52))
        assertEquals(date(21, 8, 15), store.activeRun?.leaveAt)
    }

    @Test fun openingAnOldAlertOnlyOpensTheApp() {
        val store = makeStore()
        store.startRunFromAlert(routine.id, date(21, 8, 15), date(21, 12))
        assertNull(store.activeRun)
    }

    @Test fun startingOnASkippedDayPracticesInsteadOfRecordingTheSkippedDeparture() {
        val store = makeStore()
        val state = store.state
        store.replaceState(state.copy(routines = listOf(state.routines[0].settingChange(DayChange(day(21), null), day(21)))))
        assertEquals(date(22, 8, 15), store.nextPlan(store.state.routines[0], date(21, 7, 50))?.leaveAt)
        store.startRun(routine.id, date(21, 7, 50))
        assertTrue(store.activeRun!!.isPractice)
        store.finishRun(date(21, 8))
        assertTrue(store.state.departures.isEmpty())
    }

    @Test fun anOffDayDoesNotStartADifferentDepartureFromTheHomePlan() {
        val store = makeStore()
        store.startRun(routine.id, date(20, 7, 50))
        assertTrue(store.activeRun!!.isPractice)
        assertNull(store.activeRun?.alertAt)
    }

    @Test fun startingAgainAfterLeavingEarlyDoesNotRecordTheDepartureTwice() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        store.finishRun(date(21, 8))
        store.dismissSummary()
        store.startRun(routine.id, date(21, 8, 1))
        assertTrue(store.activeRun!!.isPractice)
        store.finishRun(date(21, 8, 10))
        assertEquals(1, store.state.departures.size)
    }

    @Test fun anAlertForASkippedOrMovedDepartureDoesNotStartARun() {
        for (override in listOf<Int?>(null, 7 * 60)) {
            val store = makeStore()
            val state = store.state
            store.replaceState(state.copy(routines = listOf(state.routines[0].settingChange(DayChange(day(21), override), day(21)))))
            store.startRunFromAlert(routine.id, date(21, 8, 15), date(21, 7, 50))
            assertNull(store.activeRun)
        }
    }

    // Android-specific: the state file survives a relaunch exactly.

    @Test fun stateRoundTripsThroughTheFile() {
        val file = MemoryStateFile()
        val store = makeStore(file)
        store.setChange(DayChange(day(23), 7 * 60 + 30), day(23), routine.id)
        store.startRun(routine.id, date(21, 7, 50))
        store.completeStep(date(21, 7, 56))
        store.dropUpcomingStep(routine.steps[1].id)
        val reloaded = RoutineStore(file, zone = { zone }, clock = { date(21, 6) })
        assertEquals(store.state, reloaded.state)
        assertEquals(StateCodec.encode(store.state), StateCodec.encode(reloaded.state))
    }

    @Test fun aRoutineSavedBeforeChangesExistedStillLoads() {
        val json = """
            {"id":"5A0E5A0E-0000-4000-8000-000000000001","name":"Mornings","leaveHour":8,"leaveMinute":15,
             "weekdays":[2,3],"steps":[{"id":"5A0E5A0E-0000-4000-8000-000000000002","name":"Shower","guessMinutes":10}]}
        """.trimIndent()
        val decoded = StateCodec.routine(org.json.JSONObject(json))
        assertEquals("Mornings", decoded.name)
        assertTrue(decoded.changes.isEmpty())
    }

    @Test fun aCorruptFileStartsFresh() {
        val store = RoutineStore(MemoryStateFile("{not json"), zone = { zone })
        assertTrue(store.routines.isEmpty())
    }

    @Test fun deletingARoutineTakesItsHistoryAndRun() {
        val store = makeStore()
        val second = routine.copy(id = java.util.UUID.randomUUID(), name = "Gym")
        store.save(second)
        store.startRun(routine.id, date(21, 7, 50))
        store.completeStep(date(21, 7, 56))
        store.delete(routine.id)
        assertNull(store.activeRun)
        assertTrue(store.state.stepHistory.isEmpty())
        assertEquals(second.id, store.selectedRoutine?.id)
    }

    @Test fun aTapThroughDoneIsNotATiming() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        store.completeStep(date(21, 7, 50).plusSeconds(10))
        assertTrue(store.state.stepHistory.isEmpty())
        assertEquals(1, store.activeRun?.stepIndex)
    }

    @Test fun refreshDropsAnAbandonedRunButKeepsItsTimings() {
        val store = makeStore()
        store.startRun(routine.id, date(21, 7, 50))
        store.completeStep(date(21, 7, 56))
        store.refresh(date(21, 12))
        assertNull(store.activeRun)
        assertEquals(1, store.state.stepHistory.size)
        assertTrue(store.state.departures.isEmpty())
    }
}
