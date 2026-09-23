import SwiftUI
@preconcurrency import RevenueCat

/// The full plan picker: yearly (selected) and monthly, both with a free trial
/// for people who have not had one.
struct PaywallView: View {
    @EnvironmentObject private var purchases: StoreService
    @Environment(\.dismiss) private var dismiss
    let surface: String
    @State private var selection: PlanKind = ScreenshotConfig.value(after: "-PaywallSnapshot") == "monthly" ? .monthly : .yearly

    private var selected: Package? {
        selection == .yearly ? purchases.yearly : purchases.monthly
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                IconButton(symbol: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shoes On Pro")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Text("Your first routine stays free. Pro adds the rest of your week.")
                            .font(.body)
                            .foregroundStyle(Theme.secondary)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        ProBenefit(symbol: "rectangle.stack.fill", title: "Every routine", detail: "Workdays, school runs, the gym, weekends. Each learns its own times.")
                        ProBenefit(symbol: "applewatch", title: "Apple Watch coach", detail: "Your step, the time left, and whether you're slipping. Tap Done from your wrist.")
                    }
                    VStack(spacing: 10) {
                        if let yearly = purchases.yearly {
                            PlanCard(package: yearly, title: "Yearly", badge: savingsBadge, trial: purchases.isEligibleForTrial(yearly) ? yearly.trialLabel : nil, isSelected: selection == .yearly) {
                                selection = .yearly
                            }
                        }
                        if let monthly = purchases.monthly {
                            PlanCard(package: monthly, title: "Monthly", badge: nil, trial: purchases.isEligibleForTrial(monthly) ? monthly.trialLabel : nil, isSelected: selection == .monthly) {
                                selection = .monthly
                            }
                        }
                        if purchases.packages.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
        .onAppear { purchases.trackPaywallImpression(id: surface) }
        .onChange(of: purchases.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    /// "Save 58%" against twelve months of the monthly price.
    private var savingsBadge: String? {
        guard let yearly = purchases.yearly, let monthly = purchases.monthly else { return nil }
        let year = NSDecimalNumber(decimal: yearly.storeProduct.price).doubleValue
        let month = NSDecimalNumber(decimal: monthly.storeProduct.price).doubleValue
        guard month > 0 else { return nil }
        let saving = Int(((1 - year / (month * 12)) * 100).rounded())
        return saving >= 10 ? "Save \(saving)%" : nil
    }

    private var isTrial: Bool {
        guard let selected else { return false }
        return purchases.isEligibleForTrial(selected)
    }

    private var purchaseBar: some View {
        VStack(spacing: 8) {
            if let message = purchases.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.late)
                    .multilineTextAlignment(.center)
            }
            if let selected {
                Text(isTrial ? "Free for 7 days, then \(selected.billedLabel)" : selected.billedLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text("Renews automatically unless cancelled at least 24 hours before the \(isTrial ? "trial" : "period") ends. Manage in Settings > Apple Account > Subscriptions.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                guard let selected else { return }
                Task { _ = await purchases.purchase(selected) }
            } label: {
                ZStack {
                    Text(isTrial ? "Start 7-day free trial" : "Subscribe").opacity(purchases.isPurchasing ? 0 : 1)
                    if purchases.isPurchasing { ProgressView().tint(Theme.inkInverse) }
                }
            }
            .buttonStyle(.primary)
            .disabled(purchases.isPurchasing || selected == nil)
            OnboardingLegalFooter(isRestoring: purchases.isPurchasing) {
                Task { await purchases.restore() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.background)
    }
}

private struct PlanCard: View {
    let package: Package
    let title: String
    let badge: String?
    let trial: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.ink : Theme.hairline)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Theme.inkInverse)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.onTrack, in: Capsule())
                        }
                    }
                    if let trial {
                        Text(trial)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
                Text(package.billedLabel)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.trailing)
            }
            .padding(18)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isSelected ? Theme.ink : Theme.hairline.opacity(0.7), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The enjoyment gate. Apple's prompt only follows a yes.
struct ReviewPromptView: View {
    @EnvironmentObject private var review: ReviewPromptService
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Text("Is Shoes On helping you get out the door?")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 28)
            VStack(spacing: 4) {
                Button("Yes, it is") {
                    review.markRated()
                    requestReview()
                }
                .buttonStyle(.primary)
                Button("Not really") {
                    review.markDeferred()
                    openURL(URL(string: "mailto:jackwallner@gmail.com?subject=Shoes%20On%20feedback")!)
                }
                .buttonStyle(.secondary)
                Button("Maybe later") { review.markDeferred() }
                    .buttonStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .presentationDetents([.height(300)])
        .background(Theme.background.ignoresSafeArea())
    }
}
