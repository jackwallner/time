import XCTest
@testable import ShoesOn

final class NotificationPlanTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private let routine = Routine(
        name: "Weekday mornings",
        leaveHour: 8,
        leaveMinute: 15,
        weekdays: [2, 3, 4, 5, 6],
        steps: [RoutineStep(name: "Shower", guessMinutes: 20), RoutineStep(name: "Shoes", guessMinutes: 10)]
    )

    private func alerts(departures: [DepartureRecord] = [], run: ActiveRun? = nil, now: Date) -> [PlannedAlert] {
        NotificationPlan.alerts(
            routines: [routine],
            calibration: Calibration(basePace: 1.5, stepHistory: [], departures: []),
            departures: departures,
            activeRun: run,
            preferences: AlertPreferences(),
            now: now,
            calendar: calendar
        )
    }

    func testGetReadyAlertFiresAtThePacedStart() {
        // Monday 21 September, early.
        let result = alerts(now: date(21, 5, 0))
        let first = result.first { $0.kind == .getReady }
        XCTAssertEqual(first?.fireAt, date(21, 7, 30))
        XCTAssertEqual(first?.routineID, routine.id)
        XCTAssertTrue(result.contains { $0.kind == .leaveSoon && $0.fireAt == date(21, 8, 5) })
        XCTAssertTrue(result.contains { $0.kind == .leaveNow && $0.fireAt == date(21, 8, 15) })
    }

    func testWeekendsGetNoAlerts() {
        let result = alerts(now: date(19, 5, 0))
        XCTAssertFalse(result.contains { calendar.isDate($0.fireAt, inSameDayAs: date(19, 0, 0)) })
        XCTAssertFalse(result.contains { calendar.isDate($0.fireAt, inSameDayAs: date(20, 0, 0)) })
    }

    func testADepartureAlreadyMadeIsNotAlertedAgain() {
        let left = DepartureRecord(routineID: routine.id, target: date(21, 8, 15), left: date(21, 8, 0), startDelaySeconds: nil)
        let result = alerts(departures: [left], now: date(21, 8, 1))
        XCTAssertFalse(result.contains { calendar.isDate($0.fireAt, inSameDayAs: date(21, 0, 0)) })
    }

    func testRunningStepGetsAWrapUpAndAnOverrunNudge() {
        let now = date(21, 7, 30)
        let plan = Planner.plan(routine, leaveAt: date(21, 8, 15), calibration: Calibration(basePace: 1.5, stepHistory: [], departures: []))
        let run = ActiveRun(plan: plan, routineName: routine.name, startedAt: now, alertAt: nil)
        let result = alerts(run: run, now: now)
        // A thirty minute shower gets its heads-up two minutes before the end.
        let wrap = result.first { $0.kind == .wrapUp }
        XCTAssertEqual(wrap?.fireAt, date(21, 7, 58))
        XCTAssertEqual(wrap?.title, "2 min left: Shower")
        let over = result.first { $0.kind == .overrun }
        XCTAssertEqual(over?.fireAt, date(21, 8, 5))
        XCTAssertTrue(over?.body.hasPrefix("5 min behind") ?? false, over?.body ?? "")
        // The scheduled get-ready for the same departure is replaced by the run.
        XCTAssertFalse(result.contains { $0.kind == .getReady && calendar.isDate($0.fireAt, inSameDayAs: now) })
    }

    func testShortStepsGetAWrapUpWhenTimeIsUp() {
        let short = Routine(name: "Quick", leaveHour: 8, leaveMinute: 15, weekdays: [2], steps: [RoutineStep(name: "Shoes", guessMinutes: 3)])
        let plan = Planner.plan(short, leaveAt: date(21, 8, 15), calibration: Calibration(basePace: 1, stepHistory: [], departures: []))
        let run = ActiveRun(plan: plan, routineName: short.name, startedAt: date(21, 8, 12), alertAt: nil)
        let wrap = NotificationPlan.runAlerts(run, preferences: AlertPreferences(), now: date(21, 8, 12)).first { $0.kind == .wrapUp }
        XCTAssertEqual(wrap?.fireAt, date(21, 8, 15))
        XCTAssertEqual(wrap?.title, "Wrap up: Shoes")
    }

    func testAnUnansweredAlertIsFollowedUpWithWhatStartingNowCosts() {
        // Paced plan: 30 + 15 = 45 min, so start 7:30 for 8:15.
        let nudges = alerts(now: date(21, 5, 0)).filter { $0.kind == .startNudge && calendar.isDate($0.fireAt, inSameDayAs: date(21, 0, 0)) }
        XCTAssertEqual(nudges.map(\.fireAt), [date(21, 7, 35), date(21, 7, 42)])
        XCTAssertEqual(nudges.first?.routineID, routine.id)
        XCTAssertEqual(nudges.first?.leaveAt, date(21, 8, 15))
        XCTAssertTrue(nudges[0].body.contains("5 min late"), nudges[0].body)
        XCTAssertTrue(nudges[1].body.contains("12 min late"), nudges[1].body)
    }

    func testNudgesSurviveTheAppOpeningAfterTheAlert() {
        let result = alerts(now: date(21, 7, 33))
        XCTAssertFalse(result.contains { $0.kind == .getReady && calendar.isDate($0.fireAt, inSameDayAs: date(21, 0, 0)) })
        XCTAssertTrue(result.contains { $0.kind == .startNudge && $0.fireAt == date(21, 7, 35) })
    }

    func testStartingTheRunCancelsTheNudges() {
        let plan = Planner.plan(routine, leaveAt: date(21, 8, 15), calibration: Calibration(basePace: 1.5, stepHistory: [], departures: []))
        let run = ActiveRun(plan: plan, routineName: routine.name, startedAt: date(21, 7, 31), alertAt: date(21, 7, 30))
        let result = alerts(run: run, now: date(21, 7, 31))
        XCTAssertFalse(result.contains { $0.kind == .startNudge && calendar.isDate($0.fireAt, inSameDayAs: date(21, 0, 0)) })
    }

    func testASkippedDayGetsNoAlertsAndTheNextDayIsUntouched() {
        var skipping = routine
        skipping.setChange(DayChange(day: date(22, 0, 0), leaveMinuteOfDay: nil), on: date(22, 0, 0), calendar: calendar)
        let result = NotificationPlan.scheduledAlerts(
            routines: [skipping],
            calibration: Calibration(basePace: 1.5, stepHistory: [], departures: []),
            departures: [],
            activeRun: nil,
            preferences: AlertPreferences(),
            now: date(21, 9, 0),
            calendar: calendar
        )
        XCTAssertFalse(result.contains { calendar.isDate($0.fireAt, inSameDayAs: date(22, 0, 0)) })
        XCTAssertTrue(result.contains { $0.kind == .getReady && $0.fireAt == date(23, 7, 30) })
    }

    func testAOneOffTimeMovesThatDayOnlyAndCanAddAWeekend() {
        var changed = routine
        changed.setChange(DayChange(day: date(22, 0, 0), leaveMinuteOfDay: 7 * 60), on: date(22, 0, 0), calendar: calendar)
        // Saturday the 26th, not a routine day, gets a one-off at 10:40.
        changed.setChange(DayChange(day: date(26, 0, 0), leaveMinuteOfDay: 10 * 60 + 40), on: date(26, 0, 0), calendar: calendar)
        let result = NotificationPlan.scheduledAlerts(
            routines: [changed],
            calibration: Calibration(basePace: 1.5, stepHistory: [], departures: []),
            departures: [],
            activeRun: nil,
            preferences: AlertPreferences(),
            now: date(21, 9, 0),
            calendar: calendar
        )
        let ready = result.filter { $0.kind == .getReady }.map(\.fireAt)
        XCTAssertTrue(ready.contains(date(22, 6, 15)))
        XCTAssertTrue(ready.contains(date(23, 7, 30)))
        XCTAssertTrue(ready.contains(date(26, 9, 55)))
        XCTAssertFalse(ready.contains(date(22, 7, 30)))
    }

    func testScheduleStaysUnderTheSystemLimit() {
        let many = (0..<8).map { index in
            Routine(name: "R\(index)", leaveHour: 8, leaveMinute: index, weekdays: Set(1...7), steps: [RoutineStep(name: "S", guessMinutes: 5)])
        }
        let result = NotificationPlan.scheduledAlerts(
            routines: many,
            calibration: Calibration(basePace: 1, stepHistory: [], departures: []),
            departures: [],
            activeRun: nil,
            preferences: AlertPreferences(),
            now: date(21, 5, 0),
            calendar: calendar
        )
        XCTAssertLessThanOrEqual(result.count, NotificationPlan.scheduledLimit)
        XCTAssertEqual(result.map(\.fireAt), result.map(\.fireAt).sorted())
    }

    func testCopyHasNoDashes() {
        let now = date(21, 7, 30)
        let plan = Planner.plan(routine, leaveAt: date(21, 8, 15), calibration: Calibration(basePace: 1.5, stepHistory: [], departures: []))
        let run = ActiveRun(plan: plan, routineName: routine.name, startedAt: now, alertAt: nil)
        for alert in alerts(run: run, now: date(21, 5, 0)) + alerts(now: date(21, 5, 0)) {
            XCTAssertFalse((alert.title + alert.body).contains("\u{2014}"))
            XCTAssertFalse((alert.title + alert.body).contains("\u{2013}"))
        }
    }
}
