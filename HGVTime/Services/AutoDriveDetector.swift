import CoreLocation
import CoreMotion
import Foundation
import Observation
import SwiftData
import UIKit

/// "In cab" mode: works like a tachograph's motion sensor.
///
/// Driving starts only when GPS shows the vehicle moving above the set speed for 8 seconds
/// (and, when the motion chip is available, it agrees you're in a vehicle at lower speeds).
/// Shaking or carrying the phone around never counts: GPS position must actually change at road speed.
/// When the vehicle has been stopped for the set delay, the stop activity (Other work by default)
/// is recorded from the moment it stopped.
@MainActor
@Observable
final class AutoDriveDetector: NSObject {
    static let shared = AutoDriveDetector()

    enum State: Equatable {
        case off
        case needsPermission
        case denied
        case waitingForGPS
        case stopped
        case moving
    }

    private(set) var state: State = .off
    private(set) var isMoving = false
    private(set) var speedKmh: Double?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var inVehicle = false
    private(set) var lastFix: Date?
    private(set) var lastEvent: String?
    /// Above the overspeed threshold right now.
    private(set) var isOverspeeding = false

    @ObservationIgnored private var lastMovingLocation: CLLocation?
    @ObservationIgnored private var lastFixLocation: CLLocation?
    @ObservationIgnored private var lastTrackPoint: CLLocation?

    /// Where the phone was in the last minute (in-cab mode only).
    var recentCoordinate: CLLocationCoordinate2D? {
        guard let l = lastFixLocation, abs(l.timestamp.timeIntervalSinceNow) < 60 else { return nil }
        return l.coordinate
    }
    @ObservationIgnored private var pendingKm: Double = 0
    @ObservationIgnored private var overspeedStart: Date?
    @ObservationIgnored private var overspeedMax: Double = 0
    @ObservationIgnored private var overspeedCoordinate: CLLocationCoordinate2D?

    var isRunning: Bool { state != .off && state != .denied && state != .needsPermission }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let motion = CMMotionActivityManager()
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var settings = AppSettings()
    @ObservationIgnored private var movingSince: Date?
    @ObservationIgnored private var stoppedSince: Date?
    @ObservationIgnored private var stopTimer: Timer?
    @ObservationIgnored private var started = false

    /// Below this speed the vehicle counts as stopped.
    private let stoppedSpeedKmh = 4.0
    /// Speed must stay above the threshold this long before driving starts (filters GPS jumps).
    private let movingConfirmSeconds: TimeInterval = 8
    /// Above this speed GPS alone is trusted (nobody walks or cycles at 25 km/h for 8 seconds by accident).
    private let gpsOnlySpeedKmh = 25.0

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    func configure(context: ModelContext, settings: AppSettings) {
        self.context = context
        update(settings: settings)
    }

    func update(settings: AppSettings) {
        self.settings = settings
        settings.autoDetectEnabled ? start() : stop()
    }

    var needsAlwaysPermission: Bool { authorization == .authorizedWhenInUse }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func requestAlways() { manager.requestAlwaysAuthorization() }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    /// One-line status for the Today screen.
    var statusText: String {
        switch state {
        case .off: return "Off — tap the buttons yourself"
        case .needsPermission: return "Waiting for location permission…"
        case .denied: return "Location is off for HGV Hours — tap to fix"
        case .waitingForGPS: return "Looking for GPS… (go outside the building if it takes long)"
        case .stopped:
            let speed = speedKmh.map { "\(Int($0.rounded())) km/h" } ?? "0 km/h"
            return "Vehicle stopped · \(speed)"
        case .moving:
            let speed = speedKmh.map { "\(Int($0.rounded())) km/h" } ?? ""
            return "Moving \(speed) → recording Driving"
        }
    }

    // MARK: Start / stop

