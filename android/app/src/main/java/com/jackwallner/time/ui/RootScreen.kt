package com.jackwallner.time.ui

import android.app.Activity
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.jackwallner.time.AppGraph
import com.jackwallner.time.DebugLaunchOptions
import com.jackwallner.time.model.Routine
import com.jackwallner.time.ui.screens.DayChangeSheet
import com.jackwallner.time.ui.screens.HomeScreen
import com.jackwallner.time.ui.screens.OnboardingScreen
import com.jackwallner.time.ui.screens.PaywallScreen
import com.jackwallner.time.ui.screens.RoutineEditorScreen
import com.jackwallner.time.ui.screens.RunCover
import com.jackwallner.time.ui.screens.SettingsScreen
import com.jackwallner.time.ui.theme.LocalPalette
import java.time.LocalDate

/** What sits over Home, one at a time, like the iOS sheets. */
sealed interface Overlay {
    data object Settings : Overlay
    data class Paywall(val surface: String) : Overlay
    data class Editor(val routine: Routine, val isNew: Boolean) : Overlay
    data class DayChange(val routine: Routine, val day: LocalDate) : Overlay
}

@Composable
fun RootScreen(graph: AppGraph, launchIntent: Intent?, modifier: Modifier = Modifier) {
    val settings = graph.settings
    val store = graph.store
    val purchases = graph.purchases
    val palette = LocalPalette.current
    // The routine is saved before the Pro offer, so a saved routine with
    // setup unfinished means they left on the offer: pick up there.
    val resumesAtOffer = remember { !settings.hasCompletedSetup && store.routines.isNotEmpty() }
    val paywallSnapshot = remember(launchIntent) { DebugLaunchOptions.paywallSnapshot(launchIntent) }
    val onboardingPage = remember(launchIntent) { DebugLaunchOptions.onboardingPage(launchIntent) }
    val view = LocalView.current
    // Light icons over the always-dark run and in dark mode; dark icons on paper.
    val darkBars = palette.isDark || (settings.hasCompletedSetup && store.activeRun != null)
    SideEffect {
        val window = (view.context as? Activity)?.window ?: return@SideEffect
        WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = !darkBars
            isAppearanceLightNavigationBars = !darkBars
        }
    }

    Box(modifier.fillMaxSize().background(palette.background)) {
        when {
            paywallSnapshot != null -> PaywallScreen(graph, "shoeson_snapshot", initialMonthly = paywallSnapshot == "monthly", onClose = {})
            onboardingPage != null && !settings.hasCompletedSetup -> OnboardingScreen(graph, startPage = onboardingPage)
            !settings.hasCompletedSetup -> OnboardingScreen(graph, startPage = if (resumesAtOffer) OnboardingPages.COUNT - 1 else 0, resumingOffer = resumesAtOffer)
            else -> HomeWithOverlays(graph)
        }
    }
}

object OnboardingPages {
    const val COUNT = 6
}

@Composable
private fun HomeWithOverlays(graph: AppGraph) {
    val store = graph.store
    var overlay by remember { mutableStateOf<Overlay?>(null) }
    val runPresent = store.activeRun != null || store.state.lastFinished != null

    // A run can begin from a notification or the launcher while a sheet is
    // open here; the run then needs the whole screen.
    LaunchedEffect(store.activeRun != null) { if (store.activeRun != null) overlay = null }

    Box(Modifier.fillMaxSize()) {
        HomeScreen(graph, onOverlay = { overlay = it })
        when (val current = overlay) {
            Overlay.Settings -> SettingsScreen(graph, onOverlay = { overlay = it }, onClose = { overlay = null })
            is Overlay.Paywall -> PaywallScreen(graph, current.surface, onClose = { overlay = null })
            is Overlay.Editor -> RoutineEditorScreen(graph, current.routine, current.isNew, onClose = { overlay = null })
            is Overlay.DayChange -> DayChangeSheet(graph, current.routine, current.day, onClose = { overlay = null })
            null -> Unit
        }
        if (overlay != null && overlay !is Overlay.DayChange) BackHandler { overlay = null }
        // The run is a cover over Home that slides up like the session it is.
        AnimatedVisibility(
            visible = runPresent,
            enter = slideInVertically(tween(420)) { it } + fadeIn(tween(200)),
            exit = slideOutVertically(tween(380)) { it } + fadeOut(tween(300)),
        ) {
            RunCover(graph)
        }
    }
}
