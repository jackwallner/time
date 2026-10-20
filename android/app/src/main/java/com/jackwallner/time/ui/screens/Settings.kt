package com.jackwallner.time.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.AlarmOff
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.time.AppGraph
import com.jackwallner.time.BuildConfig
import com.jackwallner.time.data.AlertScheduler
import com.jackwallner.time.data.StoreService
import com.jackwallner.time.model.Format
import com.jackwallner.time.model.PaceAnswer
import com.jackwallner.time.ui.Overlay
import com.jackwallner.time.ui.theme.Divider
import com.jackwallner.time.ui.theme.LocalPalette
import com.jackwallner.time.ui.theme.TextAction
import com.jackwallner.time.ui.theme.Type
import kotlinx.coroutines.launch

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SettingsScreen(graph: AppGraph, onOverlay: (Overlay) -> Unit, onClose: () -> Unit) {
    val palette = LocalPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = graph.store
    val settings = graph.settings
    val purchases = graph.purchases
    var notificationsOff by remember { mutableStateOf(false) }
    var exactOff by remember { mutableStateOf(false) }
    var confirmReset by remember { mutableStateOf(false) }
    var pickingPace by remember { mutableStateOf(false) }
    var restoreMessage by remember { mutableStateOf<String?>(null) }
    var reviewCodeOpen by remember { mutableStateOf(false) }
    // Re-read on return from system Settings, so the fix shows at once.
    LaunchedEffect(graph.foregroundCount) {
        notificationsOff = !AlertScheduler.notificationsEnabled(context)
        exactOff = !AlertScheduler.canScheduleExact(context)
    }

    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding().navigationBarsPadding().testTag("settingsScreen")) {
        Row(Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Settings", style = Type.headline(), color = palette.ink, modifier = Modifier.weight(1f).padding(start = 12.dp))
            TextAction("Done", onClick = onClose, modifier = Modifier.testTag("settingsDone"))
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp)) {
            FormSection(header = "Your pace", footer = "Your answer sets the starting point. Each step you time moves the pace toward how long things really take you.") {
                ValueRow("30 minutes really takes", store.state.pace.title, onClick = { pickingPace = true })
                Divider()
                ValueRow("Your pace so far", Format.multiplier(store.calibration.pace))
                Divider()
                ValueRow("Timed steps", "${store.calibration.pacedStepCount}")
            }
            FormSection(
                header = "Alerts",
                footer = if (exactOff) {
                    "Alerts come through on the minute only with alarms allowed. Without it, Android may hold them a minute or two."
                } else {
                    "Alerts are sent on the minute, through Do Not Disturb if you allow Shoes On there."
                },
            ) {
                if (notificationsOff) {
                    FixRow("Turn on notifications in Settings", Icons.Filled.NotificationsOff) { Links.openNotificationSettings(context) }
                    Divider()
                }
                if (exactOff) {
                    FixRow("Allow alarms and reminders", Icons.Filled.AlarmOff) { Links.openExactAlarmSettings(context) }
                    Divider()
                }
                ToggleRow("Time to get ready", settings.startAlerts, !notificationsOff, settings::updateStartAlerts)
                Divider()
                ToggleRow("Leave in 10 minutes, and time to go", settings.leaveAlerts, !notificationsOff, settings::updateLeaveAlerts)
                Divider()
                ToggleRow("Nudges when a step runs over", settings.stepNudges, !notificationsOff, settings::updateStepNudges)
            }
            FormSection(footer = if (purchases.isPro) null else "Every routine, each with its own days and alerts. Free for 7 days if you haven't tried it.") {
                if (purchases.isPro) {
                    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Filled.Verified, contentDescription = null, tint = palette.onTrack, modifier = Modifier.size(20.dp))
                        Text("Shoes On Pro is active", style = Type.body(), color = palette.ink)
                    }
                    Divider()
                    LinkRow("Manage subscription") { Links.open(context, StoreService.manageSubscriptionURL(purchases.activeProductId)) }
                } else {
                    LinkRow("Try Shoes On Pro", Modifier.testTag("tryPro")) { onOverlay(Overlay.Paywall("shoeson_settings")) }
                    Divider()
                    LinkRow(if (purchases.isPurchasing) "Restoring…" else "Restore purchase") {
                        scope.launch {
                            purchases.restore()
                            restoreMessage = if (purchases.isPro) "Shoes On Pro is active again." else purchases.errorMessage ?: "Nothing to restore."
                            purchases.clearError()
                        }
                    }
                }
            }
            FormSection {
                // Separate rows: Play forbids gating the rating card behind a question.
                LinkRow("Rate Shoes On") { Links.openPlayListing(context) }
                Divider()
                LinkRow("Send feedback", external = true) { Links.open(context, Links.FEEDBACK) }
                Divider()
                LinkRow("Help and support", external = true) { Links.open(context, Links.SUPPORT) }
                Divider()
                LinkRow("Privacy Policy", external = true) { Links.open(context, Links.PRIVACY) }
                Divider()
                LinkRow("Terms of Use", external = true) { Links.open(context, Links.TERMS) }
            }
            FormSection(footer = "Shoes On is a planning tool, not medical advice, and does not diagnose or treat any condition.") {
                Text(
                    "Forget my real times",
                    style = Type.body(),
                    color = palette.late,
                    modifier = Modifier.fillMaxWidth().clickable(role = Role.Button) { confirmReset = true }.padding(16.dp),
                )
            }
            // Long-press opens Play reviewer access (code in the review notes).
            Text(
                "Shoes On ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}). Everything stays on this phone.",
                style = Type.footnote(),
                color = palette.secondary,
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp).combinedClickable(onClick = {}, onLongClick = { reviewCodeOpen = true })
                    .padding(horizontal = 16.dp, vertical = 8.dp).testTag("versionRow"),
            )
            if (BuildConfig.DEBUG) {
                FormSection(header = "Debug") {
                    ToggleRow("Pro", purchases.isPro, true) { purchases.setLocalOverride(it) }
                }
            }
        }
    }

    if (pickingPace) {
        AlertDialog(
            onDismissRequest = { pickingPace = false },
            title = { Text("30 minutes really takes", style = Type.headline()) },
            text = {
                Column {
                    PaceAnswer.entries.forEach { answer ->
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.RadioButton) {
                                store.setPace(answer)
                                pickingPace = false
                            },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(answer.title, style = Type.body(), color = palette.ink, modifier = Modifier.weight(1f))
                            if (answer == store.state.pace) Icon(Icons.Filled.Check, contentDescription = "Selected", tint = palette.ink)
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { pickingPace = false }) { Text("Cancel", style = Type.subheadline(FontWeight.SemiBold), color = palette.ink) } },
            containerColor = palette.surface,
        )
    }
    if (confirmReset) {
        AlertDialog(
            onDismissRequest = { confirmReset = false },
            title = { Text("Forget your real times?", style = Type.headline()) },
            text = { Text("Plans go back to your guesses adjusted for your pace. Routines stay.", style = Type.subheadline()) },
            confirmButton = { TextButton(onClick = { confirmReset = false; store.resetLearning() }) { Text("Forget", style = Type.subheadline(FontWeight.Bold), color = palette.late) } },
            dismissButton = { TextButton(onClick = { confirmReset = false }) { Text("Cancel", style = Type.subheadline(FontWeight.SemiBold), color = palette.ink) } },
            containerColor = palette.surface,
        )
    }
    if (reviewCodeOpen) {
        var code by remember { mutableStateOf("") }
        var wrong by remember { mutableStateOf(false) }
        AlertDialog(
            onDismissRequest = { reviewCodeOpen = false },
            title = { Text("Reviewer access", style = Type.headline()) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Enter the code from the review notes.", style = Type.subheadline())
                    PlainField(code, { code = it; wrong = false }, "Code", Modifier.fillMaxWidth().testTag("reviewCode"))
                    if (wrong) Text("That code didn't work.", style = Type.footnote(), color = palette.late)
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    if (purchases.activateReviewAccess(code)) reviewCodeOpen = false else wrong = true
                }, modifier = Modifier.testTag("reviewCodeSubmit")) { Text("Unlock", style = Type.subheadline(FontWeight.Bold), color = palette.ink) }
            },
            dismissButton = { TextButton(onClick = { reviewCodeOpen = false }) { Text("Cancel", style = Type.subheadline(FontWeight.SemiBold), color = palette.ink) } },
            containerColor = palette.surface,
        )
    }
    restoreMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { restoreMessage = null },
            text = { Text(message, style = Type.body()) },
            confirmButton = { TextButton(onClick = { restoreMessage = null }) { Text("OK", style = Type.subheadline(FontWeight.Bold), color = palette.ink) } },
            containerColor = palette.surface,
        )
    }
}

