package com.jackwallner.time.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.time.model.ActiveRun
import com.jackwallner.time.model.Calibration
import com.jackwallner.time.model.DayChange
import com.jackwallner.time.model.DeparturePlan
import com.jackwallner.time.model.DepartureRecord
import com.jackwallner.time.model.NotificationPlan
import com.jackwallner.time.model.PaceAnswer
import com.jackwallner.time.model.Planner
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.StepRecord
import com.jackwallner.time.model.day
import com.jackwallner.time.model.plusSeconds
import com.jackwallner.time.model.secondsSince
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlin.math.ceil

/** Where the state file lives. A file in the app, or memory in tests. */
interface StateFile {
    fun read(): String?
    fun write(text: String)
}

class DiskStateFile(private val file: File) : StateFile {
    override fun read(): String? = if (file.exists()) file.readText() else null

    override fun write(text: String) {
        val temp = File(file.parentFile, "${file.name}.tmp")
        temp.writeText(text)
        if (!temp.renameTo(file)) {
            file.writeText(text)
            temp.delete()
        }
    }
}

class MemoryStateFile(var text: String? = null) : StateFile {
    override fun read(): String? = text
    override fun write(text: String) { this.text = text }
}

/**
 * The run as it stood before the last Done, Skip or catch-up skip, so a
 * mis-tap on a busy morning can be taken back. Memory only.
 */
data class StepUndo(
    val before: ActiveRun,
    val after: ActiveRun,
    /** The timing that Done added to the history, removed again on undo. */
    val recordedStepID: UUID?,
    val kind: Kind,
    val stepName: String,
    val id: UUID = UUID.randomUUID(),
) {
    enum class Kind { DONE, SKIP, DROP }
}

data class UpcomingDeparture(val routine: Routine, val plan: DeparturePlan)

/**
 * The single door to routines, runs and history. Every change goes through
 * here, and every change fans out to alerts and the run notification, so no
 * surface can drift from the others.
 */
