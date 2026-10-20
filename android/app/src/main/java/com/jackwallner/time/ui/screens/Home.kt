package com.jackwallner.time.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.jackwallner.time.AppClock
import com.jackwallner.time.AppGraph
import com.jackwallner.time.data.AlertScheduler
import com.jackwallner.time.model.Calibration
import com.jackwallner.time.model.DayChange
import com.jackwallner.time.model.DeparturePlan
import com.jackwallner.time.model.DepartureRecord
import com.jackwallner.time.model.Format
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import com.jackwallner.time.model.day
import com.jackwallner.time.model.secondsSince
import com.jackwallner.time.ui.Overlay
import com.jackwallner.time.ui.theme.Card
import com.jackwallner.time.ui.theme.Divider
import com.jackwallner.time.ui.theme.GapBars
import com.jackwallner.time.ui.theme.LocalPalette
import com.jackwallner.time.ui.theme.Palette
import com.jackwallner.time.ui.theme.PlanTimeline
import com.jackwallner.time.ui.theme.PrimaryButton
import com.jackwallner.time.ui.theme.SectionLabel
import com.jackwallner.time.ui.theme.TextAction
import com.jackwallner.time.ui.theme.Type
import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.ceil
import kotlinx.coroutines.delay

/** The app clock, re-read on a period. Ticks stop when the screen leaves composition. */
@Composable
fun rememberNow(periodMillis: Long): Instant {
    val now by produceState(AppClock.now(), periodMillis) {
        while (true) {
            value = AppClock.now()
            val wait = periodMillis - (System.currentTimeMillis() % periodMillis)
            delay(wait.coerceAtLeast(50))
        }
    }
    return now
}

/** The next departure, the real plan behind it, and how recent mornings went. */
@Composable
fun HomeScreen(graph: AppGraph, onOverlay: (Overlay) -> Unit) {
    val palette = LocalPalette.current
    val store = graph.store
    val purchases = graph.purchases

    fun newRoutine() {
        if (store.routines.isNotEmpty() && !purchases.isPro) {
            onOverlay(Overlay.Paywall("shoeson_new_routine"))
            return
        }
        onOverlay(
            Overlay.Editor(
                Routine(
                    name = "",
                    leaveHour = 9,
                    leaveMinute = 0,
                    weekdays = setOf(1, 7),
                    steps = listOf(RoutineStep(name = "Get dressed", guessMinutes = 10), RoutineStep(name = "Shoes, keys, out", guessMinutes = 5)),
                ),
                isNew = true,
            ),
        )
    }

    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            RoutineMenu(graph, ::newRoutine, Modifier.weight(1f))
            Box(
                Modifier.size(44.dp).clip(CircleShape).clickable(role = Role.Button) { onOverlay(Overlay.Settings) }
                    .semantics { contentDescription = "Settings" }.testTag("settings"),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Outlined.Settings, contentDescription = null, tint = palette.ink)
            }
        }
        val routine = store.selectedRoutine
        if (routine == null) {
            Column(Modifier.fillMaxSize().padding(40.dp), verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("No routine yet", style = Type.title2(), color = palette.ink)
                PrimaryButton("Create a routine", ::newRoutine)
            }
        } else {
            RoutineDashboard(graph, routine, onOverlay)
        }
    }
}

@Composable
private fun RoutineMenu(graph: AppGraph, onNew: () -> Unit, modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    val store = graph.store
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        Row(
            Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(12.dp)).clickable(role = Role.DropdownList) { open = true }
                .semantics { contentDescription = "Routines, ${store.selectedRoutine?.name ?: "Shoes On"}" }
                .testTag("routineMenu")
                .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Text(store.selectedRoutine?.name ?: "Shoes On", style = Type.headline(), color = palette.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 240.dp))
            Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null, tint = palette.ink, modifier = Modifier.size(20.dp))
        }
        DropdownMenu(open, onDismissRequest = { open = false }, containerColor = palette.surface) {
            store.routines.forEach { routine ->
                DropdownMenuItem(
                    text = { Text(routine.name, style = Type.body(), color = palette.ink) },
                    leadingIcon = { if (routine.id == store.selectedRoutine?.id) Icon(Icons.Filled.Check, null, tint = palette.ink) else Spacer(Modifier.size(24.dp)) },
                    onClick = {
                        open = false
                        store.select(routine.id)
                    },
                )
            }
            HorizontalDivider(color = palette.hairline)
            DropdownMenuItem(
                text = { Text(if (graph.purchases.isPro || store.routines.isEmpty()) "New routine" else "New routine (Pro)", style = Type.body(), color = palette.ink) },
                leadingIcon = { Icon(Icons.Filled.Add, null, tint = palette.ink) },
                onClick = {
                    open = false
                    onNew()
                },
                modifier = Modifier.testTag("newRoutine"),
            )
        }
    }
}

