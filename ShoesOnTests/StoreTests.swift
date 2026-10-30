import XCTest
@testable import ShoesOn

/// The store's run handling: practice runs, undo, and starting from an alert.
@MainActor
final class StoreTests: XCTestCase {
    private let routine = Routine(
        name: "Weekday mornings",
        leaveHour: 8,
        leaveMinute: 15,
        weekdays: [2, 3, 4, 5, 6],
        steps: [RoutineStep(name: "Shower", guessMinutes: 10), RoutineStep(name: "Shoes", guessMinutes: 5)]
    )

    /// The 21st of September 2026 is a Monday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    /// A fresh store with the routine, guesses taken at face value.
    private func makeStore() -> RoutineStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString).json")
        let store = RoutineStore(fileURL: url)
        store.save(routine)
        store.setPace(.onTheDot)
        return store
    }

    func testAnEveningRunIsPracticeAndLeavesTomorrowAlone() {
        let store = makeStore()
        store.startRun(routineID: routine.id, now: date(21, 21))
        let run = store.activeRun
        XCTAssertEqual(run?.isPracticeRun, true)
        XCTAssertEqual(run?.leaveAt, date(21, 21, 15))
        XCTAssertNil(run?.alertAt)
        store.completeStep(now: date(21, 21, 8))
        store.completeStep(now: date(21, 21, 12))
        store.finishRun(now: date(21, 21, 13))
        XCTAssertTrue(store.state.departures.isEmpty)
        XCTAssertEqual(store.state.stepHistory.count, 2)
        XCTAssertEqual(store.nextPlan(for: routine, now: date(21, 21, 14))?.leaveAt, date(22, 8, 15))
    }

    func testARunNearTheStartAimsForTheDeparture() {
        let store = makeStore()
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        XCTAssertEqual(store.activeRun?.isPracticeRun, false)
        XCTAssertEqual(store.activeRun?.leaveAt, date(21, 8, 15))
        store.finishRun(now: date(21, 8, 14))
        XCTAssertEqual(store.state.departures.count, 1)
    }

    func testUndoPutsTheStepBackAndForgetsItsTiming() {
        let store = makeStore()
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        store.completeStep(now: date(21, 7, 56))
        XCTAssertEqual(store.state.stepHistory.count, 1)
        store.undoLastStep()
        XCTAssertEqual(store.activeRun?.stepIndex, 0)
        XCTAssertEqual(store.activeRun?.stepStartedAt, date(21, 7, 50))
        XCTAssertNil(store.activeRun?.steps[0].actualSeconds)
        XCTAssertTrue(store.state.stepHistory.isEmpty)
        XCTAssertNil(store.lastStepUndo)
    }

    func testUndoingASkipPutsTheStepBack() {
        let store = makeStore()
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        store.skipStep(now: date(21, 7, 51))
        store.undoLastStep()
        XCTAssertEqual(store.activeRun?.stepIndex, 0)
        XCTAssertEqual(store.activeRun?.steps[0].skipped, false)
    }

    func testUndoingACatchUpSkipPutsTheStepBack() {
        let store = makeStore()
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        let shoes = routine.steps[1].id
        store.dropUpcomingStep(id: shoes)
        XCTAssertEqual(store.activeRun?.steps[1].skipped, true)
        XCTAssertEqual(store.lastStepUndo?.kind, .drop)
        XCTAssertEqual(store.lastStepUndo?.stepName, "Shoes")
        store.undoLastStep()
        XCTAssertEqual(store.activeRun?.steps[1].skipped, false)
        XCTAssertEqual(store.activeRun?.stepIndex, 0)
        XCTAssertNil(store.lastStepUndo)
    }

    func testUndoDoesNothingOnceTheRunHasMovedOn() {
        let store = makeStore()
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        store.completeStep(now: date(21, 7, 56))
        store.cancelRun()
        store.undoLastStep()
        XCTAssertNil(store.activeRun)
        XCTAssertEqual(store.state.stepHistory.count, 1)
    }

    func testOpeningTheAlertStartsThatDeparture() {
        let store = makeStore()
        store.startRunFromAlert(routineID: routine.id, leaveAt: date(21, 8, 15), now: date(21, 7, 52))
        XCTAssertEqual(store.activeRun?.leaveAt, date(21, 8, 15))
    }

    func testOpeningAnOldAlertOnlyOpensTheApp() {
        let store = makeStore()
        store.startRunFromAlert(routineID: routine.id, leaveAt: date(21, 8, 15), now: date(21, 12))
        XCTAssertNil(store.activeRun)
    }

    func testStartingOnASkippedDayPracticesInsteadOfRecordingTheSkippedDeparture() {
        let store = makeStore()
        var state = store.state
        state.routines[0].setChange(DayChange(day: date(21, 0), leaveMinuteOfDay: nil), on: date(21, 0))
        store.replaceState(state)
        XCTAssertEqual(store.nextPlan(for: state.routines[0], now: date(21, 7, 50))?.leaveAt, date(22, 8, 15))
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        XCTAssertEqual(store.activeRun?.isPracticeRun, true)
        store.finishRun(now: date(21, 8))
        XCTAssertTrue(store.state.departures.isEmpty)
    }

    func testAnOffDayDoesNotStartADifferentDepartureFromTheHomePlan() {
        let store = makeStore()
        store.startRun(routineID: routine.id, now: date(20, 7, 50))
        XCTAssertEqual(store.activeRun?.isPracticeRun, true)
        XCTAssertNil(store.activeRun?.alertAt)
    }

    func testStartingAgainAfterLeavingEarlyDoesNotRecordTheDepartureTwice() {
        let store = makeStore()
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        store.finishRun(now: date(21, 8))
        store.dismissSummary()
        store.startRun(routineID: routine.id, now: date(21, 8, 1))
        XCTAssertEqual(store.activeRun?.isPracticeRun, true)
        store.finishRun(now: date(21, 8, 10))
        XCTAssertEqual(store.state.departures.count, 1)
    }

    func testAnAlertForASkippedOrMovedDepartureDoesNotStartARun() {
        for override in [Int?.none, 7 * 60] {
            let store = makeStore()
            var state = store.state
            state.routines[0].setChange(DayChange(day: date(21, 0), leaveMinuteOfDay: override), on: date(21, 0))
            store.replaceState(state)
            store.startRunFromAlert(routineID: routine.id, leaveAt: date(21, 8, 15), now: date(21, 7, 50))
            XCTAssertNil(store.activeRun)
        }
    }

    // MARK: - A forgotten run

    /// Start 7:50, Shower done at 8:00, walk out without a tap, then clear the
    /// run at 10:30. Tuesday's plan must not grow by the hours it sat open.
    func testAStepLeftRunningForHoursDoesNotTakeOverItsPlan() {
        let store = makeStore()
        let before = store.plan(for: routine, leaveAt: date(22, 8, 15)).alertAt
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        store.completeStep(now: date(21, 8))
        store.completeStep(now: date(21, 10, 30))
        store.cancelRun()
        let shoes = store.calibration.estimate(for: routine.steps[1])
        XCTAssertLessThanOrEqual(shoes.minutes, 6, "Shoes (guess 5) is now planned at \(shoes.minutes) min")
        let after = store.plan(for: routine, leaveAt: date(22, 8, 15)).alertAt
        XCTAssertEqual(after.timeIntervalSince(before), 0, accuracy: 60, "Tuesday's alert moved from \(before) to \(after)")
    }

    /// A timing already stored from an older build is bounded too.
    func testOneHugeTimingIsBoundedInThePlan() {
        let step = routine.steps[1]
        let calibration = Calibration(
            basePace: 1,
            stepHistory: [StepRecord(stepID: step.id, routineID: routine.id, guessMinutes: 5, actualSeconds: 24 * 3600, date: date(21, 8))],
            departures: []
        )
        XCTAssertLessThanOrEqual(calibration.estimate(for: step).minutes, 15)
    }

    func testARealLongStepStillTeaches() {
        let store = makeStore()
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        store.completeStep(now: date(21, 8, 10))
        XCTAssertEqual(store.state.stepHistory.last?.actualSeconds, 20 * 60)
        XCTAssertGreaterThan(store.calibration.estimate(for: routine.steps[0]).minutes, 10)
    }

    // MARK: - A run left open overnight

    func testARunLeftOpenOvernightDoesNotBlockTheNextMorning() {
        let store = makeStore()
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        store.startNextRun(now: date(22, 7, 55))
        XCTAssertEqual(store.activeRun?.leaveAt, date(22, 8, 15))

        let other = makeStore()
        other.startRun(routineID: routine.id, now: date(21, 7, 50))
        other.startRunFromAlert(routineID: routine.id, leaveAt: date(22, 8, 15), now: date(22, 8))
        XCTAssertEqual(other.activeRun?.leaveAt, date(22, 8, 15))
    }

    func testADoneOnYesterdaysRunClosesItWithoutTimingAStep() {
        let store = makeStore()
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        store.completeStep(now: date(22, 7, 50))
        XCTAssertNil(store.activeRun)
        XCTAssertTrue(store.state.stepHistory.isEmpty)
        XCTAssertNil(store.finishRun(now: date(22, 7, 51)))
        XCTAssertTrue(store.state.departures.isEmpty)
    }

    func testAnAbandonedRunIsGoneAtLaunch() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString).json")
        let store = RoutineStore(fileURL: url)
        store.save(routine)
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        XCTAssertNotNil(RoutineStore(fileURL: url, now: date(21, 9)).activeRun)
        XCTAssertNil(RoutineStore(fileURL: url, now: date(22, 7)).activeRun)
    }

    // MARK: - Pro lapsed

    private func makeStoreWithTwoRoutines(isPro: Bool) -> (RoutineStore, Routine) {
        let store = makeStore()
        let gym = Routine(
            name: "Gym",
            leaveHour: 7,
            leaveMinute: 0,
            weekdays: [2, 3, 4, 5, 6],
            steps: [RoutineStep(name: "Bag", guessMinutes: 5)]
        )
        store.save(gym)
        store.hasPro = { isPro }
        return (store, gym)
    }

    func testWithoutProOnlyTheFirstRoutineAlertsAndRuns() {
        let (store, gym) = makeStoreWithTwoRoutines(isPro: false)
        XCTAssertEqual(store.activeRoutines.map(\.id), [routine.id])
        XCTAssertTrue(store.isLocked(gym.id))
        XCTAssertEqual(store.selectedRoutine?.id, routine.id)
        XCTAssertFalse(store.upcomingDepartures(now: date(21, 6)).contains { $0.routine.id == gym.id })
        XCTAssertEqual(store.nextDeparture(now: date(21, 6))?.routine.id, routine.id)
        let alerts = NotificationPlan.alerts(
            routines: store.activeRoutines,
            calibration: store.calibration,
            departures: [],
            activeRun: nil,
            preferences: AlertPreferences(startAlerts: true, leaveAlerts: true, stepNudges: true),
            now: date(21, 6)
        )
        XCTAssertFalse(alerts.contains { $0.routineID == gym.id })
        store.startRun(routineID: gym.id, now: date(21, 6, 50))
        XCTAssertNil(store.activeRun)
        store.startRun(routineID: routine.id, now: date(21, 7, 50))
        XCTAssertEqual(store.activeRun?.routineID, routine.id)
    }

    func testProBringsEveryRoutineBack() {
        let (store, gym) = makeStoreWithTwoRoutines(isPro: true)
        XCTAssertEqual(store.activeRoutines.count, 2)
        XCTAssertFalse(store.isLocked(gym.id))
        XCTAssertEqual(store.selectedRoutine?.id, gym.id)
        XCTAssertEqual(store.nextDeparture(now: date(21, 6))?.routine.id, gym.id)
    }
}

/// `-FixedNow` for captures: the time on the latest weekday, never a weekend.
@MainActor
final class AppClockTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testWeekdayKeepsTheDay() {
        // Friday 23 October, 17:49.
        let now = date(23, 17, 49)
        let offset = AppClock.fixedOffset("06:20", now: now, calendar: calendar)
        XCTAssertEqual(offset.map { now.addingTimeInterval($0) }, date(23, 6, 20))
    }

    func testWeekendMovesToTheFridayBefore() {
        for day in [24, 25] {
            let now = date(day, 1, 10)
            let offset = AppClock.fixedOffset("08:14", now: now, calendar: calendar)
            XCTAssertEqual(offset.map { now.addingTimeInterval($0) }, date(23, 8, 14), "day \(day)")
        }
    }

    func testMalformedValueIsIgnored() {
        XCTAssertNil(AppClock.fixedOffset("soon", now: date(23, 9, 0), calendar: calendar))
    }
}
