package com.jackwallner.time

import android.content.Intent

/** Release builds ignore every launch option, so nothing here can unlock Pro or seed data. */
object DebugLaunchOptions {
    fun apply(intent: Intent?, graph: AppGraph) = Unit

    fun onboardingPage(intent: Intent?): Int? = null

    fun paywallSnapshot(intent: Intent?): String? = null

    fun appearance(intent: Intent?): String? = null

    fun isScreenshot(intent: Intent?): Boolean = false
}
