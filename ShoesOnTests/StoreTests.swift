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
}
