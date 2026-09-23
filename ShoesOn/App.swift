import SwiftUI

@main
struct ShoesOnApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = RoutineStore.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var purchases = StoreService.shared
    @StateObject private var review = ReviewPromptService.shared

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
                .environmentObject(review)
                .task { purchases.start() }
                .onChange(of: scenePhase) { _, phase in
                    // Plans move as timings arrive and days pass, so the
                    // rolling alert window is rebuilt whenever the app is seen.
                    if phase == .active { store.propagate() }
                }
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var store: RoutineStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var review: ReviewPromptService

    var body: some View {
        content
            .tint(Theme.ink)
            .fontDesign(.rounded)
            .animation(.smooth, value: store.activeRun == nil)
            .animation(.smooth, value: settings.hasCompletedSetup)
            .sheet(isPresented: $review.isPresented) { ReviewPromptView() }
    }

    @ViewBuilder private var content: some View {
        if ScreenshotConfig.has("-PaywallSnapshot") {
            PaywallView(surface: "shoeson_snapshot")
        } else if let page = ScreenshotConfig.value(after: "-OnboardingPage").flatMap(Int.init) {
            OnboardingView(startPage: page)
        } else if !settings.hasCompletedSetup {
            OnboardingView()
        } else if store.activeRun != nil || store.state.lastFinished != nil {
            RunView()
        } else {
            HomeView()
        }
    }
}
