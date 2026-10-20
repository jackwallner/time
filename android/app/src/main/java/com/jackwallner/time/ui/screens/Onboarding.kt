package com.jackwallner.time.ui.screens

import android.Manifest
import android.app.Activity
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TimeInput
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.time.AppClock
import com.jackwallner.time.AppGraph
import com.jackwallner.time.R
import com.jackwallner.time.data.AlertScheduler
import com.jackwallner.time.data.PurchaseOutcome
import com.jackwallner.time.model.Calibration
import com.jackwallner.time.model.DeparturePlan
import com.jackwallner.time.model.Format
import com.jackwallner.time.model.PaceAnswer
import com.jackwallner.time.model.Planner
import com.jackwallner.time.model.Routine
import com.jackwallner.time.model.RoutineStep
import com.jackwallner.time.ui.OnboardingPages
import com.jackwallner.time.ui.theme.Card
import com.jackwallner.time.ui.theme.CheckCircle
import com.jackwallner.time.ui.theme.Divider
import com.jackwallner.time.ui.theme.GapBars
import com.jackwallner.time.ui.theme.LocalPalette
import com.jackwallner.time.ui.theme.MinuteStepper
import com.jackwallner.time.ui.theme.Palette
import com.jackwallner.time.ui.theme.PrimaryButton
import com.jackwallner.time.ui.theme.SecondaryButton
import com.jackwallner.time.ui.theme.SectionLabel
import com.jackwallner.time.ui.theme.TextAction
import com.jackwallner.time.ui.theme.Type
import com.jackwallner.time.ui.theme.WeekdayPicker
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

data class StepDraft(val id: UUID = UUID.randomUUID(), val name: String, val minutes: Int, val isOn: Boolean) {
    companion object {
        val presets: List<StepDraft>
            get() = listOf(
                StepDraft(name = "Wake up and bathroom", minutes = 10, isOn = true),
                StepDraft(name = "Shower", minutes = 15, isOn = true),
                StepDraft(name = "Get dressed", minutes = 10, isOn = true),
                StepDraft(name = "Hair and makeup", minutes = 15, isOn = false),
                StepDraft(name = "Breakfast", minutes = 15, isOn = true),
                StepDraft(name = "Get the kids ready", minutes = 20, isOn = false),
                StepDraft(name = "Pack bag and lunch", minutes = 10, isOn = true),
                StepDraft(name = "Shoes, keys, out", minutes = 5, isOn = true),
            )
    }
}

