import SwiftUI

@main
struct ShoesOnApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = RoutineStore.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var purchases = StoreService.shared

    init() {
        NotificationService.shared.configure()
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
            if resumesAtOffer { OnboardingView.resumingOffer } else { OnboardingView() }
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
