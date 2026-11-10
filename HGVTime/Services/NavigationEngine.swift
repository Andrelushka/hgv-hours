import CoreLocation
import Foundation
import MapKit
import Observation
import UIKit

/// Turn-by-turn navigation with spoken directions, traffic delay announcements, and a check
/// that you have enough driving time to arrive (otherwise it suggests places to park).
@MainActor
@Observable
final class NavigationEngine: NSObject, CLLocationManagerDelegate {
    var destinationName = ""
    var destination: CLLocationCoordinate2D?
    var route: MKRoute?
    var stepIndex = 0
    var location: CLLocation?
    var remainingDistance: CLLocationDistance = 0
    var eta: Date?
    var status = "Finding route…"
    var notEnoughTime = false
    var parkingOptions: [MKMapItem] = []
    var isRunning = false

    /// Driving time left, provided by the app (drivers' hours).
    @ObservationIgnored var driveLeft: () -> TimeInterval = { .infinity }
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var lastETACheck = Date.distantPast
    @ObservationIgnored private var baselineTravelTime: TimeInterval?
    @ObservationIgnored private var spokenForStep: Set<String> = []
    @ObservationIgnored private var lastReroute = Date.distantPast
    @ObservationIgnored private var warnedAboutTime = false

    var currentStep: MKRoute.Step? {
        guard let route, stepIndex < route.steps.count else { return nil }
        return route.steps[stepIndex]
    }

    var distanceToNextManeuver: CLLocationDistance? {
        guard let step = currentStep, let loc = location, let end = step.polyline.coordinates.last else { return nil }
        return loc.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }

    func start(to coordinate: CLLocationCoordinate2D, name: String) {
        destination = coordinate
        destinationName = name
        isRunning = true
        warnedAboutTime = false
        baselineTravelTime = nil
        parkingOptions = []
        notEnoughTime = false
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = true
        VoiceService.shared.say("Starting navigation to \(name).", force: true)
        Task { await calculate(announce: true) }
    }

    func stop() {
        manager.stopUpdatingLocation()
        isRunning = false
        route = nil
        status = "Navigation ended"
    }

    // MARK: Route

    private func calculate(announce: Bool) async {
        guard let destination else { return }
        let request = MKDirections.Request()
        request.source = location.map { MKMapItem(placemark: MKPlacemark(coordinate: $0.coordinate)) } ?? MKMapItem.forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.departureDate = .now
        guard let response = try? await MKDirections(request: request).calculate(), let best = response.routes.first else {
            status = "Couldn't find a route. Check your connection."
            return
        }
        route = best
        stepIndex = best.steps.first?.distance == 0 ? 1 : 0
        spokenForStep = []
        remainingDistance = best.distance
        eta = Date.now.addingTimeInterval(best.expectedTravelTime)
        status = "\(Self.distanceText(best.distance)) · arrive \(Fmt.time(eta!))"
        if announce {
            var lines = ["Route found. \(Self.distanceText(best.distance)), arriving about \(Fmt.time(eta!))."]
            lines += best.advisoryNotices
            VoiceService.shared.say(lines.joined(separator: " "), force: true)
        }
        // Traffic: compare the new travel time with the first one.
        if let base = baselineTravelTime {
            let delay = best.expectedTravelTime - base
            if delay > 5 * 60 {
                VoiceService.shared.say("Traffic ahead. About \(Int(delay / 60)) minutes of delay. New arrival time \(Fmt.time(eta!)).", force: true)
            }
            if !best.advisoryNotices.isEmpty && announce == false {
                VoiceService.shared.say(best.advisoryNotices.joined(separator: " "), force: true)
            }
        }
        baselineTravelTime = best.expectedTravelTime
        await checkDrivingTime()
    }

    /// Warns when your drivers' hours run out before you arrive, and finds parking within reach.
    private func checkDrivingTime() async {
        guard let route else { return }
        let left = driveLeft()
        guard left.isFinite, route.expectedTravelTime > left else { notEnoughTime = false; return }
        notEnoughTime = true
        // The point on the route you can reach in the time left.
        let fraction = max(0, min(1, left / route.expectedTravelTime))
        let coords = route.polyline.coordinates
        let reach = coords[min(coords.count - 1, Int(Double(coords.count - 1) * fraction))]
        parkingOptions = await Self.findParking(near: reach)
        guard !warnedAboutTime else { return }
        warnedAboutTime = true
        var text = "You have \(Fmt.hm(left)) of driving left, but the journey takes \(Fmt.hm(route.expectedTravelTime))."
        if let first = parkingOptions.first {
            text += " Nearest place to stop within reach: \(first.name ?? "services"). Check it's suitable for your vehicle."
        }
        VoiceService.shared.say(text, force: true)
    }

    /// Services, truck stops and lorry parks near a point.
    static func findParking(near c: CLLocationCoordinate2D) async -> [MKMapItem] {
        var found: [MKMapItem] = []
        for query in ["truck stop", "lorry park", "motorway services", "truck parking"] {
            let r = MKLocalSearch.Request()
            r.naturalLanguageQuery = query
            r.region = MKCoordinateRegion(center: c, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
            r.resultTypes = .pointOfInterest
            if let res = try? await MKLocalSearch(request: r).start() {
                for item in res.mapItems where !found.contains(where: { $0.name == item.name }) { found.append(item) }
            }
        }
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return found.sorted {
            here.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude))
                < here.distance(from: CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude))
        }.prefix(8).map { $0 }
    }

    // MARK: Following the route

    private func update(with loc: CLLocation) {
        location = loc
        guard let route, let step = currentStep else { return }
        // Arrived?
        if let dest = destination, loc.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude)) < 60 {
            VoiceService.shared.say("You have arrived at \(destinationName).", force: true)
            stop()
            status = "Arrived"
            return
        }
        // Off route? Recalculate (at most every 30 s).
        let nearest = route.polyline.coordinates.map { loc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }.min() ?? 0
        if nearest > 120, Date.now.timeIntervalSince(lastReroute) > 30 {
            lastReroute = .now
            VoiceService.shared.say("Recalculating.", force: true)
            Task { await calculate(announce: false) }
            return
        }
        // Spoken directions before each turn.
        if let d = distanceToNextManeuver {
            let next = stepIndex + 1 < route.steps.count ? route.steps[stepIndex + 1] : nil
            let instruction = (next?.instructions.isEmpty == false ? next!.instructions : step.instructions)
            for (threshold, label) in [(1000.0, "far"), (300.0, "near"), (40.0, "now")] where d < threshold {
                let key = "\(stepIndex)-\(label)"
                if !spokenForStep.contains(key) && !instruction.isEmpty {
                    spokenForStep.insert(key)
                    VoiceService.shared.say(label == "now" ? instruction : "In \(Self.distanceText(d)), \(instruction.lowercased())", force: true)
                    break
                }
            }
            if d < 25 && stepIndex + 1 < route.steps.count { stepIndex += 1 }
        }
        remainingDistance = route.steps[stepIndex...].reduce(0) { $0 + $1.distance }
        // Re-check traffic every 3 minutes.
        if Date.now.timeIntervalSince(lastETACheck) > 180 {
            lastETACheck = .now
            Task { await calculate(announce: false) }
        }
    }

    static func distanceText(_ m: CLLocationDistance) -> String {
        let miles = m / 1609.344
        if miles >= 0.2 { return String(format: miles >= 10 ? "%.0f miles" : "%.1f miles", miles) }
        return "\(Int((m / 10).rounded() * 10)) metres"
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.update(with: loc) }
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