/**
 * Six pages: what it does, the pace question, the leave time, the steps, the
 * reveal of the real plan, and the free-trial offer. The primary button sits
 * in the same place on every page.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnboardingScreen(graph: AppGraph, startPage: Int = 0, resumingOffer: Boolean = false) {
    val palette = LocalPalette.current
    val store = graph.store
    val purchases = graph.purchases
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val pager = rememberPagerState(initialPage = startPage) { OnboardingPages.COUNT }
    val page = pager.currentPage
    val lastPage = OnboardingPages.COUNT - 1
    val isTrialPage = page == lastPage

    // Back after leaving the app on the offer: the pace was saved already, so
    // none is set here and finishing cannot overwrite it.
    var pace by remember { mutableStateOf(if (startPage >= 1 && !resumingOffer) PaceAnswer.HALF_OVER else null) }
    val time = rememberTimePickerState(initialHour = 8, initialMinute = 15, is24Hour = android.text.format.DateFormat.is24HourFormat(context))
    var weekdays by remember { mutableStateOf(setOf(2, 3, 4, 5, 6)) }
    val drafts = remember { mutableStateListOf<StepDraft>().apply { addAll(StepDraft.presets) } }
    var customName by remember { mutableStateOf("") }
    var isAdvancing by remember { mutableStateOf(false) }
    var furthest by remember { mutableStateOf(startPage) }
    var permissionAnswered by remember { mutableStateOf<Boolean?>(null) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { permissionAnswered = it }

    fun draftRoutine() = Routine(
        name = if (weekdays == setOf(2, 3, 4, 5, 6)) "Weekday mornings" else "Getting out the door",
        leaveHour = time.hour,
        leaveMinute = time.minute,
        weekdays = weekdays,
        steps = drafts.filter { it.isOn }.map { RoutineStep(name = it.name, guessMinutes = it.minutes) },
    )

    fun draftPlan(): DeparturePlan {
        val routine = draftRoutine()
        val now = AppClock.now()
        val zone = java.time.ZoneId.systemDefault()
        val leave = routine.nextScheduledLeave(now, zone) ?: routine.leaveTimeForRunStarted(now, zone)
        return Planner.plan(routine, leave, Calibration((pace ?: PaceAnswer.QUARTER_OVER).multiplier, emptyList(), emptyList()))
    }

    fun go(to: Int) {
        furthest = maxOf(furthest, to)
        scope.launch { pager.animateScrollToPage(to) }
    }

    fun saveRoutine() {
        pace?.let(store::setPace)
        if (store.routines.isEmpty()) store.save(draftRoutine())
    }

    fun finish() {
        saveRoutine()
        purchases.clearError()
        graph.settings.completeSetup()
        graph.propagate()
    }

    fun addCustom() {
        val name = customName.trim()
        if (name.isEmpty()) return
        drafts.add(maxOf(drafts.size - 1, 0), StepDraft(name = name, minutes = 10, isOn = true))
        customName = ""
    }

    LaunchedEffect(page) {
        if (page == lastPage) {
            if (purchases.isPro) finish() else purchases.trackPaywallImpression("shoeson_onboarding_trial")
        }
    }
    // Pro that lands while the offer shows has nothing left to offer.
    LaunchedEffect(purchases.isPro) { if (purchases.isPro && isTrialPage) finish() }

    val trialEligible = purchases.yearly?.let(purchases::isEligibleForTrial) == true
    val canContinue = when (page) {
        1 -> pace != null
        2 -> weekdays.isNotEmpty()
        3 -> drafts.any { it.isOn } || customName.isNotBlank()
        lastPage -> purchases.yearly != null || purchases.plansUnavailable
        else -> true
    }
    val primaryTitle = when {
        !isTrialPage -> "Continue"
        purchases.plansUnavailable -> "Try again"
        trialEligible -> "Start 7-day free trial"
        else -> "Continue with Pro"
    }

    fun advance() {
        focus.clearFocus()
        when (page) {
            3 -> {
                addCustom()
                go(4)
            }
            4 -> {
                saveRoutine()
                isAdvancing = true
                scope.launch {
                    // The prompt returns once answered. Setup waits for that,
                    // but never longer than the prompt should take to appear.
                    if (Build.VERSION.SDK_INT >= 33 && !AlertScheduler.canPostNotifications(context)) {
                        permissionAnswered = null
                        permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                        withTimeoutOrNull(10_000) { while (permissionAnswered == null) delay(100) }
                    }
                    graph.propagate()
                    isAdvancing = false
                    if (purchases.isPro) finish() else go(5)
                }
            }
            lastPage -> {
                val yearly = purchases.yearly
                if (yearly == null) {
                    scope.launch { purchases.reloadProducts() }
                    return
                }
                val activity = context as? Activity ?: return
                scope.launch { if (purchases.purchase(activity, yearly) == PurchaseOutcome.PURCHASED) finish() }
            }
            else -> go(page + 1)
        }
    }

    if (page in 1 until lastPage) BackHandler { go(page - 1) }

    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding().navigationBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().height(48.dp).padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            val showBack = page in 1 until lastPage
            Box(
                Modifier.size(44.dp).clip(CircleShape).alpha(if (showBack) 1f else 0f)
                    .clickable(enabled = showBack, role = Role.Button) { go(page - 1) }
                    .semantics { contentDescription = "Back" },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = palette.ink)
            }
        }
        HorizontalPager(state = pager, userScrollEnabled = false, modifier = Modifier.weight(1f), beyondViewportPageCount = 0) { index ->
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(top = 8.dp, bottom = 24.dp),
            ) {
                // Pages ahead of the furthest one reached stay empty until
                // reached, so the reveal plays its bars as it slides in.
                if (index <= maxOf(furthest, page)) {
                    when (index) {
                        0 -> WelcomePage()
                        1 -> PacePage(pace) { pace = it }
                        2 -> LeavePage(time, weekdays) { weekdays = it }
                        3 -> StepsPage(drafts, customName, { customName = it }, ::addCustom)
                        4 -> RevealPage(draftPlan())
                        else -> TrialPage(graph, trialEligible)
                    }
                }
            }
        }
        // The fleet onboarding bar: variable content grows upward, the primary
        // button and the reserved legal footer never move.
        Column(Modifier.fillMaxWidth().background(palette.background).padding(horizontal = 24.dp).padding(bottom = 10.dp)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (isTrialPage) {
                    purchases.errorMessage?.let { Text(it, style = Type.footnote(), color = palette.late, textAlign = TextAlign.Center) }
                    trialDisclosure(graph, trialEligible)?.let {
                        Text(it, style = Type.footnote(), color = palette.secondary, textAlign = TextAlign.Center, modifier = Modifier.testTag("trialDisclosure"))
                    }
                    SecondaryButton("Get Started", onClick = ::finish, modifier = Modifier.testTag("getStarted"))
                } else {
                    PageDots(OnboardingPages.COUNT - 1, page, Modifier.padding(bottom = 6.dp))
                }
            }
            PrimaryButton(
                primaryTitle,
                onClick = ::advance,
                enabled = canContinue,
                busy = isAdvancing || (isTrialPage && (purchases.isPurchasing || (purchases.isLoadingProducts && purchases.yearly == null))),
                modifier = Modifier.padding(top = 10.dp).testTag("onboardingPrimary"),
            )
            LegalFooter(graph, visible = isTrialPage, onRestored = { if (purchases.isPro) finish() }, modifier = Modifier.padding(top = 10.dp))
        }
    }
}

private fun trialDisclosure(graph: AppGraph, trialEligible: Boolean): String? {
    val purchases = graph.purchases
    val yearly = purchases.yearly
    if (yearly == null) {
        if (!purchases.plansUnavailable) return "Loading plans…"
        return if (purchases.errorMessage == null) "Plans couldn't load. Check your connection and try again." else null
    }
    if (trialEligible) return "Free for 7 days, then ${yearly.billedLabel}. Cancel anytime in Google Play before the trial ends."
    return "${yearly.billedLabel}. Renews automatically until you cancel in Google Play."
}

@Composable
private fun PageTitle(text: String) {
    Text(text, style = Type.display(34), color = LocalPalette.current.ink, modifier = Modifier.semantics { heading() })
}

@Composable
private fun Lead(text: String) {
    Text(text, style = Type.body(), color = LocalPalette.current.secondary)
}

@Composable
private fun WelcomePage() {
    val palette = LocalPalette.current
    Column(verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Image(
            painterResource(R.drawable.onboarding_mark),
            contentDescription = null,
            modifier = Modifier.padding(top = 16.dp).size(76.dp).shadow(16.dp, RoundedCornerShape(18.dp), ambientColor = Color.Black.copy(alpha = 0.18f), spotColor = Color.Black.copy(alpha = 0.18f)).clip(RoundedCornerShape(18.dp)),
        )
        Text("Leave on time.\nFor real this time.", style = Type.display(40), color = palette.ink, modifier = Modifier.semantics { heading() })
        Lead("Tell Shoes On when you walk out the door. It works backward through your routine, learns how long each step really takes you, and tells you when to start.")
        Card {
            SectionLabel("Why you run late", Modifier.padding(bottom = 14.dp))
            GapBars(guess = 45, real = 68)
            Text("Most guesses run short. Shoes On plans with your real times.", style = Type.footnote(), color = palette.secondary, modifier = Modifier.padding(top = 14.dp))
        }
    }
}

@Composable
private fun PacePage(pace: PaceAnswer?, onPick: (PaceAnswer) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        PageTitle("You plan 30 minutes to get ready. It usually takes…")
        Lead("Be honest. This only sets the starting point; your real times take over as you go.")
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            PaceAnswer.entries.forEach { answer -> PaceChoice(answer, pace == answer) { onPick(answer) } }
        }
    }
}

/** One pace answer, with a bar showing how far the half hour stretches. */
@Composable
private fun PaceChoice(answer: PaceAnswer, isSelected: Boolean, onClick: () -> Unit) {
    val palette = LocalPalette.current
    val haptics = LocalHapticFeedback.current
    val shape = RoundedCornerShape(22.dp)
    val border by animateDpAsState(if (isSelected) 2.dp else 1.dp, label = "border")
    val borderColor by animateColorAsState(if (isSelected) palette.ink else palette.hairline.copy(alpha = 0.7f), label = "borderColor")
    Column(
        Modifier.fillMaxWidth().clip(shape).background(palette.surface).border(border, borderColor, shape)
            .clickable(role = Role.RadioButton) {
                haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
                onClick()
            }
            .semantics { selected = isSelected }
            .testTag("pace.${answer.raw}")
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(answer.title, style = Type.headline(), color = palette.ink)
                Text(answer.detail, style = Type.subheadline(), color = palette.secondary)
            }
            CheckCircle(isSelected)
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(6.dp)) {
            val unit = maxWidth / 2
            Row {
                Box(Modifier.width(unit * minOf(answer.multiplier, 1.0).toFloat()).height(6.dp).clip(CircleShape).background(palette.ink.copy(alpha = if (isSelected) 1f else 0.25f)))
                if (answer.multiplier > 1) {
                    Box(Modifier.padding(start = 3.dp).width(unit * (answer.multiplier - 1).toFloat()).height(6.dp).clip(CircleShape).background(Palette.gap.copy(alpha = if (isSelected) 1f else 0.35f)))
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LeavePage(time: androidx.compose.material3.TimePickerState, weekdays: Set<Int>, onWeekdays: (Set<Int>) -> Unit) {
    val palette = LocalPalette.current
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        PageTitle("When do you need to walk out the door?")
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            TimeInput(state = time, colors = timeColors(palette))
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionLabel("On these days")
            WeekdayPicker(weekdays, onWeekdays)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun timeColors(palette: Palette) = TimePickerDefaults.colors(
    clockDialColor = palette.raised,
    selectorColor = palette.ink,
    periodSelectorBorderColor = palette.hairline,
    periodSelectorSelectedContainerColor = palette.ink,
    periodSelectorUnselectedContainerColor = palette.surface,
    periodSelectorSelectedContentColor = palette.inkInverse,
    periodSelectorUnselectedContentColor = palette.secondary,
    timeSelectorSelectedContainerColor = palette.ink,
    timeSelectorUnselectedContainerColor = palette.raised,
    timeSelectorSelectedContentColor = palette.inkInverse,
    timeSelectorUnselectedContentColor = palette.ink,
)

@Composable
private fun StepsPage(drafts: MutableList<StepDraft>, customName: String, onCustomName: (String) -> Unit, onAdd: () -> Unit) {
    val palette = LocalPalette.current
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        PageTitle("What happens before you leave?")
        Lead("Guess how long each takes. Being wrong is fine; that's what Shoes On is for.")
        val shape = RoundedCornerShape(28.dp)
        Column(Modifier.fillMaxWidth().clip(shape).background(palette.surface).border(1.dp, palette.hairline.copy(alpha = 0.7f), shape).padding(horizontal = 16.dp)) {
            drafts.forEachIndexed { index, draft ->
                StepDraftRow(draft) { drafts[index] = it }
                Divider()
            }
            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                PlainField(customName, onCustomName, "Add your own step", Modifier.weight(1f).testTag("customStep"), onDone = onAdd)
                TextAction("Add", onClick = onAdd, enabled = customName.isNotBlank())
            }
        }
    }
}

@Composable
private fun StepDraftRow(draft: StepDraft, onChange: (StepDraft) -> Unit) {
    val palette = LocalPalette.current
    val haptics = LocalHapticFeedback.current
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(10.dp))
                .clickable(role = Role.Checkbox) {
                    haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
                    onChange(draft.copy(isOn = !draft.isOn))
                }
                .semantics(mergeDescendants = true) { selected = draft.isOn },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            CheckCircle(draft.isOn)
            Text(draft.name, style = Type.body(), color = if (draft.isOn) palette.ink else palette.secondary)
        }
        Box(Modifier.alpha(if (draft.isOn) 1f else 0.35f)) {
            MinuteStepper(draft.minutes, { onChange(draft.copy(minutes = it)) }, enabled = draft.isOn)
        }
    }
}

