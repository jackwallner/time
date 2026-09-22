import SwiftUI

@main
struct ShoesOnWatchApp: App {
    @StateObject private var model = WatchModel.shared

    init() {
        WatchSyncService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
        }
    }
}
