package com.jackwallner.time.model

import java.time.Instant

/** The next departure, for the widget. */
data class NextDepartureSnapshot(val routineName: String, val alertAt: Instant, val leaveAt: Instant)

/** The run in progress, as far as the widget needs it. */
data class WidgetRun(val routineName: String, val leaveAt: Instant, val stepName: String?, val isLeaving: Boolean)

/**
 * What the next-start widget draws at one moment, from iOS
 * `NextDepartureWidget`'s `Phase`. Within the hour before the start it is a
 * live countdown, because "7:32" means little to someone who cannot feel time
 * passing and "11:48" going down means a lot.
 */
sealed interface WidgetPhase {
    data class Running(val run: WidgetRun) : WidgetPhase
    data class Later(val next: NextDepartureSnapshot) : WidgetPhase
    data class Countdown(val next: NextDepartureSnapshot) : WidgetPhase
    data class Overdue(val next: NextDepartureSnapshot) : WidgetPhase
    data object None : WidgetPhase

    val routineName: String?
        get() = when (this) {
            is Running -> run.routineName
            is Later -> next.routineName
            is Countdown -> next.routineName
            is Overdue -> next.routineName
            None -> null
        }

    val isUrgent: Boolean get() = this is Overdue

    val smallLabel: String
        get() = when (this) {
            is Running -> "Now"
            is Later -> "Start at"
            is Countdown -> "Start in"
            is Overdue -> "Late to start"
            None -> "Next start"
        }

    /** The big line; a countdown draws its own live clock instead. */
    val headline: String
        get() = when (this) {
            is Running -> if (run.isLeaving) "Head out" else run.stepName ?: "Getting ready"
            is Later -> Format.time(next.alertAt)
            is Countdown -> Format.time(next.alertAt)
            is Overdue -> "Start now"
            None -> "None"
        }

    fun footer(now: Instant): String = when (this) {
        is Running -> "Out the door ${Format.time(run.leaveAt)}"
        is Later -> leaveLine(next, now)
        is Countdown -> leaveLine(next, now)
        is Overdue -> leaveLine(next, now)
        None -> "Set one in the app"
    }

    companion object {
        /** The countdown shows from this long before the start. */
        const val COUNTDOWN_WINDOW_SECONDS = 3600L

        /** A run stays on the widget until this long after its leave time. */
        const val RUN_GRACE_SECONDS = 30 * 60L

        fun at(now: Instant, departures: List<NextDepartureSnapshot>, run: WidgetRun?): WidgetPhase {
            if (run != null && now < run.leaveAt.plusSeconds(RUN_GRACE_SECONDS)) return Running(run)
            val next = departures.firstOrNull { it.leaveAt > now } ?: return None
            return when {
                next.alertAt <= now -> Overdue(next)
                next.alertAt.secondsSince(now) <= COUNTDOWN_WINDOW_SECONDS.toDouble() -> Countdown(next)
                else -> Later(next)
            }
        }

        /**
         * When the drawing can next change on its own, so the widget redraws
         * then. Midnight too, when "Tomorrow, out 8:15" becomes today's.
         */
        fun nextChange(now: Instant, departures: List<NextDepartureSnapshot>, run: WidgetRun?): Instant {
            val midnight = now.day(Format.zone).plusDays(1).atStartOfDay(Format.zone).toInstant()
            val moments = departures.flatMap {
                listOf(it.alertAt.minusSeconds(COUNTDOWN_WINDOW_SECONDS), it.alertAt, it.leaveAt)
            } + listOfNotNull(run?.leaveAt?.plusSeconds(RUN_GRACE_SECONDS)) + midnight
            return moments.filter { it > now }.min()
        }

        private fun leaveLine(next: NextDepartureSnapshot, now: Instant): String =
            if (next.leaveAt.day(Format.zone) == now.day(Format.zone)) {
                "Out the door ${Format.time(next.leaveAt)}"
            } else {
                "${Format.day(next.leaveAt, now)}, out ${Format.time(next.leaveAt)}"
            }
    }
}
