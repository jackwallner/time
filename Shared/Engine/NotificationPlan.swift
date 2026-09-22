import Foundation

/// One local notification Shoes On wants delivered.
struct PlannedAlert: Hashable, Sendable {
    enum Kind: String, Sendable {
        case getReady
        case leaveSoon
        case leaveNow
        case wrapUp
        case overrun
    }

    var id: String
    var kind: Kind
    var fireAt: Date
    var title: String
    var body: String
    /// The routine a get-ready alert starts when tapped.
    var routineID: UUID?
}

struct AlertPreferences: Sendable {
    var startAlerts = true
    var leaveAlerts = true
    var stepNudges = true
}

/// Decides every alert from the routines, the history and the run. Pure, so the
/// schedule can be tested without a notification center.
enum NotificationPlan {
    /// iOS keeps 64 pending requests; leave room for the run's own alerts.
    static let scheduledLimit = 56
    static let horizonDays = 10
    static let leaveSoonMinutes = 10
    static let overrunGraceMinutes = 5

    static func alerts(
        routines: [Routine],
        calibration: Calibration,
        departures: [DepartureRecord],
        activeRun: ActiveRun?,
        preferences: AlertPreferences,
        now: Date,
        calendar: Calendar = .current
    ) -> [PlannedAlert] {
        var alerts = runAlerts(activeRun, preferences: preferences, now: now)
        alerts += scheduledAlerts(
            routines: routines,
            calibration: calibration,
            departures: departures,
            activeRun: activeRun,
            preferences: preferences,
            now: now,
            calendar: calendar
        )
        return alerts
    }

    /// Get-ready and leave alerts for upcoming scheduled departures, nearest
    /// first, skipping the one being run and any already left for.
    static func scheduledAlerts(
        routines: [Routine],
        calibration: Calibration,
        departures: [DepartureRecord],
        activeRun: ActiveRun?,
        preferences: AlertPreferences,
        now: Date,
        calendar: Calendar
    ) -> [PlannedAlert] {
        guard preferences.startAlerts || preferences.leaveAlerts else { return [] }
        var alerts: [PlannedAlert] = []
        let today = calendar.startOfDay(for: now)
        for routine in routines {
            for offset in 0...horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      routine.weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
                let leaveAt = routine.leaveTime(on: day, calendar: calendar)
                guard leaveAt > now else { continue }
                if let run = activeRun, run.routineID == routine.id, run.leaveAt == leaveAt { continue }
                let alreadyLeft = departures.contains { (record: DepartureRecord) -> Bool in
                    record.routineID == routine.id && record.target == leaveAt
                }
                if alreadyLeft { continue }
                let plan = Planner.plan(routine, leaveAt: leaveAt, calibration: calibration)
                let key = "\(routine.id.uuidString).\(Int(leaveAt.timeIntervalSince1970))"
                if preferences.startAlerts, plan.alertAt > now {
                    alerts.append(PlannedAlert(
                        id: "ready.\(key)",
                        kind: .getReady,
                        fireAt: plan.alertAt,
                        title: "Time to get ready",
                        body: "Start now to leave at \(Format.time(leaveAt)). \(routine.name) really takes \(Format.duration(minutes: plan.realMinutes)).",
                        routineID: routine.id
                    ))
                }
                if preferences.leaveAlerts {
                    alerts += leaveAlerts(key: key, routineName: routine.name, leaveAt: leaveAt, now: now)
                }
            }
        }
        return Array(alerts.sorted { $0.fireAt < $1.fireAt }.prefix(scheduledLimit))
    }

    /// Alerts for the run in progress: wrap up the current step when its time
    /// is up, a nudge if it is still going a few minutes later, and the leave
    /// alerts for this departure.
    static func runAlerts(_ run: ActiveRun?, preferences: AlertPreferences, now: Date) -> [PlannedAlert] {
        guard let run else { return [] }
        var alerts: [PlannedAlert] = []
        let leave = Format.time(run.leaveAt)
        if preferences.stepNudges, let step = run.currentStep {
            let next = run.nextStep?.name ?? "shoes on and out the door"
            if run.stepEndsAt > now {
                alerts.append(PlannedAlert(
                    id: "run.wrap.\(run.stepIndex)",
                    kind: .wrapUp,
                    fireAt: run.stepEndsAt,
                    title: "Wrap up: \(step.name)",
                    body: "Next: \(next). Leave at \(leave)."
                ))
            }
            let overrunAt = run.stepEndsAt.addingTimeInterval(TimeInterval(overrunGraceMinutes * 60))
            if overrunAt > now {
                let status = RunStatus(slipSeconds: run.projectedReadyAt(now: overrunAt).timeIntervalSince(run.leaveAt))
                alerts.append(PlannedAlert(
                    id: "run.over.\(run.stepIndex)",
                    kind: .overrun,
                    fireAt: overrunAt,
                    title: "Still on \(step.name)?",
                    body: "\(status.label). Leave at \(leave)."
                ))
            }
        }
        if preferences.leaveAlerts {
            alerts += leaveAlerts(key: "run", routineName: run.routineName, leaveAt: run.leaveAt, now: now)
        }
        return alerts
    }

    private static func leaveAlerts(key: String, routineName: String, leaveAt: Date, now: Date) -> [PlannedAlert] {
        var alerts: [PlannedAlert] = []
        let soon = leaveAt.addingTimeInterval(TimeInterval(-leaveSoonMinutes * 60))
        if soon > now {
            alerts.append(PlannedAlert(
                id: "soon.\(key)",
                kind: .leaveSoon,
                fireAt: soon,
                title: "Leave in \(leaveSoonMinutes) minutes",
                body: "Shoes on by \(Format.time(leaveAt))."
            ))
        }
        guard leaveAt > now else { return alerts }
        alerts.append(PlannedAlert(
            id: "leave.\(key)",
            kind: .leaveNow,
            fireAt: leaveAt,
            title: "Time to go",
            body: "Head out now for \(routineName)."
        ))
        return alerts
    }
}
