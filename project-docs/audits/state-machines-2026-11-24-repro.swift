// Repro suite for state-machines-2026-11-24.md. Not in the test target: copy
// it into ShoesOnTests/ to run it (gh-sim test --scheme ShoesOn
// --only ShoesOnTests/StateMachineRepro). Each claim asserts its
// preconditions first, then the promise; each has a passing control.
import XCTest
@testable import ShoesOn

@MainActor
final class StateMachineRepro: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func day(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    /// Weekdays at 8:15. The 21st of September 2026 is a Monday.
    private let routine = Routine(
        name: "Weekday mornings",
        leaveHour: 8,
        leaveMinute: 15,
        weekdays: [2, 3, 4, 5, 6],
        steps: [RoutineStep(name: "Shower", guessMinutes: 10)]
    )

    // MARK: B1, a one-off day moves to the day before after flying west

    func testASkipStaysOnItsDayAfterFlyingWest() {
        let newYork = calendar("America/New_York")
        let losAngeles = calendar("America/Los_Angeles")
        var skipping = routine
        // Home, "Skip Wednesday", set in New York.
        skipping.setChange(DayChange(day: day(23, in: newYork), leaveMinuteOfDay: nil), on: day(23, in: newYork), calendar: newYork)
        XCTAssertFalse(skipping.departs(on: day(23, in: newYork), calendar: newYork), "precondition: Wednesday is skipped in New York")
        XCTAssertTrue(skipping.departs(on: day(22, in: newYork), calendar: newYork), "precondition: Tuesday still departs in New York")
        // Landed in Los Angeles on Monday evening.
        XCTAssertFalse(skipping.departs(on: day(23, in: losAngeles), calendar: losAngeles), "the skipped Wednesday must stay skipped in Los Angeles")
        XCTAssertTrue(skipping.departs(on: day(22, in: losAngeles), calendar: losAngeles), "Tuesday was never skipped")
        XCTAssertEqual(
            skipping.nextScheduledLeave(after: day(21, 20, in: losAngeles), calendar: losAngeles),
            day(22, 8, 15, in: losAngeles),
            "Tuesday's alerts must still come"
        )
    }

    func testControlASkipStaysOnItsDayInOneTimeZone() {
        let newYork = calendar("America/New_York")
        var skipping = routine
        skipping.setChange(DayChange(day: day(23, in: newYork), leaveMinuteOfDay: nil), on: day(23, in: newYork), calendar: newYork)
        XCTAssertFalse(skipping.departs(on: day(23, in: newYork), calendar: newYork))
        XCTAssertEqual(skipping.nextScheduledLeave(after: day(21, 20, in: newYork), calendar: newYork), day(22, 8, 15, in: newYork))
    }

    func testControlASkipStaysOnItsDayAfterFlyingEast() {
        let losAngeles = calendar("America/Los_Angeles")
        let newYork = calendar("America/New_York")
        var skipping = routine
        skipping.setChange(DayChange(day: day(23, in: losAngeles), leaveMinuteOfDay: nil), on: day(23, in: losAngeles), calendar: losAngeles)
        XCTAssertFalse(skipping.departs(on: day(23, in: newYork), calendar: newYork))
        XCTAssertTrue(skipping.departs(on: day(22, in: newYork), calendar: newYork))
    }

    // MARK: B2, saving the routine editor undoes a skip made while it was open

    private func makeStore() -> RoutineStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("repro-\(UUID().uuidString).json")
        let store = RoutineStore(fileURL: url)
        store.save(routine)
        return store
    }

    /// Two days out, so the store's prune of past days never touches it.
    private var soon: Date {
        Calendar.current.startOfDay(for: Date.now.addingTimeInterval(2 * 86_400))
    }

    func testSavingTheEditorKeepsASkipMadeWhileItWasOpen() {
        let store = makeStore()
        // Home, Edit: the editor holds its own copy of the routine.
        var editing = store.routine(id: routine.id)!
        // A get-ready banner's "Skip this time" lands while the editor is up.
        store.setChange(DayChange(day: soon, leaveMinuteOfDay: nil), on: soon, routineID: routine.id)
        XCTAssertNotNil(store.routine(id: routine.id)?.change(on: soon), "precondition: the skip is saved")
        XCTAssertTrue(editing.changes.isEmpty, "precondition: the editor's copy predates the skip")
        // Rename and Save.
        editing.name = "School run"
        store.save(editing)
        XCTAssertEqual(store.routine(id: routine.id)?.name, "School run", "precondition: the edit saved")
        XCTAssertNotNil(store.routine(id: routine.id)?.change(on: soon), "the skip must survive an unrelated edit")
    }

    func testControlSavingTheEditorKeepsAnEarlierSkip() {
        let store = makeStore()
        store.setChange(DayChange(day: soon, leaveMinuteOfDay: nil), on: soon, routineID: routine.id)
        var editing = store.routine(id: routine.id)!
        editing.name = "School run"
        store.save(editing)
        XCTAssertNotNil(store.routine(id: routine.id)?.change(on: soon))
    }
}
