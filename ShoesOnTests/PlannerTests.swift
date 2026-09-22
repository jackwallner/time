import XCTest
@testable import ShoesOn

final class PlannerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func routine(_ steps: [(String, Int)] = [("Shower", 10), ("Dress", 10), ("Breakfast", 15), ("Shoes", 5)]) -> Routine {
        Routine(
            name: "Weekday mornings",
            leaveHour: 8,
            leaveMinute: 15,
            weekdays: [2, 3, 4, 5, 6],
            steps: steps.map { RoutineStep(name: $0.0, guessMinutes: $0.1) }
        )
    }

    func testEachStepRoundsUpToAWholeMinute() {
        let routine = routine([("Shoes", 5)])
        let plan = Planner.plan(routine, leaveAt: date(22, 8, 15), calibration: Calibration(basePace: 1.5, stepHistory: [], departures: []))
        XCTAssertEqual(plan.realMinutes, 8)
    }

    func testGuessesAreTrustedAtAnHonestPace() {
        let routine = routine()
        let plan = Planner.plan(routine, leaveAt: date(22, 8, 15), calibration: Calibration(basePace: 1.0, stepHistory: [], departures: []))
        XCTAssertEqual(plan.guessMinutes, 40)
        XCTAssertEqual(plan.realMinutes, 40)
        XCTAssertEqual(plan.getReadyAt, date(22, 7, 35))
        XCTAssertEqual(plan.alertAt, date(22, 7, 35))
    }

    /// The motivating case: someone who underestimates by half and runs about
    /// half an hour late gets told to start that much earlier.
    func testHalfOverPaceStartsTwentyMinutesEarlierOnAFortyMinuteRoutine() {
        let routine = routine([("Shower", 10), ("Dress", 10), ("Breakfast", 14), ("Shoes", 6)])
        let plan = Planner.plan(routine, leaveAt: date(22, 8, 15), calibration: Calibration(basePace: 1.5, stepHistory: [], departures: []))
        XCTAssertEqual(plan.realMinutes, 60)
        XCTAssertEqual(plan.hiddenMinutes, 20)
        XCTAssertEqual(plan.getReadyAt, date(22, 7, 15))
    }

    func testStepsAreLaidOutBackwardFromTheLeaveTime() {
        let routine = routine([("A", 10), ("B", 20)])
        let plan = Planner.plan(routine, leaveAt: date(22, 8, 0), calibration: Calibration(basePace: 1.0, stepHistory: [], departures: []))
        XCTAssertEqual(plan.steps.map(\.step.name), ["A", "B"])
        XCTAssertEqual(plan.steps[0].startsAt, date(22, 7, 30))
        XCTAssertEqual(plan.steps[0].endsAt, date(22, 7, 40))
        XCTAssertEqual(plan.steps[1].endsAt, date(22, 8, 0))
    }

    func testTimedStepsReplaceTheGuess() {
        let routine = routine([("Shower", 10)])
        let step = routine.steps[0]
        let history = (0..<8).map { day in
            StepRecord(stepID: step.id, routineID: routine.id, guessMinutes: 10, actualSeconds: 18 * 60, date: date(10 + day, 7, 0))
        }
        let calibration = Calibration(basePace: 1.0, stepHistory: history, departures: [])
        let estimate = calibration.estimate(for: step)
        XCTAssertEqual(estimate.source, .learned(runs: 8))
        // Eight timings of 18 against a paced prior worth two: pulled most of the way.
        XCTAssertGreaterThanOrEqual(estimate.minutes, 16)
        XCTAssertLessThanOrEqual(estimate.minutes, 18)
    }

    func testOneOddMorningDoesNotSwingAStep() {
        let routine = routine([("Shower", 10)])
        let step = routine.steps[0]
        let history = [StepRecord(stepID: step.id, routineID: routine.id, guessMinutes: 10, actualSeconds: 45 * 60, date: date(21, 7, 0))]
        let estimate = Calibration(basePace: 1.0, stepHistory: history, departures: []).estimate(for: step)
        XCTAssertLessThan(estimate.minutes, 25)
    }

    func testPaceLearnsFromEveryStepAndAppliesToNewOnes() {
        let routine = routine([("Shower", 10), ("New thing", 10)])
        let shower = routine.steps[0]
        let history = (0..<30).map { day in
            StepRecord(stepID: shower.id, routineID: routine.id, guessMinutes: 10, actualSeconds: 20 * 60, date: date(1, 7, 0).addingTimeInterval(Double(day) * 86_400))
        }
        let calibration = Calibration(basePace: 1.0, stepHistory: history, departures: [])
        XCTAssertGreaterThan(calibration.pace, 1.7)
        let untimed = calibration.estimate(for: routine.steps[1])
        XCTAssertEqual(untimed.source, .pace)
        XCTAssertGreaterThanOrEqual(untimed.minutes, 18)
    }

    func testPaceStaysWithinBounds() {
        let routine = routine([("Shower", 1)])
        let history = (0..<40).map { day in
            StepRecord(stepID: routine.steps[0].id, routineID: routine.id, guessMinutes: 1, actualSeconds: 60 * 60, date: date(1, 7, 0).addingTimeInterval(Double(day) * 3600))
        }
        XCTAssertLessThanOrEqual(Calibration(basePace: 2.0, stepHistory: history, departures: []).pace, 3.0)
    }

    func testStartDelayBecomesAHeadStart() {
        let routine = routine()
        let departures = (0..<6).map { day in
            DepartureRecord(routineID: routine.id, target: date(10 + day, 8, 15), left: date(10 + day, 8, 15), startDelaySeconds: 8 * 60)
        }
        let calibration = Calibration(basePace: 1.0, stepHistory: [], departures: departures)
        // Median 8, blended with two pseudo-samples of zero: 6.
        XCTAssertEqual(calibration.startDelayMinutes, 6)
        let plan = Planner.plan(routine, leaveAt: date(22, 8, 15), calibration: calibration)
        XCTAssertEqual(plan.alertAt, date(22, 7, 29))
    }

    func testStartDelayIsCapped() {
        let routine = routine()
        let departures = (0..<10).map { day in
            DepartureRecord(routineID: routine.id, target: date(10 + day, 8, 15), left: date(10 + day, 8, 15), startDelaySeconds: 50 * 60)
        }
        XCTAssertLessThanOrEqual(Calibration(basePace: 1.0, stepHistory: [], departures: departures).startDelayMinutes, 20)
    }

    func testNextScheduledLeaveSkipsDaysOff() {
        let routine = routine()
        // Saturday 19 September 2026, after the leave time: next is Monday.
        let next = routine.nextScheduledLeave(after: date(19, 9, 0), calendar: calendar)
        XCTAssertEqual(next, date(21, 8, 15))
    }

    func testManualRunAimsForTodayOrTomorrow() {
        let routine = routine()
        XCTAssertEqual(routine.leaveTimeForRunStarted(at: date(19, 7, 0), calendar: calendar), date(19, 8, 15))
        XCTAssertEqual(routine.leaveTimeForRunStarted(at: date(19, 9, 0), calendar: calendar), date(20, 8, 15))
    }
}
