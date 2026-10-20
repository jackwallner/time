package com.jackwallner.time.ui.screens

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent

/** Static URLs shared by onboarding, Settings and the paywall. */
object Links {
    const val PRIVACY = "https://jackwallner.github.io/time/privacy-policy.html"
    const val TERMS = "https://jackwallner.github.io/time/terms.html"
    const val SUPPORT = "https://jackwallner.github.io/time/support.html"
    const val PLAY_LISTING = "https://play.google.com/store/apps/details?id=com.jackwallner.time"
    const val FEEDBACK = "mailto:jackwallner@gmail.com?subject=Shoes%20On%20(Android)"

    fun open(context: Context, url: String) {
        val uri = Uri.parse(url)
        try {
            if (uri.scheme == "https") {
                CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, uri)
            } else {
                context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        } catch (_: ActivityNotFoundException) {
            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
    }

    /** The Play listing in the Play Store app when it is there, else the web. */
    fun openPlayListing(context: Context) {
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.jackwallner.time")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(market)
        } catch (_: ActivityNotFoundException) {
            open(context, PLAY_LISTING)
        }
    }

    fun openNotificationSettings(context: Context) {
        val intent = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
    }

    fun openExactAlarmSettings(context: Context) {
        if (android.os.Build.VERSION.SDK_INT < 31) return
        val intent = Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
    }
}
