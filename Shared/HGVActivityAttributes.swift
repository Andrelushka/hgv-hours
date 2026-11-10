#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Data shown on the Lock Screen / Dynamic Island Live Activity.
struct HGVActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Current tachograph mode.
        var kind: DutyKind
        /// When the current mode started.
        var startedAt: Date
        /// What the countdown is counting to, e.g. "Break due".
        var targetLabel: String
        /// Countdown target. `nil` shows only the elapsed timer.
        var targetDate: Date?
        /// Highlights the countdown in red/orange when a limit is close.
        var isWarning: Bool
    }

    var driverName: String
}
#endif
