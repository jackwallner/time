import AppIntents
import Foundation

/// The Done button on the Live Activity. A `LiveActivityIntent` runs in the
/// app's process, so the widget extension compiles an empty body and the app
/// compiles the real one.
struct CompleteStepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Finish Step"
    static let description = IntentDescription("Marks the current step of your routine as done.")
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let store = RoutineStore.shared
        if store.activeRun?.isLeaving == true {
            store.finishRun()
        } else {
            store.completeStep()
        }
        #endif
        return .result()
    }
}

/// The Lock Screen and Control Center button. Like Done, it runs in the
/// app's process without opening it: the run starts and its Live Activity
/// puts the first step on the Lock Screen.
struct StartRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Getting Ready Now"
    static let description = IntentDescription("Starts your next routine and shows the first step on the Lock Screen.")
    static let openAppWhenRun = false
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let store = RoutineStore.shared
        if store.activeRun == nil { store.startNextRun() }
        #endif
        return .result()
    }
}

#if !WIDGET_EXTENSION
/// "Start my routine" from Siri, Spotlight, or the Action button.
struct StartRoutineIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Getting Ready"
    static let description = IntentDescription("Starts your next routine in Shoes On.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = RoutineStore.shared
        if store.activeRun == nil { store.startNextRun() }
        return .result()
    }
}

struct ShoesOnShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRoutineIntent(),
            phrases: [
                "Start getting ready in \(.applicationName)",
                "Start my routine in \(.applicationName)",
            ],
            shortTitle: "Start Getting Ready",
            systemImageName: "figure.walk.departure"
        )
        AppShortcut(
            intent: CompleteStepIntent(),
            phrases: ["Next step in \(.applicationName)", "Done in \(.applicationName)"],
            shortTitle: "Finish Step",
            systemImageName: "checkmark.circle"
        )
    }
}
#endif
