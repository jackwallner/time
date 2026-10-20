package com.jackwallner.time.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.time.model.AlertPreferences
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Small preferences, with the iOS UserDefaults keys. Routines live in `RoutineStore`. */
class AppSettings(private val defaults: KeyValueStore) {
    /** Alerts are rebuilt whenever one of these changes. */
    var onAlertsChanged: () -> Unit = {}

    var hasCompletedSetup by mutableStateOf(defaults.getBoolean(SETUP))
        private set

    var startAlerts by mutableStateOf(defaults.getBoolean(START, true))
        private set
    var leaveAlerts by mutableStateOf(defaults.getBoolean(LEAVE, true))
        private set
    var stepNudges by mutableStateOf(defaults.getBoolean(NUDGES, true))
        private set

    val alertPreferences: AlertPreferences get() = AlertPreferences(startAlerts, leaveAlerts, stepNudges)

    fun completeSetup(value: Boolean = true) {
        hasCompletedSetup = value
        defaults.putBoolean(SETUP, value)
    }

    fun updateStartAlerts(value: Boolean) {
        startAlerts = value
        defaults.putBoolean(START, value)
        onAlertsChanged()
    }

    fun updateLeaveAlerts(value: Boolean) {
        leaveAlerts = value
        defaults.putBoolean(LEAVE, value)
        onAlertsChanged()
    }

    fun updateStepNudges(value: Boolean) {
        stepNudges = value
        defaults.putBoolean(NUDGES, value)
        onAlertsChanged()
    }

    private companion object {
        const val SETUP = "hasCompletedSetup"
        const val START = "alerts.start"
        const val LEAVE = "alerts.leave"
        const val NUDGES = "alerts.nudges"
    }
}

/**
 * When to ask for a rating: walking out on time, for the third time or more,
 * at most once per cooldown. On Play the card is called straight away, with no
 * question in front of it (Google's in-app review rules); feedback is its own
 * row in Settings.
 */
class ReviewPromptTracker(private val defaults: KeyValueStore, private val clock: () -> Instant = { Instant.now() }) {
    private var askedThisSession = false

    fun isEligible(onTimeCount: Int): Boolean {
        if (askedThisSession || onTimeCount < MINIMUM_ON_TIME_DEPARTURES) return false
        if (defaults.contains(LAST_ASKED)) {
            val last = Instant.ofEpochMilli(defaults.getLong(LAST_ASKED))
            if (ChronoUnit.DAYS.between(last, clock()) < COOLDOWN_DAYS) return false
        }
        return true
    }

    /** True when an on-time departure has earned the card; records the ask. */
    fun shouldAskAfterOnTimeDeparture(onTimeCount: Int): Boolean {
        if (!isEligible(onTimeCount)) return false
        askedThisSession = true
        defaults.putLong(LAST_ASKED, clock().toEpochMilli())
        return true
    }

    companion object {
        const val MINIMUM_ON_TIME_DEPARTURES = 3
        const val COOLDOWN_DAYS = 90L
        private const val LAST_ASKED = "reviewLastAskedAt"
    }
}

/**
 * On-device record of how someone met Shoes On Pro before they bought it. The
 * attribute keys and formats are fleet-wide and match iOS exactly; nothing
 * here may carry free text. Counts, dates, and short surface names only.
 */
class ConversionDiagnostics(private val defaults: KeyValueStore, private val clock: () -> Instant = { Instant.now() }) {
    fun surface(impressionID: String): String = impressionID.removePrefix(IMPRESSION_PREFIX)

    fun recordAppOpen() {
        if (!defaults.contains(INSTALLED_AT)) defaults.putLong(INSTALLED_AT, clock().toEpochMilli())
        defaults.putInt(APP_OPENS, defaults.getInt(APP_OPENS) + 1)
    }

    fun recordPitchView(impressionID: String) {
        val surface = surface(impressionID)
        defaults.putInt(TOTAL_VIEWS, defaults.getInt(TOTAL_VIEWS) + 1)
        defaults.putInt(views(surface), defaults.getInt(views(surface)) + 1)
        defaults.putString(LAST_SURFACE, surface)
        if (!defaults.contains(FIRST_SEEN)) {
            defaults.putLong(FIRST_SEEN, clock().toEpochMilli())
            defaults.putInt(OPENS_BEFORE_FIRST_PITCH, defaults.getInt(APP_OPENS))
            if (defaults.contains(INSTALLED_AT)) {
                defaults.putInt(DAYS_TO_FIRST_PITCH, daysSince(defaults.getLong(INSTALLED_AT)))
            }
        }
    }

