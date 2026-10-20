package com.jackwallner.time.model

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil

object Format {
    /** Set by the app so times follow the device's 12/24-hour setting. */
    @Volatile var timeFormatter: DateTimeFormatter = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)

    @Volatile var zone: ZoneId = ZoneId.systemDefault()

    /** "8:15" or "8:15 AM" per the user's locale. */
    fun time(instant: Instant): String = timeFormatter.format(instant.atZone(zone))

    /** "45 min", "1 hr", "1 hr 8 min". */
    fun duration(minutes: Int): String {
        val hours = minutes / 60
        val rest = minutes % 60
        if (hours == 0) return "$rest min"
        if (rest == 0) return "$hours hr"
        return "$hours hr $rest min"
    }

    /** Whole minutes from seconds, rounded to nearest, at least 1 once started. */
    fun minutes(fromSeconds: Double): Int = maxOf(if (fromSeconds > 0) 1 else 0, roundHalfAway(fromSeconds / 60).toInt())

    /** "Today", "Tomorrow", or the weekday name. */
    fun day(date: LocalDate, now: Instant, locale: Locale = Locale.getDefault()): String {
        val today = now.day(zone)
        if (date == today) return "Today"
        if (date == today.plusDays(1)) return "Tomorrow"
        return date.dayOfWeek.getDisplayName(TextStyle.FULL, locale)
    }

    fun day(instant: Instant, now: Instant): String = day(instant.day(zone), now)

    /** "today", "tomorrow" or "Wednesday", for the middle of a sentence. */
    fun dayPhrase(date: LocalDate, now: Instant): String {
        val name = day(date, now)
        val today = now.day(zone)
        return if (date == today || date == today.plusDays(1)) name.lowercase() else name
    }

    /** "in 42 min", "in 3 hr 5 min", "now". */
    fun relative(to: Instant, now: Instant): String {
        val minutes = ceil(to.secondsSince(now) / 60).toInt()
        if (minutes <= 0) return "now"
        return "in ${duration(minutes)}"
    }

    /** "2 min early", "On time", "6 min late". */
    fun lateness(seconds: Double): String {
        if (seconds in -60.0..60.0) return "On time"
        val minutes = roundHalfAway(abs(seconds) / 60).toInt()
        return if (seconds < 0) "$minutes min early" else "$minutes min late"
    }

    /** "Weekdays", "Every day", "Weekends", or "Mon, Wed, Fri". */
    fun weekdays(days: Set<Int>, locale: Locale = Locale.getDefault()): String {
        if (days.size == 7) return "Every day"
        if (days == setOf(2, 3, 4, 5, 6)) return "Weekdays"
        if (days == setOf(1, 7)) return "Weekends"
        if (days.isEmpty()) return "No days set"
        return orderedWeekdays(locale).filter { it in days }.joinToString(", ") { shortWeekday(it, locale) }
    }

    /** Weekday numbers (1 = Sunday) in the locale's order, from its first weekday. */
    fun orderedWeekdays(locale: Locale = Locale.getDefault()): List<Int> {
        val first = WeekFields.of(locale).firstDayOfWeek.value % 7 + 1
        return (0 until 7).map { (first - 1 + it) % 7 + 1 }
    }

    fun shortWeekday(iosWeekday: Int, locale: Locale = Locale.getDefault()): String =
        dayOfWeek(iosWeekday).getDisplayName(TextStyle.SHORT, locale)

    fun narrowWeekday(iosWeekday: Int, locale: Locale = Locale.getDefault()): String =
        dayOfWeek(iosWeekday).getDisplayName(TextStyle.NARROW, locale)

    fun fullWeekday(iosWeekday: Int, locale: Locale = Locale.getDefault()): String =
        dayOfWeek(iosWeekday).getDisplayName(TextStyle.FULL, locale)

    private fun dayOfWeek(iosWeekday: Int) = java.time.DayOfWeek.of((iosWeekday + 5) % 7 + 1)

    /** "1.5×" style, trimmed. */
    fun multiplier(value: Double): String {
        val rounded = roundHalfAway(value * 10) / 10
        if (rounded == roundHalfAway(rounded)) return "${rounded.toInt()}×"
        return String.format(Locale.US, "%.1f×", rounded)
    }

    /** "50% longer than you guess" style. */
    fun paceSentence(pace: Double): String {
        val percent = roundHalfAway((pace - 1) * 100).toInt()
        if (abs(percent) < 5) return "about as long as you guess"
        if (percent > 0) return "$percent% longer than you guess"
        return "${-percent}% less than you guess"
    }

    /** "12:04" counting down, "1:36:57" past an hour, or "+3:10" once over. */
    fun clock(seconds: Double): String {
        val total = kotlin.math.floor(abs(seconds)).toLong()
        val text = if (total >= 3600) {
            String.format(Locale.US, "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        } else {
            String.format(Locale.US, "%d:%02d", total / 60, total % 60)
        }
        return if (seconds < 0) "+$text" else text
    }
}
