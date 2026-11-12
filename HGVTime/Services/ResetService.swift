import Foundation
import SwiftData
import UserNotifications
import WidgetKit
#if canImport(HGVAI)
import HGVAI
#endif

/// Records that can be erased, one group at a time.
enum DataGroup: String, CaseIterable, Identifiable, Hashable {
    case driverLog, jobs, earnings, vehicles, notes, reminders, events, assistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .driverLog: "Driver log"
        case .jobs: "Jobs & day debriefs"
        case .earnings: "Earnings extras & nights out"
        case .vehicles: "Vehicles, mileage & fuel"
        case .notes: "Notes"
        case .reminders: "Reminders"
        case .events: "Event log, speed & routes"
        case .assistant: "Assistant keys & AI models"
        }
    }

    var detail: String {
        switch self {
        case .driverLog: "All activities (driving, work, breaks, rest) and driver card in/out"
        case .jobs: "Planned jobs, stops, cancelled jobs and per-day vehicle and distance records"
        case .earnings: "Bonuses, deductions, holidays and nights out (pay is worked out from the driver log)"
        case .vehicles: "Your vehicles and trailers, mileage per shift, fuel, AdBlue and other items used"
        case .notes: "Notebook pages and tables"
        case .reminders: "Your reminders (the default ones come back)"
        case .events: "Event log, overspeed and harsh braking, recorded GPS routes"
        case .assistant: "Claude and DVLA keys in the Keychain, downloaded on-device AI models"
        }
    }

    var symbol: String {
        switch self {
        case .driverLog: "list.bullet.rectangle.portrait.fill"
        case .jobs: "shippingbox.fill"
        case .earnings: "sterlingsign.circle.fill"
        case .vehicles: "truck.box.fill"
        case .notes: "note.text"
        case .reminders: "alarm.fill"
        case .events: "exclamationmark.triangle.fill"
        case .assistant: "sparkles"
        }
    }
}

