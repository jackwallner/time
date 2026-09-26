import XCTest
@testable import ShoesOn

final class RunTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeRun(leaveIn minutes: Double = 40) -> ActiveRun {
        let steps = [("Shower", 10), ("Dress", 10), ("Shoes", 5)].map { RoutineStep(name: $0.0, guessMinutes: $0.1) }
        let routine = Routine(name: "Mornings", leaveHour: 8, leaveMinute: 0, weekdays: [], steps: steps)
        let plan = Planner.plan(routine, leaveAt: t0.addingTimeInterval(minutes * 60), calibration: Calibration(basePace: 1.2, stepHistory: [], departures: []))
        return ActiveRun(plan: plan, routineName: routine.name, startedAt: t0, alertAt: t0.addingTimeInterval(-300))
    }

    func testFreshRunWithSlackIsAhead() {
        // Planned 12 + 12 + 6 = 30 min against 40 available.
        XCTAssertEqual(makeRun().status(now: t0), .ahead(minutes: 10))
    }

    func testRunningOverAStepSlipsTheWholeMorning() {
        let run = makeRun(leaveIn: 30)
        XCTAssertEqual(run.status(now: t0), .onTrack)
        // Twenty minutes into a twelve-minute shower.
        XCTAssertEqual(run.status(now: t0.addingTimeInterval(20 * 60)), .behind(minutes: 8))
    }

    func testFinishingEarlyBanksTheTime() {
        var run = makeRun(leaveIn: 30)
        _ = run.completeCurrentStep(at: t0.addingTimeInterval(7 * 60))
        XCTAssertEqual(run.status(now: t0.addingTimeInterval(7 * 60)), .ahead(minutes: 5))
        XCTAssertEqual(run.steps[0].actualSeconds, 7 * 60)
        XCTAssertEqual(run.stepIndex, 1)
    }

    func testSkippingRecordsNoTime() {
        var run = makeRun()
        run.skipCurrentStep(at: t0.addingTimeInterval(60))
        XCTAssertTrue(run.steps[0].skipped)
        XCTAssertNil(run.steps[0].actualSeconds)
    }

    func testLeavingPhaseComparesNowWithTheLeaveTime() {
        var run = makeRun(leaveIn: 30)
        for minute in [10.0, 20, 25] { _ = run.completeCurrentStep(at: t0.addingTimeInterval(minute * 60)) }
        XCTAssertTrue(run.isLeaving)
        XCTAssertEqual(run.status(now: t0.addingTimeInterval(25 * 60)), .ahead(minutes: 5))
        XCTAssertEqual(run.status(now: t0.addingTimeInterval(34 * 60)), .behind(minutes: 4))
    }

    func testStartDelayOnlyCountsWhenAnsweringTheAlert() {
        XCTAssertEqual(makeRun().startDelaySeconds, 300)
        var early = makeRun()
        early.alertAt = t0.addingTimeInterval(600)
        XCTAssertEqual(early.startDelaySeconds, 0)
        var unrelated = makeRun()
        unrelated.alertAt = t0.addingTimeInterval(-7200)
        XCTAssertNil(unrelated.startDelaySeconds)
    }

    func testWhenBehindItSuggestsTheStepThatCoversTheSlip() {
        // Planned 12 + 12 + 6 = 30 min for a 30 min window, twenty minutes into the shower.
        let run = makeRun(leaveIn: 30)
        let late = t0.addingTimeInterval(20 * 60)
        XCTAssertEqual(run.catchUpSuggestion(now: late)?.name, "Dress")
        // Never the last step, and nothing to suggest when on track.
        XCTAssertNil(run.catchUpSuggestion(now: t0))
    }

    func testDroppingAStepWinsItsTimeBackAndIsPassedOver() {
        var run = makeRun(leaveIn: 30)
        let late = t0.addingTimeInterval(20 * 60)
        run.dropUpcomingStep(id: run.steps[1].id)
        // Ready at 20 + 6 = 26 min for a 30 min window.
        XCTAssertEqual(run.status(now: late), .ahead(minutes: 4))
        XCTAssertEqual(run.nextStep?.name, "Shoes")
        XCTAssertEqual(run.planStepCount, 2)
        _ = run.completeCurrentStep(at: late)
        XCTAssertEqual(run.currentStep?.name, "Shoes")
        XCTAssertEqual(run.planStepNumber, 2)
        XCTAssertNil(run.steps[1].actualSeconds)
        XCTAssertTrue(run.steps[1].skipped)
    }

    func testTheCurrentStepCannotBeDropped() {
        var run = makeRun()
        run.dropUpcomingStep(id: run.steps[0].id)
        XCTAssertFalse(run.steps[0].skipped)
    }

    func testARunLeftOpenForHoursIsAbandoned() {
        let run = makeRun(leaveIn: 30)
        XCTAssertFalse(run.isAbandoned(now: t0.addingTimeInterval(2 * 3600)))
        XCTAssertTrue(run.isAbandoned(now: t0.addingTimeInterval(4 * 3600)))
    }

    func testSnapshotProjectsTheSameStatusAsTheRun() {
        let run = makeRun(leaveIn: 30)
        let snapshot = RunSnapshot(run: run)
        for minute in stride(from: 0.0, through: 40, by: 5) {
            let now = t0.addingTimeInterval(minute * 60)
            XCTAssertEqual(snapshot.status(now: now), run.status(now: now), "minute \(minute)")
        }
    }
}
