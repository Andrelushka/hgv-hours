import CoreLocation
import Foundation
import MapKit
import Observation
import UIKit

/// Turn-by-turn navigation for lorries. One engine for the whole app, so navigation keeps going when you switch
/// screens, go to another app or lock the phone (directions keep being spoken and shown on the Lock Screen).
@MainActor
@Observable
final class NavigationEngine: NSObject, CLLocationManagerDelegate {
    static let shared = NavigationEngine()

    var destinationName = ""
    var destination: CLLocationCoordinate2D?
    var route: NavRoute?
    /// Index of the step you're on (its manoeuvre is behind you; the next one is `stepIndex + 1`).
    var stepIndex = 0
    var location: CLLocation?
    /// Position drawn on the map, moved smoothly between GPS fixes.
    var displayCoordinate: CLLocationCoordinate2D?
    /// Direction of travel for the lorry marker (degrees).
    var heading: CLLocationDirection = 0
    var remainingDistance: CLLocationDistance = 0
    var remainingTime: TimeInterval = 0
    var eta: Date?
    var status = "Finding route…"
    var notEnoughTime = false
    var parkingOptions: [MKMapItem] = []
    var isRunning = false
    var isRouting = false
    /// Extra minutes from traffic (from Apple Maps' live traffic).
    var trafficDelay: TimeInterval = 0
    /// Navigation voice on/off (the speaker button).
    var voiceOn = true
    /// Speed limit sign text and road number for the current road (set by the navigation screen), for Today tiles.
    var speedLimitText: String?
    var roadRef: String?
    /// Only say turns (no "continue for…", traffic or notices).
    @ObservationIgnored var turnsOnly = false
    @ObservationIgnored var profile = TruckProfile()
    /// "valhalla" (lorry route) or "apple".
    @ObservationIgnored var provider = "valhalla"
    /// Driving time left, provided by the app (drivers' hours).
    @ObservationIgnored var driveLeft: () -> TimeInterval = { .infinity }
    /// Called with each new position (speed limits, cameras, Live Activity).
    @ObservationIgnored var onUpdate: ((CLLocation) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var lastTrafficCheck = Date.distantPast
    @ObservationIgnored private var lastReroute = Date.distantPast
    @ObservationIgnored private var warnedAboutTime = false
    @ObservationIgnored private var spoken: Set<String> = []
    @ObservationIgnored private var coords: [CLLocationCoordinate2D] = []
    @ObservationIgnored private var cumulative: [CLLocationDistance] = []
    /// Distance along the route where each step's manoeuvre is.
    @ObservationIgnored private var stepStarts: [CLLocationDistance] = []
    @ObservationIgnored private var segmentIndex = 0
    @ObservationIgnored private var lastFix: (location: CLLocation, along: CLLocationDistance, onRoute: Bool)?
    @ObservationIgnored private var smoother: Timer?
    @ObservationIgnored private var filter = GPSFilter()
    private(set) var progress: CLLocationDistance = 0

    // MARK: What's next

    var nextStep: NavStep? {
        guard let route, stepIndex + 1 < route.steps.count else { return nil }
        return route.steps[stepIndex + 1]
    }

    var currentStep: NavStep? {
        guard let route, stepIndex < route.steps.count else { return nil }
        return route.steps[stepIndex]
    }

    /// Along-the-road distance to the next manoeuvre.
    var distanceToNextManeuver: CLLocationDistance? {
        guard route != nil else { return nil }
        if stepIndex + 1 < stepStarts.count { return max(0, stepStarts[stepIndex + 1] - progress) }
        return remainingDistance
    }

    var nextInstruction: String {
        nextStep?.instruction ?? (route == nil ? "" : "Arrive at \(destinationName)")
    }

    /// Road you're on now.
    var currentRoad: String { currentStep?.roadLabel ?? "" }

    // MARK: Start / stop

    func start(to coordinate: CLLocationCoordinate2D, name: String) {
        destination = coordinate
        destinationName = name
        isRunning = true
        warnedAboutTime = false
        spoken = []
        trafficDelay = 0
        parkingOptions = []
        notEnoughTime = false
        route = nil
        lastFix = nil
        filter.reset()
        status = "Finding route…"
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.requestWhenInUseAuthorization()
        // Keep navigating with the app in the background or the phone locked (Info.plist has the location mode).
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes").map({ "\($0)".contains("location") }) == true {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = true
        startSmoothing()
        say("Starting navigation to \(name).")
        Task { await calculate(announce: true) }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        smoother?.invalidate()
        smoother = nil
        isRunning = false
        route = nil
        destination = nil
        status = "Navigation ended"
        UIApplication.shared.isIdleTimerDisabled = false
        NavLiveActivity.shared.end()
    }

    // MARK: Route

    private func calculate(announce: Bool) async {
        guard let destination, !isRouting else { return }
        isRouting = true
        defer { isRouting = false }
        var newRoute: NavRoute?
        if provider == "valhalla", let from = location ?? manager.location {
            newRoute = try? await TruckRouter.valhalla(from: from, to: destination, profile: profile)
            if newRoute == nil { status = "Lorry routing unavailable — using Apple Maps" }
        }
        if newRoute == nil {
            newRoute = try? await TruckRouter.apple(from: location, to: destination, preferMajor: profile.preferMotorways,
                                                   limiterKmh: profile.topSpeedKmh)
        }
        guard let best = newRoute, isRunning else {
            if isRunning { status = "Couldn't find a route. Check your connection." }
            return
        }
        setRoute(best)
        updateRemaining()
        status = "\(Self.distanceText(best.distance)) · arrive \(Fmt.time(eta ?? .now))"
        if announce {
            var lines = ["Route found. \(Self.distanceText(best.distance)), arriving about \(Fmt.time(eta ?? .now))."]
            if !best.isTruckRoute { lines.append("This route isn't checked for lorry restrictions.") }
            lines += best.notices
            say(lines.joined(separator: " "))
        } else {
            for n in best.notices where !turnsOnly { sayOnce("notice-\(n)", n) }
        }
        lastTrafficCheck = .distantPast
        await checkDrivingTime()
    }

    /// Caches geometry for fast progress tracking along the route.
    private func setRoute(_ r: NavRoute) {
        route = r
        coords = r.coordinates
        cumulative = [0]
        cumulative.reserveCapacity(coords.count)
        for i in 1..<max(1, coords.count) { cumulative.append(cumulative[i - 1] + Self.metres(coords[i - 1], coords[i])) }
        let total = cumulative.last ?? r.distance
        let stepSum = max(1, r.steps.reduce(0) { $0 + $1.distance })
        var run: CLLocationDistance = 0
        stepStarts = r.steps.map { step in
            defer { run += step.distance * total / stepSum }
            return run
        }
        segmentIndex = 0
        progress = 0
        stepIndex = 0
        // The last fix's distance-along belonged to the old route: drop it, or the marker jumps along the new one.
        lastFix = nil
        if let loc = location {
            let off = locate(loc, fullSearch: true)
            lastFix = (loc, progress, off <= max(80, loc.horizontalAccuracy * 2))
        }
    }

    /// Live traffic from Apple Maps: if it says the drive takes longer than the lorry route, the difference is traffic.
    private func checkTraffic() async {
        guard let destination, let from = location, route != nil else { return }
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        req.transportType = .automobile
        guard let response = try? await MKDirections(request: req).calculateETA() else { return }
        // Apple's time is for a car; allow for the limiter before comparing.
        let carTime = response.expectedTravelTime
        let lorryFactor = profile.topSpeedKmh > 0 ? max(1, 105 / profile.topSpeedKmh) : 1
        let baseRemaining = remainingTime - trafficDelay
        let delay = max(0, carTime * min(lorryFactor, 1.2) - baseRemaining)
        let previous = trafficDelay
        trafficDelay = delay > 120 ? delay : 0
        updateRemaining()
        if trafficDelay - previous > 5 * 60 && !turnsOnly {
            sayOnce("traffic-\(Int(trafficDelay / 300))",
                    "Traffic ahead. About \(Int(trafficDelay / 60)) minutes of delay. New arrival time \(Fmt.time(eta ?? .now)).")
        }
    }

    /// Warns when your drivers' hours run out before you arrive, and finds parking within reach.
    private func checkDrivingTime() async {
        guard let route else { return }
        let left = driveLeft()
        guard left.isFinite, remainingTime > left else { notEnoughTime = false; return }
        notEnoughTime = true
        let fraction = max(0, min(1, left / max(1, remainingTime)))
        let reach = coordinate(atAlong: progress + (route.distance - progress) * fraction)
        parkingOptions = await Self.findParking(near: reach)
        guard !warnedAboutTime else { return }
        warnedAboutTime = true
        var text = "You have \(Fmt.hm(left)) of driving left, but the journey takes \(Fmt.hm(remainingTime))."
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

    static func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        let k = 111_320.0
        let dx = (b.longitude - a.longitude) * k * cos((a.latitude + b.latitude) / 2 * .pi / 180)
        let dy = (b.latitude - a.latitude) * k
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Point on the route this far along it.
    func coordinate(atAlong d: CLLocationDistance) -> CLLocationCoordinate2D {
        guard coords.count > 1 else { return coords.first ?? kCLLocationCoordinate2DInvalid }
        let target = max(0, min(d, cumulative.last ?? 0))
        var lo = 0, hi = cumulative.count - 1
        while lo < hi - 1 { let mid = (lo + hi) / 2; if cumulative[mid] <= target { lo = mid } else { hi = mid } }
        let seg = cumulative[hi] - cumulative[lo]
        let t = seg > 0 ? (target - cumulative[lo]) / seg : 0
        let a = coords[lo], b = coords[hi]
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// Bearing of the route at a distance along it.
    private func bearing(atAlong d: CLLocationDistance) -> CLLocationDirection {
        let a = coordinate(atAlong: d), b = coordinate(atAlong: d + 15)
        return RoadSpeedLimit.bearing(a, b)
    }

    /// Snaps the location onto the route near where we last were. Returns the distance off the route (m).
    private func locate(_ loc: CLLocation, fullSearch: Bool = false) -> CLLocationDistance {
        guard coords.count > 1 else { return .infinity }
        let p = loc.coordinate
        // Moving: a segment pointing the other way (the opposite carriageway, or the same road on the way back)
        // isn't where you are, however close it is.
        let course = loc.course >= 0 && loc.speed > 3 ? loc.course : -1
        let from = fullSearch ? 0 : max(0, segmentIndex - 10)
        let to = fullSearch ? coords.count - 1 : min(coords.count - 1, segmentIndex + 400)
        var best = (dist: CLLocationDistance.infinity, seg: segmentIndex, along: progress)
        let k = 111_320.0, cosLat = cos(p.latitude * .pi / 180)
        for i in from..<to {
            let a = coords[i], b = coords[i + 1]
            let bx = (b.longitude - a.longitude) * k * cosLat, by = (b.latitude - a.latitude) * k
            let px = (p.longitude - a.longitude) * k * cosLat, py = (p.latitude - a.latitude) * k
            let len2 = bx * bx + by * by
            let t = len2 > 0 ? max(0, min(1, (px * bx + py * by) / len2)) : 0
            let dx = px - t * bx, dy = py - t * by
            var d = (dx * dx + dy * dy).squareRoot()
            if course >= 0 && len2 > 4 {
                var diff = abs(atan2(bx, by) * 180 / .pi - course).truncatingRemainder(dividingBy: 360)
                if diff < 0 { diff += 360 }
                if diff > 180 { diff = 360 - diff }
                if diff > 100 { d += 150 }
            }
            // Don't leap far ahead along the route unless we're searching from scratch.
            let along = cumulative[i] + t * len2.squareRoot()
            if !fullSearch && along - progress > max(400, loc.speed * 30) { d += 200 }
            if d < best.dist { best = (d, i, along) }
        }
        if best.dist < 80 && best.along >= progress - 30 {
            segmentIndex = best.seg
            progress = best.along
            stepIndex = max(0, (stepStarts.lastIndex { $0 <= progress + 1 } ?? 0))
        }
        return best.dist
    }

    private func updateRemaining() {
        guard let route else { return }
        remainingDistance = max(0, (cumulative.last ?? route.distance) - progress)
        // Remaining time: what's left of the current step plus all later steps (route times already allow for the lorry).
        var t: TimeInterval = 0
        for (i, step) in route.steps.enumerated() where i >= stepIndex {
            if i == stepIndex, i + 1 < stepStarts.count {
                let len = max(1, stepStarts[i + 1] - stepStarts[i])
                t += step.duration * max(0, min(1, (stepStarts[i + 1] - progress) / len))
            } else {
                t += step.duration
            }
        }
        if t == 0 && route.distance > 0 { t = route.duration * remainingDistance / route.distance }
        remainingTime = t + trafficDelay
        eta = Date.now.addingTimeInterval(remainingTime)
    }

    private func update(with loc: CLLocation) {
        guard filter.accept(loc) else { return }
        location = loc
        if loc.course >= 0 && loc.speed > 1.5 { heading = loc.course }
        guard isRunning else { return }
        onUpdate?(loc)
        guard let route else { return }
        if let dest = destination, loc.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude)) < 60 {
            say("You have arrived at \(destinationName).", interrupt: true)
            stop()
            status = "Arrived"
            return
        }
        var off = locate(loc)
        if off > 80 { off = locate(loc, fullSearch: true) }
        let onRoute = off <= max(80, loc.horizontalAccuracy * 2)
        lastFix = (loc, progress, onRoute)
        if !onRoute, Date.now.timeIntervalSince(lastReroute) > 20, !isRouting {
            lastReroute = .now
            sayOnce("reroute-\(Int(Date.now.timeIntervalSince1970 / 20))", "Recalculating.")
            Task { await calculate(announce: false) }
            return
        }
        speakPrompts(route: route, speed: max(0, loc.speed))
        updateRemaining()
        NavLiveActivity.shared.update(from: self)
        if Date.now.timeIntervalSince(lastTrafficCheck) > 180 {
            lastTrafficCheck = .now
            Task { await checkTraffic(); await checkDrivingTime() }
        }
    }

    /// Spoken prompts for the next manoeuvre, each said once (kept across traffic checks and reroutes).
    private func speakPrompts(route: NavRoute, speed: CLLocationSpeed) {
        guard let d = distanceToNextManeuver, let next = nextStep ?? route.steps.last else { return }
        let at = String(format: "%.3f,%.3f", next.location.latitude, next.location.longitude)
        let step = route.steps[min(stepIndex, route.steps.count - 1)]
        if !step.voice.isEmpty {
            // Valhalla's own prompts: said when this many metres are left. Skip any that are well past.
            for v in step.voice.sorted(by: { $0.before > $1.before }) where d <= v.before + 10 && d > v.before * 0.4 - 30 {
                if turnsOnly && v.text.lowercased().hasPrefix("continue") { continue }
                let bucket = v.before > 1500 ? "far" : v.before > 250 ? "near" : "now"
                let key = "\(at)|\(bucket)|\(v.text.prefix(12))"
                if !spoken.contains(key) {
                    spoken.insert(key)
                    say(v.text, interrupt: true)
                }
                break
            }
            return
        }
        // Apple routes: our own early / close / now prompts, earlier on fast roads.
        let far: Double = speed > 22 ? 2000 : 1000
        let near: Double = speed > 22 ? 500 : 300
        let now: Double = max(40, speed * 4)
        let instruction = next.type == "arrive" ? "Arrive at \(destinationName)" : next.instruction
        let stage: (String, String)? =
            d <= now ? ("now", instruction) :
            d <= near ? ("near", "In \(Self.distanceText(d)), \(instruction.lowercased())") :
            d <= far && d > near + 150 ? ("far", "In \(Self.distanceText(d)), \(instruction.lowercased())") : nil
        if let (label, text) = stage, !instruction.isEmpty {
            let key = "\(at)|\(label)"
            if !spoken.contains(key) && !spoken.contains("\(at)|now") {
                spoken.insert(key)
                say(text, interrupt: true)
            }
        }
    }

    // MARK: Smooth marker

    /// Moves the lorry marker 10 times a second between GPS fixes, along the road, so it glides instead of jumping.
    private func startSmoothing() {
        smoother?.invalidate()
        smoother = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.smoothStep() }
        }
    }

    private func smoothStep() {
        // Nobody can see the map in the background: save the battery.
        guard UIApplication.shared.applicationState == .active else { return }
        guard let fix = lastFix ?? location.map({ ($0, progress, false) }) else { return }
        let dt = min(2.5, Date.now.timeIntervalSince(fix.location.timestamp))
        let speed = max(0, fix.location.speed)
        if fix.onRoute, route != nil {
            let along = fix.along + speed * dt
            displayCoordinate = coordinate(atAlong: along)
            if speed > 1.5 { heading = bearing(atAlong: along) }
        } else if speed > 1.5, fix.location.course >= 0 {
            displayCoordinate = NavigationEngine.offset(fix.location.coordinate, metres: speed * dt, bearing: fix.location.course)
        } else {
            displayCoordinate = fix.location.coordinate
        }
    }

    static func offset(_ c: CLLocationCoordinate2D, metres: Double, bearing: CLLocationDirection) -> CLLocationCoordinate2D {
        let r = 6_371_000.0
        let b = bearing * .pi / 180, lat = c.latitude * .pi / 180, lon = c.longitude * .pi / 180
        let d = metres / r
        let lat2 = asin(sin(lat) * cos(d) + cos(lat) * sin(d) * cos(b))
        let lon2 = lon + atan2(sin(b) * sin(d) * cos(lat), cos(d) - sin(lat) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    // MARK: Voice

    /// Navigation prompts: a newer one replaces one still being spoken, so you never hear a stale turn.
    func say(_ text: String, interrupt: Bool = false) {
        guard voiceOn else { return }
        VoiceService.shared.sayNavigation(text, interrupt: interrupt)
    }

    func sayOnce(_ key: String, _ text: String) {
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
