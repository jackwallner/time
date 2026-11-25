import XCTest
@testable import ShoesOn

/// Regression tests for the 2026-11-24 state machine audit
/// (project-docs/audits/state-machines-2026-11-24.md). Each failed on the
/// starting commit; the controls passed there too.
@MainActor
final class StateMachineRegressionTests: XCTestCase {
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

    // MARK: B1, a one-off day stays on its day across time zones

    func testASkipStaysOnItsDayAfterFlyingWest() {
        let newYork = calendar("America/New_York")
        let losAngeles = calendar("America/Los_Angeles")
        var skipping = routine
        skipping.setChange(DayChange(day: day(23, in: newYork), leaveMinuteOfDay: nil), on: day(23, in: newYork), calendar: newYork)
        XCTAssertFalse(skipping.departs(on: day(23, in: newYork), calendar: newYork), "precondition: Wednesday is skipped in New York")
        XCTAssertTrue(skipping.departs(on: day(22, in: newYork), calendar: newYork), "precondition: Tuesday still departs in New York")
        XCTAssertFalse(skipping.departs(on: day(23, in: losAngeles), calendar: losAngeles))
        XCTAssertTrue(skipping.departs(on: day(22, in: losAngeles), calendar: losAngeles))
        XCTAssertEqual(skipping.nextScheduledLeave(after: day(21, 20, in: losAngeles), calendar: losAngeles), day(22, 8, 15, in: losAngeles))
    }

    func testAOneOffTimeStaysOnItsDayAfterFlyingWestAndShowsThere() {
        let london = calendar("Europe/London")
        let losAngeles = calendar("America/Los_Angeles")
        var changed = routine
        changed.setChange(DayChange(day: day(24, in: london), leaveMinuteOfDay: 7 * 60), on: day(24, in: london), calendar: london)
        XCTAssertEqual(changed.leaveTime(on: day(24, in: losAngeles), calendar: losAngeles), day(24, 7, 0, in: losAngeles))
        XCTAssertEqual(changed.leaveTime(on: day(23, in: losAngeles), calendar: losAngeles), day(23, 8, 15, in: losAngeles))
        // Home's "Just this once" card dates it in the zone it is read in.
        let upcoming = changed.upcomingChanges(from: day(22, 12, in: losAngeles), calendar: losAngeles)
        XCTAssertEqual(upcoming.map(\.day), [day(24, in: losAngeles)])
        // Its Undo finds it from that date.
        changed.setChange(nil, on: upcoming[0].day, calendar: losAngeles)
        XCTAssertTrue(changed.changes.isEmpty)
    }

    func testPruningAfterFlyingWestKeepsTodaysChange() {
        let newYork = calendar("America/New_York")
        let losAngeles = calendar("America/Los_Angeles")
        var skipping = routine
        skipping.setChange(DayChange(day: day(23, in: newYork), leaveMinuteOfDay: nil), on: day(23, in: newYork), calendar: newYork)
        skipping.pruneChanges(before: day(23, 6, in: losAngeles), calendar: losAngeles)
        XCTAssertEqual(skipping.changes.count, 1)
        skipping.pruneChanges(before: day(24, 6, in: losAngeles), calendar: losAngeles)
        XCTAssertTrue(skipping.changes.isEmpty)
    }

    func testASkipStaysOnItsDayInOneTimeZone() {
        let newYork = calendar("America/New_York")
        var skipping = routine
        skipping.setChange(DayChange(day: day(23, in: newYork), leaveMinuteOfDay: nil), on: day(23, in: newYork), calendar: newYork)
        XCTAssertFalse(skipping.departs(on: day(23, in: newYork), calendar: newYork))
        XCTAssertEqual(skipping.nextScheduledLeave(after: day(21, 20, in: newYork), calendar: newYork), day(22, 8, 15, in: newYork))
    }

    func testASkipStaysOnItsDayAfterFlyingEast() {
        let losAngeles = calendar("America/Los_Angeles")
        let newYork = calendar("America/New_York")
        var skipping = routine
        skipping.setChange(DayChange(day: day(23, in: losAngeles), leaveMinuteOfDay: nil), on: day(23, in: losAngeles), calendar: losAngeles)
        XCTAssertFalse(skipping.departs(on: day(23, in: newYork), calendar: newYork))
        XCTAssertTrue(skipping.departs(on: day(22, in: newYork), calendar: newYork))
    }

    /// A change saved by 1.0.3 has no time zone. It reads in the current
    /// zone exactly as before, and decodes unchanged.
    func testAChangeSavedBeforeTimeZonesWereKeptStillApplies() throws {
        let newYork = calendar("America/New_York")
        let midnight = day(23, in: newYork)
        let json = """
        {"id":"5A0E5A0E-0000-4000-8000-000000000001","name":"Mornings","leaveHour":8,"leaveMinute":15,
         "weekdays":[2,3,4,5,6],"steps":[{"id":"5A0E5A0E-0000-4000-8000-000000000002","name":"Shower","guessMinutes":10}],
         "changes":[{"day":\(midnight.timeIntervalSinceReferenceDate)}]}
        """
        let decoded = try JSONDecoder().decode(Routine.self, from: Data(json.utf8))
        XCTAssertNil(decoded.changes.first?.timeZone)
        XCTAssertFalse(decoded.departs(on: midnight, calendar: newYork))
        XCTAssertTrue(decoded.departs(on: day(22, in: newYork), calendar: newYork))
        XCTAssertTrue(decoded.departs(on: day(24, in: newYork), calendar: newYork))
        let reencoded = try JSONDecoder().decode(Routine.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(reencoded, decoded)
    }
}
