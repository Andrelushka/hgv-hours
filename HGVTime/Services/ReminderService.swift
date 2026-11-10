import Foundation
import SwiftData
import UserNotifications

/// Schedules your own reminders and fires the ones tied to button presses.
@MainActor
final class ReminderService: NSObject {
    static let shared = ReminderService()
    private let center = UNUserNotificationCenter.current()
    private let prefix = "hgv.rem."

    /// Shows reminders (and limit alerts) while the app is open, and speaks them if wanted.
    func becomeDelegate() { center.delegate = self }

    /// Default reminders the first time the app runs.
    func seedDefaults(context: ModelContext, store: SettingsStore) {
        guard !store.settings.seededDefaultReminders else { return }
        let walk = Reminder(title: "Walk-round check", message: "Do your vehicle defect check and record it.", trigger: .shiftStart)
        let end = Reminder(title: "End of shift", message: "Enter your end mileage and withdraw your driver card.", trigger: .shiftEnd)
        let brk = Reminder(title: "Break coming up", message: "Look for somewhere to stop.", trigger: .beforeDrivingBreak, offsetMinutes: 30)
        brk.enabled = false
        [walk, end, brk].forEach(context.insert)
        try? context.save()
        store.settings.seededDefaultReminders = true
    }

    func schedule(context: ModelContext, status s: ComplianceStatus, settings: AppSettings, shiftEnded: Bool) {
        let all = ((try? context.fetch(FetchDescriptor<Reminder>())) ?? []).filter(\.enabled)
        center.getPendingNotificationRequests { [prefix, center] requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
        let now = s.now
        let onShift = s.currentShift != nil && !shiftEnded
        for r in all {
            let content = Self.content(for: r)
            let id = prefix + r.id.uuidString
            let offset = TimeInterval(r.offsetMinutes * 60)
            var fireIn: TimeInterval?
            switch r.trigger {
            case .time:
                scheduleTime(r, content: content, id: id)
            case .beforeDrivingBreak where onShift && s.currentKind == .drive:
                fireIn = s.continuousDrivingRemaining - offset
            case .beforeWorkingBreak where onShift && (s.currentKind == .drive || s.currentKind == .otherWork) && settings.applyWorkingTime:
                fireIn = s.wtdWorkBeforeBreak - offset
            case .beforeDailyRest where onShift:
                if let by = s.restStartByFull { fireIn = by.timeIntervalSince(now) - offset }
            case .beforeWeeklyRest:
                if let due = s.weeklyRestDueBy { fireIn = due.timeIntervalSince(now) - offset }
            case .afterShiftStart where onShift:
                if let start = s.currentShift?.period.start { fireIn = start.addingTimeInterval(offset).timeIntervalSince(now) }
            case .dailyRestComplete where shiftEnded && s.currentKind == .rest:
                fireIn = Limits.regularDailyRest - s.currentRestLength
            default:
                break
            }
            if let fireIn, fireIn > 5 {
                center.add(UNNotificationRequest(identifier: id, content: content,
                                                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: fireIn, repeats: false)))
            }
        }
    }

    private func scheduleTime(_ r: Reminder, content: UNMutableNotificationContent, id: String) {
        let cal = Calendar.hgv
        let hm = cal.dateComponents([.hour, .minute], from: r.time)
        switch r.repeatRule {
        case .once:
            guard r.time > .now else { return }
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.time)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        case .daily:
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: hm, repeats: true)))
        case .weekdays:
            for weekday in 2...6 {
                var c = hm
                c.weekday = weekday
                center.add(UNNotificationRequest(identifier: id + ".\(weekday)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true)))
            }
        case .weekly:
            var c = hm
            c.weekday = cal.component(.weekday, from: r.time)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true)))
        }
    }

    /// Fires reminders tied to a button press (start/end shift, arrived, card inserted).
    func fire(_ trigger: ReminderTrigger, context: ModelContext) {
        let list = ((try? context.fetch(FetchDescriptor<Reminder>())) ?? []).filter { $0.enabled && $0.trigger == trigger }
        for r in list {
            center.add(UNNotificationRequest(identifier: prefix + "now." + UUID().uuidString, content: Self.content(for: r),
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        }
    }

    static func content(for r: Reminder) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = r.title
        c.body = r.message.isEmpty ? r.summary : r.message
        c.sound = .default
        c.userInfo = ["speak": r.speak, "reminder": true]
        return c
    }
}

extension ReminderService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        let speak = content.userInfo["speak"] as? Bool ?? false
        let isReminder = content.userInfo["reminder"] as? Bool ?? false
        let title = content.title, body = content.body
        Task { @MainActor in
            if isReminder && speak {
                VoiceService.shared.reminder(title, body)
            } else if !isReminder {
                VoiceService.shared.warning(title)
            }
        }
        completionHandler([.banner, .sound, .list])
    }
}
