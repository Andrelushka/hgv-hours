import CoreLocation
import Foundation
import MapKit

/// One lane at a junction: which way it goes and whether it's a lane you can use for the next manoeuvre.
struct NavLane: Equatable, Hashable {
    var indications: [String]
    var valid: Bool
    var active: Bool

    /// Arrow for the lane ("left", "slight right", "straight"…).
    var symbol: String {
        NavStep.symbol(type: "turn", modifier: indications.first ?? "straight")
    }
}

/// One manoeuvre and the road after it.
struct NavStep: Identifiable, Equatable {
    var id = UUID()
    var instruction: String
    /// OSRM manoeuvre type: turn, new name, depart, arrive, merge, on ramp, off ramp, fork, end of road, continue, roundabout…
    var type: String
    /// left, slight left, sharp left, right, …, straight, uturn.
    var modifier: String
    /// Road name and number after the manoeuvre.
    var name: String
    var ref: String
    var distance: CLLocationDistance
    var duration: TimeInterval
    var location: CLLocationCoordinate2D
    /// Lanes at this manoeuvre (empty when unknown).
    var lanes: [NavLane] = []
    /// Spoken prompts for the *next* manoeuvre, said when this many metres are left of this step.
    var voice: [(text: String, before: CLLocationDistance)] = []
    var roundaboutExit: Int?

    static func == (a: NavStep, b: NavStep) -> Bool { a.id == b.id }

    var symbol: String { Self.symbol(type: type, modifier: modifier) }

    /// "M1", "A45" or the road name.
    var roadLabel: String {
        let r = ref.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return r.isEmpty ? name : r
    }

    /// SF Symbol for a manoeuvre.
    static func symbol(type: String, modifier: String) -> String {
        let m = modifier.lowercased(), t = type.lowercased()
        if t == "arrive" { return "flag.checkered" }
        if t.contains("roundabout") || t.contains("rotary") {
            return t.hasPrefix("exit") ? "arrow.up.right" : "arrow.triangle.turn.up.right.circle.fill"
        }
        if m == "uturn" { return "arrow.uturn.down" }
        if t == "merge" { return "arrow.merge" }
        switch m {
        case "sharp left": return "arrow.turn.left.down"
        case "left": return "arrow.turn.up.left"
        case "slight left": return "arrow.up.left"
        case "sharp right": return "arrow.turn.right.down"
        case "right": return "arrow.turn.up.right"
        case "slight right": return "arrow.up.right"
        default: return "arrow.up"
        }
    }
}

/// A route to drive: geometry, steps and how it was made.
struct NavRoute {
    var coordinates: [CLLocationCoordinate2D]
    var distance: CLLocationDistance
    var duration: TimeInterval
    var steps: [NavStep]
    /// "Lorry route (OpenStreetMap)" or "Apple Maps".
    var source: String
    var isTruckRoute: Bool
    var notices: [String] = []

    var polyline: MKPolyline { MKPolyline(coordinates: coordinates, count: coordinates.count) }

    /// Share of the distance on motorways and A-roads.
    @MainActor var majorShare: Double {
        guard distance > 0 else { return 0 }
        let major = steps.filter { RoadSpeedLimit.isMajor($0.ref) || RoadSpeedLimit.isMajor($0.name) }.reduce(0) { $0 + $1.distance }
        return min(1, major / distance)
    }
}

/// What the router needs to know about the lorry.
struct TruckProfile: Equatable {
    var heightM: Double = 4.0
    var widthM: Double = 2.55
    var lengthM: Double = 16.5
    var weightT: Double = 44
    var axleLoadT: Double = 11.5
    var axles: Int = 5
    var topSpeedKmh: Double = 90
    var preferMotorways = true
    var avoidTolls = false
    var isTruck = true
}

@MainActor
enum TruckRouter {
    /// Free OpenStreetMap routing server run by FOSSGIS (Valhalla, MIT licence). Fair use: one route at a time.
    static let valhallaURL = URL(string: "https://valhalla1.openstreetmap.de/route")!

    enum Failure: Error { case noRoute, badResponse }

