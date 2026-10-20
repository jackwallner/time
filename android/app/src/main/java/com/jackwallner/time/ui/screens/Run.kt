package com.jackwallner.time.ui.screens

import android.app.Activity
import android.view.HapticFeedbackConstants
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
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
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCut
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.google.android.play.core.review.ReviewManagerFactory
import com.jackwallner.time.AppClock
import com.jackwallner.time.AppGraph
import com.jackwallner.time.data.FinishedRun
import com.jackwallner.time.data.StepUndo
import com.jackwallner.time.model.ActiveRun
import com.jackwallner.time.model.Format
import com.jackwallner.time.model.RunStatus
import com.jackwallner.time.model.RunStep
import com.jackwallner.time.model.secondsSince
import com.jackwallner.time.ui.theme.Card
import com.jackwallner.time.ui.theme.Dial
import com.jackwallner.time.ui.theme.IconCircleButton
import com.jackwallner.time.ui.theme.LocalPalette
import com.jackwallner.time.ui.theme.Palette
import com.jackwallner.time.ui.theme.PrimaryButton
import com.jackwallner.time.ui.theme.SectionLabel
import com.jackwallner.time.ui.theme.SecondaryButton
import com.jackwallner.time.ui.theme.ShoesOnTheme
import com.jackwallner.time.ui.theme.Type
import kotlinx.coroutines.delay

/**
 * The routine in progress: one step at a time, a dial for it, and whether the
 * morning is on schedule. Then the walk out, then how it went. The run is
 * always dark; the summary follows the app's appearance.
 */
@Composable
fun RunCover(graph: AppGraph) {
    val store = graph.store
    // What the cover last had to show, kept through its exit so the slide
    // down never shows an empty screen.
    var lastRun by remember { mutableStateOf<ActiveRun?>(null) }
    var lastFinished by remember { mutableStateOf<FinishedRun?>(null) }
    val run = store.activeRun
    val finished = store.state.lastFinished
    if (run != null) {
        lastRun = run
        lastFinished = null
    } else if (finished != null) {
        lastFinished = finished
    }
    val showRun = run ?: if (finished == null && lastFinished == null) lastRun else null
    val showFinished = finished ?: lastFinished
    when {
        showRun != null -> ShoesOnTheme(dark = true) { ActiveRunScreen(graph, showRun) }
        showFinished != null -> SummaryScreen(graph, showFinished)
        else -> Box(Modifier.fillMaxSize().background(LocalPalette.current.background))
    }
}

