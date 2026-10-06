import SwiftUI
import WidgetKit

/// The Watch face complication: the same next-start widget as the iPhone's
/// Lock Screen, fed by what the Watch app last heard from the phone.
@main
struct ShoesOnWatchWidgets: WidgetBundle {
    var body: some Widget {
        NextDepartureWidget()
    }
}