@Composable
private fun ValueRow(title: String, value: String, onClick: (() -> Unit)? = null) {
    val palette = LocalPalette.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = Type.body(), color = palette.ink, modifier = Modifier.weight(1f))
        Text(value, style = Type.body(), color = palette.secondary, textAlign = TextAlign.End)
    }
}

@Composable
private fun ToggleRow(title: String, checked: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(enabled = enabled, role = Role.Switch) { onChange(!checked) }.padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = Type.body(), color = if (enabled) palette.ink else palette.secondary, modifier = Modifier.weight(1f).padding(end = 12.dp))
        Switch(
            checked = checked,
            onCheckedChange = null,
            enabled = enabled,
            colors = SwitchDefaults.colors(checkedTrackColor = palette.onTrack, checkedThumbColor = Color.White, uncheckedTrackColor = palette.raised, uncheckedBorderColor = palette.hairline, uncheckedThumbColor = palette.secondary),
        )
    }
}

@Composable
private fun LinkRow(title: String, modifier: Modifier = Modifier, external: Boolean = false, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Row(
        modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button, onClick = onClick).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = Type.body(), color = palette.ink, modifier = Modifier.weight(1f))
        if (external) Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null, tint = palette.secondary, modifier = Modifier.size(16.dp))
    }
}

/** A fix that lives in system Settings: flagged, and clearly a way out. */
@Composable
private fun FixRow(title: String, icon: ImageVector, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button, onClick = onClick).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(icon, contentDescription = null, tint = palette.late, modifier = Modifier.size(20.dp))
        Text(title, style = Type.body(), color = palette.late, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null, tint = palette.secondary, modifier = Modifier.size(16.dp))
    }
}