    /** Only the first conversion is recorded: a renewal is not a new answer. */
    fun recordConversion(plan: String, startedTrial: Boolean, offeringID: String? = null) {
        if (defaults.contains(CONVERTED_ON)) return
        defaults.putString(CONVERTED_ON, defaults.getString(LAST_SURFACE) ?: "unknown")
        defaults.putInt(VIEWS_AT_CONVERT, defaults.getInt(TOTAL_VIEWS))
        defaults.putString(CONVERTED_PLAN, plan)
        defaults.putBoolean(CONVERTED_WITH_TRIAL, startedTrial)
        offeringID?.let { defaults.putString(CONVERTED_OFFERING, it) }
        defaults.putLong(CONVERTED_AT, clock().toEpochMilli())
        if (defaults.contains(FIRST_SEEN)) defaults.putInt(DAYS_TO_CONVERT, daysSince(defaults.getLong(FIRST_SEEN)))
    }

    /** Empty until the first pitch, so a customer never shown a paywall sends nothing. */
    val subscriberAttributes: Map<String, String>
        get() {
            val total = defaults.getInt(TOTAL_VIEWS)
            if (total <= 0) return emptyMap()
            val attributes = mutableMapOf("pitch_views_total" to total.toString())
            defaults.keys().filter { it.startsWith(VIEWS_PREFIX) && it != TOTAL_VIEWS }.forEach { key ->
                val count = defaults.getInt(key)
                if (count > 0) attributes["pitch_views_${key.removePrefix(VIEWS_PREFIX)}".take(40)] = count.toString()
            }
            defaults.getString(LAST_SURFACE)?.let { attributes["pitch_last"] = it }
            if (defaults.contains(FIRST_SEEN)) {
                val first = defaults.getLong(FIRST_SEEN)
                attributes["pitch_first_seen"] = Instant.ofEpochMilli(first).truncatedTo(ChronoUnit.SECONDS).toString()
                attributes["days_since_first_pitch"] = daysSince(first).toString()
            }
            if (defaults.contains(DAYS_TO_FIRST_PITCH)) attributes["days_since_install"] = defaults.getInt(DAYS_TO_FIRST_PITCH).toString()
            if (defaults.contains(OPENS_BEFORE_FIRST_PITCH)) {
                attributes["opens_before_first_pitch"] = defaults.getInt(OPENS_BEFORE_FIRST_PITCH).toString()
            }
            defaults.getString(CONVERTED_ON)?.let { on ->
                attributes["converted_surface"] = on
                if (defaults.contains(CONVERTED_AT)) {
                    attributes["converted_at"] = Instant.ofEpochMilli(defaults.getLong(CONVERTED_AT)).truncatedTo(ChronoUnit.SECONDS).toString()
                }
                attributes["pitch_views_at_convert"] = defaults.getInt(VIEWS_AT_CONVERT).toString()
                attributes["days_to_convert"] = defaults.getInt(DAYS_TO_CONVERT).toString()
                attributes["converted_plan"] = defaults.getString(CONVERTED_PLAN) ?: "unknown"
                attributes["converted_with_trial"] = if (defaults.getBoolean(CONVERTED_WITH_TRIAL)) "true" else "false"
                defaults.getString(CONVERTED_OFFERING)?.let { attributes["converted_offering"] = it }
            }
            return attributes
        }

    private fun daysSince(millis: Long): Int {
        val zone = ZoneId.systemDefault()
        val from = Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()
        return maxOf(0, ChronoUnit.DAYS.between(from, clock().atZone(zone).toLocalDate()).toInt())
    }

    private fun views(surface: String) = "$VIEWS_PREFIX$surface"

    private companion object {
        const val IMPRESSION_PREFIX = "shoeson_"
        const val VIEWS_PREFIX = "conv.pitchViews."
        const val TOTAL_VIEWS = "conv.pitchViews.total"
        const val FIRST_SEEN = "conv.pitchFirstSeen"
        const val LAST_SURFACE = "conv.pitchLastSurface"
        const val INSTALLED_AT = "conv.installedAt"
        const val APP_OPENS = "conv.appOpens"
        const val OPENS_BEFORE_FIRST_PITCH = "conv.opensBeforeFirstPitch"
        const val DAYS_TO_FIRST_PITCH = "conv.daysToFirstPitch"
        const val CONVERTED_ON = "conv.convertedOn"
        const val CONVERTED_AT = "conv.convertedAt"
        const val VIEWS_AT_CONVERT = "conv.viewsAtConvert"
        const val DAYS_TO_CONVERT = "conv.daysToConvert"
        const val CONVERTED_PLAN = "conv.convertedPlan"
        const val CONVERTED_WITH_TRIAL = "conv.convertedWithTrial"
        const val CONVERTED_OFFERING = "conv.convertedOffering"
    }
}
