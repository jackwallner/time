package com.jackwallner.time.ui.theme

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.time.model.DeparturePlan
import com.jackwallner.time.model.EstimateSource
import com.jackwallner.time.model.Format
import com.jackwallner.time.model.RunStatus
import java.time.Instant

// MARK: Buttons

/** Full-width capsule: the one primary action on a screen. */
@Composable
fun PrimaryButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    fill: Color = LocalPalette.current.ink,
    text: Color = LocalPalette.current.inkInverse,
    enabled: Boolean = true,
    busy: Boolean = false,
    leading: ImageVector? = null,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessMediumLow), label = "press")
    Box(
        modifier
            .fillMaxWidth()
            .height(58.dp)
            .scale(scale)
            .clip(CircleShape)
            .background(fill.copy(alpha = if (enabled) 1f else 0.35f))
            .clickable(interactionSource = interaction, indication = null, enabled = enabled && !busy, role = Role.Button, onClick = onClick)
            .semantics { if (busy) stateDescription = "Working" },
        contentAlignment = Alignment.Center,
    ) {
        if (busy) {
            CircularProgressIndicator(color = text, strokeWidth = 2.5.dp, modifier = Modifier.size(22.dp))
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (leading != null) Icon(leading, contentDescription = null, tint = text, modifier = Modifier.size(18.dp))
                Text(title, style = Type.headline(), color = text)
            }
        }
    }
}

/** Quiet text button for secondary actions. */
@Composable
fun SecondaryButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, color: Color = LocalPalette.current.secondary, enabled: Boolean = true) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = Type.subheadline(FontWeight.SemiBold), color = color.copy(alpha = if (pressed) 0.5f else color.alpha), textAlign = TextAlign.Center)
    }
}

/** Inline text action, like "Edit" or "Undo". */
@Composable
fun TextAction(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, color: Color = LocalPalette.current.ink, enabled: Boolean = true) {
    Box(
        modifier.heightIn(min = 44.dp).widthIn(min = 44.dp).clip(RoundedCornerShape(10.dp))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick).padding(horizontal = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = Type.subheadline(FontWeight.SemiBold), color = if (enabled) color else color.copy(alpha = 0.35f))
    }
}

/** Round icon button used in top bars and on the run screen. */
@Composable
fun IconCircleButton(icon: ImageVector, label: String, onClick: () -> Unit, tint: Color = LocalPalette.current.ink, background: Color = LocalPalette.current.raised) {
    Box(
        Modifier.size(44.dp).clip(CircleShape).background(background).clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
    }
}

// MARK: Surfaces

/** A plain surface card. */
@Composable
fun Card(modifier: Modifier = Modifier, padding: Dp = 20.dp, content: @Composable ColumnScope.() -> Unit) {
    val palette = LocalPalette.current
    val shape = RoundedCornerShape(Metrics.radius)
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(palette.surface)
            .border(1.dp, palette.hairline.copy(alpha = 0.7f), shape)
            .padding(padding),
        content = content,
    )
}

/** Small uppercase label above a section. */
@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier, color: Color = LocalPalette.current.secondary) {
    Text(text.uppercase(), modifier = modifier.semantics { heading() }, style = Type.caption(FontWeight.Bold).copy(letterSpacing = 0.8.sp), color = color)
}

