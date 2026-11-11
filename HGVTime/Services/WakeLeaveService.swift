import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftData
import SwiftUI
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Wake-up and leave-home times for one job.
struct WakeLeavePlan: Equatable {
    var jobID: UUID
    var jobTitle: String
    var start: Date
    var destination: String
    /// Journey time from home to the job's start place.
    var travel: TimeInterval
    /// The journey time came from Apple Maps with traffic (otherwise it's the time set in Settings).
    var trafficBased: Bool
    var leaveAt: Date
    var wakeAt: Date
    var leaveIsManual: Bool
    var wakeIsManual: Bool
    var alarmsOff: Bool

    /// leave = start − journey − arrive-early margin; wake = leave − get-ready time. Times set by hand win.
    static func times(start: Date, travel: TimeInterval, settings s: AppSettings,
                      wakeOverride: Date?, leaveOverride: Date?) -> (wake: Date, leave: Date) {
        let leave = leaveOverride ?? start.addingTimeInterval(-travel - Double(s.leaveBufferMinutes * 60))
        let wake = wakeOverride ?? leave.addingTimeInterval(-Double(s.wakeGetReadyMinutes * 60))
        return (wake, leave)
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct WakeAlarmMetadata: AlarmMetadata {}
#endif

/// Plans a wake-up alarm and "time to leave home" notifications for the next planned job.
/// Uses real alarms (ring on silent, full screen) on iOS 26, and notifications on older iOS.
@MainActor
@Observable
final class WakeLeaveService {
    static let shared = WakeLeaveService()

    /// The next job's wake-up and leave times (nil when nothing is planned or both features are off).
    private(set) var plan: WakeLeavePlan?
    /// Real alarms can be used (iOS 26 and permission given).
    private(set) var alarmsAllowed = false

    @ObservationIgnored private var lastSignature = ""
    @ObservationIgnored private var lastRun = Date.distantPast
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var travelCache: [String: TimeInterval] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard
    private let scheduledKey = "hgv.wake.scheduled"
    private let leaveIDs = ["hgv.leave.now", "hgv.leave.soon"]
    private let wakeNoteIDs = (0..<3).map { "hgv.wake.\($0)" }

    /// The next job that should get an alarm: not done or cancelled, starting within 36 hours.
    static func nextJob(_ plans: [WorkPlan], now: Date = .now) -> WorkPlan? {
        plans.filter { !$0.completed && !$0.cancelled && $0.plannedStart > now && $0.plannedStart < now.addingTimeInterval(36 * 3600) }
            .min { $0.plannedStart < $1.plannedStart }
    }

    /// Recalculate and reschedule. Cheap to call often: it only redoes the work when something changed
    /// (or every 10 minutes, so the traffic estimate stays fresh).
    func refresh(context: ModelContext, settings: AppSettings, force: Bool = false) {
        let plans = (try? context.fetch(FetchDescriptor<WorkPlan>())) ?? []
        let job = Self.nextJob(plans)
        let sig = signature(job: job, settings: settings)
        guard force || sig != lastSignature || Date.now.timeIntervalSince(lastRun) > 600 else { return }
        lastSignature = sig
        lastRun = .now

        let snapshot = job.map(JobInfo.init)
        running?.cancel()
        running = Task { await self.update(job: snapshot, settings: settings) }
    }

    /// Ask for permission to set real alarms (iOS 26+). Returns true when allowed.
    @discardableResult
    func requestAlarmPermission() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let state = (try? await AlarmManager.shared.requestAuthorization()) ?? .denied
            alarmsAllowed = state == .authorized
            return alarmsAllowed
        }
        #endif
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        return false
    }

