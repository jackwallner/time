package com.jackwallner.time.data

import com.jackwallner.time.model.ActiveRun
import com.jackwallner.time.model.DayChange
import com.jackwallner.time.model.DepartureRecord
import com.jackwallner.time.model.PaceAnswer
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import com.jackwallner.time.model.RunStep
import com.jackwallner.time.model.StepRecord
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Everything Shoes On remembers, in one JSON file in app storage. */
data class PersistedState(
    val routines: List<Routine> = emptyList(),
    val selectedRoutineID: UUID? = null,
    val pace: PaceAnswer = PaceAnswer.QUARTER_OVER,
    val stepHistory: List<StepRecord> = emptyList(),
    val departures: List<DepartureRecord> = emptyList(),
    val activeRun: ActiveRun? = null,
    /** The run that just ended, kept so the summary survives a relaunch. */
    val lastFinished: FinishedRun? = null,
)

/** A run after the user walked out, for the summary screen. */
data class FinishedRun(val run: ActiveRun, val departure: DepartureRecord)

/**
 * JSON for `PersistedState`. Field names follow the iOS Codable keys; times
 * are epoch milliseconds and days ISO dates. Unknown or missing optional
 * fields decode to their defaults so older files still load.
 */
object StateCodec {
    fun encode(state: PersistedState): String = JSONObject().apply {
        put("routines", JSONArray(state.routines.map(::routine)))
        state.selectedRoutineID?.let { put("selectedRoutineID", it.toString()) }
        put("pace", state.pace.raw)
        put("stepHistory", JSONArray(state.stepHistory.map(::stepRecord)))
        put("departures", JSONArray(state.departures.map(::departure)))
        state.activeRun?.let { put("activeRun", run(it)) }
        state.lastFinished?.let { put("lastFinished", JSONObject().put("run", run(it.run)).put("departure", departure(it.departure))) }
    }.toString()

    fun decode(text: String): PersistedState {
        val json = JSONObject(text)
        return PersistedState(
            routines = json.optJSONArray("routines").objects().map(::routine),
            selectedRoutineID = json.optStringOrNull("selectedRoutineID")?.let(UUID::fromString),
            pace = PaceAnswer.fromRaw(json.optStringOrNull("pace")) ?: PaceAnswer.QUARTER_OVER,
            stepHistory = json.optJSONArray("stepHistory").objects().map(::stepRecord),
            departures = json.optJSONArray("departures").objects().map(::departure),
            activeRun = json.optJSONObject("activeRun")?.let(::run),
            lastFinished = json.optJSONObject("lastFinished")?.let {
                FinishedRun(run(it.getJSONObject("run")), departure(it.getJSONObject("departure")))
            },
        )
    }

    fun routine(r: Routine): JSONObject = JSONObject().apply {
        put("id", r.id.toString())
        put("name", r.name)
        put("leaveHour", r.leaveHour)
        put("leaveMinute", r.leaveMinute)
        put("weekdays", JSONArray(r.weekdays.sorted()))
        put("steps", JSONArray(r.steps.map { JSONObject().put("id", it.id.toString()).put("name", it.name).put("guessMinutes", it.guessMinutes) }))
        put("changes", JSONArray(r.changes.map { c -> JSONObject().put("day", c.day.toString()).also { o -> c.leaveMinuteOfDay?.let { o.put("leaveMinuteOfDay", it) } } }))
    }

    /** `changes` arrived after the first builds; routines without it still load. */
    fun routine(o: JSONObject): Routine = Routine(
        id = UUID.fromString(o.getString("id")),
        name = o.getString("name"),
        leaveHour = o.getInt("leaveHour"),
        leaveMinute = o.getInt("leaveMinute"),
        weekdays = o.getJSONArray("weekdays").let { a -> (0 until a.length()).map(a::getInt).toSet() },
        steps = o.getJSONArray("steps").objects().map { RoutineStep(UUID.fromString(it.getString("id")), it.getString("name"), it.getInt("guessMinutes")) },
        changes = o.optJSONArray("changes").objects().map {
            DayChange(LocalDate.parse(it.getString("day")), if (it.has("leaveMinuteOfDay")) it.getInt("leaveMinuteOfDay") else null)
        },
    )

    private fun stepRecord(s: StepRecord) = JSONObject()
        .put("stepID", s.stepID.toString())
        .put("routineID", s.routineID.toString())
        .put("guessMinutes", s.guessMinutes)
        .put("actualSeconds", s.actualSeconds)
        .put("date", s.date.toEpochMilli())

    private fun stepRecord(o: JSONObject) = StepRecord(
        UUID.fromString(o.getString("stepID")),
        UUID.fromString(o.getString("routineID")),
        o.getInt("guessMinutes"),
        o.getDouble("actualSeconds"),
        Instant.ofEpochMilli(o.getLong("date")),
    )

    private fun departure(d: DepartureRecord) = JSONObject().apply {
        put("id", d.id.toString())
        put("routineID", d.routineID.toString())
        put("target", d.target.toEpochMilli())
        put("left", d.left.toEpochMilli())
        d.startDelaySeconds?.let { put("startDelaySeconds", it) }
    }

    private fun departure(o: JSONObject) = DepartureRecord(
        UUID.fromString(o.getString("id")),
        UUID.fromString(o.getString("routineID")),
        Instant.ofEpochMilli(o.getLong("target")),
        Instant.ofEpochMilli(o.getLong("left")),
        if (o.has("startDelaySeconds")) o.getDouble("startDelaySeconds") else null,
    )

    private fun run(r: ActiveRun) = JSONObject().apply {
        put("routineID", r.routineID.toString())
        put("routineName", r.routineName)
        put("leaveAt", r.leaveAt.toEpochMilli())
        put("startedAt", r.startedAt.toEpochMilli())
        r.alertAt?.let { put("alertAt", it.toEpochMilli()) }
        put("steps", JSONArray(r.steps.map { s ->
            JSONObject().apply {
                put("id", s.id.toString())
                put("name", s.name)
                put("guessMinutes", s.guessMinutes)
                put("plannedMinutes", s.plannedMinutes)
                s.actualSeconds?.let { put("actualSeconds", it) }
                put("skipped", s.skipped)
            }
        }))
        put("stepIndex", r.stepIndex)
        put("stepStartedAt", r.stepStartedAt.toEpochMilli())
        if (r.isPractice) put("isPractice", true)
    }

    private fun run(o: JSONObject) = ActiveRun(
        routineID = UUID.fromString(o.getString("routineID")),
        routineName = o.getString("routineName"),
        leaveAt = Instant.ofEpochMilli(o.getLong("leaveAt")),
        startedAt = Instant.ofEpochMilli(o.getLong("startedAt")),
        alertAt = if (o.has("alertAt")) Instant.ofEpochMilli(o.getLong("alertAt")) else null,
        steps = o.getJSONArray("steps").objects().map {
            RunStep(
                id = UUID.fromString(it.getString("id")),
                name = it.getString("name"),
                guessMinutes = it.getInt("guessMinutes"),
                plannedMinutes = it.getInt("plannedMinutes"),
                actualSeconds = if (it.has("actualSeconds")) it.getDouble("actualSeconds") else null,
                skipped = it.optBoolean("skipped", false),
            )
        },
        stepIndex = o.getInt("stepIndex"),
        stepStartedAt = Instant.ofEpochMilli(o.getLong("stepStartedAt")),
        isPractice = o.optBoolean("isPractice", false),
    )

    private fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else (0 until length()).map(::getJSONObject)

    private fun JSONObject.optStringOrNull(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null
}
