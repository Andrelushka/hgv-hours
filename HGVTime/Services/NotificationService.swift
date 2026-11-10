import Foundation
import UserNotifications

/// Schedules local alerts assuming the current activity carries on.
/// Every activity change reschedules, so alerts always match what you're doing.
final class NotificationService {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func reschedule(status: ComplianceStatus, settings: AppSettings, shiftEnded: Bool) {
        // Only replace the limit alerts; custom reminders are scheduled separately.
        center.removePendingNotificationRequests(withIdentifiers: (0..<40).map { "hgv.alert.\($0)" })
        guard settings.notificationsEnabled, status.hasData else { return }

        let lead = TimeInterval(settings.warningLeadMinutes * 60)
        let leadText = "\(settings.warningLeadMinutes) min"
        let usesEU = settings.primaryRegime == .assimilated || status.stats.euDriving > 0
        var plan: [(after: TimeInterval, title: String, body: String)] = []

        switch status.currentKind {
        case .drive:
            if usesEU {
                let c = status.continuousDrivingRemaining
                plan.append((c - lead, "Break due in \(leadText)", "You'll reach 4h30 of driving. Plan a 45 min break (or the 30 min second part)."))
                plan.append((c, "Break required now", "4h30 of driving reached. Stop for your break."))
                let d = status.dailyDrivingRemaining
                if d < c + 1 || d < .hours(5) {
                    plan.append((d - lead, "Daily driving ends in \(leadText)", "Limit today: \(Fmt.hm(status.dailyDrivingLimit))."))
                    plan.append((d, "Daily driving limit reached", "Stop driving: \(Fmt.hm(status.dailyDrivingLimit)) driven today."))
                }
                let w = status.weeklyDrivingRemaining
                if w < d {
                    plan.append((w - lead, "Weekly driving ends in \(leadText)", "56h weekly / 90h fortnightly limit."))
                    plan.append((w, "Weekly driving limit reached", "No more driving until your weekly rest."))
                }
            }
            if status.gbApplies {
                let g = min(status.gbDrivingRemaining, status.gbDutyRemaining)
                plan.append((g - lead, "GB domestic limit in \(leadText)", "Max 10h driving / 11h duty in the working day."))
            }
        case .otherWork, .availability:
            break
        case .rest:
            if status.breakRemaining > 0 {
                plan.append((status.breakRemaining, "Break complete", "Your break now counts. You can drive up to 4h30."))
            }
            if shiftEnded || status.isOnDailyRest {
                let r = status.currentRestLength
                plan.append((Limits.reducedDailyRest - r, "9h rest complete", "That's a reduced daily rest. 11h makes it a regular one."))
                plan.append((Limits.regularDailyRest - r, "11h rest complete", "Regular daily rest done."))
                plan.append((Limits.reducedWeeklyRest - r, "24h rest complete", "That's a reduced weekly rest. 45h makes it a regular one."))
                plan.append((Limits.regularWeeklyRest - r, "45h weekly rest complete", "Regular weekly rest done."))
            }
        }

        let working = status.currentKind == .drive || status.currentKind == .otherWork
        if working && settings.applyWorkingTime {
            plan.append((status.wtdWorkBeforeBreak - lead, "Working-time break due in \(leadText)", "You can't work more than 6h without a 30 min break."))
            if let night = status.nightWorkRemaining {
                plan.append((night - lead, "Night-work limit in \(leadText)", "This shift includes night time: max \(Fmt.hm(settings.nightWorkLimitHours * 3600)) work."))
            }
        }
        if status.currentKind != .rest, let latest = status.restStartByLatest {
            plan.append((latest.timeIntervalSince(status.now) - max(lead, 1800), "Daily rest due by \(Fmt.time(latest))", "Finish up so your rest fits in the 24h period."))
        }
        if let due = status.weeklyRestDueBy {
            plan.append((due.timeIntervalSince(status.now) - .hours(3), "Weekly rest due by \(Fmt.time(due))", status.nextWeeklyMustBeRegular ? "This one must be a regular 45h rest." : "At least 24h off required."))
        }

        for (index, item) in plan.enumerated() where item.after > 5 {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: item.after, repeats: false)
            center.add(UNNotificationRequest(identifier: "hgv.alert.\(index)", content: content, trigger: trigger))
        }
    }

    /// Alerts for USA / Canada / Australia / New Zealand rules.
    func rescheduleWorld(_ w: WorldStatus, settings: AppSettings, shiftEnded: Bool) {
        center.removePendingNotificationRequests(withIdentifiers: (0..<40).map { "hgv.alert.\($0)" })
        guard settings.notificationsEnabled, !shiftEnded else { return }
        let lead = TimeInterval(settings.warningLeadMinutes * 60)
        var plan: [(TimeInterval, String, String)] = []
        for l in w.limits where l.remaining > 0 {
            plan.append((l.remaining - lead, "\(l.title): \(settings.warningLeadMinutes) min left", l.note))
            plan.append((l.remaining, "\(l.title) reached", l.note))
        }
        for (i, item) in plan.enumerated() where item.0 > 5 {
            let c = UNMutableNotificationContent()
            c.title = item.1
            c.body = item.2
            c.sound = .default
            center.add(UNNotificationRequest(identifier: "hgv.alert.\(i)", content: c,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: item.0, repeats: false)))
        }
    }
}
