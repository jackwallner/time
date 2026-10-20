package com.jackwallner.time.model

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.UUID

/** iOS `Calendar` weekday numbers: 1 = Sunday through 7 = Saturday. */
fun LocalDate.iosWeekday(): Int = dayOfWeek.value % 7 + 1

fun Instant.day(zone: ZoneId): LocalDate = atZone(zone).toLocalDate()

fun LocalDate.startInstant(zone: ZoneId): Instant = atStartOfDay(zone).toInstant()

fun LocalDate.at(hour: Int, minute: Int, zone: ZoneId): Instant =
    ZonedDateTime.of(this, LocalTime.of(hour, minute), zone).toInstant()

fun Instant.plusSeconds(seconds: Double): Instant = plusMillis((seconds * 1000).toLong())

fun Instant.plusMinutes(minutes: Int): Instant = plusSeconds(minutes * 60L)

/** Seconds from `other` to this instant, like `Date.timeIntervalSince`. */
fun Instant.secondsSince(other: Instant): Double = (toEpochMilli() - other.toEpochMilli()) / 1000.0

/** Swift's `rounded()`: half away from zero. Kotlin's `round` is half-even. */
fun roundHalfAway(value: Double): Double = if (value < 0) -kotlin.math.floor(-value + 0.5) else kotlin.math.floor(value + 0.5)

/**
 * One thing that happens before leaving, with the user's own guess of how
 * long it takes. The guess is never overwritten: the gap between it and the
 * real time is the point of the app.
 */
data class RoutineStep(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    val guessMinutes: Int,
)

/** A one-off change to a single day: leave at another time, or not at all. */
data class DayChange(
    /** The changed day. */
    val day: LocalDate,
    /** Minutes after midnight to leave at, or null when the day is skipped. */
    val leaveMinuteOfDay: Int?,
) {
    val isSkip: Boolean get() = leaveMinuteOfDay == null
}

/**
 * A departure the user makes on a schedule: when they walk out the door, on
 * which days, and the steps that come before it.
 */
data class Routine(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    val leaveHour: Int,
    val leaveMinute: Int,
    /** iOS weekdays, 1 = Sunday through 7 = Saturday. */
    val weekdays: Set<Int>,
    val steps: List<RoutineStep>,
    /** One-off changes to single days, at most one per day. */
    val changes: List<DayChange> = emptyList(),
) {
    val guessTotalMinutes: Int get() = steps.sumOf { it.guessMinutes }

    fun change(on: LocalDate): DayChange? = changes.firstOrNull { it.day == on }

    /**
     * Whether there is a departure on this day: a scheduled weekday that was
     * not skipped, or any day given a one-off time.
     */
    fun departs(on: LocalDate): Boolean {
        change(on)?.let { return !it.isSkip }
        return on.iosWeekday() in weekdays
    }

    /** The usual leave time on the day, ignoring any one-off change. */
    fun usualLeaveTime(on: LocalDate, zone: ZoneId): Instant = on.at(leaveHour, leaveMinute, zone)

    /** The leave time on the day with any one-off time for that day applied. */
    fun leaveTime(on: LocalDate, zone: ZoneId): Instant {
        val override = change(on)?.leaveMinuteOfDay ?: return on.at(leaveHour, leaveMinute, zone)
        return on.at(override / 60, override % 60, zone)
    }

    /** The next departure strictly after `now`, honouring skips and one-offs. */
    fun nextScheduledLeave(after: Instant, zone: ZoneId): Instant? {
        val today = after.day(zone)
        for (offset in 0L..14L) {
            val day = today.plusDays(offset)
            if (!departs(day)) continue
            val leave = leaveTime(day, zone)
            if (leave > after) return leave
        }
        return null
    }

    /**
     * The leave time a run started now aims for: today's if it is still
     * ahead, otherwise tomorrow's. Weekdays are ignored so the routine can be
     * run on any day by hand.
     */
    fun leaveTimeForRunStarted(at: Instant, zone: ZoneId): Instant {
        val today = leaveTime(at.day(zone), zone)
        if (today > at) return today
        return leaveTime(at.day(zone).plusDays(1), zone)
    }

    /**
     * Replaces any change on that day. A time equal to the usual one on a
     * scheduled day is no change at all, so it is dropped.
     */
    fun settingChange(change: DayChange?, on: LocalDate): Routine {
        val kept = changes.filter { it.day != on }
        if (change == null) return copy(changes = kept)
        val usual = leaveHour * 60 + leaveMinute
        val scheduled = on.iosWeekday() in weekdays
        if (scheduled && change.leaveMinuteOfDay == usual) return copy(changes = kept)
        if (!scheduled && change.isSkip) return copy(changes = kept)
        return copy(changes = (kept + change.copy(day = on)).sortedBy { it.day })
    }

    /** Forgets changes for days already gone. */
    fun pruningChanges(before: Instant, zone: ZoneId): Routine {
        val today = before.day(zone)
        return copy(changes = changes.filter { it.day >= today })
    }

    /** Changes from today on, soonest first. */
    fun upcomingChanges(from: Instant, zone: ZoneId): List<DayChange> {
        val today = from.day(zone)
        return changes.filter { it.day >= today }.sortedBy { it.day }
    }
}

/** How long a step really took, captured when the user taps Done. */
data class StepRecord(
    val stepID: UUID,
    val routineID: UUID,
    val guessMinutes: Int,
    val actualSeconds: Double,
    val date: Instant,
) {
    val ratio: Double get() = if (guessMinutes <= 0) 1.0 else actualSeconds / (guessMinutes * 60).toDouble()
}

/** One finished run: when the user actually walked out, against when they meant to. */
data class DepartureRecord(
    val id: UUID = UUID.randomUUID(),
    val routineID: UUID,
    val target: Instant,
    val left: Instant,
    /** Seconds between the get-ready alert and the start, when the run answered one. */
    val startDelaySeconds: Double?,
) {
    /** Positive when late, negative when early. */
    val lateSeconds: Double get() = left.secondsSince(target)

    /** A minute of grace, so leaving at 8:15:40 for 8:15 still counts. */
    val wasOnTime: Boolean get() = lateSeconds <= 60
}

/**
 * The answer to "when you plan 30 minutes to get ready, it usually takes...".
 * It seeds the pace multiplier until real runs replace it. Raw values match
 * iOS, so stored answers keep their names.
 */
enum class PaceAnswer(val raw: String, val multiplier: Double, val title: String, val detail: String) {
    AHEAD("ahead", 0.85, "About 25 minutes", "I'm usually ready early"),
    ON_THE_DOT("onTheDot", 1.0, "About 30 minutes", "My guesses hold up"),
    QUARTER_OVER("quarterOver", 1.25, "35 to 40 minutes", "I run a little behind"),
    HALF_OVER("halfOver", 1.5, "About 45 minutes", "I'm often 15 minutes late"),
    DOUBLE_OVER("doubleOver", 2.0, "An hour or more", "Everything takes twice as long");

    companion object {
        fun fromRaw(raw: String?): PaceAnswer? = entries.firstOrNull { it.raw == raw }
    }
}
