import SwiftUI

/// The one purchase: Shoes On Pro, once, for good.
struct PaywallView: View {
    @EnvironmentObject private var purchases: StoreService
    @Environment(\.dismiss) private var dismiss
    let surface: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shoes On Pro")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Theme.ink)
                        Text("Your first routine stays free. Pro adds the rest of your week.")
                            .font(.title3)
                            .foregroundStyle(Theme.secondary)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        benefit("square.stack", "Every routine", "Workdays, school runs, the gym, Sunday brunch. Each one learns its own times.")
                        benefit("applewatch", "Apple Watch coach", "The step you're on, the time left, and whether you're slipping. Tap Done from your wrist.")
                        benefit("checkmark.seal", "Pay once", "No subscription. It's yours.")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
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

    private var purchaseBar: some View {
        VStack(spacing: 10) {
            if let message = purchases.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.late)
                    .multilineTextAlignment(.center)
            }
            Text(priceLine)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Button {
                Task { _ = await purchases.purchase() }
            } label: {
                ZStack {
                    Text("Unlock Pro").opacity(purchases.isPurchasing ? 0 : 1)
                    if purchases.isPurchasing { ProgressView().tint(Theme.inkInverse) }
                }
            }
            .buttonStyle(.primary)
            .disabled(purchases.isPurchasing || purchases.lifetimePackage == nil)
            OnboardingLegalFooter(isRestoring: purchases.isPurchasing) {
                Task { await purchases.restore() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.background)
    }

    private var priceLine: String {
        guard let price = purchases.priceLabel else { return "Loading price…" }
        return "\(price) once. No subscription."
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .accessibilityElement(children: .combine)
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
                .font(.title3.bold())
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