    func checkPermission() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { alarmsAllowed = AlarmManager.shared.authorizationState == .authorized }
        #endif
    }

    /// Rings in a minute, to check the sound and volume.
    func testAlarm(settings: AppSettings) async {
        let at = Date.now.addingTimeInterval(60)
        if await scheduleRealAlarm(at: at, title: "\(settings.wakeAlarmTitle) (test)") == nil {
            let c = UNMutableNotificationContent()
            c.title = "\(settings.wakeAlarmTitle) (test)"
            c.body = "This is how your wake-up alarm will look."
            c.sound = .default
            c.interruptionLevel = .timeSensitive
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "hgv.wake.test", content: c,
                                      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)))
        }
    }

    // MARK: - Work

    /// What we need from a job, copied so the background work doesn't touch SwiftData objects.
    private struct JobInfo {
        var id: UUID
        var title: String
        var start: Date
        var destination: String
        var query: String
        var latitude: Double?
        var longitude: Double?
        var wakeOverride: Date?
        var leaveOverride: Date?
        var alarmsOff: Bool

        init(_ p: WorkPlan) {
            id = p.id
            start = p.plannedStart
            let first = p.stops.first
            let startPlace = [p.startName, p.startLocation].first { !$0.isEmpty } ?? ""
            destination = !startPlace.isEmpty ? startPlace
                : !p.startPostcode.isEmpty ? p.startPostcode
                : first.map(\.displayName) ?? (p.company.isEmpty ? "work" : p.company)
            title = p.company.isEmpty ? destination : p.company
            if p.startLatitude != nil || !p.startPostcode.isEmpty || !p.startLocation.isEmpty {
                latitude = p.startLatitude
                longitude = p.startLongitude
                query = [p.startLocation, p.startPostcode].filter { !$0.isEmpty }.joined(separator: ", ")
            } else {
                latitude = first?.latitude
                longitude = first?.longitude
                query = [first?.address, first?.postcode, first?.place].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            }
            wakeOverride = p.wakeOverride
            leaveOverride = p.leaveOverride
            alarmsOff = p.alarmsOff
        }
    }

    private func signature(job: WorkPlan?, settings s: AppSettings) -> String {
        let j = job.map { "\($0.id)|\($0.plannedStart.timeIntervalSince1970)|\($0.startLatitude ?? 0)|\($0.startPostcode)|\($0.startLocation)|\($0.wakeOverride?.timeIntervalSince1970 ?? 0)|\($0.leaveOverride?.timeIntervalSince1970 ?? 0)|\($0.alarmsOff)" } ?? "-"
        return [j, "\(s.wakeAlarmEnabled)\(s.wakeAlarmTitle)\(s.wakeGetReadyMinutes)\(s.wakeBackupMinutes)",
                "\(s.leaveReminderEnabled)\(s.leaveBufferMinutes)\(s.leaveHeadsUpMinutes)\(s.commuteMinutes)\(s.commuteUseTraffic)",
                "\(s.homeLatitude ?? 0)\(s.homeLongitude ?? 0)\(s.homePostcode)\(s.manualAlarmAt)"].joined(separator: "#")
    }

    private func update(job: JobInfo?, settings s: AppSettings) async {
        checkPermission()
        var newPlan: WakeLeavePlan?
        if let job, s.wakeAlarmEnabled || s.leaveReminderEnabled {
            let (travel, traffic) = await travelTime(to: job, settings: s)
            guard !Task.isCancelled else { return }
            let t = WakeLeavePlan.times(start: job.start, travel: travel, settings: s,
                                        wakeOverride: job.wakeOverride, leaveOverride: job.leaveOverride)
            newPlan = WakeLeavePlan(jobID: job.id, jobTitle: job.title, start: job.start, destination: job.destination,
                                    travel: travel, trafficBased: traffic, leaveAt: t.leave, wakeAt: t.wake,
                                    leaveIsManual: job.leaveOverride != nil, wakeIsManual: job.wakeOverride != nil,
                                    alarmsOff: job.alarmsOff)
        }
        plan = newPlan
        await scheduleAlarms(plan: newPlan, settings: s)
        scheduleLeave(plan: newPlan, settings: s)
    }

    /// Drive time from home with traffic (Apple Maps), or the journey time from Settings.
    private func travelTime(to job: JobInfo, settings s: AppSettings) async -> (TimeInterval, Bool) {
        let fallback = (Double(s.commuteMinutes * 60), false)
        guard s.commuteUseTraffic, let hLat = s.homeLatitude, let hLon = s.homeLongitude else { return fallback }
        var dest: CLLocationCoordinate2D?
        if let lat = job.latitude, let lon = job.longitude {
            dest = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else if !job.query.isEmpty {
            dest = (try? await CLGeocoder().geocodeAddressString(job.query))?.first?.location?.coordinate
        }
        guard let dest else { return fallback }
        // Depart roughly when we'd leave, so the traffic estimate is for that time of day.
        let departure = job.start.addingTimeInterval(-Double(s.commuteMinutes * 60) - Double(s.leaveBufferMinutes * 60))
        let hourSlot = Int(departure.timeIntervalSince1970 / 1800)
        let key = String(format: "%.4f,%.4f>%.4f,%.4f@%d", hLat, hLon, dest.latitude, dest.longitude, hourSlot)
        if let cached = travelCache[key] { return (cached, true) }

        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: hLat, longitude: hLon)))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        req.transportType = .automobile
        if departure > .now { req.departureDate = departure }
        guard let eta = try? await MKDirections(request: req).calculateETA() else { return fallback }
        // Round up to whole minutes.
        let seconds = (eta.expectedTravelTime / 60).rounded(.up) * 60
        travelCache[key] = seconds
        return (seconds, true)
    }

    // MARK: - Alarms

    private func wantedAlarms(plan: WakeLeavePlan?, settings s: AppSettings) -> [(Date, String)] {
        var out: [(Date, String)] = []
        let soon = Date.now.addingTimeInterval(30)
        if s.wakeAlarmEnabled, let p = plan, !p.alarmsOff, p.wakeAt > soon {
            let title = "\(s.wakeAlarmTitle) · \(p.jobTitle) at \(Fmt.time(p.start))"
            out.append((p.wakeAt, title))
            if s.wakeBackupMinutes > 0 {
                out.append((p.wakeAt.addingTimeInterval(Double(s.wakeBackupMinutes * 60)), "\(s.wakeAlarmTitle) (again)"))
            }
        }
        if s.manualAlarmAt > 0 {
            let at = Date(timeIntervalSince1970: s.manualAlarmAt)
            if at > soon { out.append((at, s.wakeAlarmTitle)) }
        }
        return out
    }

    private func scheduleAlarms(plan: WakeLeavePlan?, settings s: AppSettings) async {
        let wanted = wantedAlarms(plan: plan, settings: s)
        let wantedKey = wanted.map { "\(Int($0.0.timeIntervalSince1970))|\($0.1)" }
        let stored = defaults.dictionary(forKey: scheduledKey) as? [String: String] ?? [:]
        // Nothing changed: leave the alarms alone.
        if Set(stored.values) == Set(wantedKey), stored.values.count == wantedKey.count { return }

        cancelStoredAlarms(stored)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: wakeNoteIDs)

        var saved: [String: String] = [:]
        for (i, (date, title)) in wanted.enumerated() {
            if let id = await scheduleRealAlarm(at: date, title: title) {
                saved[id] = wantedKey[i]
            } else if i < wakeNoteIDs.count {
                let c = UNMutableNotificationContent()
                c.title = title
                c.body = plan.map { "Leave at \(Fmt.time($0.leaveAt)) to get to \($0.destination) for \(Fmt.time($0.start))." } ?? ""
                c.sound = .default
                c.interruptionLevel = .timeSensitive
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                try? await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: wakeNoteIDs[i], content: c,
                                          trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
                saved[wakeNoteIDs[i]] = wantedKey[i]
            }
        }
        defaults.set(saved, forKey: scheduledKey)
    }

    private func cancelStoredAlarms(_ stored: [String: String]) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for id in stored.keys.compactMap(UUID.init(uuidString:)) { try? AlarmManager.shared.cancel(id: id) }
        }
        #endif
    }

    /// A real alarm (iOS 26). Returns its id, or nil if alarms can't be used.
    private func scheduleRealAlarm(at date: Date, title: String) async -> String? {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            guard AlarmManager.shared.authorizationState == .authorized else { return nil }
            let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
            let alert = AlarmPresentation.Alert(title: "\(title)", stopButton: stop)
            let attributes = AlarmAttributes<WakeAlarmMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: .orange)
            let id = UUID()
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: .alarm(schedule: .fixed(date), attributes: attributes))
                return id.uuidString
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    // MARK: - Leave home

    private func scheduleLeave(plan: WakeLeavePlan?, settings s: AppSettings) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: leaveIDs)
        guard s.leaveReminderEnabled, let p = plan, !p.alarmsOff else { return }
        let journey = "\(Fmt.hm(p.travel)) drive\(p.trafficBased ? " with traffic" : "")"
        let arrive = p.start.addingTimeInterval(-Double(s.leaveBufferMinutes * 60))

        func add(_ id: String, at date: Date, title: String, body: String) {
            guard date > .now.addingTimeInterval(10) else { return }
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            c.sound = .default
            c.interruptionLevel = .timeSensitive
            c.userInfo = ["speak": true, "reminder": true]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            center.add(UNNotificationRequest(identifier: id, content: c,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
        add(leaveIDs[0], at: p.leaveAt, title: "Time to leave for work",
            body: "Leave now to reach \(p.destination) by \(Fmt.time(arrive)) for your \(Fmt.time(p.start)) start · \(journey).")
        if s.leaveHeadsUpMinutes > 0 {
            add(leaveIDs[1], at: p.leaveAt.addingTimeInterval(-Double(s.leaveHeadsUpMinutes * 60)),
                title: "Leave in \(s.leaveHeadsUpMinutes) minutes",
                body: "Leave home at \(Fmt.time(p.leaveAt)) for \(p.jobTitle) at \(Fmt.time(p.start)) · \(journey).")
        }
    }
}
