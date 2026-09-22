#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// The Live Activity for a run. The leave time never changes during a run; the
/// rest arrives as a `RunSnapshot` each time a step changes.
struct RunActivityAttributes: ActivityAttributes {
    typealias ContentState = RunSnapshot

    var routineName: String
    var leaveAt: Date
}
#endif