/// Settings that can be put back to their defaults, one group at a time.
enum SettingsGroup: String, CaseIterable, Identifiable, Hashable {
    case profile, pay, rules, alerts, inCab, layout, assistant, security, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "Driver profile & home"
        case .pay: "Pay rates & overtime"
        case .rules: "Country & hours rules"
        case .alerts: "Alerts, voice, alarm & leave home"
        case .inCab: "In-cab, speed & navigation"
        case .layout: "Today & Hours layout, units"
        case .assistant: "Assistant choices"
        case .security: "App lock"
        case .other: "Everything else"
        }
    }

    var detail: String {
        switch self {
        case .profile: "Name, employer, licence, card, CPC and medical dates, home address"
        case .pay: "Hourly or day rate, overtime, extras, currency"
        case .rules: "Country, tachograph/GB rules, working time, double-manned"
        case .alerts: "Notifications, Live Activity, spoken alerts, wake-up alarm, leave-home reminder"
        case .inCab: "Automatic drive detection, overspeed, harsh braking, routes, screen on"
        case .layout: "Tile order and hidden tiles, date style, miles and feet"
        case .assistant: "Claude or on-device AI, chosen model"
        case .security: "Face ID lock"
        case .other: "Welcome screen, current vehicle and card state"
        }
    }

    var symbol: String {
        switch self {
        case .profile: "person.crop.circle.fill"
        case .pay: "banknote.fill"
        case .rules: "globe.europe.africa.fill"
        case .alerts: "bell.badge.fill"
        case .inCab: "gauge.with.dots.needle.67percent"
        case .layout: "square.grid.2x2.fill"
        case .assistant: "sparkles"
        case .security: "faceid"
        case .other: "ellipsis.circle.fill"
        }
    }

    /// Copies this group's values from `defaults` into `s`.
    func reset(_ s: inout AppSettings, to d: AppSettings = AppSettings()) {
        switch self {
        case .profile:
            s.driverName = d.driverName; s.employer = d.employer; s.vehicleReg = d.vehicleReg
            s.phone = d.phone; s.licenceCategories = d.licenceCategories; s.driverCardNumber = d.driverCardNumber
            s.licenceExpiry = d.licenceExpiry; s.cardExpiry = d.cardExpiry; s.cpcExpiry = d.cpcExpiry
            s.medicalDue = d.medicalDue; s.expiryWarningDays = d.expiryWarningDays
            s.homeAddress = d.homeAddress; s.homePostcode = d.homePostcode
            s.homeLatitude = d.homeLatitude; s.homeLongitude = d.homeLongitude
        case .pay:
            s.pay = d.pay
        case .rules:
            s.ruleRegionRaw = d.ruleRegionRaw; s.usCycle70 = d.usCycle70; s.primaryRegime = d.primaryRegime
            s.applyWorkingTime = d.applyWorkingTime; s.nightWorkLimitHours = d.nightWorkLimitHours
            s.wtdReferenceWeeks = d.wtdReferenceWeeks; s.allowConsecutiveReducedWeekly = d.allowConsecutiveReducedWeekly
            s.currentRegime = d.currentRegime; s.multiManned = d.multiManned; s.shiftStartKind = d.shiftStartKind
        case .alerts:
            s.notificationsEnabled = d.notificationsEnabled; s.warningLeadMinutes = d.warningLeadMinutes
            s.liveActivityEnabled = d.liveActivityEnabled
            s.voiceEnabled = d.voiceEnabled; s.voiceRate = d.voiceRate; s.voiceIdentifier = d.voiceIdentifier
            s.speakActivityChanges = d.speakActivityChanges; s.speakWarnings = d.speakWarnings
            s.speakOverspeed = d.speakOverspeed; s.speakReminders = d.speakReminders
            s.voiceWarningMinutes = d.voiceWarningMinutes
            s.wakeAlarmEnabled = d.wakeAlarmEnabled; s.wakeAlarmTitle = d.wakeAlarmTitle
            s.wakeGetReadyMinutes = d.wakeGetReadyMinutes; s.wakeBackupMinutes = d.wakeBackupMinutes
            s.leaveReminderEnabled = d.leaveReminderEnabled; s.leaveBufferMinutes = d.leaveBufferMinutes
            s.leaveHeadsUpMinutes = d.leaveHeadsUpMinutes; s.commuteMinutes = d.commuteMinutes
            s.commuteUseTraffic = d.commuteUseTraffic; s.manualAlarmAt = d.manualAlarmAt
        case .inCab:
            s.autoDetectEnabled = d.autoDetectEnabled; s.autoMovingSpeedKmh = d.autoMovingSpeedKmh
            s.autoStopDelaySeconds = d.autoStopDelaySeconds; s.autoStoppedKind = d.autoStoppedKind
            s.overspeedLimitKmh = d.overspeedLimitKmh; s.autoSpeedLimit = d.autoSpeedLimit
            s.recordOverspeed = d.recordOverspeed; s.recordHarshBraking = d.recordHarshBraking
            s.harshBrakeMS2 = d.harshBrakeMS2; s.onlineSpeedLimits = d.onlineSpeedLimits
            s.recordEventLocations = d.recordEventLocations; s.recordRoute = d.recordRoute
            s.keepScreenOn = d.keepScreenOn
        case .layout:
            s.todayOrder = d.todayOrder; s.todayHidden = d.todayHidden
            s.hoursOrder = d.hoursOrder; s.hoursHidden = d.hoursHidden
            s.dateStyle = d.dateStyle; s.useMiles = d.useMiles; s.showFeet = d.showFeet
            s.distanceBoth = d.distanceBoth; s.heightUnit = d.heightUnit
        case .assistant:
            s.assistantUseClaude = d.assistantUseClaude; s.assistantUseLocal = d.assistantUseLocal
            s.assistantLocalModel = d.assistantLocalModel
        case .security:
            s.lockEnabled = d.lockEnabled; s.lockAfterMinutes = d.lockAfterMinutes
        case .other:
            // Everything not in another group: take the defaults, then put the other groups' values back.
            var fresh = d
            for g in SettingsGroup.allCases where g != .other { g.copy(from: s, into: &fresh) }
            s = fresh
        }
    }

    /// Copies this group's values from `src` into `dst` (the reverse of reset).
    fileprivate func copy(from src: AppSettings, into dst: inout AppSettings) {
        // reset(dst, to: src) sets dst's group fields to src's values.
        reset(&dst, to: src)
    }
}

