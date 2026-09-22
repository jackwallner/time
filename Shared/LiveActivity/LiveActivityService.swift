#if canImport(ActivityKit)
import ActivityKit
import Foundation
import os

/// Keeps one Live Activity alive while a routine runs, and none otherwise.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private let logger = Logger(subsystem: AppGroup.subsystem, category: "LiveActivity")

    private init() {}

    /// `Activity` is not Sendable. It is only touched from the main actor here.
    private struct ActivityBox: @unchecked Sendable {
        let activity: Activity<RunActivityAttributes>
    }

    func sync(run: ActiveRun?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let existing = Activity<RunActivityAttributes>.activities
        guard let run else {
            for activity in existing { end(activity) }
            return
        }
        let snapshot = RunSnapshot(run: run)
        // Stale once the step should have ended: from then on the status it
        // shows can only have got worse, and the view says so.
        let content = ActivityContent(state: snapshot, staleDate: run.isLeaving ? run.leaveAt : run.stepEndsAt)
        if let current = existing.first(where: { $0.attributes.leaveAt == run.leaveAt && $0.attributes.routineName == run.routineName }) {
            for activity in existing where activity.id != current.id { end(activity) }
            let box = ActivityBox(activity: current)
            Task { @MainActor in await box.activity.update(content) }
            return
        }
        for activity in existing { end(activity) }
        do {
            _ = try Activity.request(
                attributes: RunActivityAttributes(routineName: run.routineName, leaveAt: run.leaveAt),
                content: content
            )
        } catch {
            logger.error("Live Activity request failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func end(_ activity: Activity<RunActivityAttributes>) {
        let box = ActivityBox(activity: activity)
        Task { @MainActor in await box.activity.end(nil, dismissalPolicy: .immediate) }
    }
}
#endif
