import XCTest
@testable import ShoesOn

/// The unfolded iPhone Duo's split, and the run timeline its second pane shows.
final class UnfoldedLayoutTests: XCTestCase {
    func testCompactWidthNeverSplits() {
        // The folded Duo and every ordinary iPhone.
        XCTAssertNil(UnfoldedSplit.make(width: 867, isRegularWidth: false, fold: 455.5...495.5))
    }

    func testTooNarrowForTwoPanesStaysOneColumn() {
        // The unfolded Duo held in portrait.
        XCTAssertNil(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil))
    }

    func testPanesMeetTheFoldEdges() {
        let split = UnfoldedSplit.make(width: 867, isRegularWidth: true, fold: 455.5...495.5)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 455.5, secondaryX: 495.5, secondaryWidth: 371.5))
    }

    func testNoFoldSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    func testFoldLeavingANarrowPaneFallsBackToEven() {
        let split = UnfoldedSplit.make(width: 900, isRegularWidth: true, fold: 100...140)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 450, secondaryX: 450, secondaryWidth: 450))
    }

    // MARK: - Run timeline

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    /// Planned 12 + 12 + 6 min (10, 10 and 5 guessed at a 1.2 pace).
    private func makeRun() -> ActiveRun {
        let steps = [("Shower", 10), ("Dress", 10), ("Shoes", 5)].map { RoutineStep(name: $0.0, guessMinutes: $0.1) }
        let routine = Routine(name: "Mornings", leaveHour: 8, leaveMinute: 0, weekdays: [], steps: steps)
        let plan = Planner.plan(routine, leaveAt: t0.addingTimeInterval(40 * 60), calibration: Calibration(basePace: 1.2, stepHistory: [], departures: []))
        return ActiveRun(plan: plan, routineName: routine.name, startedAt: t0, alertAt: nil)
    }

    func testUpcomingStepsChainFromTheCurrentStepsEnd() {
        let stops = makeRun().timeline(now: t0.addingTimeInterval(5 * 60))
        XCTAssertEqual(stops.map(\.phase), [.current, .upcoming, .upcoming])
        XCTAssertEqual(stops.map(\.startsAt), [t0, t0.addingTimeInterval(12 * 60), t0.addingTimeInterval(24 * 60)])
        XCTAssertEqual(stops.map(\.minutes), [12, 12, 6])
    }

    func testARunningOverStepPushesTheRestFromNow() {
        let now = t0.addingTimeInterval(15 * 60)
        let stops = makeRun().timeline(now: now)
        XCTAssertEqual(stops[1].startsAt, now)
        XCTAssertEqual(stops[2].startsAt, now.addingTimeInterval(12 * 60))
    }

    func testDoneStepsShowTheirRealMinutesAndDroppedOnesHoldNoTime() {
        var run = makeRun()
        _ = run.completeCurrentStep(at: t0.addingTimeInterval(16 * 60))
        run.dropUpcomingStep(id: run.steps[2].id)
        let stops = run.timeline(now: t0.addingTimeInterval(17 * 60))
        XCTAssertEqual(stops.map(\.phase), [.done, .current, .skipped])
        XCTAssertEqual(stops[0].minutes, 16)
        XCTAssertNil(stops[0].startsAt)
        XCTAssertNil(stops[2].startsAt)
    }

    func testLeavingHasEveryStepBehindIt() {
        var run = makeRun()
        for minute in [10.0, 20, 25] { _ = run.completeCurrentStep(at: t0.addingTimeInterval(minute * 60)) }
        XCTAssertEqual(run.timeline(now: t0.addingTimeInterval(26 * 60)).map(\.phase), [.done, .done, .done])
    }
}
