import MapKit
import SwiftData
import SwiftUI

/// Full-screen turn-by-turn navigation.
struct NavigationModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var engine = NavigationEngine()
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var view: ViewMode = .follow3D
    @State private var lastHeading: CLLocationDirection = 0
    @State private var showingSteps = false
    @State private var cameraHeading: CLLocationDirection = 0
    @State private var limits = RoadSpeedLimit()
    @State private var roadLimit: RoadSpeedLimit.Result?
    var target: MapScreen.NavTarget

    /// How the map follows you, like Apple Maps navigation.
    enum ViewMode: String, CaseIterable, Identifiable {
        case follow3D, headingUp, northUp, overview
        var id: String { rawValue }
        var title: String {
            switch self {
            case .follow3D: "3D from behind"
            case .headingUp: "Heading up"
            case .northUp: "North up"
            case .overview: "Route overview"
            }
        }
        var symbol: String {
            switch self {
            case .follow3D: "view.3d"
            case .headingUp: "location.north.line.fill"
            case .northUp: "safari"
            case .overview: "point.topleft.down.to.point.bottomright.curvepath"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                if let loc = engine.location {
                    // Small lorry seen from above, pointing where you're heading.
                    Annotation("", coordinate: loc.coordinate, anchor: .center) {
                        TruckMarker(rotation: lastHeading - cameraHeading)
                    }
                } else {
                    UserAnnotation()
                }
                if let route = engine.route {
                    MapPolyline(route.polyline).stroke(.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
                if let d = engine.destination {
                    Marker(engine.destinationName, systemImage: "flag.checkered", coordinate: d).tint(.indigo)
                }
                ForEach(engine.parkingOptions, id: \.self) { item in
                    Marker(item.name ?? "Parking", systemImage: "parkingsign.circle.fill", coordinate: item.placemark.coordinate).tint(.green)
                }
            }
            .mapStyle(.standard(elevation: view == .follow3D ? .realistic : .flat,
                                pointsOfInterest: .including([.parking, .gasStation, .restroom]), showsTraffic: true))
            .mapControls { MapCompass(); MapScaleView() }
            .ignoresSafeArea()
            .onMapCameraChange(frequency: .continuous) { ctx in cameraHeading = ctx.camera.heading }
            .onChange(of: engine.location) { _, loc in
                follow(loc)
                if let loc, store.settings.onlineSpeedLimits {
                    limits.update(loc, heavyVehicle: isHeavy) { roadLimit = $0 }
                }
            }
            .onChange(of: view) { _, _ in follow(engine.location, animated: true) }

            VStack(spacing: 8) {
                instructionBanner
                HStack(alignment: .top) {
                    VStack(spacing: 8) {
                        speedLimitSign
                        speedBubble
                        if let road = currentRoad {
                            RoadShield(text: road, large: true)
                        }
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        Menu {
                            Picker("View", selection: $view) {
                                ForEach(ViewMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                            }
                        } label: {
                            Image(systemName: view.symbol).font(.title3).frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                        }
                        if position.positionedByUser {
                            Button { follow(engine.location, animated: true, force: true) } label: {
                                Image(systemName: "location.fill").font(.title3).frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: Circle())
                            }
                            .accessibilityLabel("Re-centre")
                        }
                        Button { showingSteps = true } label: {
                            Image(systemName: "list.bullet").font(.title3).frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel("All directions")
                    }
                    .foregroundStyle(.primary)
                }
                Spacer()
                bottomPanel
            }
            .padding()
        }
        .sheet(isPresented: $showingSteps) {
            NavigationStack {
                List(Array((engine.route?.steps ?? []).enumerated()).filter { !$0.element.instructions.isEmpty }, id: \.offset) { i, step in
                    HStack(spacing: 12) {
                        Image(systemName: Self.maneuverSymbol(step.instructions)).frame(width: 28)
                            .foregroundStyle(i == engine.stepIndex + 1 ? Color.green : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.instructions).font(.subheadline)
                            Text(NavigationEngine.distanceText(step.distance)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .opacity(i <= engine.stepIndex ? 0.4 : 1)
                }
                .navigationTitle("Directions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { showingSteps = false } }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            engine.driveLeft = { driveLeftNow() }
            engine.limiterKmh = limiterKmh
            if let c = target.coordinate {
                engine.start(to: c, name: target.name)
            } else {
                Task {
                    let placemark = try? await CLGeocoder().geocodeAddressString(target.address).first
                    if let c = placemark?.location?.coordinate { engine.start(to: c, name: target.name) } else { engine.status = "Couldn't find that address." }
                }
            }
        }
        .onDisappear { engine.stop() }
    }

    private var instructionBanner: some View {
        HStack(spacing: 12) {
            let nextText = engine.route.flatMap { r in engine.stepIndex + 1 < r.steps.count ? r.steps[engine.stepIndex + 1].instructions : nil }
                ?? engine.currentStep?.instructions ?? ""
            Image(systemName: Self.maneuverSymbol(nextText)).font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 2) {
                if let d = engine.distanceToNextManeuver {
                    Text(NavigationEngine.distanceText(d)).font(.title2.weight(.bold)).foregroundStyle(.white)
                }
                let next = engine.route.flatMap { r in engine.stepIndex + 1 < r.steps.count ? r.steps[engine.stepIndex + 1].instructions : nil }
                if let n = next.flatMap(RoadSpeedLimit.roadNumber) {
                    RoadShield(text: n, large: true)
                }
                Text(next ?? engine.currentStep?.instructions ?? engine.status)
                    .font(.headline).foregroundStyle(.white).lineLimit(2)
            }
            Spacer()
        }
        .padding()
        .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 18))
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(engine.eta.map { "Arrive \(Fmt.time($0))" } ?? "—").font(.title3.weight(.bold).monospacedDigit())
                    Text("\(NavigationEngine.distanceText(engine.remainingDistance)) · \(engine.destinationName)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) { engine.stop(); dismiss() } label: {
                    Text("End").font(.headline).padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            if let h = heightText {
                Label(h, systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            if engine.notEnoughTime {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Not enough driving time to arrive", systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.red)
                    Text("Places to stop within reach (check they suit your vehicle):").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(engine.parkingOptions, id: \.self) { item in
                                Button {
                                    engine.start(to: item.placemark.coordinate, name: item.name ?? "Parking")
                                } label: {
                                    Label(item.name ?? "Parking", systemImage: "parkingsign.circle.fill").font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    /// Current speed, like the sat-nav speedometer.
    private var speedBubble: some View {
        let kmh = max(0, (engine.location?.speed ?? 0) * 3.6)
        let miles = store.settings.useMiles
        return VStack(spacing: 0) {
            Text("\(Int((miles ? kmh / 1.609344 : kmh).rounded()))").font(.title2.weight(.bold).monospacedDigit())
            Text(miles ? "mph" : "km/h").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 64, height: 64)
        .background(.regularMaterial, in: Circle())
        .overlay(Circle().stroke(kmh > effectiveLimitKmh + 2 ? Color.red : .clear, lineWidth: 3))
        .overlay(alignment: .bottom) {
            if limiterKmh > 0 {
                Text("Limiter \(miles ? Int((limiterKmh / 1.609344).rounded()) : Int(limiterKmh))")
                    .font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.thinMaterial, in: Capsule()).offset(y: 8)
            }
        }
    }

    /// The road's limit as a round sign (with the lower of the road and your vehicle's limit).
    @ViewBuilder
    private var speedLimitSign: some View {
        if let r = roadLimit {
            let miles = store.settings.useMiles
            let vehicleMax = SpeedLimits.defaultKmh(kind: currentVehicle?.kind ?? .tractor, weightT: currentVehicle?.weight ?? 0,
                                                    region: store.settings.region)
            let lower = isHeavy && vehicleMax + 1 < r.roadKmh
            let text = lower ? "\(Int((miles ? vehicleMax / 1.609344 : vehicleMax).rounded()))" : r.signText
            VStack(spacing: 2) {
                Text(text)
                    .font(.system(size: text.count > 2 ? 22 : 26, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(.white))
                    .overlay(Circle().stroke(.red, lineWidth: 7))
                    .shadow(radius: 2)
                if lower {
                    Text("Road \(r.signText)").font(.system(size: 10, weight: .bold)).padding(.horizontal, 5)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .accessibilityLabel("Speed limit \(text)")
        }
    }

    /// Lowest of the road limit (for your vehicle) and the limiter, km/h.
    private var effectiveLimitKmh: Double {
        var l = AutoDriveDetector.shared.speedLimitKmh
        if let r = roadLimit { l = min(l, r.roadKmh) }
        return l
    }

    /// Road you're on: OpenStreetMap ref, else the current direction step.
    private var currentRoad: String? {
        if let ref = roadLimit?.roadRef, !ref.isEmpty { return ref.components(separatedBy: ";").first }
        return engine.currentStep.flatMap { RoadSpeedLimit.roadNumber(in: $0.instructions) }
    }

    private var currentVehicle: Vehicle? { vehicles.first { $0.id.uuidString == store.settings.currentVehicleID } }

    private var isHeavy: Bool {
        guard let v = currentVehicle else { return true }
        return !(v.kind == .van && (v.weight == 0 || v.weight <= 3.5))
    }

    /// Speed limiter of the vehicle in use: as set, or 90 km/h (56 mph) for lorries over 3.5 t.
    private var limiterKmh: Double {
        if let l = currentVehicle?.limiterKmh, l > 0 { return l }
        return isHeavy ? 90 : 0
    }

    /// Moves the camera with you: behind the lorry in 3D (zooming out as speed rises), heading up, north up, or the whole route.
    private func follow(_ loc: CLLocation?, animated: Bool = false, force: Bool = false) {
        if position.positionedByUser && !force { return }
        if view == .overview, let route = engine.route {
            let rect = route.polyline.boundingMapRect
            let padded = rect.insetBy(dx: -rect.size.width * 0.15, dy: -rect.size.height * 0.25)
            withAnimation(.easeInOut(duration: 0.6)) { position = .rect(padded) }
            return
        }
        guard let loc else { return }
        if loc.course >= 0 && loc.speed > 1.5 { lastHeading = loc.course }
        let kmh = max(0, loc.speed * 3.6)
        let camera: MapCamera
        switch view {
        case .follow3D:
            // Look ahead of the lorry: camera centre a little in front, tilted like Apple Maps.
            let ahead = Self.offset(loc.coordinate, metres: 120 + kmh * 2, bearing: lastHeading)
            camera = MapCamera(centerCoordinate: ahead, distance: 420 + kmh * 9, heading: lastHeading, pitch: 62)
        case .headingUp:
            camera = MapCamera(centerCoordinate: loc.coordinate, distance: 900 + kmh * 15, heading: lastHeading, pitch: 0)
        case .northUp, .overview:
            camera = MapCamera(centerCoordinate: loc.coordinate, distance: 1100 + kmh * 15, heading: 0, pitch: 0)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) { position = .camera(camera) }
        } else {
            withAnimation(.linear(duration: 0.9)) { position = .camera(camera) }
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

    /// Arrow for a spoken instruction.
    static func maneuverSymbol(_ text: String) -> String {
        let t = text.lowercased()
        if t.contains("arrive") || t.contains("destination") { return "flag.checkered" }
        if t.contains("roundabout") { return "arrow.triangle.turn.up.right.circle.fill" }
        if t.contains("u-turn") || t.contains("make a u") { return "arrow.uturn.down" }
        if t.contains("exit") || t.contains("slip") { return t.contains("left") ? "arrow.up.left" : "arrow.up.right" }
        if t.contains("keep left") || t.contains("bear left") || t.contains("slight left") { return "arrow.up.left" }
        if t.contains("keep right") || t.contains("bear right") || t.contains("slight right") { return "arrow.up.right" }
        if t.contains("left") { return "arrow.turn.up.left" }
        if t.contains("right") { return "arrow.turn.up.right" }
        if t.contains("merge") { return "arrow.merge" }
        return "arrow.up"
    }

    private var heightText: String? {
        let ids = [store.settings.currentVehicleID, store.settings.currentTrailerID]
        let h = vehicles.filter { ids.contains($0.id.uuidString) }.map(\.height).max() ?? 0
        return h > 0 ? "Your height: \(Fmt.length(h, feet: true)). Route isn't checked for low bridges — follow the signs." : nil
    }

    private func driveLeftNow() -> TimeInterval {
        let settings = store.settings
        let snaps = ActivityController.recentSnapshots(context: context, settings: settings)
        let s = RulesEngine.status(snaps, now: .now, config: settings.ruleConfig)
        if let world = WorldRulesCache.refresh(snaps, now: .now, settings: settings) { return world.driveLeft }
        return s.currentShift == nil ? .infinity : s.driveAvailableNow
    }
}

/// Top-down lorry: cab at the front, trailer behind, an arrow on the cab. Rotated to your heading.
struct TruckMarker: View {
    var rotation: Double

    var body: some View {
        VStack(spacing: 1.5) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.blue)
                Image(systemName: "arrowtriangle.up.fill").font(.system(size: 9, weight: .black)).foregroundStyle(.white)
            }
            .frame(width: 20, height: 15)
            RoundedRectangle(cornerRadius: 2.5).fill(Color(white: 0.92))
                .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.blue, lineWidth: 2))
                .frame(width: 20, height: 34)
        }
        .padding(3)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        .rotationEffect(.degrees(rotation))
        .animation(.linear(duration: 0.8), value: rotation)
        .accessibilityLabel("Your lorry")
    }
}

/// Road number in its sign colours: blue motorway (M), green primary (A / E), white for others.
struct RoadShield: View {
    var text: String
    var large = false

    var body: some View {
        let t = text.uppercased()
        let motorway = t.hasPrefix("M") || t.contains("(M)") || t.hasPrefix("I")
        let green = !motorway && (t.hasPrefix("A") || t.hasPrefix("E") || t.hasPrefix("N") || t.hasPrefix("US"))
        Text(t)
            .font(.system(size: large ? 24 : 15, weight: .heavy, design: .rounded))
            .foregroundStyle(green ? Color.yellow : (motorway ? .white : .black))
            .padding(.horizontal, large ? 10 : 6).padding(.vertical, large ? 4 : 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(motorway ? Color.blue : (green ? Color(red: 0, green: 0.42, blue: 0.24) : .white)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 2))
            .shadow(radius: 1)
            .accessibilityLabel("Road \(t)")
    }
}
