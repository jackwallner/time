package com.jackwallner.time.data

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.time.BuildConfig
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesException
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.models.Period
import com.revenuecat.purchases.paywalls.events.CustomPaywallImpressionParams
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.roundToInt

/** Must match App Store Connect and the Play subscriptions exactly. */
object ShoesOnProduct {
    const val YEARLY = "com.jackwallner.time.yearly"
    const val MONTHLY = "com.jackwallner.time.monthly"
}

enum class PlanKind { YEARLY, MONTHLY, OTHER }

enum class PurchaseOutcome { PURCHASED, CANCELLED, PENDING, FAILED }

/** One plan on the paywall, with the price and trial straight from the store. */
data class Plan(
    val packageId: String,
    val productId: String,
    val kind: PlanKind,
    val priceFormatted: String,
    val priceMicros: Long,
    /** Free trial length in days, when the plan carries one. */
    val trialDays: Int?,
) {
    /** "$9.99 per year". */
    val billedLabel: String
        get() = when (kind) {
            PlanKind.YEARLY -> "$priceFormatted per year"
            PlanKind.MONTHLY -> "$priceFormatted per month"
            PlanKind.OTHER -> priceFormatted
        }

    /** "7-day free trial". */
    val trialLabel: String? get() = trialDays?.let { "$it-day free trial" }

    companion object {
        /** Same prices and trial as `ShoesOn.storekit`, for debug runs with no store key. */
        val fixtures = listOf(
            Plan("\$rc_annual", ShoesOnProduct.YEARLY, PlanKind.YEARLY, "$9.99", 9_990_000, 7),
            Plan("\$rc_monthly", ShoesOnProduct.MONTHLY, PlanKind.MONTHLY, "$1.99", 1_990_000, 7),
        )

        /** "Save 58%" against twelve months of the monthly price. */
        fun savingsBadge(yearly: Plan?, monthly: Plan?): String? {
            if (yearly == null || monthly == null || monthly.priceMicros <= 0) return null
            val saving = ((1 - yearly.priceMicros.toDouble() / (monthly.priceMicros * 12)) * 100).roundToInt()
            return if (saving >= 10) "Save $saving%" else null
        }
    }
}

/**
 * Shoes On Pro: a yearly or monthly subscription, both with a one-week free
 * trial, behind the single `pro` entitlement. Debug builds use the RevenueCat
 * Test Store key, or fixture plans with purchases off when none is set (the
 * iOS simulator does the same with StoreKit Testing). Release builds use the
 * Play key only.
 */