/** Near-black with a soft glow that drifts, tinted by the status. */
@Composable
private fun StatusGlow(color: Color) {
    val tint by animateColorAsState(color, tween(1200), label = "glow")
    val drift by rememberInfiniteTransition(label = "drift").animateFloat(
        -0.08f, 0.08f, infiniteRepeatable(tween(9000, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "drift",
    )
    Canvas(Modifier.fillMaxSize().background(Palette.night)) {
        val w = size.width
        val h = size.height
        drawRect(Brush.radialGradient(listOf(tint.copy(alpha = 0.35f), Color.Transparent), Offset(w * (0.5f + drift), 0f), w * 0.95f))
        drawRect(Brush.radialGradient(listOf(tint.copy(alpha = 0.20f), Color.Transparent), Offset(w * (0.5f + drift), h * (0.45f - drift)), w * 0.7f))
        drawRect(Brush.radialGradient(listOf(tint.copy(alpha = 0.16f), Color.Transparent), Offset(w, h), w * 0.8f))
        drawRect(Brush.radialGradient(listOf(tint.copy(alpha = 0.10f), Color.Transparent), Offset(0f, h), w * 0.6f))
    }
}

@Composable
private fun ActiveRunScreen(graph: AppGraph, run: ActiveRun) {
    val store = graph.store
    val palette = LocalPalette.current
    val view = LocalView.current
    val now = rememberNow(1_000)
    val status = run.status(now)
    val isOverdue = now >= (if (run.isLeaving) run.leaveAt else run.stepEndsAt)
    var confirmEnd by remember { mutableStateOf(false) }
    var undoOffered by remember { mutableStateOf<java.util.UUID?>(null) }

    // Mornings happen with the phone on the counter: the screen stays on for
    // as long as a routine runs.
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }
    // A buzz the moment time runs out, for when nobody is looking.
    LaunchedEffect(isOverdue, run.stepIndex) {
        if (isOverdue) view.performHapticFeedback(HapticFeedbackConstants.REJECT)
    }
    LaunchedEffect(run.stepIndex) {
        if (run.stepIndex > 0) view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
    }
    LaunchedEffect(store.lastStepUndo?.id) { undoOffered = store.lastStepUndo?.id }
    LaunchedEffect(undoOffered) {
        if (undoOffered == null) return@LaunchedEffect
        delay(5_000)
        undoOffered = null
    }
    BackHandler { confirmEnd = true }

    /** A second Done from a double tap would skip a step the user never did. */
    fun advance(action: () -> Unit) {
        if (AppClock.now().secondsSince(run.stepStartedAt) <= 0.6) return
        action()
    }

    Box(Modifier.fillMaxSize().testTag("runScreen")) {
        StatusGlow(palette.color(status))
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 24.dp).padding(bottom = 8.dp)) {
            TopBar(run) { confirmEnd = true }
            Spacer(Modifier.weight(1f))
            AnimatedContent(
                targetState = run.isLeaving,
                transitionSpec = { stepChange() },
                label = "face",
            ) { leaving ->
                if (leaving) LeavingFace(run, now) else StepFace(graph, run, now, status)
            }
            Spacer(Modifier.weight(1f))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (run.isLeaving) {
                    PrimaryButton("I'm out the door", onClick = { store.finishRun(AppClock.now()) }, fill = Color.White, text = Color.Black, modifier = Modifier.testTag("outTheDoor"))
                } else {
                    PrimaryButton("Done", onClick = { advance { store.completeStep(AppClock.now()) } }, fill = Color.White, text = Color.Black, modifier = Modifier.testTag("done"))
                }
                // Right under the thumb that just tapped Done, in the slot the
                // skip button keeps, so offering it never moves anything.
                Box(Modifier.fillMaxWidth().height(44.dp)) {
                    val undo = store.lastStepUndo
                    AnimatedContent(
                        targetState = if (undo != null && undoOffered == undo.id) undo else null,
                        transitionSpec = { fadeIn(tween(250, 100)) togetherWith fadeOut(tween(100)) },
                        label = "undo",
                    ) { offered ->
                        if (offered != null) {
                            UndoButton(offered) {
                                undoOffered = null
                                store.undoLastStep()
                            }
                        } else if (!run.isLeaving) {
                            SecondaryButton("Skip this step", onClick = { advance { store.skipStep(AppClock.now()) } }, color = Color.White.copy(alpha = 0.6f), modifier = Modifier.testTag("skipStep"))
                        }
                    }
                }
            }
        }
    }
    if (confirmEnd) {
        AlertDialog(
            onDismissRequest = { confirmEnd = false },
            title = { Text("End this routine?", style = Type.headline()) },
            text = { Text("Steps you finished still count toward your real times.", style = Type.subheadline()) },
            confirmButton = {
                TextButton(onClick = { confirmEnd = false; store.cancelRun() }, modifier = Modifier.testTag("endWithoutLeaving")) {
                    Text("End without leaving", style = Type.subheadline(FontWeight.Bold), color = palette.late)
                }
            },
            dismissButton = { TextButton(onClick = { confirmEnd = false }) { Text("Keep going", style = Type.subheadline(FontWeight.SemiBold), color = palette.ink) } },
            containerColor = palette.surface,
        )
    }
}

private fun androidx.compose.animation.AnimatedContentTransitionScope<*>.stepChange() =
    (fadeIn(tween(380, 120)) + slideInHorizontally(tween(380, 120)) { 60 }) togetherWith
        (fadeOut(tween(120)) + slideOutHorizontally(tween(120)) { -60 })

@Composable
private fun TopBar(run: ActiveRun, onEnd: () -> Unit) {
    Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(run.routineName, style = Type.subheadline(FontWeight.SemiBold), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    if (run.isPractice) "Practice run · ready by ${Format.time(run.leaveAt)}" else "Out the door ${Format.time(run.leaveAt)}",
                    style = Type.subheadline(),
                    color = Color.White.copy(alpha = 0.6f),
                )
            }
            IconCircleButton(Icons.Filled.Close, "End routine", onEnd, tint = Color.White, background = Color.White.copy(alpha = 0.12f))
        }
        Row(Modifier.fillMaxWidth().clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            run.steps.forEachIndexed { index, step ->
                val fill by animateColorAsState(
                    when {
                        step.skipped -> Color.White.copy(alpha = 0.05f)
                        index < run.stepIndex -> Color.White
                        index == run.stepIndex -> Color.White.copy(alpha = 0.45f)
                        else -> Color.White.copy(alpha = 0.14f)
                    },
                    label = "progress",
                )
                Box(Modifier.weight(1f).height(4.dp).clip(CircleShape).background(fill))
            }
        }
    }
}

