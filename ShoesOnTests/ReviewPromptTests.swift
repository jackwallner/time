import XCTest
@testable import ShoesOn

/// The rating ask: which mornings count, and the gates around the call.
@MainActor
final class ReviewPromptTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "review-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private let target = Date(timeIntervalSinceReferenceDate: 820_000_000)

    private func finished(leftAfter seconds: TimeInterval, practice: Bool = false, skipFirst: Bool = false) -> FinishedRun {
        let routine = Routine(
            name: "Weekday mornings", leaveHour: 8, leaveMinute: 15, weekdays: [2, 3, 4, 5, 6],
            steps: [RoutineStep(name: "Shower", guessMinutes: 10), RoutineStep(name: "Shoes", guessMinutes: 5)]
        )
        let plan = Planner.plan(routine, leaveAt: target, calibration: Calibration(basePace: 1, stepHistory: [], departures: []))
        var run = ActiveRun(plan: plan, routineName: routine.name, startedAt: target.addingTimeInterval(-900), alertAt: nil, isPractice: practice)
        for index in run.steps.indices {
            if skipFirst && index == 0 { run.steps[index].skipped = true } else { run.steps[index].actualSeconds = 400 }
        }
        run.stepIndex = run.steps.count
        let departure = DepartureRecord(routineID: routine.id, target: target, left: target.addingTimeInterval(seconds), startDelaySeconds: nil)
        return FinishedRun(run: run, departure: departure)
    }

    // MARK: The moment

    func testLeavingOnTimeIsAGoodMoment() {
        let early = finished(leftAfter: -240)
        XCTAssertTrue(ReviewPromptService.isGoodMoment(early, now: early.departure.left.addingTimeInterval(5)))
        let onTheDot = finished(leftAfter: 50)
        XCTAssertTrue(ReviewPromptService.isGoodMoment(onTheDot, now: onTheDot.departure.left.addingTimeInterval(5)))
    }

    func testLeavingLateIsNot() {
        let late = finished(leftAfter: 61)
        XCTAssertFalse(ReviewPromptService.isGoodMoment(late, now: late.departure.left.addingTimeInterval(5)))
        let veryLate = finished(leftAfter: 900)
        XCTAssertFalse(ReviewPromptService.isGoodMoment(veryLate, now: veryLate.departure.left.addingTimeInterval(5)))
    }

    func testAPracticeRunCountsOnlyWithEveryStepDone() {
        let done = finished(leftAfter: 0, practice: true)
        XCTAssertTrue(ReviewPromptService.isGoodMoment(done, now: done.departure.left.addingTimeInterval(5)))
        let skipped = finished(leftAfter: 0, practice: true, skipFirst: true)
        XCTAssertFalse(ReviewPromptService.isGoodMoment(skipped, now: skipped.departure.left.addingTimeInterval(5)))
    }

    /// A summary reopened after a relaunch hours later is not the moment.
    func testAStaleSummaryIsNotAMoment() {
        let early = finished(leftAfter: -240)
        XCTAssertFalse(ReviewPromptService.isGoodMoment(early, now: early.departure.left.addingTimeInterval(31 * 60)))
    }

    // MARK: The gates

    func testFirstLaunchIsBlockedAndTheSecondAllowed() {
        let now = Date()
        let first = ReviewPromptService(defaults: defaults)
        XCTAssertFalse(first.shouldRequestReview(now: now), "no launch yet")
        first.recordLaunch()
        first.recordLaunch()
        XCTAssertEqual(first.launchCount, 1, "one process is one launch")
        XCTAssertFalse(first.shouldRequestReview(now: now), "launch 1 is blocked")
        let second = ReviewPromptService(defaults: defaults)
        second.recordLaunch()
        XCTAssertEqual(second.launchCount, 2)
        XCTAssertTrue(second.shouldRequestReview(now: now), "launch 2 is allowed")
    }

    func testThirtyDayCooldownFromTheCall() {
        let service = launched(times: 2)
        let asked = Date()
        service.markAsked(now: asked)
        XCTAssertFalse(service.shouldRequestReview(now: asked.addingTimeInterval(29 * 86_400)))
        XCTAssertTrue(service.shouldRequestReview(now: asked.addingTimeInterval(30 * 86_400)))
    }

    func testAStampFromTheFutureDoesNotHoldTheCooldownShut() {
        let service = launched(times: 2)
        let now = Date()
        service.markAsked(now: now.addingTimeInterval(400 * 86_400))
        XCTAssertTrue(service.shouldRequestReview(now: now))
    }

    func testOpeningWriteReviewEndsTheAsks() {
        let service = launched(times: 2)
        let now = Date()
        service.markOpenedWriteReview(now: now)
        XCTAssertFalse(service.shouldRequestReview(now: now.addingTimeInterval(400 * 86_400)))
    }

    /// An install asked by 1.0.3 keeps that stamp's cooldown.
    func testA103AskStampStillCounts() {
        let asked = Date()
        defaults.set(asked, forKey: "reviewLastAskedAt")
        let service = launched(times: 3)
        XCTAssertFalse(service.shouldRequestReview(now: asked.addingTimeInterval(10 * 86_400)))
    }

    private func launched(times: Int) -> ReviewPromptService {
        var service = ReviewPromptService(defaults: defaults)
        for _ in 0..<times {
            service = ReviewPromptService(defaults: defaults)
            service.recordLaunch()
        }
        return service
    }
}
