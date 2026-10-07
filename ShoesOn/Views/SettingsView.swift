import ActivityKit
import StoreKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: RoutineStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var purchases: StoreService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showPaywall = false
    @State private var confirmReset = false
    @State private var notificationsDenied = false
    @State private var liveActivitiesOff = false
    @State private var showManageSubscription = false
    @State private var restoreMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                paceSection
                alertsSection
                proSection
                Section {
                    Button("Rate Shoes On") { openURL(AppStoreReviewLinks.writeReviewURL) }
                    Link("Send feedback", destination: URL(string: "mailto:jackwallner@gmail.com?subject=Shoes%20On")!)
                    Link("Help and support", destination: ShoesOnLinks.support)
                    Link("Privacy Policy", destination: ShoesOnLinks.privacyPolicy)
                    Link("Terms of Use", destination: ShoesOnLinks.standardEULA)
                }
                Section {
                    Button("Forget my real times", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Shoes On is a planning tool, not medical advice, and does not diagnose or treat any condition.\n\nShoes On \(Bundle.main.appVersionLabel). Everything stays on this iPhone.")
                }
                #if DEBUG
                Section("Debug") {
                    Toggle("Pro", isOn: Binding(
                        get: { purchases.isPro },
                        set: { purchases.setLocalOverride(isPro: $0) }
                    ))
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Forget your real times?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Forget", role: .destructive) { store.resetLearning() }
            } message: {
                Text("Plans go back to your guesses adjusted for your pace. Routines stay.")
            }
            .sheet(isPresented: $showPaywall) { PaywallView(surface: "shoeson_settings") }
            .alert(restoreMessage ?? "", isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscription)
            .task { await refreshPermissions() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await refreshPermissions() }
            }
        }
        .tint(Theme.ink)
    }

    private var paceSection: some View {
        Section {
            Picker("An hour really takes", selection: Binding(
                get: { store.state.pace },
                set: { store.setPace($0) }
            )) {
                ForEach(PaceAnswer.allCases) { answer in
                    Text(answer.title).tag(answer)
                }
            }
            .pickerStyle(.navigationLink)
            LabeledContent("Your pace so far", value: Format.multiplier(store.calibration.pace))
            LabeledContent("Timed steps", value: "\(store.calibration.pacedStepCount)")
        } header: {
            Text("Your pace")
        } footer: {
            Text("Your answer sets the starting point. Each step you time moves the pace toward how long things really take you.")
        }
    }

    /// Re-read on return from the Settings app, so the fix shows at once.
    private func refreshPermissions() async {
        notificationsDenied = await NotificationService.shared.authorizationStatus() == .denied
        liveActivitiesOff = !ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private var alertsSection: some View {
        Section {
            if notificationsDenied {
                settingsLink("Turn on notifications in Settings", systemImage: "bell.slash") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            }
            if liveActivitiesOff {
                settingsLink("Turn on Live Activities in Settings", systemImage: "rectangle.badge.xmark") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Toggle("Time to get ready", isOn: $settings.startAlerts)
                .toggleStyle(SwitchToggleStyle(tint: Theme.onTrack))
                .disabled(notificationsDenied)
            Toggle("Leave in 10 minutes, and time to go", isOn: $settings.leaveAlerts)
                .toggleStyle(SwitchToggleStyle(tint: Theme.onTrack))
                .disabled(notificationsDenied)
            Toggle("Nudges when a step runs over", isOn: $settings.stepNudges)
                .toggleStyle(SwitchToggleStyle(tint: Theme.onTrack))
                .disabled(notificationsDenied)
        } header: {
            Text("Alerts")
        } footer: {
            Text(liveActivitiesOff
                 ? "Alerts are Time Sensitive, so they can come through a Focus if you allow it. With Live Activities off, the step and its Done button can't show on the Lock Screen."
                 : "Alerts are Time Sensitive, so they can come through a Focus if you allow it.")
        }
    }

    /// A fix that lives in the Settings app: flagged, and clearly a way out.
    private func settingsLink(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(Theme.late)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func restore() {
        Task {
            await purchases.restore()
            restoreMessage = purchases.isPro ? "Shoes On Pro is active again." : (purchases.errorMessage ?? "Nothing to restore.")
            purchases.clearError()
        }
    }

    private var proSection: some View {
        Section {
            if purchases.isPro {
                Label("Shoes On Pro is active", systemImage: "checkmark.seal.fill")
                Button("Manage subscription") { showManageSubscription = true }
            } else {
                Button("Try Shoes On Pro") { showPaywall = true }
                Button(purchases.isPurchasing ? "Restoring…" : "Restore purchase", action: restore)
                    .disabled(purchases.isPurchasing)
            }
        } footer: {
            if !purchases.isPro {
                Text("Every routine, plus the Apple Watch coach. Free for 7 days if you haven't tried it.")
            }
        }
    }
}
