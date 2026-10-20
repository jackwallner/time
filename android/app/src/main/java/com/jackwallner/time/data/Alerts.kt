package com.jackwallner.time.data

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.jackwallner.time.AppGraph
import com.jackwallner.time.MainActivity
import com.jackwallner.time.R
import com.jackwallner.time.model.ActiveRun
import com.jackwallner.time.model.DayChange
import com.jackwallner.time.model.Format
import com.jackwallner.time.model.PlannedAlert
import com.jackwallner.time.model.day
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * Owns every pending alert. Each reschedule replaces the whole set with what
 * `NotificationPlan` says should exist right now, so a stale alert can never
 * outlive the plan that made it. AlarmManager stands in for iOS's pending
 * notification requests; the alert itself is posted when the alarm fires.
 */
object AlertScheduler {
    const val CHANNEL_ALERTS = "alerts"
    const val CHANNEL_STEPS = "steps"
    const val CHANNEL_RUN = "run"
    const val CHANNEL_TRIAL = "trial"
    const val RUN_NOTIFICATION_ID = 1

    const val EXTRA_ALERT_ID = "alertId"
    const val EXTRA_KIND = "kind"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_ROUTINE = "routineID"
    const val EXTRA_LEAVE_AT = "leaveAt"

    const val ACTION_FIRE = "com.jackwallner.time.ALERT"
    const val ACTION_DONE = "com.jackwallner.time.DONE"
    const val ACTION_SKIP_DAY = "com.jackwallner.time.SKIP_DAY"
    const val ACTION_START = "com.jackwallner.time.START_RUN"
    const val ACTION_START_FROM_ALERT = "com.jackwallner.time.START_FROM_ALERT"

