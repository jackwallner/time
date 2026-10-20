package com.jackwallner.time.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TimeInput
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.time.AppGraph
import com.jackwallner.time.model.DayChange
import com.jackwallner.time.model.Format
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.at
import com.jackwallner.time.model.day
import com.jackwallner.time.model.iosWeekday
import com.jackwallner.time.ui.theme.Card
import com.jackwallner.time.ui.theme.LocalPalette
import com.jackwallner.time.ui.theme.PrimaryButton
import com.jackwallner.time.ui.theme.SecondaryButton
import com.jackwallner.time.ui.theme.SectionLabel
import com.jackwallner.time.ui.theme.Type
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.TextStyle

/**
 * One day, just this once: leave at another time, or skip it. The plan for
 * that day is worked out as the time moves, so the start is never a guess.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DayChangeSheet(graph: AppGraph, routineAtOpen: Routine, startDay: LocalDate, onClose: () -> Unit) {
    val palette = LocalPalette.current
    val context = LocalContext.current
    val store = graph.store
    val zone = ZoneId.systemDefault()
    val routine = store.routine(routineAtOpen.id) ?: routineAtOpen
    val now = rememberNow(60_000)
    var day by remember { mutableStateOf(startDay) }
    var skip by remember { mutableStateOf(routine.change(startDay)?.isSkip ?: false) }
    val initial = routine.leaveTime(startDay, zone).atZone(zone)
    val time = rememberTimePickerState(initial.hour, initial.minute, android.text.format.DateFormat.is24HourFormat(context))
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    val isScheduled = day.iosWeekday() in routine.weekdays
    val isSkipping = skip && isScheduled
    val leaveAt = day.at(time.hour, time.minute, zone)

    fun select(date: LocalDate) {
        day = date
        skip = routine.change(date)?.isSkip ?: false
        val leave = routine.leaveTime(date, zone).atZone(zone)
        time.hour = leave.hour
        time.minute = leave.minute
    }

    fun save() {
        val change = if (isSkipping) DayChange(day, null) else DayChange(day, time.hour * 60 + time.minute)
        store.setChange(change, day, routine.id)
        onClose()
    }

    ModalBottomSheet(onDismissRequest = onClose, sheetState = sheet, containerColor = palette.background, modifier = Modifier.testTag("dayChange")) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
            Text("Just this once", style = Type.headline(), color = palette.ink, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp))
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                DayStrip(routine, day, now.day(zone), ::select)
                if (isScheduled) {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        listOf(false to "Another time", true to "Skip it").forEachIndexed { index, (value, label) ->
                            SegmentedButton(
                                selected = skip == value,
                                onClick = { skip = value },
                                shape = SegmentedButtonDefaults.itemShape(index, 2),
                                colors = SegmentedButtonDefaults.colors(
                                    activeContainerColor = palette.ink,
                                    activeContentColor = palette.inkInverse,
                                    inactiveContainerColor = palette.surface,
                                    inactiveContentColor = palette.ink,
                                    activeBorderColor = palette.ink,
                                    inactiveBorderColor = palette.hairline,
                                ),
                                icon = {},
                                modifier = Modifier.testTag(if (value) "segmentSkip" else "segmentTime"),
                            ) { Text(label, style = Type.subheadline(FontWeight.SemiBold)) }
                        }
                    }
                }
                if (!isSkipping) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { TimeInput(time, colors = timeColors(palette)) }
                }
                Card {
                    when {
                        isSkipping -> {
                            Text("No alerts ${Format.dayPhrase(day, now)}.", style = Type.title2(FontWeight.ExtraBold), color = palette.ink)
                            Text("${routine.name} is back to normal the day after.", style = Type.subheadline(), color = palette.secondary, modifier = Modifier.padding(top = 4.dp))
                        }
                        leaveAt <= now -> Text("That time has already passed.", style = Type.subheadline(FontWeight.SemiBold), color = palette.late)
                        else -> {
                            SectionLabel(Format.day(day, now), Modifier.padding(bottom = 8.dp))
                            StartToLeave(store.plan(routine, leaveAt))
                        }
                    }
                }
            }
            val hasChange = routine.change(day) != null
            Column(Modifier.padding(horizontal = 24.dp).padding(top = 10.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                PrimaryButton("Save", ::save, enabled = isSkipping || leaveAt > now, modifier = Modifier.testTag("saveDayChange"))
                Box(Modifier.alpha(if (hasChange) 1f else 0f)) {
                    SecondaryButton("Back to normal", onClick = { store.setChange(null, day, routine.id); onClose() }, enabled = hasChange)
                }
            }
        }
    }
}

@Composable
private fun DayStrip(routine: Routine, selected: LocalDate, today: LocalDate, onPick: (LocalDate) -> Unit) {
    val palette = LocalPalette.current
    val locale = androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        (0L until 7L).map { today.plusDays(it) }.forEach { date ->
            val isOn = date == selected
            val departs = routine.departs(date)
            val shape = RoundedCornerShape(14.dp)
            Column(
                Modifier.weight(1f).clip(shape).background(if (isOn) palette.ink else palette.surface)
                    .border(if (isOn) 0.dp else 1.dp, palette.hairline, shape)
                    .clickable(role = Role.Tab) { onPick(date) }
                    .semantics {
                        contentDescription = "${date.dayOfWeek.getDisplayName(TextStyle.FULL, locale)} ${date.dayOfMonth}"
                        this.selected = isOn
                    }
                    .padding(vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                val ink = if (isOn) palette.inkInverse else palette.ink
                Text(date.dayOfWeek.getDisplayName(TextStyle.SHORT, locale).uppercase(), style = Type.caption2(FontWeight.Bold), color = ink)
                Text("${date.dayOfMonth}", style = Type.headline().copy(fontFeatureSettings = "tnum"), color = ink)
                Box(Modifier.size(5.dp).clip(CircleShape).background(if (departs) ink else androidx.compose.ui.graphics.Color.Transparent))
            }
        }
    }
}