@Composable
private fun RoutineDashboard(graph: AppGraph, routine: Routine, onOverlay: (Overlay) -> Unit) {
    val store = graph.store
    val context = LocalContext.current
    val now = rememberNow(60_000)
    val zone = ZoneId.systemDefault()
    val next = store.nextPlan(routine, now)
    val plan = next ?: store.plan(routine, routine.leaveTimeForRunStarted(now, zone))
    val changes = routine.upcomingChanges(now, zone)
    // Without alerts the plan is only a screen nobody looks at in the
    // morning. Checked again on every return to the app.
    var alertsOff by remember { mutableStateOf(false) }
    LaunchedEffect(graph.foregroundCount) { alertsOff = !AlertScheduler.notificationsEnabled(context) }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 32.dp).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        AnimatedVisibility(alertsOff) { AlertsOffCard { Links.openNotificationSettings(context) } }
        NextDepartureCard(
            routine = routine,
            plan = plan,
            isScheduled = next != null,
            startTitle = startTitle(graph, routine, now),
            now = now,
            onStart = { store.startRun(routine.id, AppClock.now()) },
            onSkip = { store.setChange(DayChange(plan.leaveAt.day(zone), null), plan.leaveAt.day(zone), routine.id) },
            onChange = { day -> onOverlay(Overlay.DayChange(routine, day)) },
        )
        if (changes.isNotEmpty()) ChangesCard(graph, routine, changes, now)
        Card {
            Row(Modifier.fillMaxWidth().padding(bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                SectionLabel("The real plan", Modifier.weight(1f))
                TextAction("Edit", onClick = { onOverlay(Overlay.Editor(routine, isNew = false)) }, modifier = Modifier.testTag("editRoutine"))
            }
            PlanTimeline(plan)
        }
        RecordCard(store.departures(routine.id), store.calibration)
    }
}

/** "Start now" when the start is close or passed, "Start early" ahead of it, and a practice run when none is due for hours. */
private fun startTitle(graph: AppGraph, routine: Routine, now: Instant): String {
    val target = graph.store.runTarget(routine, now)
    if (target.isPractice) return "Practice run"
    val alertAt = graph.store.plan(routine, target.leaveAt).alertAt
    return if (alertAt.secondsSince(now) > 5 * 60) "Start early" else "Start now"
}

/** Shown while notifications are off, since every alert depends on them. */
@Composable
private fun AlertsOffCard(onTurnOn: () -> Unit) {
    val palette = LocalPalette.current
    Card(Modifier.testTag("alertsOff")) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Filled.NotificationsOff, contentDescription = null, tint = palette.late, modifier = Modifier.padding(top = 2.dp).size(20.dp))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Alerts are off", style = Type.headline(), color = palette.ink)
                Text("Shoes On can't tell you when to start. Turn on notifications so the plan reaches you in the morning.", style = Type.subheadline(), color = palette.secondary)
                Text(
                    "Turn on",
                    style = Type.subheadline(FontWeight.Bold),
                    color = palette.ink,
                    modifier = Modifier.padding(top = 2.dp).clip(RoundedCornerShape(8.dp)).clickable(role = Role.Button, onClick = onTurnOn).padding(vertical = 10.dp, horizontal = 2.dp),
                )
            }
        }
    }
}