/** A borderless text field for list rows, like an iOS form row. */
@Composable
fun PlainField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, onDone: () -> Unit = {}, singleLine: Boolean = true) {
    val palette = LocalPalette.current
    TextField(
        value = value,
        onValueChange = onChange,
        placeholder = { Text(placeholder, style = Type.body(), color = palette.secondary) },
        textStyle = Type.body().copy(color = palette.ink),
        singleLine = singleLine,
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done, capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Sentences),
        keyboardActions = KeyboardActions(onDone = { onDone() }),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent,
            unfocusedContainerColor = Color.Transparent,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            cursorColor = palette.ink,
        ),
        modifier = modifier,
    )
}

@Composable
private fun RevealPage(plan: DeparturePlan) {
    val palette = LocalPalette.current
    Column(verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("It really takes", style = Type.title2(), color = palette.secondary)
            Text(Format.duration(plan.realMinutes), style = Type.display(60), color = palette.ink, maxLines = 1, modifier = Modifier.testTag("revealTotal"))
        }
        GapBars(guess = plan.guessMinutes, real = plan.realMinutes)
        Card {
            SectionLabel("Your plan", Modifier.padding(bottom = 8.dp))
            StartToLeave(plan)
        }
        Lead("Shoes On nudges you at ${Format.time(plan.alertAt)}, keeps you on pace step by step, and swaps these estimates for your real times as you use it.")
    }
}

