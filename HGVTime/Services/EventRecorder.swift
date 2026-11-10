import CoreLocation
import Foundation
import SwiftData

/// Saves events (shift, activity, card, stops, fuel, overspeed, infringements) with where they happened.
@MainActor
enum EventRecorder {
    static func log(_ kind: EventKind, title: String = "", detail: String = "", speedKmh: Double = 0, duration: Double = 0,
                    at time: Date = .now, coordinate: CLLocationCoordinate2D? = nil, key: String = "", activity: String = "",
                    context: ModelContext, settings: AppSettings) {
        let event = EventLog(time: time, kind: kind, title: title, detail: detail)
        event.activityRaw = activity
        event.speedKmh = speedKmh
        event.duration = duration
        event.key = key
        context.insert(event)
        try? context.save()
        guard settings.recordEventLocations else { return }
        if let c = coordinate ?? AutoDriveDetector.shared.recentCoordinate {
            event.latitude = c.latitude
            event.longitude = c.longitude
            try? context.save()
            return
        }
        // Only look up a location if the app is already allowed to (no prompt on every button press).
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        Task {
            if let loc = await LocationOnce.shared.current() {
                event.latitude = loc.coordinate.latitude
                event.longitude = loc.coordinate.longitude
                if event.speedKmh == 0, loc.speed > 0 { event.speedKmh = loc.speed * 3.6 }
                try? context.save()
            }
        }
    }

    /// Logs each new infringement once (with where you were when it happened).
    static func logInfringements(_ status: ComplianceStatus, context: ModelContext, settings: AppSettings) {
        let violations = status.warnings.filter { $0.severity == .violation }
        guard !violations.isEmpty else { return }
        let shiftKey = status.currentShift.map { String(Int($0.period.start.timeIntervalSince1970)) } ?? "none"
        let descriptor = FetchDescriptor<EventLog>(predicate: #Predicate { $0.kindRaw == "infringement" })
        let existing = Set(((try? context.fetch(descriptor)) ?? []).map(\.key))
        for v in violations {
            let key = "\(shiftKey)|\(v.title)"
            guard !existing.contains(key) else { continue }
            log(.infringement, title: v.title, detail: v.detail, key: key, context: context, settings: settings)
        }
    }
}
