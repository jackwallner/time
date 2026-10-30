import SwiftUI

@main
struct ShoesOnApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = RoutineStore.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var purchases = StoreService.shared

    init() {
        NotificationService.shared.configure()
        // At launch, not from a view: a background launch for a Watch
        // command may never connect a scene.
        WatchSyncService.shared.start()
        ConversionDiagnostics.recordAppOpen()
        #if DEBUG
        ScreenshotFixtures.applyIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(purchases)
                .task { purchases.start() }
                .onChange(of: scenePhase) { _, phase in
                    // Plans move as timings arrive and days pass, so the
                    // rolling alert window is rebuilt whenever the app is seen.
                    if phase == .active { store.refresh(now: AppClock.now) }
                }
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var store: RoutineStore
    @EnvironmentObject private var settings: AppSettings
    /// The routine is saved before the Pro offer, so a saved routine with
    /// setup unfinished means they left on the offer: pick up there, not at
    /// page one. Read once at launch, so saving mid-setup never swaps the
    /// onboarding out from under itself.
    @State private var resumesAtOffer = !AppSettings.shared.hasCompletedSetup && !RoutineStore.shared.routines.isEmpty
    /// The run is a presentation over Home. Mirrors the store so a run found
    /// open at launch shows at once, and one started later slides up like
    /// the session it is.
    @State private var runShown = false

    private var runPresent: Bool { store.activeRun != nil || store.state.lastFinished != nil }

    var body: some View {
        content
            // Painted from the first frame, so launch never shows a blank window.
            .background(Theme.background.ignoresSafeArea())
            .tint(Theme.ink)
            .fontDesign(.rounded)
            .animation(.smooth, value: settings.hasCompletedSetup)
    }

    @ViewBuilder private var content: some View {
        if ScreenshotConfig.has("-PaywallSnapshot") {
            PaywallView(surface: "shoeson_snapshot")
        } else if let page = ScreenshotConfig.value(after: "-OnboardingPage").flatMap(Int.init) {
            OnboardingView(startPage: page)
        } else if !settings.hasCompletedSetup {
            // Unfolded, setup keeps to the leading pane, clear of the fold.
            FoldSplit { _ in
                if resumesAtOffer { OnboardingView.resumingOffer } else { OnboardingView() }
            } secondary: {
                SetupMark()
            }
            .background(Theme.background.ignoresSafeArea())
        } else {
            // Presented from a wrapper, not from Home itself, so a run that
            // starts while a Home sheet is open still comes up on top. As its
            // own presentation, the run's dark scheme never flips Home dark
            // underneath it mid-fade.
            ZStack { HomeView() }
                .fullScreenCover(isPresented: $runShown) {
                    RunView()
                        .tint(Theme.ink)
                        .fontDesign(.rounded)
                }
                .onAppear {
                    guard runPresent, !runShown else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { runShown = true }
                }
                .onChange(of: runPresent) { _, present in
                    withAnimation(.smooth) { runShown = present }
                }
        }
    }
}

/// The quiet half of the unfolded display while setup runs beside it.
private struct SetupMark: View {
    var body: some View {
        VStack(spacing: 18) {
            Image("OnboardingMark")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            Text("Shoes On")
                .displayFont(28)
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}