@Composable
private fun StepFace(graph: AppGraph, run: ActiveRun, now: java.time.Instant, status: RunStatus) {
    val palette = LocalPalette.current
    val remaining = run.stepEndsAt.secondsSince(now)
    val planned = maxOf(run.currentStep?.plannedSeconds ?: 1.0, 1.0)
    val statusColor = palette.color(status)
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val dialSize = minOf(260.dp, maxWidth * 0.78f)
        // The ring stays and refills; the words in and around it hand over to
        // the next step's, the old ones gone before the new ones land.
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(26.dp)) {
            AnimatedContent(run.stepIndex, transitionSpec = { stepChange() }, label = "name") { _ ->
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("STEP ${run.planStepNumber} OF ${run.planStepCount}", style = Type.footnote(FontWeight.Bold).copy(letterSpacing = androidx.compose.ui.unit.TextUnit(1f, androidx.compose.ui.unit.TextUnitType.Sp)), color = Color.White.copy(alpha = 0.55f))
                    Text(run.currentStep?.name.orEmpty(), style = Type.display(38), color = Color.White, textAlign = TextAlign.Center, maxLines = 2, modifier = Modifier.testTag("stepName"))
                }
            }
            Dial(remaining = (remaining / planned).toFloat(), color = statusColor, modifier = Modifier.size(dialSize)) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.semantics(mergeDescendants = true) {}.testTag("stepClock"),
                ) {
                    Text(
                        Format.clock(remaining),
                        style = Type.display(64, FontWeight.SemiBold, tabular = true),
                        color = if (remaining >= 0) Color.White else statusColor,
                        maxLines = 1,
                        modifier = Modifier.widthIn(max = dialSize * 0.8f),
                    )
                    Text(if (remaining >= 0) "left" else "over", style = Type.subheadline(FontWeight.SemiBold), color = Color.White.copy(alpha = 0.55f))
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.testTag("status")) { com.jackwallner.time.ui.theme.StatusPill(status) }
                val drop = run.catchUpSuggestion(now)
                AnimatedContent(drop, transitionSpec = { (fadeIn() + scaleIn(initialScale = 0.95f)) togetherWith fadeOut() }, label = "catchUp") { suggestion ->
                    if (suggestion != null) {
                        CatchUp(suggestion, statusColor) { graph.store.dropUpcomingStep(suggestion.id) }
                    } else {
                        Text("Then ${run.nextStep?.name ?: "shoes on and out the door"}", style = Type.subheadline(FontWeight.Medium), color = Color.White.copy(alpha = 0.6f), textAlign = TextAlign.Center)
                    }
                }
            }
        }
    }
}

/** Behind, with a way back: the one later step whose time would cover it. */
@Composable
private fun CatchUp(step: RunStep, color: Color, onDrop: () -> Unit) {
    val view = LocalView.current
    val shape = RoundedCornerShape(22.dp)
    Row(
        Modifier.heightIn(min = 44.dp).clip(shape).border(1.dp, color.copy(alpha = 0.6f), shape)
            .clickable(role = Role.Button) {
                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                onDrop()
            }
            .semantics { contentDescription = "Skip ${step.name} today, win back ${step.plannedMinutes} min. Takes ${step.name} off this morning's plan." }
            .testTag("catchUp")
            .padding(horizontal = 18.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Filled.ContentCut, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
        Text("Skip ${step.name} today, win back ${step.plannedMinutes} min", style = Type.subheadline(FontWeight.SemiBold), color = Color.White, maxLines = 2)
    }
}

@Composable
private fun LeavingFace(run: ActiveRun, now: java.time.Instant) {
    val palette = LocalPalette.current
    val untilLeave = run.leaveAt.secondsSince(now)
    val bounce by animateFloatAsState(1f, spring(dampingRatio = 0.4f), label = "bounce")
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Icon(Icons.AutoMirrored.Filled.DirectionsWalk, contentDescription = null, tint = Color.White, modifier = Modifier.size((64 * bounce).dp))
        Text(if (untilLeave > 0) "Shoes on." else "Time to go.", style = Type.display(44), color = Color.White)
        Text(
            if (untilLeave > 0) "${Format.clock(untilLeave)} to spare" else "${Format.clock(untilLeave)} past ${Format.time(run.leaveAt)}",
            style = Type.title2().copy(fontFeatureSettings = "tnum"),
            color = if (untilLeave > 0) palette.onTrack else palette.late,
        )
    }
}

