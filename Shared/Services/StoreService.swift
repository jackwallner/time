import Foundation
import os
import StoreKit
@preconcurrency import RevenueCat

enum RevenueCatConfig {
    /// Public iOS SDK key. Secret `sk_` keys must never ship in an app binary.
    static let publicSDKKey = "appl_YAoAYFbyLEQtALNYsWCLuuaMDai"
    /// Lookup key of the one entitlement.
    static let proEntitlement = "pro"
}

/// Must match `ShoesOn.storekit` and App Store Connect exactly.
enum ShoesOnProduct {
    static let yearly = "com.jackwallner.time.yearly"
    static let monthly = "com.jackwallner.time.monthly"
    static let all: Set<String> = [yearly, monthly]
}

enum PurchaseOutcome {
    case purchased
    case cancelled
    case pending
    case failed
}

/// How a purchase that threw is shown. RevenueCat reports Ask to Buy as an
/// error, but a request waiting on a parent is not a failure, and a lost
/// connection is not a reason to try a different card.
enum PurchaseFailure: Equatable {
    case cancelled
    /// Ask to Buy: Apple holds the request until it is approved, then the
    /// customer-info update unlocks Pro without a relaunch.
    case pending
    case offline
    case failed

    static let pendingMessage = "Waiting for approval. Your purchase unlocks once it is approved."
    static let offlineMessage = "Purchases aren't available right now. Check your connection and try again."

    /// RevenueCat's errors also arrive bridged to an NSError in this domain.
    private static let revenueCatDomain = (ErrorCode.unknownError as NSError).domain

    init(_ error: Error) {
        let bridged = error as NSError
        let code = (error as? ErrorCode)
            ?? (bridged.domain == Self.revenueCatDomain ? ErrorCode(rawValue: bridged.code) : nil)
        guard let code else {
            self = .failed
            return
        }
        switch code {
        case .purchaseCancelledError: self = .cancelled
        case .paymentPendingError: self = .pending
        case .networkError, .offlineConnectionError: self = .offline
        default: self = .failed
        }
    }

    /// The line under the button. Nil for a cancel, which needs none.
    func message(startedTrial: Bool) -> String? {
        switch self {
        case .cancelled: nil
        case .pending: Self.pendingMessage
        case .offline: Self.offlineMessage
        case .failed:
            startedTrial ? "Couldn't start your trial. Please try again." : "Couldn't complete the purchase. Please try again."
        }
    }
}

enum PlanKind: Int, Comparable {
    case yearly = 0
    case monthly = 1
    case other = 2

    init(_ package: Package) {
        switch package.packageType {
        case .annual: self = .yearly
        case .monthly: self = .monthly
        default:
            let id = package.storeProduct.productIdentifier
            self = id == ShoesOnProduct.yearly ? .yearly : id == ShoesOnProduct.monthly ? .monthly : .other
        }
    }

    static func < (lhs: PlanKind, rhs: PlanKind) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension Package {
    var plan: PlanKind { PlanKind(self) }

    /// "$9.99 per year".
    var billedLabel: String {
        let price = storeProduct.localizedPriceString
        switch plan {
        case .yearly: return "\(price) per year"
        case .monthly: return "\(price) per month"
        case .other: return price
        }
    }

    /// "7-day free trial", when the product carries a free trial at all.
    var trialLabel: String? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else { return nil }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day: return "\(period.value)-day free trial"
        case .week: return "\(period.value * 7)-day free trial"
        case .month: return "\(period.value)-month free trial"
        case .year: return "\(period.value)-year free trial"
        @unknown default: return nil
        }
    }

    /// Length of the free trial in days, for the transparency timeline.
    var trialDays: Int? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else { return nil }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }
}

/// Shoes On Pro: a yearly or monthly subscription, both with a one-week free
/// trial. RevenueCat carries them so the fleet's charts and funnel attributes
/// work the same as everywhere else.
@MainActor
final class StoreService: NSObject, ObservableObject, PurchasesDelegate {
    static let shared = StoreService()

    private static let cachedProKey = "cachedIsPro"

    @Published private(set) var isPro = false {
        didSet {
            guard oldValue != isPro else { return }
            defaults.set(isPro, forKey: Self.cachedProKey)
            RoutineStore.shared.propagate()
        }
    }
    @Published private(set) var packages: [Package] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var hasTriedLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var errorMessage: String?
    /// An Ask to Buy request is with a parent. Shown as a calm line, never as
    /// an error, and dropped when the screen that raised it closes.
    @Published private(set) var awaitingApproval = false
    /// Per-product trial eligibility. Trial copy stays hidden until resolved, so
    /// someone who already used a trial is never promised one (Apple 3.1.2).
    @Published private(set) var introEligibility: [String: Bool] = [:]
    @Published private(set) var introEligibilityResolved = false
    /// The current offering's metadata (`RemoteConfig`). Nil until offerings
    /// load, and always on a simulator, which reads as every control.
    @Published private(set) var remoteMetadata: [String: String]?

    private let logger = Logger(subsystem: AppGroup.subsystem, category: "Store")
    private let defaults = AppGroup.defaults
    private var isConfigured = false
    private var impressionsThisSession: Set<String> = []

