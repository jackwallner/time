package com.jackwallner.time

import android.content.Context
import android.text.format.DateFormat
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.time.data.AlertScheduler
import com.jackwallner.time.data.AppSettings
import com.jackwallner.time.data.ConversionDiagnostics
import com.jackwallner.time.data.DiskStateFile
import com.jackwallner.time.data.ReviewPromptTracker
import com.jackwallner.time.data.RoutineStore
import com.jackwallner.time.data.SharedPreferencesStore
import com.jackwallner.time.data.StoreService
import com.jackwallner.time.model.Format
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** The app's notion of now. Real time in release; debug screenshots may shift it. */
object AppClock {
    @Volatile var offsetMillis: Long = 0

    /** How often the run screen's clock ticks. Tests on slow emulators stretch it so Compose can idle. */
    @Volatile var runTickMillis: Long = 1_000

    fun now(): Instant = Instant.now().plusMillis(offsetMillis)
}

/** Builds every shared object once per process. */
class AppGraph private constructor(private val context: Context) {
    val defaults = SharedPreferencesStore(context)
    val settings = AppSettings(defaults)
    val diagnostics = ConversionDiagnostics(defaults)
    val reviewTracker = ReviewPromptTracker(defaults)
    val store = RoutineStore(
        file = DiskStateFile(File(context.filesDir, "shoeson-state.json")),
        zone = { ZoneId.systemDefault() },
        clock = AppClock::now,
        startAlertsEnabled = { settings.startAlerts },
    )
    val purchases = StoreService(context, defaults, diagnostics)

    /** Bumped on every foreground, so screens re-read system permissions on return from Settings. */
    var foregroundCount by mutableIntStateOf(0)

    init {
        AlertScheduler.createChannels(context)
        refreshFormats()
        store.onChange = { propagate() }
        settings.onAlertsChanged = { propagate() }
        purchases.onProChanged = { propagate() }
    }

    /** Times follow the device's 12/24-hour switch, re-read on every foreground. */
    fun refreshFormats() {
        Format.zone = ZoneId.systemDefault()
        Format.timeFormatter = DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(java.util.Locale.getDefault(), if (DateFormat.is24HourFormat(context)) "Hm" else "hm"))
    }

    /** Pushes the current state to every surface that shows it. */
    fun propagate() {
        AlertScheduler.reschedule(context, store.alerts(settings.alertPreferences, AppClock.now()))
        AlertScheduler.syncRunNotification(context, store.activeRun)
    }

    companion object {
        @Volatile private var instance: AppGraph? = null

        fun get(context: Context): AppGraph =
            instance ?: synchronized(this) { instance ?: AppGraph(context.applicationContext).also { instance = it } }
    }
}