    /// Lorry route from Valhalla: avoids low bridges, weight and width limits and lorry bans, with lanes and voice prompts.
    static func valhalla(from: CLLocation, to: CLLocationCoordinate2D, profile: TruckProfile) async throws -> NavRoute {
        var origin: [String: Any] = ["lat": from.coordinate.latitude, "lon": from.coordinate.longitude]
        // Start in the direction you're already heading (no U-turn on a dual carriageway).
        if from.course >= 0 && from.speed > 2 { origin["heading"] = Int(from.course); origin["heading_tolerance"] = 45 }
        var options: [String: Any] = [
            "use_highways": profile.preferMotorways ? 1.0 : 0.5,
            "use_tolls": profile.avoidTolls ? 0.0 : 0.5,
            "top_speed": max(40, min(140, profile.topSpeedKmh)),
        ]
        if profile.isTruck {
            options["height"] = max(2, profile.heightM)
            options["width"] = max(2, profile.widthM)
            options["length"] = max(5, profile.lengthM)
            options["weight"] = max(3.5, profile.weightT)
            options["axle_load"] = max(5, profile.axleLoadT)
            options["axle_count"] = max(2, profile.axles)
        }
        let body: [String: Any] = [
            "locations": [origin, ["lat": to.latitude, "lon": to.longitude]],
            "costing": profile.isTruck ? "truck" : "auto",
            "costing_options": [profile.isTruck ? "truck" : "auto": options],
            "format": "osrm",
            "banner_instructions": true,
            "voice_instructions": true,
            "units": "kilometers",
            "language": "en-GB",
        ]
        var req = URLRequest(url: valhallaURL, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("HGVHours/3.10 (iOS)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.badResponse }
        return try parseOSRM(data, isTruck: profile.isTruck)
    }

    /// Parses a Valhalla / OSRM-format route.
    static func parseOSRM(_ data: Data, isTruck: Bool) throws -> NavRoute {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = json["routes"] as? [[String: Any]], let route = routes.first,
              let geometry = route["geometry"] as? String,
              let legs = route["legs"] as? [[String: Any]] else { throw Failure.noRoute }
        let coords = decodePolyline(geometry, precision: 1e6)
        guard coords.count > 1 else { throw Failure.noRoute }
        var steps: [NavStep] = []
        for leg in legs {
            for s in (leg["steps"] as? [[String: Any]]) ?? [] {
                let m = s["maneuver"] as? [String: Any] ?? [:]
                let loc = m["location"] as? [Double] ?? [0, 0]
                let intersections = s["intersections"] as? [[String: Any]] ?? []
                let lanes = ((intersections.first?["lanes"] as? [[String: Any]]) ?? []).map {
                    NavLane(indications: $0["indications"] as? [String] ?? [], valid: $0["valid"] as? Bool ?? false,
                            active: $0["active"] as? Bool ?? false)
                }
                let voice = ((s["voiceInstructions"] as? [[String: Any]]) ?? []).compactMap { v -> (String, Double)? in
                    guard let text = v["announcement"] as? String, let d = v["distanceAlongGeometry"] as? Double else { return nil }
                    return (text, d)
                }
                steps.append(NavStep(instruction: m["instruction"] as? String ?? "",
                                     type: m["type"] as? String ?? "", modifier: m["modifier"] as? String ?? "",
                                     name: s["name"] as? String ?? "", ref: s["ref"] as? String ?? "",
                                     distance: s["distance"] as? Double ?? 0, duration: s["duration"] as? Double ?? 0,
                                     location: CLLocationCoordinate2D(latitude: loc.count > 1 ? loc[1] : 0, longitude: loc.first ?? 0),
                                     lanes: lanes, voice: voice, roundaboutExit: m["exit"] as? Int))
            }
        }
        return NavRoute(coordinates: coords, distance: route["distance"] as? Double ?? 0, duration: route["duration"] as? Double ?? 0,
                        steps: steps, source: isTruck ? "Lorry route (OpenStreetMap)" : "OpenStreetMap", isTruckRoute: isTruck)
    }

    /// Apple Maps route, turned into the same shape (no lorry restrictions, no lanes).
    static func apple(from: CLLocation?, to: CLLocationCoordinate2D, preferMajor: Bool, limiterKmh: Double) async throws -> NavRoute {
        let request = MKDirections.Request()
        request.source = from.map { MKMapItem(placemark: MKPlacemark(coordinate: $0.coordinate)) } ?? MKMapItem.forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        request.departureDate = .now
        request.requestsAlternateRoutes = true
        let response = try await MKDirections(request: request).calculate()
        guard !response.routes.isEmpty else { throw Failure.noRoute }
        func share(_ r: MKRoute) -> Double {
            guard r.distance > 0 else { return 0 }
            return min(1, r.steps.filter { RoadSpeedLimit.isMajor($0.instructions) }.reduce(0) { $0 + $1.distance } / r.distance)
        }
        let best = preferMajor
            ? response.routes.min { $0.expectedTravelTime * (1 - 0.2 * share($0)) < $1.expectedTravelTime * (1 - 0.2 * share($1)) }!
            : response.routes[0]
        // MKRoute steps describe the manoeuvre at their start, like OSRM.
        let steps = best.steps.map { s -> NavStep in
            let parsed = parse(s.instructions)
            let start = s.polyline.coordinates.first ?? to
            return NavStep(instruction: s.instructions.isEmpty ? "Continue" : s.instructions, type: parsed.type, modifier: parsed.modifier,
                           name: "", ref: RoadSpeedLimit.roadNumber(in: s.instructions) ?? "", distance: s.distance, duration: 0,
                           location: start)
        }
        var r = NavRoute(coordinates: best.polyline.coordinates, distance: best.distance, duration: adjusted(best, limiterKmh: limiterKmh),
                         steps: steps, source: "Apple Maps (not checked for lorries)", isTruckRoute: false, notices: best.advisoryNotices)
        if let last = r.steps.indices.last, r.steps[last].type != "arrive" { r.steps[last].type = "arrive" }
        return r
    }

    /// Apple's times are for cars: with a limiter, fast roads take at least distance ÷ limiter.
    static func adjusted(_ r: MKRoute, limiterKmh: Double) -> TimeInterval {
        guard limiterKmh > 0, r.distance > 0 else { return r.expectedTravelTime }
        let major = r.steps.filter { RoadSpeedLimit.isMajor($0.instructions) }.reduce(0) { $0 + $1.distance }
        return r.expectedTravelTime + max(0, major / (limiterKmh * 0.95 / 3.6) - major / (108 / 3.6))
    }

    /// Type and direction from an instruction like "Turn right onto Leftwich Road" (only the manoeuvre part, whole words).
    static func parse(_ text: String) -> (type: String, modifier: String) {
        let t = text.lowercased()
        if t.contains("arrive") || t.contains("destination") { return ("arrive", "") }
        var action = t
        for cut in [" onto ", " toward ", " towards ", " to stay on ", " on to ", " for "] {
            if let r = action.range(of: cut) { action = String(action[..<r.lowerBound]) }
        }
        func has(_ w: String) -> Bool { action.range(of: "\\b\(w)\\b", options: .regularExpression) != nil }
        let side = has("left") && !has("right") ? "left" : has("right") && !has("left") ? "right" : ""
        if has("roundabout") { return ("roundabout", side) }
        if has("u-turn") || action.contains("make a u") { return ("turn", "uturn") }
        if has("merge") { return ("merge", side) }
        if has("exit") || has("slip") || has("keep") || has("bear") || has("slight") || has("fork") {
            return ("fork", side.isEmpty ? "straight" : "slight \(side)")
        }
        if !side.isEmpty { return ("turn", has("sharp") ? "sharp \(side)" : side) }
        return ("continue", "straight")
    }

    /// Google/OSRM encoded polyline (precision 1e5 or 1e6).
    static func decodePolyline(_ s: String, precision: Double) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(s.count / 4)
        let bytes = Array(s.utf8)
        var i = 0, lat = 0, lon = 0
        func next() -> Int? {
            var result = 0, shift = 0
            while i < bytes.count {
                let b = Int(bytes[i]) - 63
                i += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while i < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat; lon += dLon
            coords.append(CLLocationCoordinate2D(latitude: Double(lat) / precision, longitude: Double(lon) / precision))
        }
        return coords
    }
}

