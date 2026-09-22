import Foundation
import os
import UserNotifications

/// Owns every pending local notification. Each reschedule replaces the whole
/// set with what `NotificationPlan` says should exist right now, so a stale
/// alert can never outlive the plan that made it.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    static let readyCategory = "READY"
    static let stepCategory = "STEP"
    static let startAction = "START"
    static let doneAction = "DONE"

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: AppGroup.subsystem, category: "Notifications")
    private var rescheduleTask: Task<Void, Never>?

    func configure() {
        center.delegate = self
        let start = UNNotificationAction(identifier: Self.startAction, title: "Start now", options: [.foreground])
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Done, next step", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.readyCategory, actions: [start], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.stepCategory, actions: [done], intentIdentifiers: []),
        ])
    }

    /// Asks once, from onboarding. Returns whether alerts are allowed.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Authorization failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func reschedule(store: RoutineStore, now: Date = .now) {
        let settings = AppSettings.shared
        let preferences = AlertPreferences(
            startAlerts: settings.startAlerts,
            leaveAlerts: settings.leaveAlerts,
            stepNudges: settings.stepNudges
        )
        let alerts = NotificationPlan.alerts(
            routines: store.routines,
            calibration: store.calibration,
            departures: store.state.departures,
            activeRun: store.activeRun,
            preferences: preferences,
            now: now
        )
        rescheduleTask?.cancel()
        rescheduleTask = Task { await apply(alerts) }
    }

    private func apply(_ alerts: [PlannedAlert]) async {
        let wanted = Set(alerts.map(\.id))
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { !wanted.contains($0) })
        guard !Task.isCancelled else { return }
        for alert in alerts {
            do {
                try await center.add(request(for: alert))
            } catch {
                logger.error("Schedule failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func request(for alert: PlannedAlert) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        switch alert.kind {
        case .getReady:
            content.categoryIdentifier = Self.readyCategory
            if let routineID = alert.routineID { content.userInfo = ["routineID": routineID.uuidString] }
        case .wrapUp, .overrun:
            content.categoryIdentifier = Self.stepCategory
        case .leaveSoon, .leaveNow:
            break
        }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: alert.fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger)
    }

    // MARK: - Delegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let routineID = (response.notification.request.content.userInfo["routineID"] as? String).flatMap(UUID.init)
        await MainActor.run {
            let store = RoutineStore.shared
            switch action {
            case Self.startAction:
                if let routineID { store.startRun(routineID: routineID) } else { store.startNextRun() }
            case Self.doneAction:
                store.completeStep()
            default:
                break
            }
        }
    }
}
