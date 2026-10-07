import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Everything Shoes On remembers, in one file in the App Group container.
struct PersistedState: Codable, Sendable {
    var routines: [Routine] = []
    var selectedRoutineID: UUID?
    var pace: PaceAnswer = .quarterOver
    var stepHistory: [StepRecord] = []
    var departures: [DepartureRecord] = []
    var activeRun: ActiveRun?
    /// The run that just ended, kept so the summary can be shown after a
    /// relaunch and dismissed on purpose.
    var lastFinished: FinishedRun?
}

/// The run as it stood before the last Done, Skip or catch-up skip, so a
/// mis-tap on a busy morning can be taken back. Held in memory only: it is
/// for the next few seconds, not for a relaunch.
struct StepUndo: Sendable {
    enum Kind: Sendable {
        case done
        case skip
        /// A later step taken off the plan to catch up.
        case drop
    }

    let id = UUID()
    var before: ActiveRun
    var after: ActiveRun
    /// The timing that Done added to the history, removed again on undo.
    var recordedStepID: UUID?
    var kind: Kind
    var stepName: String
}

/// A run after the user walked out, for the summary screen.
struct FinishedRun: Codable, Hashable, Sendable {
    var run: ActiveRun
    var departure: DepartureRecord
}

/// The single door to routines, runs and history. Every change goes through
/// here, and every change fans out to notifications, the Live Activity and
/// the Watch, so no surface can drift from the others.
@MainActor
final class RoutineStore: ObservableObject {
    static let shared = RoutineStore()

    @Published private(set) var state: PersistedState
    @Published private(set) var lastStepUndo: StepUndo?

    private let logger = Logger(subsystem: AppGroup.subsystem, category: "Store")
    private let fileURL: URL
    /// Kept long enough to learn from, short enough to stay small.
    private static let historyLimit = 600
    private static let departureLimit = 200
    /// A Done tapped this quickly was a tap-through, not a timing.
    static let minimumTimedSeconds: TimeInterval = 15

    init(fileURL: URL = AppGroup.containerURL.appendingPathComponent("shoeson-state.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) {
            state = decoded
        } else {
            state = PersistedState()
        }
    }

    // MARK: - Reading

    var routines: [Routine] { state.routines }
    var activeRun: ActiveRun? { state.activeRun }

    var selectedRoutine: Routine? {
        state.routines.first { $0.id == state.selectedRoutineID } ?? state.routines.first
    }

    var calibration: Calibration {
        Calibration(basePace: state.pace.multiplier, stepHistory: state.stepHistory, departures: state.departures)
    }

    func routine(id: UUID) -> Routine? {
        state.routines.first { $0.id == id }
    }

    func plan(for routine: Routine, leaveAt: Date) -> DeparturePlan {
        Planner.plan(routine, leaveAt: leaveAt, calibration: calibration)
    }

    /// The next scheduled departure, or nil when the routine has no days.
    func nextPlan(for routine: Routine, now: Date = .now) -> DeparturePlan? {
        var after = now
        // Past any departure already made, so leaving early for 8:15 at 8:05
        // moves the card on to the next one.
        for _ in 0..<3 {
            guard let leave = routine.nextScheduledLeave(after: after) else { return nil }
            let made = state.departures.contains { $0.routineID == routine.id && $0.target == leave }
            if !made { return plan(for: routine, leaveAt: leave) }
            after = leave
        }
        return nil
    }

    /// The soonest departure across every routine.
    func nextDeparture(now: Date = .now) -> (routine: Routine, plan: DeparturePlan)? {
        state.routines
            .compactMap { routine in nextPlan(for: routine, now: now).map { (routine, $0) } }
            .min { $0.1.leaveAt < $1.1.leaveAt }
    }