    private const val SCHEDULED_KEY = "alerts.scheduledIds"

    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannels(listOf(
            NotificationChannel(CHANNEL_ALERTS, "Get ready and leave", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Time to get ready, leave in 10 minutes, and time to go."
            },
            NotificationChannel(CHANNEL_STEPS, "Step nudges", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Wrap up a step, and a nudge when one runs over."
            },
            NotificationChannel(CHANNEL_RUN, "Routine in progress", NotificationManager.IMPORTANCE_LOW).apply {
                description = "The step you're on and its Done button, while a routine runs."
                setShowBadge(false)
            },
            NotificationChannel(CHANNEL_TRIAL, "Free trial", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "A reminder before your free trial ends."
            },
        ))
    }

    fun canPostNotifications(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun notificationsEnabled(context: Context): Boolean =
        canPostNotifications(context) && NotificationManagerCompat.from(context).areNotificationsEnabled()

    fun canScheduleExact(context: Context): Boolean =
        Build.VERSION.SDK_INT < 31 || context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()

    fun reschedule(context: Context, alerts: List<PlannedAlert>) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val defaults = SharedPreferencesStore(context)
        val wanted = alerts.associateBy { it.id }
        for (id in defaults.getStringSet(SCHEDULED_KEY) - wanted.keys) {
            alarms.cancel(fireIntent(context, id, null))
        }
        val exact = canScheduleExact(context)
        for (alert in alerts) {
            val intent = fireIntent(context, alert.id, alert)
            val at = alert.fireAt.toEpochMilli()
            if (exact && runCatching { alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent) }.isSuccess) {
                continue
            } else {
                // Without the exact-alarm grant the system may batch alarms;
                // a one-minute window keeps the start time honest.
                alarms.setWindow(AlarmManager.RTC_WAKEUP, at, 60_000, intent)
            }
        }
        defaults.putStringSet(SCHEDULED_KEY, wanted.keys)
    }

    private fun fireIntent(context: Context, id: String, alert: PlannedAlert?): PendingIntent {
        val intent = Intent(context, AlertReceiver::class.java).setAction("$ACTION_FIRE.$id")
        if (alert != null) {
            intent.putExtra(EXTRA_ALERT_ID, alert.id)
                .putExtra(EXTRA_KIND, alert.kind.name)
                .putExtra(EXTRA_TITLE, alert.title)
                .putExtra(EXTRA_BODY, alert.body)
            alert.routineID?.let { intent.putExtra(EXTRA_ROUTINE, it.toString()) }
            alert.leaveAt?.let { intent.putExtra(EXTRA_LEAVE_AT, it.toEpochMilli()) }
        }
        return PendingIntent.getBroadcast(context, id.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    /** Posts an alert whose alarm fired. */
    fun post(context: Context, intent: Intent) {
        if (!canPostNotifications(context)) return
        val id = intent.getStringExtra(EXTRA_ALERT_ID) ?: return
        val kind = runCatching { PlannedAlert.Kind.valueOf(intent.getStringExtra(EXTRA_KIND).orEmpty()) }.getOrNull() ?: return
        val routineID = intent.getStringExtra(EXTRA_ROUTINE)
        val leaveAt = intent.getLongExtra(EXTRA_LEAVE_AT, 0L)
        val isStep = kind == PlannedAlert.Kind.WRAP_UP || kind == PlannedAlert.Kind.OVERRUN
        val builder = NotificationCompat.Builder(context, if (isStep) CHANNEL_STEPS else CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(intent.getStringExtra(EXTRA_TITLE))
            .setContentText(intent.getStringExtra(EXTRA_BODY))
            .setStyle(NotificationCompat.BigTextStyle().bigText(intent.getStringExtra(EXTRA_BODY)))
            .setCategory(if (isStep) NotificationCompat.CATEGORY_REMINDER else NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
        val tag = id
        when (kind) {
            PlannedAlert.Kind.GET_READY, PlannedAlert.Kind.START_NUDGE -> {
                // Opening "Time to get ready" means getting ready: straight to
                // the first step instead of a home screen with a button.
                val start = activityIntent(context, ACTION_START_FROM_ALERT, routineID, leaveAt, id)
                builder.setContentIntent(start)
                builder.addAction(0, "Start now", start)
                if (routineID != null && leaveAt > 0) {
                    builder.addAction(0, "Skip this time", actionIntent(context, ACTION_SKIP_DAY, routineID, leaveAt, id))
                }
            }
            PlannedAlert.Kind.WRAP_UP, PlannedAlert.Kind.OVERRUN -> {
                builder.setContentIntent(openApp(context))
                builder.addAction(0, "Done, next step", actionIntent(context, ACTION_DONE, null, 0, id))
            }
            else -> builder.setContentIntent(openApp(context))
        }
        runCatching { NotificationManagerCompat.from(context).notify(tag, 0, builder.build()) }
    }

    fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
        context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun activityIntent(context: Context, action: String, routineID: String?, leaveAt: Long, tag: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).setAction(action)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(EXTRA_ALERT_ID, tag)
        routineID?.let { intent.putExtra(EXTRA_ROUTINE, it) }
        if (leaveAt > 0) intent.putExtra(EXTRA_LEAVE_AT, leaveAt)
        return PendingIntent.getActivity(context, tag.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun actionIntent(context: Context, action: String, routineID: String?, leaveAt: Long, tag: String): PendingIntent {
        val intent = Intent(context, AlertActionReceiver::class.java).setAction(action).putExtra(EXTRA_ALERT_ID, tag)
        routineID?.let { intent.putExtra(EXTRA_ROUTINE, it) }
        if (leaveAt > 0) intent.putExtra(EXTRA_LEAVE_AT, leaveAt)
        return PendingIntent.getBroadcast(context, (action + tag).hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    /**
     * The Android stand-in for the iOS Live Activity: an ongoing notification
     * with the step, a countdown to its planned end, and a Done button.
     */
    fun syncRunNotification(context: Context, run: ActiveRun?) {
        val manager = NotificationManagerCompat.from(context)
        if (run == null || !canPostNotifications(context)) {
            manager.cancel(RUN_NOTIFICATION_ID)
            return
        }
        val leave = if (run.isPractice) "Practice run, ready by ${Format.time(run.leaveAt)}" else "Out the door ${Format.time(run.leaveAt)}"
        val builder = NotificationCompat.Builder(context, CHANNEL_RUN)
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openApp(context))
        val step = run.currentStep
        if (step == null) {
            builder.setContentTitle("Shoes on. Time to go.").setContentText(leave)
            builder.setWhen(run.leaveAt.toEpochMilli()).setUsesChronometer(true).setChronometerCountDown(true)
            builder.addAction(0, "I'm out the door", actionIntent(context, ACTION_DONE, null, 0, "run.leave"))
        } else {
            builder.setContentTitle(step.name)
                .setContentText("Step ${run.planStepNumber} of ${run.planStepCount} · $leave")
                .setSubText(run.routineName)
                .setWhen(run.stepEndsAt.toEpochMilli())
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
                .setProgress(run.planStepCount, run.planStepNumber - 1, false)
            builder.addAction(0, "Done", actionIntent(context, ACTION_DONE, null, 0, "run.done"))
        }
        runCatching { manager.notify(RUN_NOTIFICATION_ID, builder.build()) }
    }
}

/** An alarm fired: post its alert. */
class AlertReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AlertScheduler.post(context, intent)
    }
}

/** Notification buttons that act without opening the app: Done, and Skip this time. */
class AlertActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val graph = AppGraph.get(context)
        val store = graph.store
        val tag = intent.getStringExtra(AlertScheduler.EXTRA_ALERT_ID).orEmpty()
        if (!tag.startsWith("run.")) NotificationManagerCompat.from(context).cancel(tag, 0)
        when (intent.action) {
            AlertScheduler.ACTION_DONE -> {
                val run = store.activeRun ?: return
                if (tag == "run.leave") {
                    if (run.isLeaving) store.finishRun()
                } else {
                    store.completeStep()
                }
            }
            AlertScheduler.ACTION_SKIP_DAY -> {
                val routineID = intent.getStringExtra(AlertScheduler.EXTRA_ROUTINE)?.let(UUID::fromString) ?: return
                val leaveAt = Instant.ofEpochMilli(intent.getLongExtra(AlertScheduler.EXTRA_LEAVE_AT, 0))
                val day = leaveAt.day(ZoneId.systemDefault())
                store.setChange(DayChange(day, null), day, routineID)
            }
        }
    }
}

/** Alarms do not survive a reboot or a clock change; rebuild them. */
class RescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AppGraph.get(context).propagate()
    }
}

