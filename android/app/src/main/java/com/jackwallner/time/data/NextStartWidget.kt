package com.jackwallner.time.data

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import com.jackwallner.time.AppClock
import com.jackwallner.time.AppGraph
import com.jackwallner.time.R
import com.jackwallner.time.model.WidgetPhase
import java.time.Instant

/**
 * The next start time on the Home Screen, from iOS `NextDepartureWidget`.
 * Free, like the iPhone widget. A countdown in the last hour, drawn by the
 * launcher's own chronometer so it ticks without waking the app.
 */
class NextStartWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        NextStartWidgets.refresh(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == NextStartWidgets.ACTION_TICK) NextStartWidgets.refresh(context)
    }

    override fun onDisabled(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(NextStartWidgets.tick(context))
    }
}

object NextStartWidgets {
    const val ACTION_TICK = "com.jackwallner.time.WIDGET_TICK"

    /** Redraws every placed widget and books the next redraw. Called from `propagate()`. */
    fun refresh(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, NextStartWidget::class.java))
        val alarms = context.getSystemService(AlarmManager::class.java)
        if (ids.isEmpty()) {
            alarms.cancel(tick(context))
            return
        }
        val store = AppGraph.get(context).store
        val now = AppClock.now()
        val departures = store.widgetDepartures(now)
        val run = store.widgetRun
        runCatching { manager.updateAppWidget(ids, views(context, WidgetPhase.at(now, departures, run), now)) }
        // Not a wakeup: a widget nobody can see can wait for the screen.
        val next = WidgetPhase.nextChange(now, departures, run)
        alarms.set(AlarmManager.RTC, next.toEpochMilli() - AppClock.offsetMillis, tick(context))
    }

    fun tick(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 0, Intent(context, NextStartWidget::class.java).setAction(ACTION_TICK),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    internal fun views(context: Context, phase: WidgetPhase, now: Instant): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_next_start)
        views.setTextViewText(R.id.widget_routine, phase.routineName ?: "Shoes On")
        views.setTextViewText(R.id.widget_label, phase.smallLabel)
        views.setTextViewText(R.id.widget_footer, phase.footer(now))

        val countdown = phase as? WidgetPhase.Countdown
        val headline = if (phase.isUrgent) R.id.widget_headline_urgent else R.id.widget_headline
        for (id in listOf(R.id.widget_headline, R.id.widget_headline_urgent, R.id.widget_clock)) {
            views.setViewVisibility(id, View.GONE)
        }
        if (countdown != null) {
            val base = SystemClock.elapsedRealtime() + (countdown.next.alertAt.toEpochMilli() - now.toEpochMilli())
            views.setChronometer(R.id.widget_clock, base, null, true)
            views.setChronometerCountDown(R.id.widget_clock, true)
            views.setViewVisibility(R.id.widget_clock, View.VISIBLE)
        } else {
            views.setChronometer(R.id.widget_clock, SystemClock.elapsedRealtime(), null, false)
            views.setTextViewText(headline, phase.headline)
            views.setViewVisibility(headline, View.VISIBLE)
        }
        views.setOnClickPendingIntent(R.id.widget_root, AlertScheduler.openApp(context))
        return views
    }
}
