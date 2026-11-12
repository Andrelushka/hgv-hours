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
    /// Travel time for the chosen route, with the vehicle's speed limiter applied.
    var travelTime: TimeInterval = 0
    /// Share of the route on motorways / A-roads (0…1).
    var majorShare: Double = 0

    /// Speed limiter of the vehicle (km/h, 0 = none). Slows arrival times on fast roads.
    @ObservationIgnored var limiterKmh: Double = 0
    /// Choose the route that stays on motorways and A-roads when it isn't much slower.
    @ObservationIgnored var preferMajorRoads = true

    /// Driving time left, provided by the app (drivers' hours).
    @ObservationIgnored var driveLeft: () -> TimeInterval = { .infinity }
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var lastETACheck = Date.distantPast
    @ObservationIgnored private var baselineTravelTime: TimeInterval?
    /// Prompts already spoken, keyed by the manoeuvre's position and text — kept across traffic re-checks
    /// and reroutes, so the same "turn left" is never repeated.
    @ObservationIgnored private var spoken: Set<String> = []
    /// Route geometry cached for fast progress tracking.
    @ObservationIgnored private var coords: [CLLocationCoordinate2D] = []
    /// Distance along the route at each polyline point.
    @ObservationIgnored private var cumulative: [CLLocationDistance] = []
    /// Distance along the route at the end of each step.
    @ObservationIgnored private var stepEnds: [CLLocationDistance] = []
    /// Index of the polyline segment we're on (search starts here).
    @ObservationIgnored private var segmentIndex = 0
    /// Distance travelled along the route.
    private(set) var progress: CLLocationDistance = 0
    /// Navigation voice on/off (the speaker button).
    var voiceOn = true
    @ObservationIgnored private var lastReroute = Date.distantPast
    @ObservationIgnored private var warnedAboutTime = false

    var currentStep: MKRoute.Step? {
        guard let route, stepIndex < route.steps.count else { return nil }
        return route.steps[stepIndex]
    }

    /// Along-the-road distance to the next manoeuvre (end of the current step).
    var distanceToNextManeuver: CLLocationDistance? {
        guard route != nil, stepIndex < stepEnds.count else { return nil }
        return max(0, stepEnds[stepIndex] - progress)
    }

    /// The next thing to do ("Turn left onto A45"): the instruction of the step that starts where this one ends.
    var nextInstruction: String {
        guard let route else { return "" }
        if stepIndex + 1 < route.steps.count, !route.steps[stepIndex + 1].instructions.isEmpty {
            return route.steps[stepIndex + 1].instructions
        }
        return stepIndex + 1 >= route.steps.count ? "Arrive at \(destinationName)" : (currentStep?.instructions ?? "")
    }

    func start(to coordinate: CLLocationCoordinate2D, name: String) {
        destination = coordinate
        destinationName = name
        isRunning = true
        warnedAboutTime = false
        spoken = []
        baselineTravelTime = nil
        parkingOptions = []
        notEnoughTime = false
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = true
        say("Starting navigation to \(name).")
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
        request.requestsAlternateRoutes = true
        request.highwayPreference = .any
        guard let response = try? await MKDirections(request: request).calculate(), !response.routes.isEmpty else {
            status = "Couldn't find a route. Check your connection."
            return
        }
        let best = choose(response.routes)
        setRoute(best)
        majorShare = Self.majorShare(best)
        travelTime = adjustedTime(best)
        remainingDistance = best.distance
        eta = Date.now.addingTimeInterval(travelTime)
        status = "\(Self.distanceText(best.distance)) · arrive \(Fmt.time(eta!))"
        if announce {
            var lines = ["Route found. \(Self.distanceText(best.distance)), arriving about \(Fmt.time(eta!))."]
            lines += best.advisoryNotices
            say(lines.joined(separator: " "))
        }
        // Traffic: compare the new travel time with the first one.
        if let base = baselineTravelTime {
            let delay = travelTime - base
            if delay > 5 * 60 {
                sayOnce("traffic-\(Int(delay / 600))", "Traffic ahead. About \(Int(delay / 60)) minutes of delay. New arrival time \(Fmt.time(eta!)).")
            }
            for notice in best.advisoryNotices where !announce { sayOnce("notice-\(notice)", notice) }
        }
        baselineTravelTime = travelTime
        await checkDrivingTime()
    }

    /// Lorries belong on motorways and A-roads: take the route with most of its length on them unless it is
    /// clearly slower (up to ~25% longer for a route entirely on major roads).
    private func choose(_ routes: [MKRoute]) -> MKRoute {
        guard preferMajorRoads, routes.count > 1 else { return routes[0] }
        return routes.min { score($0) < score($1) } ?? routes[0]
    }

    private func score(_ r: MKRoute) -> Double {
        adjustedTime(r) * (1 - 0.2 * Self.majorShare(r))
    }

    static func majorShare(_ r: MKRoute) -> Double {
        guard r.distance > 0 else { return 0 }
        let major = r.steps.filter { RoadSpeedLimit.isMajor($0.instructions) || RoadSpeedLimit.isMajor($0.notice ?? "") }
            .reduce(0) { $0 + $1.distance }
        return min(1, major / r.distance)
    }

    /// Apple's times are for cars. With a limiter, fast-road stretches take at least distance ÷ limiter.
    func adjustedTime(_ r: MKRoute) -> TimeInterval {
        guard limiterKmh > 0 else { return r.expectedTravelTime }
        let major = Self.majorShare(r) * r.distance
        let carSpeed = 108 / 3.6, truckSpeed = limiterKmh * 0.95 / 3.6
        return r.expectedTravelTime + max(0, major / truckSpeed - major / carSpeed)
    }

    /// Warns when your drivers' hours run out before you arrive, and finds parking within reach.
    private func checkDrivingTime() async {
        guard let route else { return }
        let left = driveLeft()
        guard left.isFinite, travelTime > left else { notEnoughTime = false; return }
        notEnoughTime = true
        // The point on the route you can reach in the time left.
        let fraction = max(0, min(1, left / travelTime))
        let coords = route.polyline.coordinates
        let reach = coords[min(coords.count - 1, Int(Double(coords.count - 1) * fraction))]
        parkingOptions = await Self.findParking(near: reach)
        guard !warnedAboutTime else { return }
        warnedAboutTime = true
        var text = "You have \(Fmt.hm(left)) of driving left, but the journey takes \(Fmt.hm(travelTime))."
        if let first = parkingOptions.first {
            text += " Nearest place to stop within reach: \(first.name ?? "services"). Check it's suitable for your vehicle."
        }
        say(text)
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

    /// Caches the route's geometry: points, distance along the route at each point, and where each step ends.
    private func setRoute(_ r: MKRoute) {
        route = r
        coords = r.polyline.coordinates
        cumulative = [0]
        cumulative.reserveCapacity(coords.count)
        for i in 1..<max(1, coords.count) {
            cumulative.append(cumulative[i - 1] + Self.metres(coords[i - 1], coords[i]))
        }
        // Step distances add up to the route length; scale to the polyline's own length so they line up.
        let total = cumulative.last ?? r.distance
        let stepSum = max(1, r.steps.reduce(0) { $0 + $1.distance })
        var run: CLLocationDistance = 0
        stepEnds = r.steps.map { run += $0.distance * total / stepSum; return run }
        segmentIndex = 0
        progress = 0
        stepIndex = 0
        if let loc = location { _ = locate(loc, fullSearch: true) }
    }

    /// Fast flat-earth distance (good to a few metres over short distances).
    static func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        let k = 111_320.0
        let dx = (b.longitude - a.longitude) * k * cos((a.latitude + b.latitude) / 2 * .pi / 180)
        let dy = (b.latitude - a.latitude) * k
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Snaps the location onto the route near where we last were. Returns the distance off the route (m).
    private func locate(_ loc: CLLocation, fullSearch: Bool = false) -> CLLocationDistance {
        guard coords.count > 1 else { return .infinity }
        let p = loc.coordinate
        let from = fullSearch ? 0 : max(0, segmentIndex - 10)
        let to = fullSearch ? coords.count - 1 : min(coords.count - 1, segmentIndex + 400)
        var best = (dist: CLLocationDistance.infinity, seg: segmentIndex, along: progress)
        let k = 111_320.0, cosLat = cos(p.latitude * .pi / 180)
        for i in from..<to {
            let a = coords[i], b = coords[i + 1]
            // Project p onto segment a→b in a local flat frame (metres).
            let bx = (b.longitude - a.longitude) * k * cosLat, by = (b.latitude - a.latitude) * k
            let px = (p.longitude - a.longitude) * k * cosLat, py = (p.latitude - a.latitude) * k
            let len2 = bx * bx + by * by
            let t = len2 > 0 ? max(0, min(1, (px * bx + py * by) / len2)) : 0
            let dx = px - t * bx, dy = py - t * by
            let d = (dx * dx + dy * dy).squareRoot()
            if d < best.dist { best = (d, i, cumulative[i] + t * len2.squareRoot()) }
        }
        // Never jump backwards more than a little (GPS noise near junctions).
        if best.dist < 80 && best.along >= progress - 30 {
            segmentIndex = best.seg
            progress = best.along
            stepIndex = stepEnds.firstIndex { $0 > progress + 1 } ?? max(0, stepEnds.count - 1)
        }
        return best.dist
    }

    private func update(with loc: CLLocation) {
        location = loc
        guard route != nil else { return }
        // Arrived?
        if let dest = destination, loc.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude)) < 60 {
            say("You have arrived at \(destinationName).", interrupt: true)
            stop()
            status = "Arrived"
            return
        }
        var off = locate(loc)
        if off > 80 { off = locate(loc, fullSearch: true) }
        // Off route (allowing for poor GPS)? Recalculate, at most every 30 s.
        let tolerance = max(80, loc.horizontalAccuracy * 2)
        if off > tolerance, Date.now.timeIntervalSince(lastReroute) > 30 {
            lastReroute = .now
            sayOnce("reroute-\(Int(Date.now.timeIntervalSince1970 / 30))", "Recalculating.")
            Task { await calculate(announce: false) }
            return
        }
        // Spoken directions before each manoeuvre: early, close, and at it — each once.
        if let d = distanceToNextManeuver, let route, stepIndex + 1 <= route.steps.count {
            let instruction = nextInstruction
            let speed = max(loc.speed, 0)
            // On fast roads warn earlier.
            let far: Double = speed > 22 ? 2000 : 1000
            let near: Double = speed > 22 ? 500 : 300
            let now: Double = max(40, speed * 4)
            let end = stepIndex < route.steps.count ? route.steps[stepIndex].polyline.coordinates.last : nil
            let id = end.map { String(format: "%.3f,%.3f", $0.latitude, $0.longitude) } ?? "\(stepIndex)"
            let stage: (String, String)? =
                d <= now ? ("now", instruction) :
                d <= near ? ("near", "In \(Self.distanceText(d)), \(instruction.lowercased())") :
                d <= far && d > near + 150 ? ("far", "In \(Self.distanceText(d)), \(instruction.lowercased())") : nil
            if let (label, text) = stage, !instruction.isEmpty {
                let key = "\(id)|\(instruction)|\(label)"
                // Saying "now" also covers the earlier prompts for this turn.
                if !spoken.contains(key) && !spoken.contains("\(id)|\(instruction)|now") {
                    spoken.insert(key)
                    say(text, interrupt: true)
                }
            }
        }
        remainingDistance = max(0, (cumulative.last ?? 0) - progress)
        if travelTime > 0, let r = self.route, r.distance > 0 {
            eta = Date.now.addingTimeInterval(travelTime * remainingDistance / r.distance)
        }
        // Re-check traffic every 3 minutes (keeps what's already been said).
        if Date.now.timeIntervalSince(lastETACheck) > 180 {
            lastETACheck = .now
            Task { await calculate(announce: false) }
        }
    }

    // MARK: Voice

    /// Navigation prompts: a newer one replaces one still being spoken, so you never hear a stale turn.
    private func say(_ text: String, interrupt: Bool = false) {
        guard voiceOn else { return }
        VoiceService.shared.sayNavigation(text, interrupt: interrupt)
    }

    private func sayOnce(_ key: String, _ text: String) {
        guard !spoken.contains(key) else { return }
        spoken.insert(key)
        say(text)
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
