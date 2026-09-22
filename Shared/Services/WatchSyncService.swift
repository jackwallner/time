import Foundation
import os
import WatchConnectivity

private let watchSyncLogger = Logger(subsystem: AppGroup.subsystem, category: "WatchSync")

/// The phone owns every routine and run. It sends the Watch a `WatchPayload`
/// through the application context; the Watch sends back `WatchCommand`s and
/// gets the new payload in the reply.
final class WatchSyncService: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSyncService()

    private static let payloadKey = "payload"
    private static let commandKey = "command"

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    static func encode(_ payload: WatchPayload) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(payload) else { return [:] }
        return [payloadKey: data]
    }

    static func decode(_ dictionary: [String: Any]) -> WatchPayload? {
        guard let data = dictionary[payloadKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }

    #if os(iOS)
    func push(payload: WatchPayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }
        do {
            try session.updateApplicationContext(Self.encode(payload))
        } catch {
            watchSyncLogger.error("Context sync failed: \(String(describing: error), privacy: .public)")
        }
    }

    @MainActor
    private func handle(_ command: WatchCommand) -> [String: Any] {
        let store = RoutineStore.shared
        // The Watch is a Pro surface; a stale free Watch cannot drive runs.
        guard StoreService.shared.isPro else { return Self.encode(store.watchPayload) }
        switch command {
        case .start: if store.activeRun == nil { store.startNextRun() }
        case .completeStep: store.completeStep()
        case .skipStep: store.skipStep()
        case .leave: store.finishRun()
        }
        return Self.encode(store.watchPayload)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let raw = message[Self.commandKey] as? String, let command = WatchCommand(rawValue: raw) else {
            replyHandler([:])
            return
        }
        let reply = SendableReply(handler: replyHandler)
        Task { @MainActor in reply.handler(self.handle(command)) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let raw = userInfo[Self.commandKey] as? String, let command = WatchCommand(rawValue: raw) else { return }
        Task { @MainActor in _ = self.handle(command) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif

    #if os(watchOS)
    /// Sends a command, preferring a live message so the reply updates the
    /// screen at once; falls back to a queued transfer when the phone is away.
    func send(_ command: WatchCommand) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let message = [Self.commandKey: command.rawValue]
        guard session.isReachable else {
            session.transferUserInfo(message)
            return
        }
        session.sendMessage(message, replyHandler: { reply in
            guard let payload = Self.decode(reply) else { return }
            Task { @MainActor in WatchModel.shared.apply(payload) }
        }, errorHandler: { error in
            watchSyncLogger.error("Command failed: \(String(describing: error), privacy: .public)")
            session.transferUserInfo(message)
        })
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let payload = Self.decode(applicationContext) else { return }
        Task { @MainActor in WatchModel.shared.apply(payload) }
    }
    #endif

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            watchSyncLogger.error("Activation failed: \(String(describing: error), privacy: .public)")
            return
        }
        #if os(watchOS)
        if let payload = Self.decode(session.receivedApplicationContext) {
            Task { @MainActor in WatchModel.shared.apply(payload) }
        }
        #else
        Task { @MainActor in self.push(payload: RoutineStore.shared.watchPayload) }
        #endif
    }
}

/// WatchConnectivity's reply handler is not marked Sendable, but it is safe to
/// call from any thread.
private struct SendableReply: @unchecked Sendable {
    let handler: ([String: Any]) -> Void
}
