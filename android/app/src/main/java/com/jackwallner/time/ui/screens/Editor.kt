package com.jackwallner.time.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.jackwallner.time.AppGraph
import com.jackwallner.time.model.Format
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import com.jackwallner.time.ui.theme.Divider
import com.jackwallner.time.ui.theme.LocalPalette
import com.jackwallner.time.ui.theme.Metrics
import com.jackwallner.time.ui.theme.MinuteStepper
import com.jackwallner.time.ui.theme.TextAction
import com.jackwallner.time.ui.theme.Type
import com.jackwallner.time.ui.theme.WeekdayPicker
import java.time.ZoneId

/** Name, leave time, days, and the steps with their guesses. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RoutineEditorScreen(graph: AppGraph, original: Routine, isNew: Boolean, onClose: () -> Unit) {
    val palette = LocalPalette.current
    val context = LocalContext.current
    val store = graph.store
    var name by remember { mutableStateOf(original.name) }
    var hour by remember { mutableStateOf(original.leaveHour) }
    var minute by remember { mutableStateOf(original.leaveMinute) }
    var weekdays by remember { mutableStateOf(original.weekdays) }
    val steps = remember { mutableStateListOf<RoutineStep>().apply { addAll(original.steps) } }
    var newStepName by remember { mutableStateOf("") }
    var confirmDelete by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var pickingTime by remember { mutableStateOf(false) }

    val edited = original.copy(name = name, leaveHour = hour, leaveMinute = minute, weekdays = weekdays, steps = steps.toList())
    val hasChanges = edited != original || newStepName.isNotBlank()
    val canSave = name.isNotBlank() && (steps.isNotEmpty() || newStepName.isNotBlank()) && steps.all { it.name.isNotBlank() }

    fun addStep() {
        val trimmed = newStepName.trim()
        if (trimmed.isEmpty()) return
        steps.add(RoutineStep(name = trimmed, guessMinutes = 10))
        newStepName = ""
    }

    fun save() {
        // A step typed but not yet added is one the user expects to keep.
        addStep()
        store.save(original.copy(name = name.trim(), leaveHour = hour, leaveMinute = minute, weekdays = weekdays, steps = steps.toList()))
        onClose()
    }

    fun cancel() {
        if (hasChanges) confirmDiscard = true else onClose()
    }

    BackHandler(onBack = ::cancel)

    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding().navigationBarsPadding().imePadding().testTag("editor")) {
        Row(Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextAction("Cancel", onClick = ::cancel, color = palette.ink)
            Text(if (isNew) "New routine" else "Edit routine", style = Type.headline(), color = palette.ink, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            TextAction("Save", onClick = ::save, enabled = canSave, modifier = Modifier.testTag("saveRoutine"))
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            FormSection(footer = if (weekdays.isEmpty()) "With no days set, there are no alerts. You can still start it by hand." else "Alerts come on these days. You can start it by hand any day.") {
                PlainField(name, { name = it }, "Name, like Weekday mornings", Modifier.fillMaxWidth().testTag("routineName"))
                Divider()
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button) { pickingTime = true }.padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Leave at", style = Type.body(), color = palette.ink, modifier = Modifier.weight(1f))
                    val time = java.time.LocalDate.now().atTime(hour, minute).atZone(ZoneId.systemDefault()).toInstant()
                    Text(Format.time(time), style = Type.body(FontWeight.SemiBold), color = palette.ink, modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(palette.raised).padding(horizontal = 10.dp, vertical = 6.dp))
                }
                Divider()
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Days", style = Type.body(), color = palette.ink)
                    WeekdayPicker(weekdays) { weekdays = it }
                }
            }
            FormSection(header = "Steps, in order", footer = "Minutes are your guess. Shoes On keeps it, and plans with your real times once it has them.") {
                steps.forEachIndexed { index, step ->
                    Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 12.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            Modifier.size(44.dp).clip(CircleShape).clickable(role = Role.Button) { steps.removeAt(index) }
                                .semantics { contentDescription = "Delete ${step.name}" },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Filled.RemoveCircle, contentDescription = null, tint = palette.late, modifier = Modifier.size(22.dp))
                        }
                        PlainField(step.name, { steps[index] = step.copy(name = it) }, "Step", Modifier.weight(1f), singleLine = false)
                        MinuteStepper(step.guessMinutes, { steps[index] = step.copy(guessMinutes = it) })
                        Column {
                            ReorderButton(Icons.Filled.KeyboardArrowUp, "Move ${step.name} up", index > 0) { steps.add(index - 1, steps.removeAt(index)) }
                            ReorderButton(Icons.Filled.KeyboardArrowDown, "Move ${step.name} down", index < steps.size - 1) { steps.add(index + 1, steps.removeAt(index)) }
                        }
                    }
                    Divider()
                }
                Row(Modifier.fillMaxWidth().padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    PlainField(newStepName, { newStepName = it }, "Add a step", Modifier.weight(1f).testTag("addStepField"), onDone = ::addStep)
                    TextAction("Add", onClick = ::addStep, enabled = newStepName.isNotBlank())
                }
            }
            if (!isNew && store.routines.size > 1) {
                FormSection {
                    Text(
                        "Delete routine",
                        style = Type.body(),
                        color = palette.late,
                        modifier = Modifier.fillMaxWidth().clickable(role = Role.Button) { confirmDelete = true }.padding(16.dp),
                    )
                }
            }
        }
    }

    if (pickingTime) {
        val state = rememberTimePickerState(hour, minute, android.text.format.DateFormat.is24HourFormat(context))
        AlertDialog(
            onDismissRequest = { pickingTime = false },
            confirmButton = {
                TextButton(onClick = { hour = state.hour; minute = state.minute; pickingTime = false }) { Text("OK", style = Type.subheadline(FontWeight.Bold), color = palette.ink) }
            },
            dismissButton = { TextButton(onClick = { pickingTime = false }) { Text("Cancel", style = Type.subheadline(FontWeight.SemiBold), color = palette.ink) } },
            title = { Text("Leave at", style = Type.headline()) },
            text = { TimePicker(state, colors = timeColors(palette)) },
            containerColor = palette.surface,
        )
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete ${original.name}?", style = Type.headline()) },
            text = { Text("Its steps and timing history go with it.", style = Type.subheadline()) },
            confirmButton = {
                TextButton(onClick = { confirmDelete = false; store.delete(original.id); onClose() }) { Text("Delete", style = Type.subheadline(FontWeight.Bold), color = palette.late) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel", style = Type.subheadline(FontWeight.SemiBold), color = palette.ink) } },
            containerColor = palette.surface,
        )
    }
    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text("Discard your changes?", style = Type.headline()) },
            confirmButton = {
                TextButton(onClick = { confirmDiscard = false; onClose() }) { Text("Discard changes", style = Type.subheadline(FontWeight.Bold), color = palette.late) }
            },
            dismissButton = { TextButton(onClick = { confirmDiscard = false }) { Text("Keep editing", style = Type.subheadline(FontWeight.SemiBold), color = palette.ink) } },
            containerColor = palette.surface,
        )
    }
}

@Composable
private fun ReorderButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Box(
        Modifier.size(36.dp, 26.dp).clip(RoundedCornerShape(6.dp)).clickable(enabled = enabled, role = Role.Button, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = if (enabled) palette.secondary else palette.secondary.copy(alpha = 0.25f), modifier = Modifier.size(20.dp))
    }
}

/** A grouped form section: optional header, a rounded surface, optional footer. */
@Composable
fun FormSection(header: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    val palette = LocalPalette.current
    val shape = RoundedCornerShape(Metrics.radius * 0.7f)
    Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (header != null) Text(header.uppercase(), style = Type.footnote(FontWeight.SemiBold), color = palette.secondary, modifier = Modifier.padding(horizontal = 16.dp))
        Column(Modifier.fillMaxWidth().clip(shape).background(palette.surface).border(1.dp, palette.hairline.copy(alpha = 0.7f), shape), content = content)
        if (footer != null) Text(footer, style = Type.footnote(), color = palette.secondary, modifier = Modifier.padding(horizontal = 16.dp))
    }
}
