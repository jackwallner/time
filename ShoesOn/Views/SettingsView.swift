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
                    Text("Shoes On \(Bundle.main.appVersionLabel). Everything stays on this iPhone.")
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
            .task {
                notificationsDenied = await NotificationService.shared.authorizationStatus() == .denied
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

    private var alertsSection: some View {
        Section {
            if notificationsDenied {
                Button("Turn on notifications in Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            }
            Toggle("Time to get ready", isOn: $settings.startAlerts)
                .toggleStyle(SwitchToggleStyle(tint: Theme.onTrack))
            Toggle("Leave in 10 minutes, and time to go", isOn: $settings.leaveAlerts)
                .toggleStyle(SwitchToggleStyle(tint: Theme.onTrack))
            Toggle("Nudges when a step runs over", isOn: $settings.stepNudges)
                .toggleStyle(SwitchToggleStyle(tint: Theme.onTrack))
        } header: {
            Text("Alerts")
        } footer: {
            Text("Alerts are Time Sensitive, so they can come through a Focus if you allow it.")
        }
    }

    private var proSection: some View {
        Section {
            if purchases.isPro {
                Label("Shoes On Pro is unlocked", systemImage: "checkmark.seal")
            } else {
                Button("Unlock Shoes On Pro") { showPaywall = true }
                Button("Restore purchase") { Task { await purchases.restore() } }
            }
        } footer: {
            if !purchases.isPro {
                Text("Every routine, plus the Apple Watch coach. One purchase, no subscription.")
            }
        }
    }
}
