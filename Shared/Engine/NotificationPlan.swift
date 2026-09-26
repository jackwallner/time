import Foundation

/// One local notification Shoes On wants delivered.
struct PlannedAlert: Hashable, Sendable {
    enum Kind: String, Sendable {
        case getReady
        /// The get-ready alert went unanswered: here is what starting now costs.
        case startNudge
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
    /// The departure a get-ready alert is for, so it can be skipped from the
    /// notification itself.
    var leaveAt: Date?
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
    /// Minutes after an unanswered get-ready alert to follow up. Time
    /// blindness means one alert is easy to swipe away and forget.
    static let startNudgeMinutes = [5, 12]
    /// Steps at least this long get a heads-up before their time is up
    /// instead of a notice when it already is.
    static let headsUpStepMinutes = 6
    static let headsUpMinutes = 2

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
                      routine.departs(on: day, calendar: calendar) else { continue }
                let leaveAt = routine.leaveTime(on: day, calendar: calendar)
                guard leaveAt > now else { continue }
                if let run = activeRun, run.routineID == routine.id, run.leaveAt == leaveAt { continue }
                let alreadyLeft = departures.contains { (record: DepartureRecord) -> Bool in
                    record.routineID == routine.id && record.target == leaveAt
                }
                if alreadyLeft { continue }
                let plan = Planner.plan(routine, leaveAt: leaveAt, calibration: calibration)
                let key = "\(routine.id.uuidString).\(Int(leaveAt.timeIntervalSince1970))"
                if preferences.startAlerts {
                    // Nudges are kept even after the alert itself has fired,
                    // so opening the app then does not cancel them.
                    alerts += startNudges(key: key, routine: routine, plan: plan, now: now)
                }
                if preferences.startAlerts, plan.alertAt > now {
                    alerts.append(PlannedAlert(
                        id: "ready.\(key)",
                        kind: .getReady,
                        fireAt: plan.alertAt,
                        title: "Time to get ready",
                        body: "Start now to leave at \(Format.time(leaveAt)). \(routine.name) really takes \(Format.duration(minutes: plan.realMinutes)).",
                        routineID: routine.id,
                        leaveAt: leaveAt
                    ))
                }
                if preferences.leaveAlerts {
                    alerts += leaveAlerts(key: key, routineName: routine.name, leaveAt: leaveAt, now: now)
                }
            }
        }
        return Array(alerts.sorted { $0.fireAt < $1.fireAt }.prefix(scheduledLimit))
    }

    /// Follow-ups to an unanswered get-ready alert, each saying honestly when
    /// starting right then gets them out the door. None once it is time to
    /// think about leaving rather than starting.
    static func startNudges(key: String, routine: Routine, plan: DeparturePlan, now: Date) -> [PlannedAlert] {
        let cutoff = plan.leaveAt.addingTimeInterval(TimeInterval(-leaveSoonMinutes * 60))
        return startNudgeMinutes.enumerated().compactMap { index, minutes in
            let fireAt = plan.alertAt.addingTimeInterval(TimeInterval(minutes * 60))
            guard fireAt > now, fireAt < cutoff else { return nil }
            let out = fireAt.addingTimeInterval(TimeInterval(plan.realMinutes * 60))
            let lateMinutes = Int((out.timeIntervalSince(plan.leaveAt) / 60).rounded(.up))
            let body = lateMinutes <= 1
                ? "Start now and you still leave on time at \(Format.time(plan.leaveAt))."
                : "Starting now puts you out the door at \(Format.time(out)), \(lateMinutes) min late."
            return PlannedAlert(
                id: "nudge\(index).\(key)",
                kind: .startNudge,
                fireAt: fireAt,
                title: "Not started yet?",
                body: body,
                routineID: routine.id,
                leaveAt: plan.leaveAt
            )
        }
    }

    /// Alerts for the run in progress: a heads-up before a long step's time is
    /// up (transitions are the hard part), a nudge if it is still going a few
    /// minutes after, and the leave alerts for this departure.
    static func runAlerts(_ run: ActiveRun?, preferences: AlertPreferences, now: Date) -> [PlannedAlert] {
        guard let run else { return [] }
        var alerts: [PlannedAlert] = []
        let leave = Format.time(run.leaveAt)
        if preferences.stepNudges, let step = run.currentStep {
            let next = run.nextStep?.name ?? "shoes on and out the door"
            let headsUp = step.plannedMinutes >= headsUpStepMinutes
            let wrapAt = run.stepEndsAt.addingTimeInterval(headsUp ? TimeInterval(-headsUpMinutes * 60) : 0)
            if wrapAt > now {
                alerts.append(PlannedAlert(
                    id: "run.wrap.\(run.stepIndex)",
                    kind: .wrapUp,
                    fireAt: wrapAt,
                    title: headsUp ? "\(headsUpMinutes) min left: \(step.name)" : "Wrap up: \(step.name)",
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
