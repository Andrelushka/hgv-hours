#if canImport(AlarmKit) && os(iOS)
import AlarmKit

/// Shared by the app (which schedules wake-up and leave-home alarms) and the widget (which shows the snooze countdown).
@available(iOS 26.0, *)
struct WakeAlarmMetadata: AlarmMetadata {
    /// "wake" or "leave".
    var kind: String = "wake"
}
#endif