@Composable
private fun NextDepartureCard(
    routine: Routine,
    plan: DeparturePlan,
    isScheduled: Boolean,
    startTitle: String,
    now: Instant,
    onStart: () -> Unit,
    onSkip: () -> Unit,
    onChange: (java.time.LocalDate) -> Unit,
) {
    val palette = LocalPalette.current
    val zone = ZoneId.systemDefault()
    // Past the start time and not started: the card stops quoting a time and
    // says what starting right now costs.
    val isOverdue = isScheduled && plan.alertAt <= now && now < plan.leaveAt
    val total = plan.realMinutes + plan.headStartMinutes
    val label = when {
        !isScheduled -> "Any day"
        routine.change(plan.leaveAt.day(zone)) != null -> "${Format.day(plan.leaveAt, now)} · one-off time"
        else -> "${Format.day(plan.leaveAt, now)} · ${Format.weekdays(routine.weekdays)}"
    }
    Card(padding = 22.dp, modifier = Modifier.testTag("nextDeparture")) {
        Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    SectionLabel(label, Modifier.weight(1f))
                    ChangeMenu(isScheduled, plan, now, onSkip, onChange)
                }
                Text(
                    if (isOverdue) "Start now" else "Start ${Format.time(plan.alertAt)}",
                    style = Type.display(44),
                    color = palette.ink,
                    maxLines = 1,
                    modifier = Modifier.testTag("startTime"),
                )
                val leave = "Out the door ${Format.time(plan.leaveAt)}"
                when {
                    isOverdue -> {
                        val out = now.plusSeconds(plan.realMinutes * 60L)
                        val late = ceil(out.secondsSince(plan.leaveAt) / 60).toInt()
                        if (late <= 1) {
                            Text("$leave · still on time if you start now", style = Type.subheadline(FontWeight.Medium), color = palette.onTrack)
                        } else {
                            Text("Starting now: out ${Format.time(out)}, $late min late", style = Type.subheadline(FontWeight.Medium), color = palette.late)
                        }
                    }
                    plan.alertAt.secondsSince(now) > 12 * 3600 -> Text(leave, style = Type.subheadline(FontWeight.Medium), color = palette.secondary)
                    else -> Text("$leave · starts ${Format.relative(plan.alertAt, now)}", style = Type.subheadline(FontWeight.Medium), color = palette.secondary)
                }
            }
            GapBars(guess = plan.guessMinutes, real = total)
            if (total > plan.guessMinutes) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.size(8.dp).clip(CircleShape).background(Palette.gap))
                    Text("${Format.duration(total - plan.guessMinutes)} your guess leaves out", style = Type.footnote(FontWeight.SemiBold), color = palette.ink)
                }
            }
            PrimaryButton(startTitle, onStart, leading = Icons.Filled.PlayArrow, modifier = Modifier.testTag("startRun"))
        }
    }
}

@Composable
private fun ChangeMenu(isScheduled: Boolean, plan: DeparturePlan, now: Instant, onSkip: () -> Unit, onChange: (java.time.LocalDate) -> Unit) {
    val palette = LocalPalette.current
    val zone = ZoneId.systemDefault()
    var open by remember { mutableStateOf(false) }
    Box {
        Box(
            Modifier.size(44.dp, 36.dp).clip(RoundedCornerShape(10.dp)).clickable(role = Role.Button) { open = true }
                .semantics { contentDescription = "Change a day" }.testTag("changeDay"),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.MoreHoriz, contentDescription = null, tint = palette.secondary)
        }
        DropdownMenu(open, onDismissRequest = { open = false }, containerColor = palette.surface) {
            if (isScheduled) {
                val day = Format.dayPhrase(plan.leaveAt.day(zone), now)
                DropdownMenuItem(
                    text = { Text("Skip $day", style = Type.body(), color = palette.ink) },
                    leadingIcon = { Icon(Icons.Filled.Bedtime, null, tint = palette.ink) },
                    onClick = { open = false; onSkip() },
                    modifier = Modifier.testTag("skipDay"),
                )
                DropdownMenuItem(
                    text = { Text("Leave at another time $day", style = Type.body(), color = palette.ink) },
                    leadingIcon = { Icon(Icons.Filled.Schedule, null, tint = palette.ink) },
                    onClick = { open = false; onChange(plan.leaveAt.day(zone)) },
                )
            }
            DropdownMenuItem(
                text = { Text("Change another day", style = Type.body(), color = palette.ink) },
                leadingIcon = { Icon(Icons.Filled.CalendarMonth, null, tint = palette.ink) },
                onClick = { open = false; onChange(now.day(zone)) },
            )
        }
    }
}

