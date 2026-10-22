import XCTest
@testable import ShoesOn

/// Persona audit evidence for the learning engine: what one odd timing or a
/// very quick step does to the plan. Each assertion documents current behaviour.
@MainActor
final class ExperiencedUserAuditTests: XCTestCase {
    private let step = RoutineStep(name: "Shower", guessMinutes: 10)

    private func calibration(history: [StepRecord]) -> Calibration {
        Calibration(basePace: 1.0, stepHistory: history, departures: [])
    }

    private func record(_ minutes: Double, daysAgo: Int) -> StepRecord {
        StepRecord(
            stepID: step.id,
            routineID: UUID(),
            guessMinutes: 10,
            actualSeconds: minutes * 60,
            date: Date(timeIntervalSince1970: 1_800_000_000 - Double(daysAgo) * 86_400)
        )
    }

    /// A Done tapped hours late (the phone left on the counter) is one timing.
    func testOneForgottenDoneSwingsAStepPlan() {
        let clean = calibration(history: [record(10, daysAgo: 1)]).estimate(for: step).minutes
        let forgotten = calibration(history: [record(174, daysAgo: 1)]).estimate(for: step).minutes
        let afterTwoGoodDays = calibration(history: [record(174, daysAgo: 3), record(10, daysAgo: 2), record(10, daysAgo: 1)]).estimate(for: step).minutes
        let afterEightGoodDays = calibration(history: [record(174, daysAgo: 9)] + (1...8).map { record(10, daysAgo: $0) }).estimate(for: step).minutes
        let text = "10 min step, one clean timing: \(clean) min\none 174 min timing: \(forgotten) min\nthen two 10 min days: \(afterTwoGoodDays) min\nthen eight 10 min days: \(afterEightGoodDays) min"
        let attachment = XCTAttachment(string: text)
        attachment.name = "forgotten-done-effect"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(clean, 10)
        XCTAssertGreaterThan(forgotten, 50, "one late Done more than quintuples the step")
        XCTAssertGreaterThan(afterTwoGoodDays, 15)
        XCTAssertEqual(afterEightGoodDays, 10)
    }

    /// A step that really takes seconds is never timed, so it keeps the paced
    /// guess forever.
    func testSubFifteenSecondStepsNeverTeach() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audit-\(UUID().uuidString).json")
        let store = RoutineStore(fileURL: url)
        let routine = Routine(name: "Mornings", leaveHour: 8, leaveMinute: 0, weekdays: [2], steps: [RoutineStep(name: "Vitamins", guessMinutes: 1), RoutineStep(name: "Shoes", guessMinutes: 5)])
        store.save(routine)
        store.setPace(.halfOver)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        store.startRun(routineID: routine.id, now: start)
        store.completeStep(now: start.addingTimeInterval(10))
        XCTAssertTrue(store.state.stepHistory.isEmpty)
        let plan = store.plan(for: routine, leaveAt: start.addingTimeInterval(3600))
        let vitamins = plan.steps[0].estimate
        let attachment = XCTAttachment(string: "Vitamins guess 1 min, done in 10 s every day, pace 1.5x: planned \(vitamins.minutes) min, source \(vitamins.source)")
        attachment.name = "short-step-never-learned"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(vitamins.minutes, 2)
    }

    /// Forgetting real times also erases the on-time record and start delay.
    func testForgetRealTimesAlsoErasesDepartures() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audit-\(UUID().uuidString).json")
        let store = RoutineStore(fileURL: url)
        let routine = Routine(name: "Mornings", leaveHour: 8, leaveMinute: 0, weekdays: [2], steps: [RoutineStep(name: "Shoes", guessMinutes: 5)])
        store.save(routine)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        store.startRun(routineID: routine.id, now: start)
        store.completeStep(now: start.addingTimeInterval(400))
        store.finishRun(now: start.addingTimeInterval(500))
        XCTAssertEqual(store.state.departures.count, 1)
        store.resetLearning()
        XCTAssertTrue(store.state.stepHistory.isEmpty)
        XCTAssertTrue(store.state.departures.isEmpty)
    }
}