class RoutineStore(
    private val file: StateFile,
    private val zone: () -> ZoneId = { ZoneId.systemDefault() },
    private val clock: () -> Instant = { Instant.now() },
    /** Whether get-ready alerts are on, so a run started on time answers one. */
    private val startAlertsEnabled: () -> Boolean = { true },
) {
    var state: PersistedState by mutableStateOf(load())
        private set
    var lastStepUndo: StepUndo? by mutableStateOf(null)
        private set

    /** Set once at launch: alerts, the run notification. */
    var onChange: (RoutineStore) -> Unit = {}

    private fun load(): PersistedState =
        file.read()?.let { runCatching { StateCodec.decode(it) }.getOrNull() } ?: PersistedState()

    // MARK: Reading

    val routines: List<Routine> get() = state.routines
    val activeRun: ActiveRun? get() = state.activeRun

    val selectedRoutine: Routine?
        get() = state.routines.firstOrNull { it.id == state.selectedRoutineID } ?: state.routines.firstOrNull()

    val calibration: Calibration
        get() = Calibration(state.pace.multiplier, state.stepHistory, state.departures)

    fun routine(id: UUID): Routine? = state.routines.firstOrNull { it.id == id }

    fun plan(routine: Routine, leaveAt: Instant): DeparturePlan = Planner.plan(routine, leaveAt, calibration)

    /** The next scheduled departure, or null when the routine has no days. */
    fun nextPlan(routine: Routine, now: Instant = clock()): DeparturePlan? {
        var after = now
        // Past any departure already made, so leaving early for 8:15 at 8:05
        // moves the card on to the next one.
        repeat(3) {
            val leave = routine.nextScheduledLeave(after, zone()) ?: return null
            val made = state.departures.any { it.routineID == routine.id && it.target == leave }
            if (!made) return plan(routine, leave)
            after = leave
        }
        return null
    }

    /** The soonest departure across every routine. */
    fun nextDeparture(now: Instant = clock()): UpcomingDeparture? =
        state.routines.mapNotNull { r -> nextPlan(r, now)?.let { UpcomingDeparture(r, it) } }.minByOrNull { it.plan.leaveAt }

    fun departures(routineID: UUID): List<DepartureRecord> =
        state.departures.filter { it.routineID == routineID }.sortedByDescending { it.left }

    // MARK: Routines

    fun setPace(pace: PaceAnswer) = mutate { it.copy(pace = pace) }

    fun select(routineID: UUID) = mutate { it.copy(selectedRoutineID = routineID) }

    fun save(routine: Routine) = mutate { s ->
        if (s.routines.any { it.id == routine.id }) {
            s.copy(routines = s.routines.map { if (it.id == routine.id) routine else it })
        } else {
            s.copy(routines = s.routines + routine, selectedRoutineID = routine.id)
        }
    }

    fun delete(routineID: UUID) = mutate { s ->
        val routines = s.routines.filter { it.id != routineID }
        s.copy(
            routines = routines,
            stepHistory = s.stepHistory.filter { it.routineID != routineID },
            departures = s.departures.filter { it.routineID != routineID },
            activeRun = s.activeRun?.takeIf { it.routineID != routineID },
            selectedRoutineID = if (s.selectedRoutineID == routineID) routines.firstOrNull()?.id else s.selectedRoutineID,
        )
    }

    /** Skips one day, gives it a one-off leave time, or with null puts it back to normal. */
    fun setChange(change: DayChange?, on: LocalDate, routineID: UUID) = mutate { s ->
        s.copy(routines = s.routines.map {
            if (it.id == routineID) it.settingChange(change, on).pruningChanges(clock(), zone()) else it
        })
    }

    /** Forgets every timing, keeping the routines and the pace answer. */
    fun resetLearning() = mutate { it.copy(stepHistory = emptyList(), departures = emptyList(), lastFinished = null) }

    // MARK: Runs

    data class RunTarget(val leaveAt: Instant, val isPractice: Boolean)

    /**
     * What a run started now aims for: the routine's next leave time, or, well
     * before that departure is due to start, a practice run planned from now.
     * A practice run at 10 PM must not count as tomorrow's departure, or it
     * would cancel tomorrow's alerts.
     */
    fun runTarget(routine: Routine, now: Instant = clock()): RunTarget {
        val leave = nextPlan(routine, now)?.leaveAt ?: routine.leaveTimeForRunStarted(now, zone())
        val due = plan(routine, leave)
        if (due.alertAt.secondsSince(now) <= PRACTICE_LEAD_SECONDS) return RunTarget(leave, false)
        val ready = now.plusSeconds((due.realMinutes * 60).toDouble())
        val minute = ceil(ready.toEpochMilli() / 60_000.0).toLong() * 60_000
        return RunTarget(Instant.ofEpochMilli(minute), true)
    }

    fun startRun(routineID: UUID, now: Instant = clock()) {
        if (state.activeRun != null) return
        val routine = routine(routineID) ?: return
        val target = runTarget(routine, now)
        val plan = plan(routine, target.leaveAt)
        val answersAlert = !target.isPractice && routine.departs(target.leaveAt.day(zone())) && startAlertsEnabled()
        lastStepUndo = null
        mutate {
            it.copy(
                activeRun = ActiveRun.start(plan, routine.name, now, if (answersAlert) plan.alertAt else null, target.isPractice),
                selectedRoutineID = routineID,
                lastFinished = null,
            )
        }
    }

    /**
     * A tap on a get-ready alert or its follow-up: the tap is the start. Does
     * nothing once that departure is under way, made or gone, so an old alert
     * opened at noon only opens the app.
     */
    fun startRunFromAlert(routineID: UUID, leaveAt: Instant, now: Instant = clock()) {
        if (state.activeRun != null || leaveAt <= now) return
        val routine = routine(routineID) ?: return
        if (nextPlan(routine, now)?.leaveAt != leaveAt) return
        if (state.departures.any { it.routineID == routineID && it.target == leaveAt }) return
        startRun(routineID, now)
    }

    /** Starts the soonest routine, for the launcher shortcut and notifications. */
    fun startNextRun(now: Instant = clock()) {
        val routine = nextDeparture(now)?.routine ?: selectedRoutine ?: return
        startRun(routine.id, now)
    }

    fun completeStep(now: Instant = clock()) {
        val before = state.activeRun ?: return
        if (before.isLeaving) return
        val (run, finished) = before.completingCurrentStep(now)
        var recorded: UUID? = null
        mutate { s ->
            val seconds = finished?.actualSeconds
            if (finished != null && seconds != null && seconds >= MINIMUM_TIMED_SECONDS) {
                recorded = finished.id
                s.copy(
                    activeRun = run,
                    stepHistory = (s.stepHistory + StepRecord(finished.id, run.routineID, finished.guessMinutes, seconds, now)).takeLast(HISTORY_LIMIT),
                )
            } else {
                s.copy(activeRun = run)
            }
        }
        lastStepUndo = StepUndo(before, run, recorded, StepUndo.Kind.DONE, finished?.name.orEmpty())
    }

    fun skipStep(now: Instant = clock()) {
        val before = state.activeRun ?: return
        if (before.isLeaving) return
        val run = before.skippingCurrentStep(now)
        mutate { it.copy(activeRun = run) }
        lastStepUndo = StepUndo(before, run, null, StepUndo.Kind.SKIP, before.currentStep?.name.orEmpty())
    }

    /**
     * Puts the last Done, Skip or catch-up skip back, as long as nothing has
     * moved since. The step picks up its clock where it was.
     */
    fun undoLastStep() {
        val undo = lastStepUndo
        lastStepUndo = null
        if (undo == null || state.activeRun != undo.after) return
        mutate { s ->
            val history = s.stepHistory.toMutableList()
            undo.recordedStepID?.let { id ->
                val index = history.indexOfLast { it.stepID == id }
                if (index >= 0) history.removeAt(index)
            }
            s.copy(activeRun = undo.before, stepHistory = history)
        }
    }

    /** Takes a later step off today's plan to catch up. */
    fun dropUpcomingStep(id: UUID) {
        val before = state.activeRun ?: return
        val step = before.steps.firstOrNull { it.id == id } ?: return
        val run = before.droppingUpcomingStep(id)
        if (run == before) return
        mutate { it.copy(activeRun = run) }
        lastStepUndo = StepUndo(before, run, null, StepUndo.Kind.DROP, step.name)
    }

    /** The user walked out. Records the departure and hands back the summary. */
    fun finishRun(now: Instant = clock()): FinishedRun? {
        val run = state.activeRun ?: return null
        val departure = DepartureRecord(routineID = run.routineID, target = run.leaveAt, left = now, startDelaySeconds = run.startDelaySeconds)
        val finished = FinishedRun(run, departure)
        lastStepUndo = null
        mutate { s ->
            val departures = if (run.isPractice) s.departures else s.departures + departure
            s.copy(activeRun = null, departures = departures.takeLast(DEPARTURE_LIMIT), lastFinished = finished)
        }
        return finished
    }

    fun cancelRun() {
        lastStepUndo = null
        mutate { it.copy(activeRun = null) }
    }

    fun dismissSummary() = mutate { it.copy(lastFinished = null) }

    /**
     * Tidies what time has made stale, then pushes everything out. Called
     * whenever the app comes to the foreground.
     */
    fun refresh(now: Instant = clock()) {
        val stale = state.activeRun?.isAbandoned(now) == true
        val oldSummary = state.lastFinished?.let { now.secondsSince(it.departure.left) > 12 * 3600 } ?: false
        val today = now.day(zone())
        val hasPastChanges = state.routines.any { r -> r.changes.any { it.day < today } }
        if (!stale && !oldSummary && !hasPastChanges) {
            onChange(this)
            return
        }
        mutate { s ->
            // A run left open for hours was never closed, not a three hour
            // morning. Its finished steps already count; the departure does not.
            s.copy(
                activeRun = if (stale) null else s.activeRun,
                lastFinished = if (oldSummary) null else s.lastFinished,
                routines = s.routines.map { it.pruningChanges(now, zone()) },
            )
        }
    }

    /** Replaces everything, for screenshots and tests. */
    fun replaceState(newState: PersistedState) {
        state = newState
        lastStepUndo = null
        persist()
    }

    private fun mutate(change: (PersistedState) -> PersistedState) {
        state = change(state)
        persist()
        onChange(this)
    }

    private fun persist() {
        runCatching { file.write(StateCodec.encode(state)) }
    }

    fun alerts(preferences: com.jackwallner.time.model.AlertPreferences, now: Instant = clock()) = NotificationPlan.alerts(
        routines = state.routines,
        calibration = calibration,
        departures = state.departures,
        activeRun = state.activeRun,
        preferences = preferences,
        now = now,
        zone = zone(),
    )

    companion object {
        /** Kept long enough to learn from, short enough to stay small. */
        const val HISTORY_LIMIT = 600
        const val DEPARTURE_LIMIT = 200
        /** A Done tapped this quickly was a tap-through, not a timing. */
        const val MINIMUM_TIMED_SECONDS = 15.0
        /** Starting more than this before a departure's start is trying the routine out. */
        const val PRACTICE_LEAD_SECONDS = 3600.0
    }
}