class StoreService(
    private val context: Context,
    private val defaults: KeyValueStore,
    private val diagnostics: ConversionDiagnostics,
) {
    private var entitlementActive by mutableStateOf(defaults.getBoolean(CACHED_PRO))
    private var overrideActive by mutableStateOf(BuildConfig.DEBUG && defaults.getBoolean(LOCAL_OVERRIDE))

    /** Fired when Pro flips, so every surface can refresh. */
    var onProChanged: () -> Unit = {}

    /** The one gate the app reads. */
    val isPro: Boolean get() = entitlementActive || overrideActive

    var plans by mutableStateOf<List<Plan>>(emptyList())
        private set
    var isLoadingProducts by mutableStateOf(false)
        private set
    var hasTriedLoading by mutableStateOf(false)
        private set
    var isPurchasing by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    /** Trial copy stays hidden until resolved, so a used trial is never promised again. */
    var introEligibilityResolved by mutableStateOf(false)
        private set
    private var hasSubscriptionHistory by mutableStateOf(false)
    var activeProductId by mutableStateOf<String?>(null)
        private set

    var isConfigured = false
        private set
    private var packages: List<Package> = emptyList()
    private var offering: Offering? = null
    private val impressionsThisSession = mutableSetOf<String>()

    val yearly: Plan? get() = plans.firstOrNull { it.kind == PlanKind.YEARLY }
    val monthly: Plan? get() = plans.firstOrNull { it.kind == PlanKind.MONTHLY }

    /** True once loading finished without plans, so a paywall offers a retry. */
    val plansUnavailable: Boolean get() = plans.isEmpty() && !isLoadingProducts && hasTriedLoading

    fun isEligibleForTrial(plan: Plan): Boolean = plan.trialDays != null && introEligibilityResolved && !hasSubscriptionHistory

    suspend fun start() {
        if (!configureIfNeeded()) {
            loadFixturePlans()
            return
        }
        refreshStatus()
        loadOffering()
    }

    /** Tries the plans again after a failed load. */
    suspend fun reloadProducts() {
        if (plans.isNotEmpty() || isLoadingProducts) return
        errorMessage = null
        if (!isConfigured) loadFixturePlans() else loadOffering()
    }

    suspend fun purchase(activity: Activity, plan: Plan): PurchaseOutcome {
        val pkg = packages.firstOrNull { it.identifier == plan.packageId }
        if (!isConfigured || pkg == null) {
            errorMessage = "Purchases aren't available right now. Check your connection and try again."
            return PurchaseOutcome.FAILED
        }
        isPurchasing = true
        val startedTrial = isEligibleForTrial(plan)
        try {
            val option = if (startedTrial) pkg.product.defaultOption else pkg.product.subscriptionOptions?.basePlan
            val params = if (option != null) {
                PurchaseParams.Builder(activity, option).presentedOfferingContext(pkg.presentedOfferingContext).build()
            } else {
                PurchaseParams.Builder(activity, pkg).build()
            }
            val result = Purchases.sharedInstance.awaitPurchase(params)
            apply(result.customerInfo)
            if (!entitlementActive) {
                errorMessage = "Waiting on Google Play to confirm this purchase. Pro turns on by itself once it goes through."
                return PurchaseOutcome.PENDING
            }
            diagnostics.recordConversion(plan.productId, startedTrial, pkg.presentedOfferingContext.offeringIdentifier)
            syncConversionAttributes()
            if (startedTrial) plan.trialDays?.let { TrialReminder.schedule(context, it, plan.billedLabel) }
            errorMessage = null
            return PurchaseOutcome.PURCHASED
        } catch (error: CancellationException) {
            throw error
        } catch (error: PurchasesTransactionException) {
            if (error.userCancelled || error.code == PurchasesErrorCode.PurchaseCancelledError) return PurchaseOutcome.CANCELLED
            if (error.code == PurchasesErrorCode.PaymentPendingError) {
                errorMessage = "Waiting on Google Play to confirm this purchase. Pro turns on by itself once it goes through."
                return PurchaseOutcome.PENDING
            }
            errorMessage = if (startedTrial) "Couldn't start your trial. Please try again." else "Couldn't complete the purchase. Please try again."
            return PurchaseOutcome.FAILED
        } catch (_: Throwable) {
            errorMessage = if (startedTrial) "Couldn't start your trial. Please try again." else "Couldn't complete the purchase. Please try again."
            return PurchaseOutcome.FAILED
        } finally {
            isPurchasing = false
        }
    }

    suspend fun restore() {
        if (!isConfigured) {
            errorMessage = "Purchases aren't available right now. Check your connection and try again."
            return
        }
        isPurchasing = true
        try {
            apply(Purchases.sharedInstance.awaitRestore())
            errorMessage = if (isPro) null else "No Shoes On Pro subscription was found for this Google Play account."
        } catch (error: CancellationException) {
            throw error
        } catch (_: PurchasesException) {
            errorMessage = "Restore failed. Please try again."
        } catch (_: Throwable) {
            errorMessage = "Restore failed. Please try again."
        } finally {
            isPurchasing = false
        }
    }

    fun clearError() {
        errorMessage = null
    }

    /** Reports a visible paywall to RevenueCat; a custom paywall emits none of its own. */
    fun trackPaywallImpression(id: String, oncePerSession: Boolean = false) {
        if (oncePerSession && !impressionsThisSession.add(id)) return
        diagnostics.recordPitchView(id)
        if (!isConfigured) return
        syncConversionAttributes()
        val params = offering?.let { CustomPaywallImpressionParams(id, it) } ?: CustomPaywallImpressionParams(id)
        runCatching { Purchases.sharedInstance.trackCustomPaywallImpression(params) }
    }

    fun syncConversionAttributes() {
        if (!isConfigured) return
        val attributes = diagnostics.subscriberAttributes
        if (attributes.isEmpty()) return
        runCatching { Purchases.sharedInstance.setAttributes(attributes) }
    }

    /** Debug only: Pro on or off without a store. Release builds ignore it. */
    fun setLocalOverride(value: Boolean) {
        if (!BuildConfig.DEBUG) return
        val before = isPro
        defaults.putBoolean(LOCAL_OVERRIDE, value)
        overrideActive = value
        if (before != isPro) onProChanged()
    }

    private suspend fun refreshStatus() {
        runCatching { Purchases.sharedInstance.awaitCustomerInfo() }
            .onSuccess(::apply)
            .onFailure { if (it is CancellationException) throw it }
    }

    private suspend fun loadOffering() {
        isLoadingProducts = true
        try {
            val offerings = Purchases.sharedInstance.awaitOfferings()
            val offering = offerings.all[OFFERING_ID] ?: offerings.current
            val loaded = offering?.availablePackages.orEmpty().filter { kind(it) != PlanKind.OTHER }.sortedBy { kind(it).ordinal }
            this.offering = offering
            packages = loaded
            plans = loaded.map(::plan)
            introEligibilityResolved = true
            if (loaded.isEmpty()) errorMessage = "Couldn't load plans. Check your connection and try again."
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            errorMessage = "Couldn't load plans. Check your connection and try again."
        } finally {
            isLoadingProducts = false
            hasTriedLoading = true
        }
    }

    /** Debug builds with no store key draw the real paywall from fixtures; purchases stay off. */
    private fun loadFixturePlans() {
        if (!BuildConfig.DEBUG) {
            hasTriedLoading = true
            errorMessage = "Couldn't load plans. Check your connection and try again."
            return
        }
        plans = Plan.fixtures
        introEligibilityResolved = true
        hasTriedLoading = true
    }

    private fun apply(info: CustomerInfo) {
        val before = isPro
        entitlementActive = info.entitlements[ENTITLEMENT]?.isActive == true
        defaults.putBoolean(CACHED_PRO, entitlementActive)
        hasSubscriptionHistory = info.allExpirationDatesByProduct.isNotEmpty()
        activeProductId = info.activeSubscriptions.map { it.substringBefore(":") }.sorted().firstOrNull()
        if (before != isPro) onProChanged()
    }

    private fun configureIfNeeded(): Boolean {
        if (isConfigured) return true
        val key = BuildConfig.REVENUECAT_API_KEY
        if (key.isBlank()) return false
        // Never the production Play key in a debug build, and never a test key in release.
        if (BuildConfig.DEBUG && key.startsWith("goog_")) return false
        if (!BuildConfig.DEBUG && !key.startsWith("goog_")) return false
        Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.ERROR
        Purchases.configure(PurchasesConfiguration.Builder(context, key).build())
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { apply(it) }
        isConfigured = true
        return true
    }

    private fun kind(pkg: Package): PlanKind = when (pkg.packageType) {
        PackageType.ANNUAL -> PlanKind.YEARLY
        PackageType.MONTHLY -> PlanKind.MONTHLY
        else -> when (pkg.product.id.substringBefore(":")) {
            ShoesOnProduct.YEARLY -> PlanKind.YEARLY
            ShoesOnProduct.MONTHLY -> PlanKind.MONTHLY
            else -> PlanKind.OTHER
        }
    }

    private fun plan(pkg: Package): Plan {
        val free = pkg.product.subscriptionOptions?.firstOrNull { it.freePhase != null }?.freePhase
            ?: pkg.product.defaultOption?.freePhase
        return Plan(
            packageId = pkg.identifier,
            productId = pkg.product.id,
            kind = kind(pkg),
            priceFormatted = pkg.product.price.formatted,
            priceMicros = pkg.product.price.amountMicros,
            trialDays = free?.billingPeriod?.days(),
        )
    }

    private fun Period.days(): Int? = when (unit) {
        Period.Unit.DAY -> value
        Period.Unit.WEEK -> value * 7
        Period.Unit.MONTH -> value * 30
        Period.Unit.YEAR -> value * 365
        else -> null
    }

    companion object {
        const val ENTITLEMENT = "pro"
        const val OFFERING_ID = "default"
        private const val CACHED_PRO = "cachedIsPro"
        private const val LOCAL_OVERRIDE = "subscription.localProOverride"

        fun manageSubscriptionURL(productId: String?): String {
            val base = "https://play.google.com/store/account/subscriptions"
            return if (productId == null) base else "$base?sku=$productId&package=com.jackwallner.time"
        }
    }
}