    /// The next departures across every routine, soonest first, as far ahead
    /// as the alerts reach so the widget never goes blank before they do.
    func upcomingDepartures(now: Date = .now, limit: Int = 12) -> [(routine: Routine, plan: DeparturePlan)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var found: [(routine: Routine, plan: DeparturePlan)] = []
        for routine in state.routines {
            for offset in 0...NotificationPlan.horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      routine.departs(on: day) else { continue }
                let leave = routine.leaveTime(on: day)
                guard leave > now else { continue }
                if state.activeRun?.routineID == routine.id && state.activeRun?.leaveAt == leave { continue }
                if state.departures.contains(where: { $0.routineID == routine.id && $0.target == leave }) { continue }
                found.append((routine, plan(for: routine, leaveAt: leave)))
            }
        }
        return Array(found.sorted { $0.plan.leaveAt < $1.plan.leaveAt }.prefix(limit))
    }

    func departures(for routineID: UUID) -> [DepartureRecord] {
        state.departures.filter { $0.routineID == routineID }.sorted { $0.left > $1.left }
    }

    // MARK: - Routines

    func setPace(_ pace: PaceAnswer) {
        mutate { $0.pace = pace }
    }

    func select(_ routineID: UUID) {
        mutate { $0.selectedRoutineID = routineID }
    }

    func save(_ routine: Routine) {
        mutate { state in
            if let index = state.routines.firstIndex(where: { $0.id == routine.id }) {
                state.routines[index] = routine
            } else {
                state.routines.append(routine)
                state.selectedRoutineID = routine.id
            }
        }
    }

    func delete(_ routineID: UUID) {
        mutate { state in
            state.routines.removeAll { $0.id == routineID }
            state.stepHistory.removeAll { $0.routineID == routineID }
            state.departures.removeAll { $0.routineID == routineID }
            if state.activeRun?.routineID == routineID { state.activeRun = nil }
            if state.selectedRoutineID == routineID { state.selectedRoutineID = state.routines.first?.id }
        }
    }

    /// Skips one day, gives it a one-off leave time, or with nil puts it back
    /// to normal.
    func setChange(_ change: DayChange?, on day: Date, routineID: UUID) {
        mutate { state in
            guard let index = state.routines.firstIndex(where: { $0.id == routineID }) else { return }
            state.routines[index].setChange(change, on: day)
            state.routines[index].pruneChanges(before: .now)
        }
    }

    /// Forgets every timing, keeping the routines and the pace answer.
    func resetLearning() {
        mutate { state in
            state.stepHistory = []
            state.departures = []
            state.lastFinished = nil
        }
    }

    // MARK: - Runs

    /// Starting more than this before a departure's start time is not getting
    /// ready for it; it is trying the routine out.
    static let practiceLeadSeconds: TimeInterval = 3600

    /// What a run started now aims for: the routine's next leave time, or,
    /// well before that departure is due to start, a practice run planned
    /// from now. A practice run at 10 PM must not count as tomorrow's
    /// departure, or it would cancel tomorrow's alerts.
    func runTarget(for routine: Routine, now: Date = .now) -> (leaveAt: Date, isPractice: Bool) {
        let leave = nextPlan(for: routine, now: now)?.leaveAt ?? routine.leaveTimeForRunStarted(at: now)
        let due = plan(for: routine, leaveAt: leave)
        guard due.alertAt.timeIntervalSince(now) > Self.practiceLeadSeconds else { return (leave, false) }
        let ready = now.addingTimeInterval(TimeInterval(due.realMinutes * 60))
        let minute = (ready.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60
        return (Date(timeIntervalSinceReferenceDate: minute), true)
    }

    func startRun(routineID: UUID, now: Date = .now) {
        guard state.activeRun == nil, let routine = routine(id: routineID) else { return }
        let target = runTarget(for: routine, now: now)
        let plan = plan(for: routine, leaveAt: target.leaveAt)
        let answersAlert = !target.isPractice && routine.departs(on: target.leaveAt) && AppSettings.shared.startAlerts
        lastStepUndo = nil
        mutate { state in
            state.activeRun = ActiveRun(
                plan: plan,
                routineName: routine.name,
                startedAt: now,
                alertAt: answersAlert ? plan.alertAt : nil,
                isPractice: target.isPractice
            )
            state.selectedRoutineID = routineID
            state.lastFinished = nil
        }
    }

    /// A tap on a get-ready alert or its follow-up: the tap is the start. Does
    /// nothing once that departure is under way, made or gone, so an old alert
    /// opened from Notification Centre at noon only opens the app.
    func startRunFromAlert(routineID: UUID, leaveAt: Date, now: Date = .now) {
        guard state.activeRun == nil, leaveAt > now,
              let routine = routine(id: routineID),
              nextPlan(for: routine, now: now)?.leaveAt == leaveAt,
              !state.departures.contains(where: { $0.routineID == routineID && $0.target == leaveAt })
        else { return }
        startRun(routineID: routineID, now: now)
    }

    /// Starts the soonest routine, for the notification and the Watch.
    func startNextRun(now: Date = .now) {
        guard let routine = nextDeparture(now: now)?.routine ?? selectedRoutine else { return }
        startRun(routineID: routine.id, now: now)
    }

    func completeStep(now: Date = .now) {
        guard let before = state.activeRun, !before.isLeaving else { return }
        var run = before
        let finished = run.completeCurrentStep(at: now)
        var recorded: UUID?
        mutate { state in
            state.activeRun = run
            if let finished, let seconds = finished.actualSeconds, seconds >= Self.minimumTimedSeconds {
                state.stepHistory.append(StepRecord(
                    stepID: finished.id,
                    routineID: run.routineID,
                    guessMinutes: finished.guessMinutes,
                    actualSeconds: seconds,
                    date: now
                ))
                state.stepHistory = Array(state.stepHistory.suffix(Self.historyLimit))
                recorded = finished.id
            }
        }
        lastStepUndo = StepUndo(before: before, after: run, recordedStepID: recorded, kind: .done, stepName: finished?.name ?? "")
    }

    func skipStep(now: Date = .now) {
        guard let before = state.activeRun, !before.isLeaving else { return }
        var run = before
        run.skipCurrentStep(at: now)
        mutate { $0.activeRun = run }
        lastStepUndo = StepUndo(before: before, after: run, recordedStepID: nil, kind: .skip, stepName: before.currentStep?.name ?? "")
    }

    /// Puts the last Done, Skip or catch-up skip back, as long as nothing has
    /// moved since. The step picks up its clock where it was, as if it never
    /// ended.
    func undoLastStep() {
        guard let undo = lastStepUndo, state.activeRun == undo.after else {
            lastStepUndo = nil
            return
        }
        lastStepUndo = nil
        mutate { state in
            state.activeRun = undo.before
            if let id = undo.recordedStepID, let index = state.stepHistory.lastIndex(where: { $0.stepID == id }) {
                state.stepHistory.remove(at: index)
            }
        }
    }

    /// Takes a later step off today's plan to catch up.
    func dropUpcomingStep(id: UUID) {
        guard let before = state.activeRun, let step = before.steps.first(where: { $0.id == id }) else { return }
        var run = before
        run.dropUpcomingStep(id: id)
        guard run != before else { return }
        mutate { $0.activeRun = run }
        lastStepUndo = StepUndo(before: before, after: run, recordedStepID: nil, kind: .drop, stepName: step.name)
    }

    /// The user walked out. Records the departure and hands back the summary.
    @discardableResult
    func finishRun(now: Date = .now) -> FinishedRun? {
        guard let run = state.activeRun else { return nil }
        let departure = DepartureRecord(
            routineID: run.routineID,
            target: run.leaveAt,
            left: now,
            startDelaySeconds: run.startDelaySeconds
        )
        let finished = FinishedRun(run: run, departure: departure)
        lastStepUndo = nil
        mutate { state in
            state.activeRun = nil
            if !run.isPracticeRun { state.departures.append(departure) }
            state.departures = Array(state.departures.suffix(Self.departureLimit))
            state.lastFinished = finished
        }
        return finished
    }

    func cancelRun() {
        lastStepUndo = nil
        mutate { $0.activeRun = nil }
    }

    func dismissSummary() {
        mutate { $0.lastFinished = nil }
    }

    // MARK: - Persistence and fan-out

    /// Tidies what time has made stale, then pushes everything out. Called
    /// whenever the app comes to the foreground.
    func refresh(now: Date = .now) {
        let stale = state.activeRun?.isAbandoned(now: now) == true
        let oldSummary = state.lastFinished.map { now.timeIntervalSince($0.departure.left) > 12 * 3600 } ?? false
        let hasPastChanges = state.routines.contains { $0.changes.contains { $0.day < Calendar.current.startOfDay(for: now) } }
        guard stale || oldSummary || hasPastChanges else {
            propagate()
            return
        }
        mutate { state in
            // A run left open for hours was never closed, not a three hour
            // morning. Its finished steps already count; the departure does not.
            if stale { state.activeRun = nil }
            if oldSummary { state.lastFinished = nil }
            for index in state.routines.indices { state.routines[index].pruneChanges(before: now) }
        }
    }

    private func mutate(_ change: (inout PersistedState) -> Void) {
        change(&state)
        persist()
        propagate()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Save failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Pushes the current state to every surface that shows it.
    func propagate() {
        #if os(iOS)
        NotificationService.shared.reschedule(store: self)
        LiveActivityService.shared.sync(run: state.activeRun)
        WatchSyncService.shared.push(payload: watchPayload)
        publishWidgetSnapshot()
        #endif
    }

    private var lastWidgetSnapshot: Data?

    /// Hands the widgets the next departures and reloads them only when that
    /// changed.
    private func publishWidgetSnapshot() {
        #if canImport(WidgetKit)
        let snapshot = WidgetSnapshot(departures: upcomingSnapshots(), run: state.activeRun.map(RunSnapshot.init(run:)))
        guard let data = try? JSONEncoder().encode(snapshot), data != lastWidgetSnapshot else { return }
        lastWidgetSnapshot = data
        AppGroup.defaults.set(data, forKey: WidgetSnapshot.defaultsKey)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
        #endif
    }

    private func upcomingSnapshots() -> [NextDepartureSnapshot] {
        upcomingDepartures().map {
            NextDepartureSnapshot(routineName: $0.routine.name, alertAt: $0.plan.alertAt, leaveAt: $0.plan.leaveAt)
        }
    }

    var watchPayload: WatchPayload {
        let next = nextDeparture().map {
            NextDepartureSnapshot(routineName: $0.routine.name, alertAt: $0.plan.alertAt, leaveAt: $0.plan.leaveAt)
        }
        return WatchPayload(
            isPro: StoreService.shared.isPro,
            run: state.activeRun.map(RunSnapshot.init(run:)),
            next: next,
            upcoming: upcomingSnapshots(),
            sentAt: .now
        )
    }

    #if DEBUG
    /// Replaces everything, for screenshots and tests.
    func replaceState(_ newState: PersistedState) {
        state = newState
        persist()
    }
    #endif
}
