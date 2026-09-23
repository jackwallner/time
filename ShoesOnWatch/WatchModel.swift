import Foundation
import SwiftUI

/// The Watch's copy of what the phone last sent. The phone stays the only
/// owner of runs; the Watch shows the snapshot and sends commands.
@MainActor
final class WatchModel: ObservableObject {
    static let shared = WatchModel()

    @Published private(set) var payload: WatchPayload?
    /// Set while a command is in flight, so a tap shows at once.
    @Published private(set) var isSending = false

    private let defaults = UserDefaults.standard
    private static let cacheKey = "watchPayload"

    private init() {
        if let data = defaults.data(forKey: Self.cacheKey) {
            payload = try? JSONDecoder().decode(WatchPayload.self, from: data)
        }
        #if DEBUG
        if ScreenshotConfig.has("-SeedScreenshotData") { payload = Self.fixture(now: .now) }
        #endif
    }

    func apply(_ payload: WatchPayload) {
        if let current = self.payload, current.sentAt > payload.sentAt { return }
        self.payload = payload
        isSending = false
        if let data = try? JSONEncoder().encode(payload) { defaults.set(data, forKey: Self.cacheKey) }
    }

    func send(_ command: WatchCommand) {
        isSending = true
        WatchSyncService.shared.send(command)
        Task {
            try? await Task.sleep(for: .seconds(4))
            isSending = false
        }
    }

    #if DEBUG
    static func fixture(now: Date) -> WatchPayload {
        var run = RunSnapshotFixture.make(now: now)
        if ScreenshotConfig.value(after: "-Screen") == "idle" { run = nil }
        return WatchPayload(
            isPro: !ScreenshotConfig.has("-Free"),
            run: run,
            next: NextDepartureSnapshot(
                routineName: "Weekday mornings",
                alertAt: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now,
                leaveAt: Calendar.current.date(bySettingHour: 8, minute: 15, second: 0, of: now) ?? now
            ),
            sentAt: now
        )
    }
    #endif
}

#if DEBUG
enum RunSnapshotFixture {
    static func make(now: Date) -> RunSnapshot? {
        let plan = DeparturePlan(routineID: UUID(), leaveAt: now.addingTimeInterval(40 * 60), steps: [], headStartMinutes: 0)
        var run = ActiveRun(plan: plan, routineName: "Weekday mornings", startedAt: now.addingTimeInterval(-30 * 60), alertAt: nil)
        run.steps = [
            RunStep(id: UUID(), name: "Shower", guessMinutes: 10, plannedMinutes: 15, actualSeconds: 960),
            RunStep(id: UUID(), name: "Get dressed", guessMinutes: 10, plannedMinutes: 13, actualSeconds: 780),
            RunStep(id: UUID(), name: "Breakfast", guessMinutes: 15, plannedMinutes: 19),
            RunStep(id: UUID(), name: "Pack bag and lunch", guessMinutes: 5, plannedMinutes: 9),
            RunStep(id: UUID(), name: "Shoes, keys, out", guessMinutes: 5, plannedMinutes: 7),
        ]
        run.stepIndex = 2
        run.stepStartedAt = now.addingTimeInterval(-11 * 60 - 25)
        run.leaveAt = run.projectedReadyAt(now: now).addingTimeInterval(-3 * 60)
        return RunSnapshot(run: run)
    }
}
#endif
