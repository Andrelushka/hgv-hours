import ActivityKit
import Foundation

/// Keeps a single Lock Screen / Dynamic Island Live Activity in step with the current activity.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    func sync(state: HGVActivityAttributes.ContentState?, driverName: String) async {
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
            _ = try? Activity.request(attributes: HGVActivityAttributes(driverName: driverName), content: content, pushType: nil)
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
