import CoreLocation
import Foundation
import SwiftData

/// Something you reported on the road (kept on this iPhone).
@Model
final class RoadReport {
    var id: UUID = UUID()
    var kindRaw: String = "hazard"
    var latitude: Double = 0
    var longitude: Double = 0
    var createdAt: Date = Date()
    var expiresAt: Date = Date()
    var note: String = ""

    init(kind: RoadReport.Kind, coordinate: CLLocationCoordinate2D, at: Date = .now) {
        kindRaw = kind.rawValue
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        createdAt = at
        expiresAt = at.addingTimeInterval(kind.lifetime)
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .hazard }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    enum Kind: String, CaseIterable, Identifiable {
        case accident, closure, roadworks, police, camera, hazard, traffic, lowBridge, weighbridge
        var id: String { rawValue }
        var title: String {
            switch self {
            case .accident: String(localized: "Accident")
            case .closure: String(localized: "Road closed")
            case .roadworks: String(localized: "Roadworks")
            case .police: String(localized: "Police / DVSA")
            case .camera: String(localized: "Speed camera")
            case .hazard: String(localized: "Hazard on road")
            case .traffic: String(localized: "Traffic jam")
            case .lowBridge: String(localized: "Low bridge")
            case .weighbridge: String(localized: "Weighbridge / check site")
            }
        }
        var symbol: String {
            switch self {
            case .accident: "car.side.rear.and.collision.and.car.side.front"
            case .closure: "xmark.octagon.fill"
            case .roadworks: "cone.fill"
            case .police: "light.beacon.max.fill"
            case .camera: "camera.fill"
            case .hazard: "exclamationmark.triangle.fill"
            case .traffic: "car.2.fill"
            case .lowBridge: "arrow.down.to.line"
            case .weighbridge: "scalemass.fill"
            }
        }
        /// How long the report stays on the map.
        var lifetime: TimeInterval {
            switch self {
            case .accident, .police, .hazard: 3 * 3600
            case .traffic: 1 * 3600
            case .closure, .roadworks: 3 * 86_400
            case .camera, .lowBridge, .weighbridge: 3650 * 86_400
            }
        }
    }
}

/// Speed cameras and traffic lights near you from OpenStreetMap, plus your own reports, with spoken warnings ahead.
@MainActor
@Observable
final class RoadHazards {
    struct Point: Identifiable, Hashable {
        enum Kind: String { case camera, trafficLight }
        var id: Int64
        var kind: Kind
        var coordinate: CLLocationCoordinate2D
        /// For cameras: the limit it enforces, if tagged.
        var maxspeed: String = ""
        static func == (a: Point, b: Point) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    static let shared = RoadHazards()
    private(set) var points: [Point] = []
    /// What's drawn on the navigation map: cameras within 5 km and up to 40 traffic lights within 1.5 km
    /// (drawing hundreds of lights made the map freeze). Updated as you move, not on every redraw.
    private(set) var nearby: [Point] = []
    @ObservationIgnored private var lastNearby: CLLocation?

    func refreshNearby(_ loc: CLLocation, lights: Bool) {
        if let last = lastNearby, loc.distance(from: last) < 150 { return }
        lastNearby = loc
        let here = loc.coordinate
        let cams = points.filter { $0.kind == .camera }
        let lightsNear = lights ? points.filter { $0.kind == .trafficLight }
            .map { ($0, NavigationEngine.metres(here, $0.coordinate)) }
            .filter { $0.1 < 1500 }.sorted { $0.1 < $1.1 }.prefix(40).map(\.0) : []
        nearby = cams + lightsNear
    }
    @ObservationIgnored private var lastQuery: (CLLocation, Date)?
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var warned: Set<String> = []

    /// Fetch again after moving 2.5 km or every 10 minutes.
    func update(_ loc: CLLocation, includeLights: Bool) {
        if let (at, when) = lastQuery, loc.distance(from: at) < 2500, Date.now.timeIntervalSince(when) < 600 { return }
        guard !busy else { return }
        busy = true
        lastQuery = (loc, .now)
        Task {
            defer { busy = false }
            if let found = try? await Self.fetch(around: loc.coordinate, radius: 5000, lights: includeLights) {
                points = found
                lastNearby = nil
                refreshNearby(loc, lights: includeLights)
            }
        }
    }

    static func fetch(around c: CLLocationCoordinate2D, radius: Int, lights: Bool) async throws -> [Point] {
        let around = "around:\(radius),\(c.latitude),\(c.longitude)"
        let q = "[out:json][timeout:15];(node(\(around))[highway=speed_camera];\(lights ? "node(\(around))[highway=traffic_signals];" : ""));out body 400;"
        var req = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.httpBody = "data=\(q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")".data(using: .utf8)
        req.setValue("HGVHours/3.10 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return parse(data)
    }

    static func parse(_ data: Data) -> [Point] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else { return [] }
        return elements.compactMap { e in
            guard let id = (e["id"] as? NSNumber)?.int64Value, let lat = e["lat"] as? Double, let lon = e["lon"] as? Double else { return nil }
            let tags = e["tags"] as? [String: String] ?? [:]
            let kind: Point.Kind = tags["highway"] == "speed_camera" ? .camera : .trafficLight
            return Point(id: id, kind: kind, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), maxspeed: tags["maxspeed"] ?? "")
        }
    }

    /// Spoken warning for cameras and your reports ahead on the route (each once).
    func warnAhead(engine: NavigationEngine, reports: [RoadReport], cameras: Bool) {
        guard let loc = engine.location, loc.speed > 3, engine.route != nil else { return }
        let heading = engine.heading
        func ahead(_ c: CLLocationCoordinate2D, within: CLLocationDistance) -> CLLocationDistance? {
            let here = loc.coordinate
            let d = NavigationEngine.metres(here, c)
            guard d < within else { return nil }
            let b = RoadSpeedLimit.bearing(here, c)
            var diff = abs(b - heading).truncatingRemainder(dividingBy: 360)
            if diff > 180 { diff = 360 - diff }
            return diff < 30 ? d : nil
        }
        if cameras {
            for p in points where p.kind == .camera {
                if let d = ahead(p.coordinate, within: 600), !warned.contains("cam\(p.id)") {
                    warned.insert("cam\(p.id)")
                    engine.say("Speed camera ahead\(p.maxspeed.isEmpty ? "" : ", limit \(p.maxspeed)"), in \(NavigationEngine.distanceText(d)).")
                }
            }
        }
        for r in reports where r.expiresAt > .now {
            if let d = ahead(r.coordinate, within: 900), !warned.contains("rep\(r.id)") {
                warned.insert("rep\(r.id)")
                engine.say("\(r.kind.title) reported ahead, in \(NavigationEngine.distanceText(d)).")
            }
        }
    }
}