    private override init() {
        // Seed the cache before super.init so didSet never runs inside the
        // shared singleton's own first-use initialization.
        _isPro = Published(initialValue: AppGroup.defaults.bool(forKey: Self.cachedProKey))
        super.init()
    }

    var yearly: Package? { packages.first { $0.plan == .yearly } }
    var monthly: Package? { packages.first { $0.plan == .monthly } }

    func isEligibleForTrial(_ package: Package) -> Bool {
        guard package.trialLabel != nil, introEligibilityResolved else { return false }
        return introEligibility[package.storeProduct.productIdentifier] ?? false
    }

    func start() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DemoPro") {
            isPro = true
        }
        #endif
        configureIfNeeded()
        guard isConfigured else {
            #if targetEnvironment(simulator)
            // StoreKit Testing serves ShoesOn.storekit under the Xcode scheme and
            // `xcodebuild test`, so the real paywall renders without ever
            // configuring RevenueCat on a simulator.
            Task { await loadSimulatorProducts() }
            #endif
            return
        }
        Task {
            await refreshStatus()
            await loadOffering()
        }
    }

    /// True once loading has finished without any plans, so a paywall can
    /// offer a retry instead of a spinner that never ends.
    var plansUnavailable: Bool { packages.isEmpty && !isLoadingProducts && hasTriedLoading }

    /// Tries the plans again after a failed load, from a paywall's retry.
    func reloadProducts() {
        guard packages.isEmpty, !isLoadingProducts else { return }
        errorMessage = nil
        Task {
            guard isConfigured else {
                #if targetEnvironment(simulator)
                await loadSimulatorProducts()
                #endif
                return
            }
            await loadOffering()
        }
    }

    func purchase(_ package: Package) async -> PurchaseOutcome {
        guard isConfigured else {
            errorMessage = PurchaseFailure.offlineMessage
            return .failed
        }
        awaitingApproval = false
        isPurchasing = true
        defer { isPurchasing = false }
        let startedTrial = isEligibleForTrial(package)
        do {
            let result = try await Purchases.shared.purchase(package: package)
            update(customerInfo: result.customerInfo)
            if result.userCancelled { return .cancelled }
            if isPro {
                ConversionDiagnostics.recordConversion(
                    plan: package.storeProduct.productIdentifier,
                    startedTrial: startedTrial,
                    offeringID: package.presentedOfferingContext.offeringIdentifier
                )
                syncConversionAttributes()
                if startedTrial, let days = package.trialDays {
                    NotificationService.shared.scheduleTrialReminder(trialDays: days, billed: package.billedLabel)
                }
                errorMessage = nil
                return .purchased
            }
            errorMessage = "Waiting on Apple to confirm this purchase. Pro turns on by itself once it goes through."
            return .pending
        } catch {
            let failure = PurchaseFailure(error)
            switch failure {
            case .cancelled:
                return .cancelled
            case .pending:
                logger.info("Purchase waiting for Ask to Buy approval")
                errorMessage = nil
                awaitingApproval = true
                return .pending
            case .offline, .failed:
                errorMessage = failure.message(startedTrial: startedTrial)
                return .failed
            }
        }
    }

    func restore() async {
        guard isConfigured else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            update(customerInfo: try await Purchases.shared.restorePurchases())
            errorMessage = isPro ? nil : "No Shoes On Pro subscription was found for this Apple ID."
        } catch {
            errorMessage = "Restore failed. Please try again."
        }
    }

    func clearError() {
        errorMessage = nil
        awaitingApproval = false
    }

    /// The screen that raised an Ask to Buy closed. Approval still unlocks
    /// Pro through the customer-info update; only the line goes.
    func clearPendingApproval() {
        guard !isPurchasing else { return }
        awaitingApproval = false
    }

    /// Reports a visible paywall to RevenueCat. `oncePerSession` dedupes
    /// surfaces the user can revisit.
    func trackPaywallImpression(id: String, oncePerSession: Bool = false) {
        guard isConfigured else { return }
        if oncePerSession {
            guard !impressionsThisSession.contains(id) else { return }
            impressionsThisSession.insert(id)
        }
        ConversionDiagnostics.recordPitchView(impressionID: id)
        syncConversionAttributes()
        Purchases.shared.trackCustomPaywallImpression(CustomPaywallImpressionParams(paywallId: id))
    }

    /// Mirrors the on-device funnel record onto the RevenueCat customer.
    /// `isConfigured` is load-bearing: `Purchases.shared` traps when
    /// RevenueCat was never configured, which is every simulator run.
    func syncConversionAttributes() {
        guard isConfigured else { return }
        var attributes = ConversionDiagnostics.subscriberAttributes
        guard !attributes.isEmpty else { return }
        // The wording this customer's trial button showed, so a test reads
        // by attribute too.
        attributes[TrialCTA.metadataKey] = trialCTA.rawValue
        Purchases.shared.attribution.setAttributes(attributes)
    }

    var trialCTA: TrialCTA { TrialCTA.from(metadata: remoteMetadata.map { $0 as [String: Any] }) }

    func isOn(_ remoteSwitch: RemoteSwitch) -> Bool {
        RemoteConfig.isOn(remoteSwitch, in: remoteMetadata.map { $0 as [String: Any] })
    }

    #if DEBUG
    func setLocalOverride(isPro: Bool) {
        self.isPro = isPro
    }
    #endif

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in self.update(customerInfo: customerInfo) }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        #if targetEnvironment(simulator)
        // Agent and simulator runs must never reach the production RevenueCat
        // project: a configure there creates a fake customer in live charts.
        return
        #else
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.publicSDKKey)
        Purchases.shared.delegate = self
        isConfigured = true
        #endif
    }

    private func refreshStatus() async {
        do {
            update(customerInfo: try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent))
        } catch {
            logger.error("Status refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadOffering() async {
        isLoadingProducts = true
        defer {
            isLoadingProducts = false
            hasTriedLoading = true
        }
        do {
            let offerings = try await Purchases.shared.offerings()
            // The current offering, so a running Experiment's variant is read.
            remoteMetadata = (offerings.current?.metadata ?? [:]).compactMapValues { $0 as? String }
            syncConversionAttributes()
            let offering = offerings.offering(identifier: "default") ?? offerings.current
            let loaded = (offering?.availablePackages ?? [])
                .filter { $0.plan != .other }
                .sorted { $0.plan < $1.plan }
            // Eligibility is resolved before the plans are published, so a
            // paywall never draws the paid copy and then flips to the trial.
            let eligibility = await introEligibility(for: loaded)
            packages = loaded
            introEligibility = eligibility
            introEligibilityResolved = true
        } catch {
            logger.error("Offering load failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't load plans. Check your connection and try again."
        }
    }

    /// Per-product trial eligibility. Anything unknown reads as ineligible, so
    /// trial copy hides rather than over-promises.
    private func introEligibility(for packages: [Package]) async -> [String: Bool] {
        let ids = packages.filter { $0.trialLabel != nil }.map(\.storeProduct.productIdentifier)
        guard !ids.isEmpty else { return [:] }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: ids)
        return result.mapValues { $0.status == .eligible }
    }

    private func update(customerInfo: CustomerInfo) {
        let pro = customerInfo.entitlements.active[RevenueCatConfig.proEntitlement]
        isPro = pro != nil
        if isPro { awaitingApproval = false }
        if pro?.willRenew != true { NotificationService.shared.cancelTrialReminder() }
    }

    #if targetEnvironment(simulator)
    /// Hydrates the packages on the simulator so the real paywall can be
    /// rendered and inspected. Purchases stay disabled: this exists to make the
    /// layout verifiable, not to fake a sale.
    private func loadSimulatorProducts() async {
        isLoadingProducts = true
        defer {
            isLoadingProducts = false
            hasTriedLoading = true
        }
        var products: [StoreProduct] = []
        if let live = try? await StoreKit.Product.products(for: ShoesOnProduct.all), !live.isEmpty {
            products = live.map { StoreProduct(sk2Product: $0) }
        } else {
            products = Self.fixtureProducts()
        }
        packages = products.map { product in
            let isYearly = product.productIdentifier == ShoesOnProduct.yearly
            return Package(
                identifier: isYearly ? "$rc_annual" : "$rc_monthly",
                packageType: isYearly ? .annual : .monthly,
                storeProduct: product,
                offeringIdentifier: "default",
                webCheckoutUrl: nil
            )
        }
        .sorted { $0.plan < $1.plan }
        introEligibility = Dictionary(uniqueKeysWithValues: packages.map { ($0.storeProduct.productIdentifier, true) })
        introEligibilityResolved = true
    }

    /// Same prices and trial as `ShoesOn.storekit`, for plain `simctl` launches.
    private static func fixtureProducts() -> [StoreProduct] {
        let locale = Locale(identifier: "en_US")
        func trial() -> TestStoreProductDiscount {
            TestStoreProductDiscount(
                identifier: "free_trial", price: 0, localizedPriceString: "$0.00",
                paymentMode: .freeTrial, subscriptionPeriod: .init(value: 1, unit: .week),
                numberOfPeriods: 1, type: .introductory
            )
        }
        return [
            TestStoreProduct(
                localizedTitle: "Shoes On Pro Yearly", price: 9.99, currencyCode: "USD",
                localizedPriceString: "$9.99", productIdentifier: ShoesOnProduct.yearly,
                productType: .autoRenewableSubscription, localizedDescription: "Every routine and the Apple Watch coach.",
                subscriptionPeriod: .init(value: 1, unit: .year), introductoryDiscount: trial(), locale: locale
            ).toStoreProduct(),
            TestStoreProduct(
                localizedTitle: "Shoes On Pro Monthly", price: 1.99, currencyCode: "USD",
                localizedPriceString: "$1.99", productIdentifier: ShoesOnProduct.monthly,
                productType: .autoRenewableSubscription, localizedDescription: "Every routine and the Apple Watch coach.",
                subscriptionPeriod: .init(value: 1, unit: .month), introductoryDiscount: trial(), locale: locale
            ).toStoreProduct(),
        ]
    }
    #endif
}