/** Upcoming one-off days, each with a way back to normal. */
@Composable
private fun ChangesCard(graph: AppGraph, routine: Routine, changes: List<DayChange>, now: Instant) {
    val palette = LocalPalette.current
    val zone = ZoneId.systemDefault()
    Card(Modifier.animateContentSize().testTag("changesCard")) {
        SectionLabel("Just this once", Modifier.padding(bottom = 6.dp))
        changes.forEach { change ->
            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(if (change.isSkip) Icons.Filled.Bedtime else Icons.Filled.Schedule, contentDescription = null, tint = palette.secondary, modifier = Modifier.size(18.dp))
                Text(Format.day(change.day, now), style = Type.subheadline(FontWeight.SemiBold), color = palette.ink)
                Text(
                    if (change.isSkip) "Skipped" else "Leave ${Format.time(routine.leaveTime(change.day, zone))}",
                    style = Type.subheadline(),
                    color = palette.secondary,
                    modifier = Modifier.weight(1f),
                )
                TextAction("Undo", onClick = { graph.store.setChange(null, change.day, routine.id) })
            }
        }
    }
}

@Composable
private fun RecordCard(departures: List<DepartureRecord>, calibration: Calibration) {
    val palette = LocalPalette.current
    Card(Modifier.testTag("recordCard")) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            SectionLabel("How it's going")
            if (departures.isEmpty()) {
                Text("Your first run starts the learning. Tap Done as you finish each step and Shoes On times it for you.", style = Type.subheadline(), color = palette.secondary)
            } else {
                val recent = departures.take(7)
                val onTime = recent.count { it.wasOnTime }
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("$onTime", style = Type.display(44), color = palette.ink)
                    Text("of ${recent.size} on time", style = Type.headline(), color = palette.secondary, modifier = Modifier.padding(bottom = 6.dp))
                }
                LatenessStrip(recent.reversed())
            }
            Divider()
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("Your pace", style = Type.subheadline(FontWeight.SemiBold), color = palette.ink)
                    val count = calibration.pacedStepCount
                    val sentence = Format.paceSentence(calibration.pace)
                    Text(
                        if (count == 0) "Until it has your real times, steps take $sentence." else "From $count timed ${if (count == 1) "step" else "steps"}: things take $sentence.",
                        style = Type.footnote(),
                        color = palette.secondary,
                    )
                }
                Text(Format.multiplier(calibration.pace), style = Type.title2(FontWeight.ExtraBold), color = palette.ink, modifier = Modifier.padding(start = 12.dp))
            }
        }
    }
}

/** Recent departures as bars around the leave-time line: up for late, down for early. */
@Composable
private fun LatenessStrip(records: List<DepartureRecord>) {
    val palette = LocalPalette.current
    val maxMinutes = maxOf(5.0, records.maxOfOrNull { abs(it.lateSeconds) / 60 } ?: 5.0)
    Box(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = records.joinToString(", ") { Format.lateness(it.lateSeconds) } }) {
        Box(Modifier.fillMaxWidth().offset(y = 28.dp).height(1.dp).background(palette.hairline))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            records.forEach { record ->
                val minutes = record.lateSeconds / 60
                val height = maxOf(4.0, abs(minutes) / maxMinutes * 26).dp
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Box(Modifier.height(56.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Box(
                            Modifier.offset(y = if (minutes > 0) -height / 2 else height / 2).width(10.dp).height(height).clip(CircleShape)
                                .background(if (record.wasOnTime) palette.onTrack else palette.behind),
                        )
                    }
                    Text(Format.narrowWeekday(record.left.day(ZoneId.systemDefault()).let { it.dayOfWeek.value % 7 + 1 }), style = Type.caption2(FontWeight.SemiBold), color = palette.secondary)
                }
            }
        }
    }
}
