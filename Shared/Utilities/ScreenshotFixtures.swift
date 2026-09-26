#if DEBUG
import Foundation

/// Seeded state for App Store captures and UI tests. `-SeedScreenshotData`
/// writes two weeks of believable mornings; `-Screen run|leaving|summary`
/// opens a run in that state. DEBUG only.
@MainActor
enum ScreenshotFixtures {
    static let routineID = UUID(uuidString: "5A0E5A0E-0000-4000-8000-000000000001")!

    static let steps: [(name: String, guess: Int, real: Double)] = [
        ("Shower", 10, 15.5),
        ("Get dressed", 10, 13),
        ("Breakfast", 15, 19),
        ("Pack bag and lunch", 5, 9),
        ("Shoes, keys, out", 5, 7),
    ]

    static func applyIfRequested(now: Date = AppClock.now) {
        if ScreenshotConfig.has("-DemoPro") { StoreService.shared.setLocalOverride(isPro: true) }
        guard ScreenshotConfig.has("-SeedScreenshotData") else { return }
        AppSettings.shared.hasCompletedSetup = true
        RoutineStore.shared.replaceState(state(screen: ScreenshotConfig.value(after: "-Screen"), now: now))
    }

    static var routine: Routine {
        Routine(
            id: routineID,
            name: "Weekday mornings",
            leaveHour: 8,
            leaveMinute: 15,
            weekdays: [2, 3, 4, 5, 6],
            steps: steps.enumerated().map { index, step in
                RoutineStep(
                    id: UUID(uuidString: String(format: "5A0E5A0E-0000-4000-8000-%012d", index + 10))!,
                    name: step.name,
                    guessMinutes: step.guess
                )
            }
        )
    }

    static func state(screen: String?, now: Date) -> PersistedState {
        let calendar = Calendar.current
        let routine = routine
        var state = PersistedState()
        state.routines = [routine]
        state.selectedRoutineID = routine.id
        state.pace = .halfOver

        // Twelve past mornings, each step a little around its real time.
        let wobble: [Double] = [0.9, 1.1, 1.0, 1.2, 0.95, 1.05, 0.85, 1.15, 1.0, 0.9, 1.1, 1.0]
        let lateness: [Double] = [-3, 0.5, 11, -1, 0, 6, -2, 0.2, -4, 1, 0, -2]
        let pastWeekdays = (1...30)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
            .filter { routine.weekdays.contains(calendar.component(.weekday, from: $0)) }
        for (day, factor) in wobble.enumerated() {
            let date = pastWeekdays[day]
            for (index, step) in routine.steps.enumerated() {
                state.stepHistory.append(StepRecord(
                    stepID: step.id,
                    routineID: routine.id,
                    guessMinutes: step.guessMinutes,
                    actualSeconds: steps[index].real * factor * 60,
                    date: date
                ))
            }
            let target = routine.leaveTime(on: date)
            state.departures.append(DepartureRecord(
                routineID: routine.id,
                target: target,
                left: target.addingTimeInterval(lateness[day] * 60),
                startDelaySeconds: Double(3 + day % 4) * 60
            ))
        }

        if ScreenshotConfig.has("-SeedDayChanges") {
            // The next routine day skipped, and a one-off on the coming Saturday.
            let upcoming = (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
            if let skip = upcoming.first(where: { routine.weekdays.contains(calendar.component(.weekday, from: $0)) }) {
                state.routines[0].setChange(DayChange(day: skip, leaveMinuteOfDay: nil), on: skip)
            }
            if let saturday = upcoming.first(where: { calendar.component(.weekday, from: $0) == 7 }) {
                state.routines[0].setChange(DayChange(day: saturday, leaveMinuteOfDay: 10 * 60 + 40), on: saturday)
            }
        }

        let calibration = Calibration(basePace: state.pace.multiplier, stepHistory: state.stepHistory, departures: state.departures)
        switch screen {
        case "run":
            state.activeRun = midRun(routine: routine, calibration: calibration, now: now)
        case "leaving":
            var run = midRun(routine: routine, calibration: calibration, now: now)
            run.stepIndex = run.steps.count
            run.leaveAt = now.addingTimeInterval(4 * 60 + 20)
            state.activeRun = run
        case "summary":
            var run = midRun(routine: routine, calibration: calibration, now: now)
            let took: [Double] = [14, 12, 17, 8, 6]
            for index in run.steps.indices { run.steps[index].actualSeconds = took[index] * 60 }
            run.stepIndex = run.steps.count
            let departure = DepartureRecord(routineID: routine.id, target: run.leaveAt, left: run.leaveAt.addingTimeInterval(-120), startDelaySeconds: 180)
            state.lastFinished = FinishedRun(run: run, departure: departure)
        default:
            break
        }
        return state
    }

    /// Two steps done, breakfast running a little long, three minutes behind.
    private static func midRun(routine: Routine, calibration: Calibration, now: Date) -> ActiveRun {
        let plan = Planner.plan(routine, leaveAt: now.addingTimeInterval(3600), calibration: calibration)
        var run = ActiveRun(plan: plan, routineName: routine.name, startedAt: now.addingTimeInterval(-30 * 60), alertAt: nil)
        run.steps[0].actualSeconds = 16 * 60
        run.steps[1].actualSeconds = 13 * 60
        run.stepIndex = 2
        run.stepStartedAt = now.addingTimeInterval(-11 * 60 - 25)
        let ready = run.projectedReadyAt(now: now)
        run.leaveAt = ready.addingTimeInterval(-3 * 60)
        return run
    }
}
#endif
