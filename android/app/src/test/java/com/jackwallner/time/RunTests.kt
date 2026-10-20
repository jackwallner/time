package com.jackwallner.time

import com.jackwallner.time.model.ActiveRun
import com.jackwallner.time.model.Calibration
import com.jackwallner.time.model.Planner
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import com.jackwallner.time.model.RunSnapshot
import com.jackwallner.time.model.RunStatus
import com.jackwallner.time.model.plusSeconds
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** One for one with iOS `RunTests`. */
class RunTests {
    private val t0: Instant = Instant.ofEpochSecond(1_790_000_000)

    private fun at(minutes: Double): Instant = t0.plusSeconds(minutes * 60)

    private fun makeRun(leaveIn: Double = 40.0): ActiveRun {
        val steps = listOf("Shower" to 10, "Dress" to 10, "Shoes" to 5).map { RoutineStep(name = it.first, guessMinutes = it.second) }
        val routine = Routine(name = "Mornings", leaveHour = 8, leaveMinute = 0, weekdays = emptySet(), steps = steps)
        val plan = Planner.plan(routine, at(leaveIn), Calibration(1.2, emptyList(), emptyList()))
        return ActiveRun.start(plan, routine.name, t0, t0.plusSeconds(-300L))
    }

    @Test fun freshRunWithSlackIsAhead() {
        // Planned 12 + 12 + 6 = 30 min against 40 available.
        assertEquals(RunStatus.Ahead(10), makeRun().status(t0))
    }

    @Test fun runningOverAStepSlipsTheWholeMorning() {
        val run = makeRun(30.0)
        assertEquals(RunStatus.OnTrack, run.status(t0))
        // Twenty minutes into a twelve-minute shower.
        assertEquals(RunStatus.Behind(8), run.status(at(20.0)))
    }

    @Test fun finishingEarlyBanksTheTime() {
        val run = makeRun(30.0).completingCurrentStep(at(7.0)).first
        assertEquals(RunStatus.Ahead(5), run.status(at(7.0)))
        assertEquals(7 * 60.0, run.steps[0].actualSeconds!!, 0.001)
        assertEquals(1, run.stepIndex)
    }

    @Test fun skippingRecordsNoTime() {
        val run = makeRun().skippingCurrentStep(at(1.0))
        assertTrue(run.steps[0].skipped)
        assertNull(run.steps[0].actualSeconds)
    }

    @Test fun leavingPhaseComparesNowWithTheLeaveTime() {
        var run = makeRun(30.0)
        for (minute in listOf(10.0, 20.0, 25.0)) run = run.completingCurrentStep(at(minute)).first
        assertTrue(run.isLeaving)
        assertEquals(RunStatus.Ahead(5), run.status(at(25.0)))
        assertEquals(RunStatus.Behind(4), run.status(at(34.0)))
    }

    @Test fun startDelayOnlyCountsWhenAnsweringTheAlert() {
        assertEquals(300.0, makeRun().startDelaySeconds!!, 0.001)
        assertEquals(0.0, makeRun().copy(alertAt = at(10.0)).startDelaySeconds!!, 0.001)
        assertNull(makeRun().copy(alertAt = t0.plusSeconds(-7200L)).startDelaySeconds)
    }

    @Test fun whenBehindItSuggestsTheStepThatCoversTheSlip() {
        val run = makeRun(30.0)
        assertEquals("Dress", run.catchUpSuggestion(at(20.0))?.name)
        // Never the last step, and nothing to suggest when on track.
        assertNull(run.catchUpSuggestion(t0))
    }

    @Test fun droppingAStepWinsItsTimeBackAndIsPassedOver() {
        var run = makeRun(30.0)
        val late = at(20.0)
        run = run.droppingUpcomingStep(run.steps[1].id)
        // Ready at 20 + 6 = 26 min for a 30 min window.
        assertEquals(RunStatus.Ahead(4), run.status(late))
        assertEquals("Shoes", run.nextStep?.name)
        assertEquals(2, run.planStepCount)
        run = run.completingCurrentStep(late).first
        assertEquals("Shoes", run.currentStep?.name)
        assertEquals(2, run.planStepNumber)
        assertNull(run.steps[1].actualSeconds)
        assertTrue(run.steps[1].skipped)
    }

    @Test fun theCurrentStepCannotBeDropped() {
        val run = makeRun()
        assertFalse(run.droppingUpcomingStep(run.steps[0].id).steps[0].skipped)
    }

    @Test fun aRunLeftOpenForHoursIsAbandoned() {
        val run = makeRun(30.0)
        assertFalse(run.isAbandoned(at(120.0)))
        assertTrue(run.isAbandoned(at(240.0)))
    }

    @Test fun snapshotProjectsTheSameStatusAsTheRun() {
        val run = makeRun(30.0)
        val snapshot = RunSnapshot.of(run)
        for (minute in 0..40 step 5) {
            assertEquals("minute $minute", run.status(at(minute.toDouble())), snapshot.status(at(minute.toDouble())))
        }
    }
}