@Composable
private fun UndoButton(undo: StepUndo, onUndo: () -> Unit) {
    val title = when (undo.kind) {
        StepUndo.Kind.DONE -> "Undo ${undo.stepName} done"
        StepUndo.Kind.SKIP -> "Undo ${undo.stepName} skip"
        StepUndo.Kind.DROP -> "Put ${undo.stepName} back"
    }
    Row(
        Modifier.fillMaxWidth().height(44.dp).clickable(role = Role.Button, onClick = onUndo).testTag("undo"),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
        Text(" $title", style = Type.subheadline(FontWeight.SemiBold), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** How the run went: when they left against the target, and each step's real time against the guess. */
@Composable
private fun SummaryScreen(graph: AppGraph, finished: FinishedRun) {
    val palette = LocalPalette.current
    val context = LocalContext.current
    val view = LocalView.current
    val store = graph.store
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        shown = true
        view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
    }
    val late = if (finished.run.isPractice) 0.0 else finished.departure.lateSeconds
    val color = when {
        late <= 60 -> palette.onTrack
        late < 5 * 60 -> palette.behind
        else -> palette.late
    }
    val longest = finished.run.steps.maxOfOrNull { maxOf(it.guessMinutes, Format.minutes(it.actualSeconds ?: 0.0)) }?.coerceAtLeast(1) ?: 1
    val headline = when {
        finished.run.isPractice -> "Practice done."
        late in -60.0..60.0 -> "Right on time."
        late < 0 -> "${com.jackwallner.time.model.roundHalfAway(-late / 60).toInt()} min early."
        else -> "${com.jackwallner.time.model.roundHalfAway(late / 60).toInt()} min late."
    }

    /** Asked once they have taken in the win, not over the top of it; no question first (Play's rules). */
    fun askForReviewIfEarned() {
        if (!finished.departure.wasOnTime || finished.run.isPractice) return
        val onTime = store.state.departures.count { it.wasOnTime }
        if (!graph.reviewTracker.shouldAskAfterOnTimeDeparture(onTime)) return
        val activity = context as? Activity ?: return
        val manager = ReviewManagerFactory.create(context)
        manager.requestReviewFlow().addOnCompleteListener { request ->
            if (request.isSuccessful) manager.launchReviewFlow(activity, request.result)
        }
    }

    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding().navigationBarsPadding().testTag("summary")) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(26.dp)) {
            Column(Modifier.padding(top = 28.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(if (late <= 60) Icons.Filled.CheckCircle else Icons.Filled.Schedule, contentDescription = null, tint = color, modifier = Modifier.size(44.dp))
                Text(headline, style = Type.display(40), color = palette.ink, modifier = Modifier.testTag("summaryHeadline"))
                Text(
                    if (finished.run.isPractice) "A practice run, so it doesn't count toward your on-time record."
                    else "Out the door at ${Format.time(finished.departure.left)}, aiming for ${Format.time(finished.departure.target)}.",
                    style = Type.body(),
                    color = palette.secondary,
                )
            }
            Card {
                SectionLabel("Guess vs real", Modifier.padding(bottom = 14.dp))
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    finished.run.steps.forEach { StepCompare(it, longest, shown) }
                }
            }
            Text("Your next plan already uses these times.", style = Type.subheadline(), color = palette.secondary)
        }
        PrimaryButton(
            "Done",
            onClick = {
                askForReviewIfEarned()
                store.dismissSummary()
            },
            modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 8.dp, top = 8.dp).testTag("summaryDone"),
        )
    }
}

/** One step: the guess as a pale bar, the real time as a bright one under it. */
@Composable
private fun StepCompare(step: RunStep, longest: Int, shown: Boolean) {
    val palette = LocalPalette.current
    val took = step.actualSeconds?.let { Format.minutes(it) }
    val progress by animateFloatAsState(if (shown) 1f else 0f, spring(dampingRatio = 0.75f, stiffness = 60f), label = "compare")
    Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(step.name, style = Type.subheadline(FontWeight.SemiBold), color = palette.ink, modifier = Modifier.weight(1f))
            when {
                step.skipped -> Text("Skipped", style = Type.subheadline(FontWeight.SemiBold), color = palette.secondary)
                took != null -> {
                    Text("${step.guessMinutes}", style = Type.subheadline(FontWeight.SemiBold, tabular = true).copy(textDecoration = androidx.compose.ui.text.style.TextDecoration.LineThrough), color = palette.secondary, modifier = Modifier.semantics { contentDescription = "guessed ${step.guessMinutes}" })
                    Text("$took min", style = Type.subheadline(FontWeight.SemiBold, tabular = true), color = palette.ink)
                }
            }
        }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val full = maxWidth
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Box(Modifier.width(maxOf(8.dp, full * (step.guessMinutes.toFloat() / longest) * progress)).height(5.dp).clip(CircleShape).background(palette.raised))
                if (took != null) {
                    Box(Modifier.width(maxOf(8.dp, full * (took.toFloat() / longest) * progress)).height(5.dp).clip(CircleShape).background(if (took > step.guessMinutes) Palette.gap else palette.onTrack))
                }
            }
        }
    }
}