/** "Start 7:12 → Out the door 8:15", shared by the reveal and the day change. */
@Composable
fun StartToLeave(plan: DeparturePlan) {
    val palette = LocalPalette.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Start", style = Type.footnote(FontWeight.SemiBold), color = palette.secondary)
            Text(Format.time(plan.alertAt), style = Type.title(FontWeight.ExtraBold), color = palette.ink)
        }
        Box(Modifier.weight(1f).padding(bottom = 8.dp), contentAlignment = Alignment.Center) {
            Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = palette.secondary)
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Out the door", style = Type.footnote(FontWeight.SemiBold), color = palette.secondary)
            Text(Format.time(plan.leaveAt), style = Type.title(FontWeight.ExtraBold), color = palette.onTrack)
        }
    }
}

@Composable
private fun TrialPage(graph: AppGraph, trialEligible: Boolean) {
    val context = LocalContext.current
    val remindersOff = !AlertScheduler.notificationsEnabled(context)
    Column(verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            PageTitle(if (trialEligible) "Try Shoes On Pro free for 7 days" else "Shoes On Pro")
            Lead("Your first routine stays free for good. Pro adds the rest of your week.")
        }
        ProBenefits()
        val yearly = graph.purchases.yearly
        if (trialEligible && yearly != null) TrialTimeline(yearly.billedLabel, remindersOff)
    }
}

