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
                UserAnnotation()
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
            .onChange(of: engine.location) { _, loc in follow(loc) }
            .onChange(of: view) { _, _ in follow(engine.location, animated: true) }

            VStack(spacing: 8) {
                instructionBanner
                HStack(alignment: .top) {
                    speedBubble
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
        .overlay(Circle().stroke(kmh > AutoDriveDetector.shared.speedLimitKmh ? Color.red : .clear, lineWidth: 3))
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
