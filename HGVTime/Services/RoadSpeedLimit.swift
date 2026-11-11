import CoreLocation
import Foundation

/// The speed limit of the road you're on, from OpenStreetMap (Overpass API), plus the legal maximum for
/// your vehicle. Looked up at most every 300 m / 20 s while navigating.
@MainActor
final class RoadSpeedLimit {
    struct Result: Equatable {
        /// Signed limit for the road, km/h (HGV-specific limit when the map has one).
        var roadKmh: Double
        /// The value as signed (mph roads in the UK/US).
        var signText: String
        var roadRef: String
        var roadName: String
    }

    private var lastQuery: CLLocation?
    private var lastTime = Date.distantPast
    private var task: Task<Void, Never>?
    private(set) var current: Result?

    /// Asks for the limit near `loc` when far enough from the last lookup; calls `done` with the result.
    func update(_ loc: CLLocation, heavyVehicle: Bool, done: @escaping (Result?) -> Void) {
        if let last = lastQuery, loc.distance(from: last) < 300, Date.now.timeIntervalSince(lastTime) < 20 { return }
        if Date.now.timeIntervalSince(lastTime) < 6 { return }
        lastQuery = loc
        lastTime = .now
        task?.cancel()
        let c = loc.coordinate
        let course = loc.course
        task = Task {
            let r = await Self.lookup(c, course: course, heavy: heavyVehicle)
            guard !Task.isCancelled else { return }
            self.current = r
            done(r)
        }
    }

    /// Overpass query for roads within 25 m that have a maxspeed tag.
    static func lookup(_ c: CLLocationCoordinate2D, course: CLLocationDirection, heavy: Bool) async -> Result? {
        // Rounded to ~10 m; only the position is sent.
        let lat = (c.latitude * 10_000).rounded() / 10_000, lon = (c.longitude * 10_000).rounded() / 10_000
        let q = "[out:json][timeout:8];way(around:25,\(lat),\(lon))[highway][maxspeed];out tags geom 3;"
        var comps = URLComponents(string: "https://overpass-api.de/api/interpreter")!
        comps.queryItems = [URLQueryItem(name: "data", value: q)]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("HGVHours-iOS/3.4 (speed-limit display)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]], !elements.isEmpty else { return nil }
        // Prefer the way whose direction matches your heading (avoids slip roads next to the carriageway).
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        func score(_ e: [String: Any]) -> Double {
            guard let geom = e["geometry"] as? [[String: Double]], geom.count >= 2 else { return 1_000 }
            let pts = geom.compactMap { g -> CLLocation? in
                guard let la = g["lat"], let lo = g["lon"] else { return nil }
                return CLLocation(latitude: la, longitude: lo)
            }
            let d = pts.map { here.distance(from: $0) }.min() ?? 1_000
            guard course >= 0, let a = pts.first, let b = pts.last else { return d }
            let bearing = Self.bearing(a.coordinate, b.coordinate)
            var diff = abs(bearing - course).truncatingRemainder(dividingBy: 180)
            diff = min(diff, 180 - diff)
            return d + diff * 0.5
        }
        guard let best = elements.min(by: { score($0) < score($1) }), let tags = best["tags"] as? [String: String] else { return nil }
        let raw = (heavy ? tags["maxspeed:hgv"] ?? tags["maxspeed:goods"] : nil) ?? tags["maxspeed"] ?? ""
        guard let parsed = parse(raw) else { return nil }
        return Result(roadKmh: parsed.kmh, signText: parsed.text, roadRef: tags["ref"] ?? "", roadName: tags["name"] ?? "")
    }

    /// "50", "30 mph", "GB:nsl_single", "DE:motorway"… → km/h and the number on the sign.
    static func parse(_ raw: String) -> (kmh: Double, text: String)? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasSuffix("mph"), let v = Double(s.dropLast(3).trimmingCharacters(in: .whitespaces)) { return (v * 1.609344, "\(Int(v))") }
        if let v = Double(s) { return (v, "\(Int(v))") }
        let named: [String: (Double, String)] = [
            "gb:nsl_single": (96.56, "60"), "gb:nsl_dual": (112.65, "70"), "gb:motorway": (112.65, "70"),
            "uk:nsl_single": (96.56, "60"), "uk:nsl_dual": (112.65, "70"), "uk:motorway": (112.65, "70"),
            "de:urban": (50, "50"), "de:rural": (100, "100"), "fr:urban": (50, "50"), "fr:rural": (80, "80"),
            "fr:motorway": (130, "130"), "it:motorway": (130, "130"), "nl:motorway": (100, "100"),
        ]
        if let n = named[s] { return (n.0, n.1) }
        return nil
    }

    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDirection {
        let la1 = a.latitude * .pi / 180, la2 = b.latitude * .pi / 180, dl = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dl) * cos(la2), x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dl)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Road number in an instruction or road name ("Take exit onto M1", "A14") — nil if none.
    static func roadNumber(in text: String) -> String? {
        let pattern = #"\b((?:M|A|B|E|N|D|I|US)[- ]?\d{1,4}(?:\([MT]\))?|A\d{1,4}\(M\))\b"#
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[r]).replacingOccurrences(of: " ", with: "")
    }

    /// Motorway / major road?
    static func isMajor(_ text: String) -> Bool {
        let t = text.lowercased()
        if t.contains("motorway") || t.contains("autobahn") || t.contains("autoroute") || t.contains("autostrada")
            || t.contains("autopista") || t.contains("snelweg") || t.contains("interstate") || t.contains("freeway") || t.contains("highway") { return true }
        guard let n = roadNumber(in: text) else { return false }
        return n.hasPrefix("M") || n.hasPrefix("A") || n.hasPrefix("E") || n.hasPrefix("I") || n.hasPrefix("US")
    }
}
