import Foundation
import Observation
import WatchConnectivity

/// Receives the dashboard from the iPhone and sends button presses back.
@MainActor
@Observable
final class WatchStore: NSObject {
    var dashboard: Dashboard?
    var isReachable = false
    var lastError: String?
    var isSending = false

    private let cacheKey = "hgv.watch.dashboard"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(Dashboard.self, from: data) {
            dashboard = cached
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func send(_ command: WatchCommand) {
        let session = WCSession.default
        lastError = nil
        let message: [String: Any] = ["command": command.rawValue]
        guard session.activationState == .activated else {
            lastError = "Not connected to iPhone"
            return
        }
        if session.isReachable {
            isSending = true
            session.sendMessage(message, replyHandler: { reply in
                Task { @MainActor in
                    self.isSending = false
                    self.apply(reply)
                }
            }, errorHandler: { _ in
                Task { @MainActor in
                    self.isSending = false
                    // Queue it so it still reaches the iPhone later.
                    session.transferUserInfo(message)
                    self.lastError = "Sent — will sync when iPhone is near"
                }
            })
        } else {
            session.transferUserInfo(message)
            lastError = "iPhone not reachable — will sync later"
        }
    }

    func refresh() {
        if WCSession.default.isReachable { send(.refresh) }
        apply(WCSession.default.receivedApplicationContext)
    }

    fileprivate func apply(_ payload: [String: Any]) {
        guard let data = payload["dashboard"] as? Data,
              let value = try? JSONDecoder().decode(Dashboard.self, from: data) else { return }
        if let current = dashboard, current.generatedAt > value.generatedAt { return }
        dashboard = value
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            self.apply(context)
            if reachable { self.send(.refresh) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }
}
