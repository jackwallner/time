import StoreKit
import SwiftUI
import UIKit

extension View {
    /// Calls Apple's rating prompt a few seconds after a good moment, with no
    /// question in front of it. Bump `moment` when the moment happens.
    ///
    /// `isClear` is checked again once the wait is over, so the prompt never
    /// lands on anything that came up meanwhile; the view leaving the screen
    /// cancels it too. A moment that is not clear is skipped, not queued.
    func requestsReview(after moment: Int, isClear: @escaping () -> Bool = { true }) -> some View {
        modifier(ReviewRequestModifier(moment: moment, isClear: isClear))
    }
}

private struct ReviewRequestModifier: ViewModifier {
    let moment: Int
    let isClear: () -> Bool

    @Environment(\.requestReview) private var requestReview
    @State private var onScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
            .onChange(of: moment) { _, _ in schedule() }
    }

    private var mayAsk: Bool {
        // Never inside setup. RevenueCat's `rating_prompt: off` pauses the
        // asks without a release.
        AppSettings.shared.hasCompletedSetup
            && StoreService.shared.isOn(.ratingPrompt)
            && ReviewPromptService.shared.shouldRequestReview()
    }

    private func schedule() {
        guard mayAsk else { return }
        Task { @MainActor in
            // Let the result land first.
            try? await Task.sleep(for: .seconds(3))
            // Read live: the wait outlasts any value captured when it began.
            guard onScreen, UIApplication.shared.applicationState == .active, isClear(), mayAsk else { return }
            ReviewPromptService.shared.markAsked()
            requestReview()
        }
    }
}