/** On track, ahead, or behind, in the colour that says so. */
@Composable
fun StatusPill(status: RunStatus, palette: Palette = LocalPalette.current) {
    val color by animateColorAsState(palette.color(status), tween(600), label = "status")
    Row(
        Modifier.clip(CircleShape).background(color.copy(alpha = 0.14f)).padding(horizontal = 14.dp, vertical = 8.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Box(Modifier.size(8.dp).drawBehind {
            drawCircle(color.copy(alpha = 0.45f), radius = size.minDimension)
            drawCircle(color)
        })
        Text(status.label, style = Type.subheadline(FontWeight.Bold), color = color)
    }
}

// MARK: The gap

/**
 * Two bars that end at the same moment, the leave time: the guess, and the
 * real time. The part the guess leaves out is the whole point of the app.
 */
@Composable
fun GapBars(guess: Int, real: Int, animate: Boolean = true) {
    val palette = LocalPalette.current
    var shown by remember { mutableStateOf(!animate) }
    LaunchedEffect(Unit) { shown = true }
    val progress by animateFloatAsState(if (shown) 1f else 0.02f, spring(dampingRatio = 0.75f, stiffness = 60f), label = "gap")
    val longest = maxOf(guess, real, 1).toFloat()
    Column(
        Modifier.fillMaxWidth().clearAndSetSemantics {
            contentDescription = "Your guess ${Format.duration(guess)}, real time ${Format.duration(real)}"
        },
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        GapRow("Your guess", guess, guess / longest * progress, palette.raised, palette.secondary, null)
        GapRow("Real time", real, real / longest * progress, palette.ink, palette.ink, if (real > guess) (1f - guess.toFloat() / real) else null)
    }
}

@Composable
private fun GapRow(label: String, minutes: Int, fraction: Float, fill: Color, text: Color, gapShare: Float?) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth()) {
            Text(label, style = Type.footnote(FontWeight.SemiBold), color = text, modifier = Modifier.weight(1f))
            Text(Format.duration(minutes), style = Type.footnote(FontWeight.SemiBold, tabular = true), color = text)
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(12.dp)) {
            val width = maxOf(maxWidth * fraction, 10.dp)
            Box(Modifier.align(Alignment.CenterEnd).width(width).fillMaxHeight().clip(CircleShape).background(fill)) {
                if (gapShare != null) {
                    Box(Modifier.width(width * gapShare).fillMaxHeight().clip(CircleShape).background(Palette.gap))
                }
            }
        }
    }
}

// MARK: Plan timeline

/** The plan as a line with stops: each step's start, its real length, and the guess it replaced. */
@Composable
fun PlanTimeline(plan: DeparturePlan) {
    Column {
        if (plan.headStartMinutes > 0) {
            TimelineStop(plan.alertAt, "Get going", "You usually start a few minutes after the alert", plan.headStartMinutes, null, isLast = false)
        }
        plan.steps.forEach { planned ->
            val detail = when (val source = planned.estimate.source) {
                EstimateSource.Pace -> "Your pace"
                is EstimateSource.Learned -> "Timed ${if (source.runs == 1) "once" else "${source.runs} times"}"
            }
            TimelineStop(planned.startsAt, planned.step.name, detail, planned.estimate.minutes, planned.estimate.guessMinutes, isLast = false)
        }
        TimelineStop(plan.leaveAt, "Out the door", null, null, null, isLast = true)
    }
}

@Composable
private fun TimelineStop(time: Instant, title: String, detail: String?, minutes: Int?, guess: Int?, isLast: Boolean) {
    val palette = LocalPalette.current
    val spoken = buildString {
        append(Format.time(time)).append(", ").append(title)
        if (minutes != null) append(", $minutes minutes")
        if (guess != null && minutes != null && guess != minutes) append(", guessed $guess")
        if (detail != null) append(", ").append(detail)
    }
    Row(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = spoken }, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(Format.time(time), style = Type.footnote(FontWeight.Medium, tabular = true), color = palette.secondary, textAlign = TextAlign.End, modifier = Modifier.width(66.dp).padding(top = 2.dp))
        Box(Modifier.width(12.dp).heightIn(min = if (isLast) 24.dp else 56.dp).drawBehind {
            val dot = if (isLast) 6.dp.toPx() else 4.5.dp.toPx()
            val cy = (if (isLast) 4.dp.toPx() else 5.dp.toPx()) + dot
            if (!isLast) drawLine(palette.hairline, Offset(center.x, cy), Offset(center.x, size.height + 4.dp.toPx()), strokeWidth = 2.dp.toPx())
            drawCircle(if (isLast) palette.onTrack else palette.ink, radius = dot, center = Offset(center.x, cy))
        })
        Column(Modifier.weight(1f).padding(bottom = if (isLast) 0.dp else 18.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Text(title, style = Type.body(if (isLast) FontWeight.Bold else FontWeight.Medium), color = palette.ink, modifier = Modifier.weight(1f))
                if (minutes != null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(start = 8.dp)) {
                        if (guess != null && guess != minutes) {
                            Text("$guess", style = Type.subheadline(FontWeight.SemiBold, tabular = true).copy(textDecoration = androidx.compose.ui.text.style.TextDecoration.LineThrough), color = palette.secondary)
                        }
                        Text("$minutes min", style = Type.subheadline(FontWeight.SemiBold, tabular = true), color = palette.ink)
                    }
                }
            }
            if (detail != null) Text(detail, style = Type.footnote(), color = palette.secondary)
        }
    }
}