/** The reminder the trial page promises: two days before the trial ends. */
object TrialReminder {
    private const val ID = "trial.reminder"

    fun schedule(context: Context, trialDays: Int, billed: String, now: Instant = Instant.now()) {
        val days = maxOf(trialDays - 2, 1)
        val alert = PlannedAlert(
            id = ID,
            kind = PlannedAlert.Kind.LEAVE_SOON,
            fireAt = now.plusSeconds(days * 86_400L),
            title = "Your free trial ends in 2 days",
            body = "Shoes On Pro renews at $billed unless you cancel in Google Play before then.",
        )
        val intent = Intent(context, TrialReceiver::class.java).setAction("$ID.fire")
            .putExtra(AlertScheduler.EXTRA_TITLE, alert.title)
            .putExtra(AlertScheduler.EXTRA_BODY, alert.body)
        val pending = PendingIntent.getBroadcast(context, ID.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        context.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alert.fireAt.toEpochMilli(), pending)
    }
}

class TrialReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!AlertScheduler.canPostNotifications(context)) return
        val notification = NotificationCompat.Builder(context, AlertScheduler.CHANNEL_TRIAL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(intent.getStringExtra(AlertScheduler.EXTRA_TITLE))
            .setContentText(intent.getStringExtra(AlertScheduler.EXTRA_BODY))
            .setStyle(NotificationCompat.BigTextStyle().bigText(intent.getStringExtra(AlertScheduler.EXTRA_BODY)))
            .setContentIntent(AlertScheduler.openApp(context))
            .setAutoCancel(true)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify("trial", 0, notification) }
    }
}