/**
 * What Pro adds on Android. The iOS list also names the Apple Watch coach;
 * there is no Wear OS app, so it is not promised here.
 */
@Composable
fun ProBenefits() {
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        ProBenefit(Icons.Filled.ViewAgenda, "Every routine", "Workdays, school runs, the gym, weekends. Each learns its own times.")
        ProBenefit(Icons.Filled.CalendarMonth, "Each on its own schedule", "Its own days, leave time and alerts, so every part of your week gets a plan.")
    }
}

@Composable
private fun ProBenefit(icon: ImageVector, title: String, detail: String) {
    val palette = LocalPalette.current
    Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.size(38.dp).clip(RoundedCornerShape(11.dp)).background(palette.ink), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = palette.inkInverse, modifier = Modifier.size(19.dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = Type.headline(), color = palette.ink)
            Text(detail, style = Type.subheadline(), color = palette.secondary)
        }
    }
}

/** Today, the reminder, the first charge. The reminder is real (`TrialReminder`). */
@Composable
private fun TrialTimeline(billed: String, remindersOff: Boolean) {
    Column {
        TimelineRow(Icons.Filled.LockOpen, "Today", "Every routine, free.", isLast = false)
        TimelineRow(
            Icons.Filled.Notifications,
            "Day 5",
            if (remindersOff) "Turn on notifications to get a reminder before your trial ends." else "A reminder before your trial ends.",
            isLast = false,
        )
        TimelineRow(Icons.Filled.CalendarMonth, "Day 7", "$billed begins, unless you cancel.", isLast = true)
    }
}

