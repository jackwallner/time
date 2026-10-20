package com.jackwallner.time.ui.screens

import android.app.Activity
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.time.AppGraph
import com.jackwallner.time.data.Plan
import com.jackwallner.time.ui.theme.CheckCircle
import com.jackwallner.time.ui.theme.IconCircleButton
import com.jackwallner.time.ui.theme.LocalPalette
import com.jackwallner.time.ui.theme.PrimaryButton
import com.jackwallner.time.ui.theme.SecondaryButton
import com.jackwallner.time.ui.theme.Type
import kotlinx.coroutines.launch

/** The full plan picker: yearly (selected) and monthly, both with a trial for people who have not had one. */
@Composable
fun PaywallScreen(graph: AppGraph, surface: String, initialMonthly: Boolean = false, onClose: () -> Unit) {
    val palette = LocalPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val purchases = graph.purchases
    var monthly by remember { mutableStateOf(initialMonthly) }
    val selected = if (monthly) purchases.monthly else purchases.yearly
    val isTrial = selected?.let(purchases::isEligibleForTrial) == true

    LaunchedEffect(Unit) {
        purchases.trackPaywallImpression(surface)
        purchases.reloadProducts()
    }
    LaunchedEffect(purchases.isPro) { if (purchases.isPro) onClose() }

    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding().navigationBarsPadding().testTag("paywall")) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 8.dp), horizontalArrangement = Arrangement.End) {
            IconCircleButton(Icons.Filled.Close, "Close", onClose)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(top = 4.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Shoes On Pro", style = Type.display(38), color = palette.ink)
                Text("Your first routine stays free. Pro adds the rest of your week.", style = Type.body(), color = palette.secondary)
            }
            ProBenefits()
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                purchases.yearly?.let { yearly ->
                    PlanCard(yearly, "Yearly", Plan.savingsBadge(yearly, purchases.monthly), if (purchases.isEligibleForTrial(yearly)) yearly.trialLabel else null, !monthly) { monthly = false }
                }
                purchases.monthly?.let { plan ->
                    PlanCard(plan, "Monthly", null, if (purchases.isEligibleForTrial(plan)) plan.trialLabel else null, monthly) { monthly = true }
                }
                when {
                    purchases.plansUnavailable -> SecondaryButton("Try again", onClick = { scope.launch { purchases.reloadProducts() } }, color = palette.ink)
                    purchases.plans.isEmpty() -> Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = palette.ink, strokeWidth = 2.5.dp)
                    }
                }
            }
        }
        Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 12.dp, bottom = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            purchases.errorMessage?.let { Text(it, style = Type.footnote(), color = palette.late, textAlign = TextAlign.Center, modifier = Modifier.testTag("paywallError")) }
            if (selected != null) {
                Text(if (isTrial) "Free for 7 days, then ${selected.billedLabel}" else selected.billedLabel, style = Type.subheadline(FontWeight.Bold), color = palette.ink, modifier = Modifier.testTag("paywallPrice"))
                Text(
                    "Renews automatically until you cancel. Cancel anytime in Google Play > Payments & subscriptions${if (isTrial) " before the trial ends and you won't be charged" else ""}.",
                    style = Type.caption(),
                    color = palette.secondary,
                    textAlign = TextAlign.Center,
                )
            }
            PrimaryButton(
                if (isTrial) "Start 7-day free trial" else "Subscribe",
                onClick = {
                    val plan = selected ?: return@PrimaryButton
                    val activity = context as? Activity ?: return@PrimaryButton
                    scope.launch { purchases.purchase(activity, plan) }
                },
                enabled = selected != null,
                busy = purchases.isPurchasing,
                modifier = Modifier.testTag("subscribe"),
            )
            LegalFooter(graph)
        }
    }
}

@Composable
private fun PlanCard(plan: Plan, title: String, badge: String?, trial: String?, isSelected: Boolean, onClick: () -> Unit) {
    val palette = LocalPalette.current
    val shape = RoundedCornerShape(22.dp)
    val borderColor by animateColorAsState(if (isSelected) palette.ink else palette.hairline.copy(alpha = 0.7f), label = "plan")
    Row(
        Modifier.fillMaxWidth().clip(shape).background(palette.surface).border(if (isSelected) 2.dp else 1.dp, borderColor, shape)
            .clickable(role = Role.RadioButton, onClick = onClick).semantics { selected = isSelected }.testTag("plan.${plan.kind.name.lowercase()}")
            .padding(18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        CheckCircle(isSelected, 26.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(title, style = Type.headline(), color = palette.ink)
                if (badge != null) {
                    Text(badge, style = Type.caption(FontWeight.ExtraBold), color = palette.inkInverse, modifier = Modifier.clip(CircleShape).background(palette.onTrack).padding(horizontal = 8.dp, vertical = 3.dp))
                }
            }
            if (trial != null) Text(trial, style = Type.subheadline(), color = palette.secondary)
        }
        Text(plan.billedLabel, style = Type.subheadline(FontWeight.Bold, tabular = true), color = palette.ink, textAlign = TextAlign.End)
    }
}
