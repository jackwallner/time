import AppIntents
import SwiftUI
import WidgetKit

/// A Lock Screen or Control Center button (iOS 18) that starts the next
/// routine without unlocking, in place of the flashlight or on the Action
/// button.
@available(iOS 18.0, *)
struct StartControl: ControlWidget {
    static let kind = "StartRoutineControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartRunIntent()) {
                Label("Start getting ready", systemImage: "figure.walk")
            } actionLabel: { isActive in
                Label(isActive ? "Starting" : "Started", systemImage: "figure.walk")
            }
        }
        .displayName("Start getting ready")
        .description("Starts your next routine and puts the first step on the Lock Screen.")
    }
}
