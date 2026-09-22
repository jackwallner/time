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
    static let lifetime = "com.jackwallner.time.pro.lifetime"
}

enum PurchaseOutcome {
    case purchased
    case cancelled
    case pending
    case failed
}

/// Shoes On Pro is one non-consumable. RevenueCat still carries it, so the
/// fleet's conversion charts and funnel attributes work the same as elsewhere.
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
    @Published private(set) var lifetimePackage: Package?
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var errorMessage: String?

    private let logger = Logger(subsystem: AppGroup.subsystem, category: "Store")
    private let defaults = AppGroup.defaults
    private var isConfigured = false
    private var impressionsThisSession: Set<String> = []

    private override init() {
        super.init()
        isPro = defaults.bool(forKey: Self.cachedProKey)
    }

    /// Localized price, or nil until the product loads. Never hard-coded.
    var priceLabel: String? { lifetimePackage?.storeProduct.localizedPriceString }

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
            Task { await loadSimulatorProduct() }
            #endif
            return
        }
        Task {
            await refreshStatus()
            await loadOffering()
        }
    }

    func purchase() async -> PurchaseOutcome {
        guard isConfigured, let package = lifetimePackage else {
            errorMessage = "The purchase isn't available right now. Check your connection and try again."
            return .failed
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            update(customerInfo: result.customerInfo)
            if result.userCancelled { return .cancelled }
            if isPro {
                ConversionDiagnostics.recordConversion(
                    plan: package.storeProduct.productIdentifier,
                    startedTrial: false,
                    offeringID: package.presentedOfferingContext.offeringIdentifier
                )
                syncConversionAttributes()
                errorMessage = nil
                return .purchased
            }
            errorMessage = "Waiting on Apple to confirm this purchase. Pro turns on by itself once it goes through."
            return .pending
        } catch {
            let nsError = error as NSError
            if nsError.code == ErrorCode.purchaseCancelledError.rawValue { return .cancelled }
            errorMessage = "Couldn't complete the purchase. Please try again."
            return .failed
        }
    }

    func restore() async {
        guard isConfigured else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            update(customerInfo: try await Purchases.shared.restorePurchases())
            errorMessage = isPro ? nil : "No Shoes On Pro purchase was found for this Apple ID."
        } catch {
            errorMessage = "Restore failed. Please try again."
        }
    }

    func clearError() {
        errorMessage = nil
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
        let attributes = ConversionDiagnostics.subscriberAttributes
        guard !attributes.isEmpty else { return }
        Purchases.shared.attribution.setAttributes(attributes)
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
        guard RevenueCatConfig.publicSDKKey.hasPrefix("appl_"),
              !RevenueCatConfig.publicSDKKey.contains("REPLACE") else { return }
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
        defer { isLoadingProducts = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.offering(identifier: "default") ?? offerings.current
            lifetimePackage = offering?.lifetime
                ?? offering?.availablePackages.first { $0.storeProduct.productIdentifier == ShoesOnProduct.lifetime }
        } catch {
            logger.error("Offering load failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't load the purchase. Check your connection and try again."
        }
    }

    private func update(customerInfo: CustomerInfo) {
        isPro = customerInfo.entitlements.active[RevenueCatConfig.proEntitlement] != nil
    }

    #if targetEnvironment(simulator)
    /// Hydrates the package on the simulator so the real paywall can be
    /// rendered and inspected. Purchases stay disabled: this exists to make the
    /// layout verifiable, not to fake a sale.
    private func loadSimulatorProduct() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        var product: StoreProduct?
        if let live = try? await StoreKit.Product.products(for: [ShoesOnProduct.lifetime]).first {
            product = StoreProduct(sk2Product: live)
        }
        let resolved = product ?? TestStoreProduct(
            localizedTitle: "Shoes On Pro",
            price: 14.99,
            currencyCode: "USD",
            localizedPriceString: "$14.99",
            productIdentifier: ShoesOnProduct.lifetime,
            productType: .nonConsumable,
            localizedDescription: "Every routine and the Apple Watch coach, forever.",
            subscriptionPeriod: nil,
            introductoryDiscount: nil,
            locale: Locale(identifier: "en_US")
        ).toStoreProduct()
        lifetimePackage = Package(
            identifier: "$rc_lifetime",
            packageType: .lifetime,
            storeProduct: resolved,
            offeringIdentifier: "default",
            webCheckoutUrl: nil
        )
    }
    #endif
}
