package com.jackwallner.time

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.lifecycle.lifecycleScope
import com.jackwallner.time.data.AlertScheduler
import com.jackwallner.time.ui.RootScreen
import com.jackwallner.time.ui.theme.ShoesOnTheme
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val graph by lazy { AppGraph.get(this) }
    private var launchIntent by mutableStateOf<Intent?>(null)

    @OptIn(ExperimentalComposeUiApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (savedInstanceState == null) DebugLaunchOptions.apply(intent, graph)
        launchIntent = intent
        if (savedInstanceState == null) handle(intent)
        lifecycleScope.launch { graph.purchases.start() }
        setContent {
            val forced = DebugLaunchOptions.appearance(launchIntent)
            val dark = when (forced) {
                "dark" -> true
                "light" -> false
                else -> isSystemInDarkTheme()
            }
            ShoesOnTheme(dark = dark) {
                RootScreen(graph, launchIntent, Modifier.semantics { testTagsAsResourceId = true })
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        // Plans move as timings arrive and days pass, so the rolling alert
        // window is rebuilt whenever the app is seen.
        graph.refreshFormats()
        graph.store.refresh(AppClock.now())
        graph.foregroundCount++
    }

    /** Alert taps, alert buttons and the launcher shortcut. */
    private fun handle(intent: Intent?) {
        when (intent?.action) {
            AlertScheduler.ACTION_START_FROM_ALERT -> {
                intent.getStringExtra(AlertScheduler.EXTRA_ALERT_ID)?.let {
                    androidx.core.app.NotificationManagerCompat.from(this).cancel(it, 0)
                }
                val routineID = intent.getStringExtra(AlertScheduler.EXTRA_ROUTINE)?.let(UUID::fromString)
                val leaveAt = intent.getLongExtra(AlertScheduler.EXTRA_LEAVE_AT, 0L)
                if (routineID != null && leaveAt > 0) {
                    graph.store.startRunFromAlert(routineID, Instant.ofEpochMilli(leaveAt), AppClock.now())
                } else {
                    graph.store.startNextRun(AppClock.now())
                }
            }
            AlertScheduler.ACTION_START -> if (graph.settings.hasCompletedSetup) graph.store.startNextRun(AppClock.now())
        }
    }
}
