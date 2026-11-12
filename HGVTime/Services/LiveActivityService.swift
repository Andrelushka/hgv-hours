import ActivityKit
import Foundation

/// Keeps a single Lock Screen / Dynamic Island Live Activity in step with the current activity.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    /// Last duty state (without navigation) and the current navigation info, merged on every update.
    private var dutyState: HGVActivityAttributes.ContentState?
    private var driverName = ""
    var nav: (instruction: String, symbol: String, distance: String, road: String, arrival: Date?)?

    func sync(state: HGVActivityAttributes.ContentState?, driverName: String) async {
        dutyState = state
        self.driverName = driverName
        await push()
    }

    /// Re-sends the Live Activity with the latest navigation info.
    func push() async {
        var state = dutyState
        if let nav {
            // Navigating off duty or with the countdown turned off: still show directions.
            var s = state ?? .init(kind: .drive, startedAt: .now, targetLabel: "", targetDate: nil, isWarning: false)
            s.navInstruction = nav.instruction
            s.navSymbol = nav.symbol
            s.navDistance = nav.distance
            s.navRoad = nav.road
            s.navArrival = nav.arrival
            state = s
        }
        await send(state)
    }

    private func send(_ state: HGVActivityAttributes.ContentState?) async {
        let running = Activity<HGVActivityAttributes>.activities
        guard let state else {
            for activity in running { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = running.first {
            await activity.update(content)
            for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: HGVActivityAttributes(driverName: self.driverName), content: content, pushType: nil)
        }
    }

    /// What the Live Activity should show, or `nil` to end it (off duty / disabled).
    nonisolated static func contentState(status: ComplianceStatus, settings: AppSettings, shiftEnded: Bool) -> HGVActivityAttributes.ContentState? {
        guard settings.liveActivityEnabled, status.hasData else { return nil }
        if status.currentKind == .rest && (shiftEnded || status.isOnDailyRest) { return nil }

        let now = status.now
        var label = ""
        var target: Date?

        switch status.currentKind {
        case .drive:
            let remaining = status.driveAvailableNow
            if remaining == status.continuousDrivingRemaining {
                label = "Break due"
            } else if status.gbApplies && remaining == min(status.gbDrivingRemaining, status.gbDutyRemaining) {
                label = "GB limit"
            } else if remaining == status.dailyDrivingRemaining {
                label = "Daily driving ends"
            } else {
                label = "Weekly driving ends"
            }
            target = now.addingTimeInterval(remaining)
        case .otherWork:
            if settings.applyWorkingTime {
                label = "Work break due"
                target = now.addingTimeInterval(status.wtdWorkBeforeBreak)
            } else if let latest = status.restStartByLatest {
                label = "Rest by"
                target = latest
            }
        case .availability:
            if let latest = status.restStartByLatest {
                label = "Rest by"
                target = latest
            }
        case .rest:
            if status.breakRemaining > 0 {
                label = "Break complete"
                target = now.addingTimeInterval(status.breakRemaining)
            } else {
                label = "Ready to drive"
            }
        }

        let lead = TimeInterval(settings.warningLeadMinutes * 60)
        let isWarning = status.currentKind != .rest && (target.map { $0.timeIntervalSince(now) <= lead } ?? false)
        return .init(kind: status.currentKind, startedAt: status.currentSince, targetLabel: label, targetDate: target, isWarning: isWarning)
    }
}


/// Puts the next turn on the Lock Screen while navigating (updated when it changes, at most every few seconds).
@MainActor
final class NavLiveActivity {
    static let shared = NavLiveActivity()
    private var lastKey = ""
    private var lastSent = Date.distantPast

    func update(from engine: NavigationEngine) {
        guard let d = engine.distanceToNextManeuver else { return }
        let next = engine.nextStep
        // Round the distance like a sat-nav, so we don't update for every metre.
        let distance = NavigationEngine.distanceText(d < 1000 ? (d / 50).rounded() * 50 : (d / 500).rounded() * 500)
        let key = "\(engine.stepIndex)|\(distance)"
        guard key != lastKey, Date.now.timeIntervalSince(lastSent) > 3 else { return }
        lastKey = key
        lastSent = .now
        LiveActivityService.shared.nav = (next?.instruction ?? "Arrive at \(engine.destinationName)",
                                          next?.symbol ?? "flag.checkered", distance, engine.currentRoad, engine.eta)
        Task { await LiveActivityService.shared.push() }
    }

    func end() {
        lastKey = ""
        LiveActivityService.shared.nav = nil
        Task { await LiveActivityService.shared.push() }
    }
}
