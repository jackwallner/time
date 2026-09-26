import XCTest
@testable import ShoesOn

final class DayChangeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    /// Weekdays at 8:15. The 21st is a Monday.
    private let routine = Routine(
        name: "Weekday mornings",
        leaveHour: 8,
        leaveMinute: 15,
        weekdays: [2, 3, 4, 5, 6],
        steps: [RoutineStep(name: "Shower", guessMinutes: 10)]
    )

    func testSkippingTomorrowMovesTheNextDepartureOn() {
        var skipping = routine
        skipping.setChange(DayChange(day: date(22), leaveMinuteOfDay: nil), on: date(22), calendar: calendar)
        XCTAssertFalse(skipping.departs(on: date(22), calendar: calendar))
        XCTAssertEqual(skipping.nextScheduledLeave(after: date(21, 9), calendar: calendar), date(23, 8, 15))
    }

    func testAOneOffTimeAppliesToThatDayOnly() {
        var changed = routine
        changed.setChange(DayChange(day: date(22), leaveMinuteOfDay: 7 * 60 + 30), on: date(22), calendar: calendar)
        XCTAssertEqual(changed.leaveTime(on: date(22), calendar: calendar), date(22, 7, 30))
        XCTAssertEqual(changed.leaveTime(on: date(23), calendar: calendar), date(23, 8, 15))
    }

    func testChangesThatChangeNothingAreDropped() {
        var changed = routine
        changed.setChange(DayChange(day: date(22), leaveMinuteOfDay: 8 * 60 + 15), on: date(22), calendar: calendar)
        // Saturday is not a routine day, so skipping it changes nothing either.
        changed.setChange(DayChange(day: date(26), leaveMinuteOfDay: nil), on: date(26), calendar: calendar)
        XCTAssertTrue(changed.changes.isEmpty)
    }

    func testOneChangePerDayAndUndoClearsIt() {
        var changed = routine
        changed.setChange(DayChange(day: date(22), leaveMinuteOfDay: nil), on: date(22, 10), calendar: calendar)
        changed.setChange(DayChange(day: date(22), leaveMinuteOfDay: 9 * 60), on: date(22), calendar: calendar)
        XCTAssertEqual(changed.changes.count, 1)
        XCTAssertEqual(changed.changes.first?.day, date(22))
        changed.setChange(nil, on: date(22), calendar: calendar)
        XCTAssertTrue(changed.changes.isEmpty)
    }

    func testPastChangesArePruned() {
        var changed = routine
        changed.setChange(DayChange(day: date(22), leaveMinuteOfDay: nil), on: date(22), calendar: calendar)
        changed.setChange(DayChange(day: date(24), leaveMinuteOfDay: nil), on: date(24), calendar: calendar)
        changed.pruneChanges(before: date(23, 6), calendar: calendar)
        XCTAssertEqual(changed.changes.map(\.day), [date(24)])
    }

    func testARoutineSavedBeforeChangesExistedStillLoads() throws {
        let json = """
        {"id":"5A0E5A0E-0000-4000-8000-000000000001","name":"Mornings","leaveHour":8,"leaveMinute":15,
         "weekdays":[2,3],"steps":[{"id":"5A0E5A0E-0000-4000-8000-000000000002","name":"Shower","guessMinutes":10}]}
        """
        let decoded = try JSONDecoder().decode(Routine.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.name, "Mornings")
        XCTAssertTrue(decoded.changes.isEmpty)
    }
}