/// Erases chosen records and puts chosen settings back to default.
@MainActor
enum ResetService {
    struct Choice: Equatable {
        var data: Set<DataGroup> = []
        var settings: Set<SettingsGroup> = []
        var isEmpty: Bool { data.isEmpty && settings.isEmpty }
        var isEverything: Bool { data.count == DataGroup.allCases.count && settings.count == SettingsGroup.allCases.count }
    }

    /// How many records each group holds now.
    static func counts(context: ModelContext) -> [DataGroup: Int] {
        func n<T: PersistentModel>(_ t: T.Type) -> Int { (try? context.fetchCount(FetchDescriptor<T>())) ?? 0 }
        return [
            .driverLog: n(ActivityEntry.self) + n(CardEvent.self),
            .jobs: n(WorkPlan.self) + n(DayRecord.self),
            .earnings: n(PayItem.self) + n(NightOut.self),
            .vehicles: n(Vehicle.self) + n(VehicleUse.self) + n(ResourceLog.self),
            .notes: n(NoteItem.self),
            .reminders: n(Reminder.self),
            .events: n(EventLog.self) + n(SpeedEvent.self) + n(TrackPoint.self),
            .assistant: (KeychainKey.hasKey ? 1 : 0) + (DVLAKey.hasKey ? 1 : 0),
        ]
    }

    static func erase(_ choice: Choice, context: ModelContext, store: SettingsStore) {
        // One by one (not a batch delete) so open screens update straight away.
        func wipe<T: PersistentModel>(_ t: T.Type) {
            for item in (try? context.fetch(FetchDescriptor<T>())) ?? [] { context.delete(item) }
        }
        for g in choice.data {
            switch g {
            case .driverLog: wipe(ActivityEntry.self); wipe(CardEvent.self)
            case .jobs: wipe(WorkPlan.self); wipe(DayRecord.self)
            case .earnings: wipe(PayItem.self); wipe(NightOut.self)
            case .vehicles: wipe(Vehicle.self); wipe(VehicleUse.self); wipe(ResourceLog.self)
            case .notes: wipe(NoteItem.self)
            case .reminders: wipe(Reminder.self)
            case .events: wipe(EventLog.self); wipe(SpeedEvent.self); wipe(TrackPoint.self)
            case .assistant:
                KeychainKey.delete()
                DVLAKey.delete()
                #if canImport(HGVAI)
                LocalModel.shared.deleteDownloads()
                #endif
            }
        }
        try? context.save()

        var s = store.settings
        // "Everything else" first, so it sees the other groups' current values.
        if choice.settings.contains(.other) { SettingsGroup.other.reset(&s) }
        for g in choice.settings where g != .other { g.reset(&s) }
        // Data the settings point at.
        if choice.data.contains(.vehicles) { s.currentVehicleID = ""; s.currentTrailerID = "" }
        if choice.data.contains(.driverLog) { s.cardInserted = false; s.cardChangedAt = 0 }
        if choice.data.contains(.reminders) { s.seededDefaultReminders = false }
        if choice.isEverything { s = AppSettings() }
        store.settings = s
        store.save()

        if choice.data.contains(.reminders) { ReminderService.shared.seedDefaults(context: context, store: store) }

        // Clear every scheduled alert and alarm; the ones still wanted are set again straight after.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UserDefaults.standard.removeObject(forKey: "calculatorMode")
        ActivityController.refreshSideEffects(context: context, settings: store.settings)
        WakeLeaveService.shared.refresh(context: context, settings: store.settings, force: true)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