// MARK: Dial

/** A countdown ring: full when the step starts, empty when its time is up. */
@Composable
fun Dial(remaining: Float, color: Color, modifier: Modifier = Modifier, lineWidth: Dp = 14.dp, center: @Composable () -> Unit) {
    val trim by animateFloatAsState(remaining.coerceIn(0.001f, 1f), tween(1000), label = "dial")
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.matchParentSize()) {
            val stroke = lineWidth.toPx()
            val inset = stroke / 2
            val arcSize = androidx.compose.ui.geometry.Size(size.width - stroke, size.height - stroke)
            drawCircle(Color.White.copy(alpha = 0.10f), radius = (size.minDimension - stroke) / 2, style = Stroke(stroke))
            drawArc(color.copy(alpha = 0.22f), -90f, 360f * trim, false, Offset(inset, inset), arcSize, style = Stroke(stroke * 2.2f, cap = StrokeCap.Round))
            drawArc(color, -90f, 360f * trim, false, Offset(inset, inset), arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
        }
        center()
    }
}

// MARK: Inputs

/** Seven round day toggles in the locale's week order. */
@Composable
fun WeekdayPicker(selection: Set<Int>, onChange: (Set<Int>) -> Unit) {
    val palette = LocalPalette.current
    val haptics = LocalHapticFeedback.current
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Format.orderedWeekdays().forEach { day ->
            val isOn = day in selection
            Box(
                Modifier.weight(1f).height(42.dp).clip(CircleShape)
                    .background(if (isOn) palette.ink else palette.surface)
                    .border(if (isOn) 0.dp else 1.dp, palette.hairline, CircleShape)
                    .clickable(role = Role.Checkbox) {
                        haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
                        onChange(if (isOn) selection - day else selection + day)
                    }
                    .semantics { contentDescription = Format.fullWeekday(day); selected = isOn },
                contentAlignment = Alignment.Center,
            ) {
                Text(Format.narrowWeekday(day), style = Type.subheadline(FontWeight.Bold), color = if (isOn) palette.inkInverse else palette.ink)
            }
        }
    }
}

private val stepperValues = listOf(1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 45, 60, 75, 90, 120)

fun stepperUp(minutes: Int): Int = stepperValues.firstOrNull { it > minutes } ?: minutes
fun stepperDown(minutes: Int): Int = stepperValues.lastOrNull { it < minutes } ?: stepperValues.first()

/** "- 10 min +" in one compact control. */
@Composable
fun MinuteStepper(minutes: Int, onChange: (Int) -> Unit, enabled: Boolean = true) {
    val palette = LocalPalette.current
    val haptics = LocalHapticFeedback.current
    Row(
        Modifier.clip(CircleShape).background(palette.raised).semantics(mergeDescendants = false) {
            stateDescription = "$minutes minutes"
        },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepperButton(Icons.Filled.Remove, "Fewer minutes", enabled && minutes > stepperValues.first()) {
            haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
            onChange(stepperDown(minutes))
        }
        Text("$minutes min", style = Type.subheadline(FontWeight.Bold, tabular = true), color = palette.ink, textAlign = TextAlign.Center, modifier = Modifier.widthIn(min = 56.dp))
        StepperButton(Icons.Filled.Add, "More minutes", enabled && minutes < stepperValues.last()) {
            haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
            onChange(stepperUp(minutes))
        }
    }
}

@Composable
private fun StepperButton(icon: ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Box(
        Modifier.size(44.dp).clip(CircleShape).clickable(enabled = enabled, role = Role.Button, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = if (enabled) palette.ink else palette.secondary.copy(alpha = 0.4f), modifier = Modifier.size(16.dp))
    }
}

/** A selectable round check, as in the iOS step and plan rows. */
@Composable
fun CheckCircle(isOn: Boolean, size: Dp = 24.dp) {
    val palette = LocalPalette.current
    Box(
        Modifier.size(size).clip(CircleShape)
            .background(if (isOn) palette.ink else Color.Transparent)
            .border(if (isOn) 0.dp else 2.dp, palette.hairline, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (isOn) Icon(Icons.Filled.Check, contentDescription = null, tint = palette.inkInverse, modifier = Modifier.size(size * 0.62f))
    }
}

@Composable
fun Divider() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(LocalPalette.current.hairline))
}

@Composable
fun VSpace(height: Dp) = Spacer(Modifier.height(height))