@Composable
private fun TimelineRow(icon: ImageVector, title: String, detail: String, isLast: Boolean) {
    val palette = LocalPalette.current
    Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(30.dp).clip(CircleShape).background(palette.raised), contentAlignment = Alignment.Center) {
                Icon(icon, contentDescription = null, tint = palette.ink, modifier = Modifier.size(15.dp))
            }
            if (!isLast) Box(Modifier.width(2.dp).height(30.dp).background(palette.hairline))
        }
        Column(Modifier.padding(top = 5.dp, bottom = if (isLast) 0.dp else 14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Type.subheadline(FontWeight.Bold), color = palette.ink)
            Text(detail, style = Type.subheadline(), color = palette.secondary)
        }
    }
}

@Composable
private fun PageDots(count: Int, current: Int, modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    Row(modifier.clearAndSetSemantics { contentDescription = "Step ${current + 1} of $count" }, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(count) { index ->
            val width by animateDpAsState(if (index == current) 20.dp else 6.dp, label = "dot")
            Box(Modifier.width(width).height(6.dp).clip(CircleShape).background(if (index == current) palette.ink else palette.hairline))
        }
    }
}

/** Restore, Terms and Privacy. Holds its height on every page; visible only on the offer. */
@Composable
fun LegalFooter(graph: AppGraph, visible: Boolean = true, onRestored: () -> Unit = {}, modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val purchases = graph.purchases
    Row(
        modifier.fillMaxWidth().height(32.dp).alpha(if (visible) 1f else 0f).then(if (visible) Modifier else Modifier.clearAndSetSemantics {}),
        horizontalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FooterLink(if (purchases.isPurchasing) "Restoring…" else "Restore", visible && !purchases.isPurchasing) {
            scope.launch {
                purchases.restore()
                onRestored()
            }
        }
        FooterLink("Terms of Use", visible) { Links.open(context, Links.TERMS) }
        FooterLink("Privacy Policy", visible) { Links.open(context, Links.PRIVACY) }
    }
}

@Composable
private fun FooterLink(title: String, enabled: Boolean, onClick: () -> Unit) {
    Text(
        title,
        style = Type.caption(FontWeight.SemiBold),
        color = LocalPalette.current.secondary,
        modifier = Modifier.clip(RoundedCornerShape(6.dp)).clickable(enabled = enabled, role = Role.Button, onClick = onClick).padding(horizontal = 4.dp, vertical = 6.dp),
    )
}