    private func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .needsPermission
            manager.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            state = .denied
            return
        default:
            break
        }
        guard !started else { return }
        started = true
        state = .waitingForGPS
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        if CMMotionActivityManager.isActivityAvailable() {
            motion.startActivityUpdates(to: .main) { [weak self] activity in
                guard let activity else { return }
                Task { @MainActor in
                    self?.inVehicle = activity.automotive && activity.confidence != .low
                }
            }
        }
        stopTimer?.invalidate()
        stopTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(now: .now) }
        }
    }

    private func stop() {
        // Only touch location/motion if they were started, so nothing asks for permission while in-cab mode is off.
        if started {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            motion.stopActivityUpdates()
        }
        if let start = overspeedStart { finishOverspeed(start: start, end: .now) }
        flushDistance()
        lastMovingLocation = nil
        stopTimer?.invalidate()
        stopTimer = nil
        started = false
        state = .off
        isMoving = false
        speedKmh = nil
        movingSince = nil
        stoppedSince = nil
    }

    // MARK: Detection

    private func handle(_ location: CLLocation) {
        // Ignore stale or inaccurate fixes.
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
              abs(location.timestamp.timeIntervalSinceNow) < 15 else { return }
        lastFix = location.timestamp
        lastFixLocation = location
        recordTrack(location)
        let kmh = max(0, location.speed) * 3.6
        let speedValid = location.speed >= 0 && location.speedAccuracy >= 0 && location.speedAccuracy < 3
        speedKmh = location.speed >= 0 ? kmh : nil
        let time = location.timestamp

        if speedValid && settings.recordOverspeed { trackOverspeed(kmh: kmh, at: time, coordinate: location.coordinate) }

        // Distance: add the gap between accurate fixes while the vehicle is moving.
        if speedValid && kmh >= stoppedSpeedKmh {
            if let previous = lastMovingLocation {
                let metres = location.distance(from: previous)
                if metres < 2_000 { pendingKm += metres / 1000 }
            }
            lastMovingLocation = location
            if pendingKm >= 0.5 { flushDistance() }
        } else {
            lastMovingLocation = nil
            if pendingKm > 0 { flushDistance() }
        }

        let fastEnough = speedValid && kmh >= settings.autoMovingSpeedKmh
        // At lower speeds also require the motion chip to say "vehicle", when it's available.
        let confirmed = kmh >= gpsOnlySpeedKmh || inVehicle || !CMMotionActivityManager.isActivityAvailable()

        if fastEnough && confirmed {
            stoppedSince = nil
            if movingSince == nil { movingSince = time }
            if let since = movingSince, time.timeIntervalSince(since) >= movingConfirmSeconds,
               time >= Self.minuteRuleStart(since) {
                isMoving = true
                state = .moving
                record(.drive, at: Self.minuteRuleStart(since))
            }
        } else if !speedValid || kmh < stoppedSpeedKmh {
            movingSince = nil
            if stoppedSince == nil { stoppedSince = time }
            if !isMoving { state = .stopped }
            tick(now: time)
        }
    }

    private func tick(now: Date) {
        if let last = lastFix, now.timeIntervalSince(last) > 30, state != .moving {
            state = .waitingForGPS
        }
        guard let since = stoppedSince, now.timeIntervalSince(since) >= Double(settings.autoStopDelaySeconds) else { return }
        if isMoving {
            isMoving = false
            state = .stopped
        }
        guard let context, let open = ActivityController.openEntries(context: context).last, open.kind == .drive else { return }
        let driveEnd = Self.minuteRuleEnd(since)
        if driveEnd <= open.start {
            // Tacho minute rule: the movement never filled most of a minute, so it isn't driving.
            ActivityController.discardShortDrive(open, context: context, settings: settings)
            lastEvent = "Short movement ignored (tacho minute rule)"
            return
        }
        record(settings.autoStoppedKind, at: driveEnd)
    }

    // MARK: Tachograph minute rule

    /// Each calendar minute (:00–:59) gets the activity that filled most of it. A drive starting at :20
    /// fills 40 s of that minute, so the whole minute is driving; starting at :40 it only fills 20 s,
    /// so driving starts at the next minute. Ties go to driving.
    static func minuteRuleStart(_ t: Date) -> Date {
        let cal = Calendar.hgv
        let floor = cal.dateInterval(of: .minute, for: t)?.start ?? t
        return t.timeIntervalSince(floor) <= 30 ? floor : floor.addingTimeInterval(60)
    }

    /// Driving that stops at :40 filled 40 s of that minute, so it counts to the end of the minute;
    /// stopping at :20 it filled only 20 s, so driving ends at the start of the minute.
    static func minuteRuleEnd(_ t: Date) -> Date {
        let cal = Calendar.hgv
        let floor = cal.dateInterval(of: .minute, for: t)?.start ?? t
        return t.timeIntervalSince(floor) >= 30 ? floor.addingTimeInterval(60) : floor
    }

    /// Saves a route point every 150 m or 60 s while moving.
    private func recordTrack(_ location: CLLocation) {
        guard settings.recordRoute, let context, location.speed * 3.6 >= stoppedSpeedKmh else { return }
        if let last = lastTrackPoint, location.distance(from: last) < 150, location.timestamp.timeIntervalSince(last.timestamp) < 60 { return }
        lastTrackPoint = location
        context.insert(TrackPoint(time: location.timestamp, latitude: location.coordinate.latitude,
                                  longitude: location.coordinate.longitude, speedKmh: max(0, location.speed * 3.6)))
        try? context.save()
    }

    private func flushDistance() {
        guard let context, pendingKm > 0 else { return }
        ActivityController.addGPSDistance(pendingKm, at: .now, context: context, vehicleID: settings.currentVehicleID)
        pendingKm = 0
    }

    // MARK: Overspeed

    private func trackOverspeed(kmh: Double, at time: Date, coordinate: CLLocationCoordinate2D) {
        if kmh > settings.overspeedLimitKmh {
            if overspeedStart == nil {
                VoiceService.shared.overspeed("Over \(Int(settings.overspeedLimitKmh)) kilometres an hour.")
                overspeedStart = time
                overspeedMax = kmh
                overspeedCoordinate = coordinate
            }
            overspeedMax = max(overspeedMax, kmh)
            isOverspeeding = true
        } else if let start = overspeedStart {
            finishOverspeed(start: start, end: time)
        }
    }

    private func finishOverspeed(start: Date, end: Date) {
        overspeedStart = nil
        isOverspeeding = false
        guard let context, end.timeIntervalSince(start) >= 1 else { return }
        let event = SpeedEvent(start: start, end: end, maxKmh: overspeedMax, limitKmh: settings.overspeedLimitKmh,
                               latitude: overspeedCoordinate?.latitude ?? 0, longitude: overspeedCoordinate?.longitude ?? 0)
        context.insert(event)
        try? context.save()
        EventRecorder.log(.overspeed, title: event.isInfringement ? "Overspeed infringement" : "Overspeed",
                          detail: "\(Int(event.maxKmh)) km/h max (limit \(Int(event.limitKmh))) for \(Int(event.duration)) s",
                          speedKmh: event.maxKmh, duration: event.duration, at: start,
                          coordinate: overspeedCoordinate, context: context, settings: settings)
        lastEvent = event.isInfringement
            ? "Overspeed infringement: \(Int(event.maxKmh)) km/h for \(Int(event.duration)) s"
            : "Short overspeed recorded: \(Int(event.maxKmh)) km/h for \(Int(event.duration)) s"
    }

    private func record(_ kind: DutyKind, at time: Date) {
        guard let context else { return }
        let open = ActivityController.openEntries(context: context).last
        if let open, open.kind == kind, !open.endsShift { return }
        // Never rewrite something the driver entered after this moment.
        let when = min(max(time, open?.start ?? time), .now)
        ActivityController.switchTo(kind, context: context, settings: settings, at: when)
        lastEvent = "\(kind == .drive ? "Driving" : kind.title) recorded automatically at \(Fmt.time(when))"
    }
}

extension AutoDriveDetector: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations { self.handle(location) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            guard self.settings.autoDetectEnabled else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.start()
                // Ask for "Always" next so it keeps working with the phone locked.
                if status == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
            case .denied, .restricted:
                self.stop()
                self.state = .denied
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
