import Foundation
import SwiftData
import WatchConnectivity

/// Keeps the Apple Watch app up to date and carries out button presses made on the Watch.
@MainActor
final class PhoneWatchBridge: NSObject {
    static let shared = PhoneWatchBridge()

    private var context: ModelContext?
    private var store: SettingsStore?
    private var lastSent: Dashboard?

    func configure(context: ModelContext, store: SettingsStore) {
        self.context = context
        self.store = store
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = self
            session.activate()
        }
    }

    func send(_ dashboard: Dashboard) {
        lastSent = dashboard
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(dashboard) else { return }
        let payload: [String: Any] = ["dashboard": data]
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func handle(_ command: WatchCommand) {
        guard let context, let store else { return }
        let settings = store.settings
        switch command {
        case .drive: ActivityController.switchTo(.drive, context: context, settings: settings)
        case .otherWork: ActivityController.switchTo(.otherWork, context: context, settings: settings)
        case .availability: ActivityController.switchTo(.availability, context: context, settings: settings)
        case .breakTime: ActivityController.switchTo(.rest, context: context, settings: settings)
        case .startShift: ActivityController.startShift(context: context, settings: settings)
        case .endShiftDaily: ActivityController.endShift(.daily, context: context, settings: settings)
        case .endShiftWeekly: ActivityController.endShift(.weekly, context: context, settings: settings)
        case .autoOn: store.settings.autoDetectEnabled = true
        case .autoOff: store.settings.autoDetectEnabled = false
        case .refresh: ActivityController.refreshSideEffects(context: context, settings: settings)
        }
        if command == .autoOn || command == .autoOff {
            store.save()
            AutoDriveDetector.shared.update(settings: store.settings)
            ActivityController.refreshSideEffects(context: context, settings: store.settings)
        }
    }
}

extension PhoneWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let last = self.lastSent { self.send(last) }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let raw = message["command"] as? String, let command = WatchCommand(rawValue: raw) else { return }
        Task { @MainActor in self.handle(command) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let raw = message["command"] as? String, let command = WatchCommand(rawValue: raw) else {
            replyHandler([:])
            return
        }
        Task { @MainActor in
            self.handle(command)
            let data = self.lastSent.flatMap { try? JSONEncoder().encode($0) }
            replyHandler(data.map { ["dashboard": $0] } ?? [:])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let raw = userInfo["command"] as? String, let command = WatchCommand(rawValue: raw) else { return }
        Task { @MainActor in self.handle(command) }
    }
}
