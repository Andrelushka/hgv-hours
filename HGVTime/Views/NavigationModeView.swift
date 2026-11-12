import MapKit
import SwiftData
import SwiftUI

/// Full-screen turn-by-turn navigation. The engine is shared, so closing this screen (or switching app) doesn't stop
/// navigation — open it again from Today or the map.
struct NavigationModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \RoadReport.createdAt) private var reports: [RoadReport]
    @State private var engine = NavigationEngine.shared
    @State private var hazards = RoadHazards.shared
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var view: ViewMode = .follow3D
    @State private var showingSteps = false
    @State private var showingSettings = false
    @State private var reporting = false
    @State private var safetyAlert = false
    /// The parked reminder is shown once per app launch.
    nonisolated(unsafe) static var safetyShown = false
    /// Moving faster than walking pace: block fiddly controls.
    private var moving: Bool { (engine.location?.speed ?? 0) * 3.6 > 8 }
    @State private var cameraHeading: CLLocationDirection = 0
    @State private var cameraDistance: Double = 1000
    @State private var limits = RoadSpeedLimit()
    @State private var roadLimit: RoadSpeedLimit.Result?
    /// Where to go. `nil` = carry on with the navigation already running.
    var target: MapScreen.NavTarget?

    enum ViewMode: String, CaseIterable, Identifiable {
        case follow3D, headingUp, northUp, overview
        var id: String { rawValue }
        var title: String {
            switch self {
            case .follow3D: String(localized: "3D from behind")
            case .headingUp: String(localized: "Heading up")
            case .northUp: String(localized: "North up")
            case .overview: String(localized: "Route overview")
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

    private var s: AppSettings { store.settings }

    var body: some View {
        ZStack(alignment: .top) {
            map
            VStack(spacing: 8) {
                instructionBanner
                if s.navShowLanes, let lanes = upcomingLanes { LaneHelper(lanes: lanes) }
                HStack(alignment: .top) {
                    if s.navSpeedoSide == "left" { speedColumn; Spacer() } else { buttonColumn; Spacer() }
                    if s.navSpeedoSide == "left" { buttonColumn } else { speedColumn }
                }
                Spacer()
                if s.navSideArrow, let next = engine.nextStep {
                    // Big see-through arrow for the next turn: right side, just above the bottom bar.
                    HStack {
                        Spacer()
                        Image(systemName: next.symbol)
                            .font(.system(size: 96, weight: .black))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 6)
                            .opacity(s.navSideArrowOpacity)
                            .accessibilityHidden(true)
                    }
                    .allowsHitTesting(false)
                }
                bottomPanel
            }
            .padding()
        }
        .sheet(isPresented: $showingSteps) { stepsList }
        .alert("Use only when parked", isPresented: $safetyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("For your safety and the law, set the route and change settings only when you're parked. While driving, just listen to the directions.")
        }
        .alert("Navigation", isPresented: Binding(get: { !NavigationModeView.safetyShown && target != nil }, set: { _ in NavigationModeView.safetyShown = true })) {
            Button("I'm parked") { NavigationModeView.safetyShown = true }
        } message: {
            Text("Set your route before you drive. It's illegal to hold or use a phone while driving (Highway Code rule 149) — keep the iPhone in a holder and follow the voice directions.")
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { NavSettingsView() } }
        .confirmationDialog("Report on the road here", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(RoadReport.Kind.allCases) { k in
                Button(k.title) { report(k) }
            }
        } message: {
            Text("Saved on your iPhone and shown on the map; you'll be warned when you come this way again.")
        }
        .onAppear(perform: begin)
    }

    // MARK: Map

    private var map: some View {
        Map(position: $position) {
            if let c = engine.displayCoordinate ?? engine.location?.coordinate {
                Annotation("", coordinate: c, anchor: .center) {
                    TruckMarker(rotation: engine.heading - cameraHeading)
                }
            } else {
                UserAnnotation()
            }
            if let route = engine.route {
                MapPolyline(route.polyline).stroke(route.isTruckRoute ? Color.blue : .purple,
                                                   style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            }
            if let d = engine.destination {
                Marker(engine.destinationName, systemImage: "flag.checkered", coordinate: d).tint(.indigo)
            }
            ForEach(s.navShowParking ? engine.parkingOptions : [], id: \.self) { item in
                Marker(item.name ?? "Parking", systemImage: "parkingsign.circle.fill", coordinate: item.placemark.coordinate).tint(.green)
            }
            ForEach(hazards.nearby.filter {
                $0.kind == .camera ? s.navShowCameras : (s.navShowTrafficLights && cameraDistance < 3000)
            }) { p in
                Annotation("", coordinate: p.coordinate) {
                    Image(systemName: p.kind == .camera ? "camera.fill" : "light.beacon.max.fill")
                        .font(.system(size: p.kind == .camera ? 13 : 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(p.kind == .camera ? Color.orange : Color.red.opacity(0.85), in: Circle())
                }
            }
            if s.navShowReports {
                ForEach(reports.filter { $0.expiresAt > .now }) { r in
                    Annotation(r.kind.title, coordinate: r.coordinate) {
                        Image(systemName: r.kind.symbol).font(.caption.weight(.bold)).foregroundStyle(.white)
                            .padding(6).background(Color.red, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                }
            }
        }
        .mapStyle(s.navMapStyle == "hybrid"
                  ? .hybrid(elevation: view == .follow3D ? .realistic : .flat, pointsOfInterest: .including([.parking, .gasStation]), showsTraffic: true)
                  : .standard(elevation: view == .follow3D ? .realistic : .flat,
                              pointsOfInterest: .including([.parking, .gasStation, .restroom]), showsTraffic: true))
        .mapControls { MapCompass(); MapScaleView() }
        .ignoresSafeArea()
        .onMapCameraChange(frequency: .onEnd) { ctx in
            cameraHeading = ctx.camera.heading
            cameraDistance = ctx.camera.distance
        }
        .onChange(of: engine.location) { _, loc in follow(loc) }
        .onChange(of: view) { _, _ in follow(engine.location, animated: true) }
    }

    // MARK: Panels

    private var bannerLarge: Bool { s.navBannerSize == "l" }

    private var instructionBanner: some View {
        let next = engine.nextStep
        return HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: next?.symbol ?? "arrow.up")
                    .font(.system(size: bannerLarge ? 52 : 40, weight: .bold)).foregroundStyle(.white)
                if let exit = next?.roundaboutExit {
                    Text("\(exit)").font(.caption.weight(.heavy)).foregroundStyle(.green)
                        .frame(width: 20, height: 20).background(.white, in: Circle()).offset(x: 6, y: 6)
                }
            }
            .frame(width: bannerLarge ? 66 : 54)
            VStack(alignment: .leading, spacing: 2) {
                if let d = engine.distanceToNextManeuver {
                    Text(NavigationEngine.distanceText(d)).font(bannerLarge ? .largeTitle.weight(.bold) : .title2.weight(.bold))
                        .foregroundStyle(.white).monospacedDigit()
                }
                if let road = next.map(\.roadLabel), !road.isEmpty, RoadSpeedLimit.isMajor(road) || road.count <= 6 {
                    RoadShield(text: road, large: true)
                }
                Text(engine.route == nil ? engine.status : engine.nextInstruction)
                    .font(bannerLarge ? .title3.weight(.semibold) : .headline).foregroundStyle(.white).lineLimit(2)
            }
            Spacer()
        }
        .padding()
        .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 18))
    }

    /// Lanes for the next junction, shown from 2 km out.
    private var upcomingLanes: [NavLane]? {
        guard let next = engine.nextStep, !next.lanes.isEmpty, let d = engine.distanceToNextManeuver, d < 2000 else { return nil }
        return next.lanes
    }

    private var speedColumn: some View {
        VStack(spacing: 14) {
            speedometer
            if s.navShowRoad, let road = currentRoad {
                RoadShield(text: road, large: true)
                    .padding(.top, 4)
            }
        }
    }

    private var buttonColumn: some View {
        VStack(spacing: 8) {
            Menu {
                Picker("View", selection: Binding(get: { view }, set: { view = $0; store.settings.navViewMode = $0.rawValue })) {
                    ForEach(ViewMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                Menu("Tilt", systemImage: "rotate.3d") {
                    Picker("Tilt", selection: Binding(get: { store.settings.navPitch }, set: { store.settings.navPitch = $0; follow(engine.location, animated: true, force: true) })) {
                        Text("Flat (from above)").tag(0.0)
                        Text("Low").tag(35.0)
                        Text("Medium").tag(50.0)
                        Text("High").tag(62.0)
                        Text("Very high (behind the cab)").tag(72.0)
                    }
                }
                Menu("Show on map", systemImage: "line.3.horizontal.decrease.circle") {
                    Toggle("Speed cameras", systemImage: "camera.fill", isOn: Binding(get: { store.settings.navShowCameras }, set: { store.settings.navShowCameras = $0 }))
                    Toggle("Traffic lights", systemImage: "light.beacon.max.fill", isOn: Binding(get: { store.settings.navShowTrafficLights }, set: { store.settings.navShowTrafficLights = $0 }))
                    Toggle("Your road reports", systemImage: "exclamationmark.bubble.fill", isOn: Binding(get: { store.settings.navShowReports }, set: { store.settings.navShowReports = $0 }))
                    Toggle("Parking suggestions", systemImage: "parkingsign.circle.fill", isOn: Binding(get: { store.settings.navShowParking }, set: { store.settings.navShowParking = $0 }))
                }
                Menu("Zoom", systemImage: "plus.magnifyingglass") {
                    Picker("Zoom", selection: Binding(get: { store.settings.navZoom }, set: { store.settings.navZoom = $0; follow(engine.location, animated: true, force: true) })) {
                        Text("Very close").tag(0.5)
                        Text("Close").tag(0.75)
                        Text("Normal").tag(1.0)
                        Text("Far").tag(1.5)
                        Text("Very far").tag(2.2)
                    }
                }
            } label: { roundIcon(view.symbol) }
            .accessibilityLabel("Map view, tilt and zoom")
            if position.positionedByUser {
                Button { follow(engine.location, animated: true, force: true) } label: { roundIcon("location.fill") }
                    .accessibilityLabel("Re-centre")
            }
            Button {
                store.settings.navVoiceOn.toggle()
                engine.voiceOn = store.settings.navVoiceOn
                if !engine.voiceOn { VoiceService.shared.stopSpeaking() }
            } label: { roundIcon(s.navVoiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill") }
            .accessibilityLabel(s.navVoiceOn ? "Mute directions" : "Unmute directions")
            Button { if moving { safetyAlert = true } else { reporting = true } } label: { roundIcon("exclamationmark.bubble.fill") }
                .accessibilityLabel("Report on the road")
            Button { if moving { safetyAlert = true } else { showingSteps = true } } label: { roundIcon("list.bullet") }
                .accessibilityLabel("All directions")
            Button { if moving { safetyAlert = true } else { showingSettings = true } } label: { roundIcon("slider.horizontal.3") }
                .accessibilityLabel("Navigation settings")
        }
        .foregroundStyle(.primary)
    }

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name).font(.title3).frame(width: 46, height: 46).background(.regularMaterial, in: Circle())
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.eta.map { "Arrive \(Fmt.time($0))" } ?? "—").font(.title2.weight(.bold).monospacedDigit())
                    HStack(spacing: 8) {
                        Text(Fmt.hm(engine.remainingTime)).font(.headline.monospacedDigit())
                        Text(NavigationEngine.distanceText(engine.remainingDistance)).font(.subheadline).foregroundStyle(.secondary)
                        if engine.trafficDelay > 120 {
                            Text("+\(Int(engine.trafficDelay / 60)) min traffic").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        }
                    }
                    Text("\(engine.destinationName) · \(engine.route?.source ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(spacing: 6) {
                    Button { dismiss() } label: { Text("Hide").font(.subheadline.weight(.semibold)) }
                        .buttonStyle(.bordered)
                    Button(role: .destructive) { engine.stop(); dismiss() } label: {
                        Text("End").font(.headline).padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent).tint(.red)
                }
            }
            if let h = heightText, engine.route?.isTruckRoute != true {
                Label(h, systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            if engine.notEnoughTime {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Not enough driving time to arrive", systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.red)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(engine.parkingOptions, id: \.self) { item in
                                Button { engine.start(to: item.placemark.coordinate, name: item.name ?? "Parking") } label: {
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

    private var stepsList: some View {
        NavigationStack {
            List(Array((engine.route?.steps ?? []).enumerated()), id: \.element.id) { i, step in
                HStack(spacing: 12) {
                    Image(systemName: step.symbol).frame(width: 28)
                        .foregroundStyle(i == engine.stepIndex + 1 ? Color.green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.instruction).font(.subheadline)
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

    // MARK: Speed

    private var speedoSize: CGFloat { s.navSpeedoSize == "s" ? 70 : s.navSpeedoSize == "m" ? 86 : 104 }

    /// Speedometer with the speed limit sign on its top corner (no caption).
    private var speedometer: some View {
        let kmh = max(0, (engine.location?.speed ?? 0) * 3.6)
        let miles = s.useMiles
        let size = speedoSize
        let over = kmh > effectiveLimitKmh + 2
        return VStack(spacing: 0) {
            Text("\(Int((miles ? kmh / 1.609344 : kmh).rounded()))")
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(over ? .red : .primary)
                .contentTransition(.numericText())
            Text(miles ? "mph" : "km/h").font(.system(size: size * 0.14)).foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .background(.regularMaterial, in: Circle())
        .overlay(Circle().stroke(over ? Color.red : .clear, lineWidth: 4))
        .overlay(alignment: s.navSpeedoSide == "left" ? .topTrailing : .topLeading) {
            if let text = limitSignText {
                Text(text)
                    .font(.system(size: size * (text.count > 2 ? 0.2 : 0.24), weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.black)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .background(Circle().fill(.white))
                    .overlay(Circle().stroke(.red, lineWidth: size * 0.065))
                    .shadow(radius: 2)
                    .offset(x: s.navSpeedoSide == "left" ? size * 0.18 : -size * 0.18, y: -size * 0.14)
                    .accessibilityLabel("Speed limit \(text)")
            }
        }
        .overlay(alignment: .bottom) {
            if limiterKmh > 0 && kmh > limiterKmh - 3 {
                Text("Limiter").font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.thinMaterial, in: Capsule()).offset(y: 6)
            }
        }
        .animation(.snappy, value: Int(kmh))
    }

    /// The limit that applies to you: the lower of the road's limit and your vehicle's (e.g. 60 mph for a lorry on a motorway).
    private var limitSignText: String? {
        guard let r = roadLimit else { return nil }
        let miles = s.useMiles
        let vehicleMax = SpeedLimits.defaultKmh(kind: currentVehicle?.kind ?? .tractor, weightT: currentVehicle?.weight ?? 0, region: s.region)
        if isHeavy && vehicleMax + 1 < r.roadKmh {
            return "\(Int((miles ? vehicleMax / 1.609344 : vehicleMax).rounded()))"
        }
        return r.signText
    }

    private var effectiveLimitKmh: Double {
        var l = AutoDriveDetector.shared.speedLimitKmh
        if let r = roadLimit { l = min(l, r.roadKmh) }
        return l
    }

    /// Road you're on: OpenStreetMap ref, else the route's.
    private var currentRoad: String? {
        if let ref = roadLimit?.roadRef, !ref.isEmpty { return ref.components(separatedBy: ";").first }
        let r = engine.currentRoad
        return r.isEmpty ? nil : r
    }

    private var currentVehicle: Vehicle? { vehicles.first { $0.id.uuidString == s.currentVehicleID } }
    private var currentTrailer: Vehicle? { vehicles.first { $0.id.uuidString == s.currentTrailerID } }

    private var isHeavy: Bool {
        guard let v = currentVehicle else { return true }
        return !(v.kind == .van && (v.weight == 0 || v.weight <= 3.5))
    }

    private var limiterKmh: Double {
        if let l = currentVehicle?.limiterKmh, l > 0 { return l }
        return isHeavy ? 90 : 0
    }

    private var heightText: String? {
        let h = [currentVehicle, currentTrailer].compactMap { $0?.height }.max() ?? 0
        return h > 0 ? "Your height: \(Fmt.length(h)). This route isn't checked for low bridges — follow the signs." : nil
    }

    /// The lorry's size and weight for the router (sensible UK artic defaults where not set).
    private var profile: TruckProfile {
        let unit = currentVehicle, trailer = currentTrailer
        var p = TruckProfile()
        p.isTruck = isHeavy
        p.heightM = [unit?.height ?? 0, trailer?.height ?? 0].max().flatMap { $0 > 0 ? $0 : nil } ?? 4.0
        p.widthM = [unit?.width ?? 0, trailer?.width ?? 0].max().flatMap { $0 > 0 ? $0 : nil } ?? 2.55
        let length = (unit?.length ?? 0) + (trailer?.length ?? 0)
        p.lengthM = length > 0 ? length : (trailer == nil ? 12 : 16.5)
        let weight = max(unit?.weight ?? 0, trailer?.weight ?? 0)
        p.weightT = weight > 0 ? weight : 44
        let axles = (unit?.axles ?? 0) + (trailer?.axles ?? 0)
        p.axles = axles > 0 ? axles : 5
        p.axleLoadT = min(11.5, p.weightT / Double(max(2, p.axles)) * 1.4)
        p.topSpeedKmh = limiterKmh > 0 ? limiterKmh : 112
        p.preferMotorways = s.navPreferMotorways
        p.avoidTolls = s.navAvoidTolls
        return p
    }

    // MARK: Actions

    private func begin() {
        view = ViewMode(rawValue: s.navViewMode) ?? .follow3D
        engine.driveLeft = { driveLeftNow() }
        engine.profile = profile
        engine.provider = s.navRouting
        engine.voiceOn = s.navVoiceOn
        engine.turnsOnly = s.navVoiceLevel == "turns"
        let lights = s.navShowTrafficLights, cameras = s.navCameraAlerts, heavy = isHeavy, online = s.onlineSpeedLimits
        let miles = s.useMiles
        let vehicleMax = SpeedLimits.defaultKmh(kind: currentVehicle?.kind ?? .tractor, weightT: currentVehicle?.weight ?? 0, region: s.region)
        let ctx = context
        engine.onUpdate = { loc in
            if online {
                limits.update(loc, heavyVehicle: heavy) { r in
                    roadLimit = r
                    let eng = NavigationEngine.shared
                    if let r {
                        eng.speedLimitText = heavy && vehicleMax + 1 < r.roadKmh
                            ? "\(Int((miles ? vehicleMax / 1.609344 : vehicleMax).rounded()))" : r.signText
                        let ref = r.roadRef.components(separatedBy: ";").first ?? ""
                        eng.roadRef = ref.isEmpty ? (r.roadName.isEmpty ? nil : r.roadName) : ref
                    } else {
                        eng.speedLimitText = nil
                    }
                }
            }
            hazards.update(loc, includeLights: lights)
            hazards.refreshNearby(loc, lights: lights)
            let active = ((try? ctx.fetch(FetchDescriptor<RoadReport>())) ?? []).filter { $0.expiresAt > .now }
            hazards.warnAhead(engine: NavigationEngine.shared, reports: active, cameras: cameras)
        }
        guard let target else { follow(engine.location, animated: true, force: true); return }
        if engine.isRunning, let d = engine.destination, let c = target.coordinate,
           NavigationEngine.metres(d, c) < 30 { return }
        if let c = target.coordinate {
            engine.start(to: c, name: target.name)
        } else {
            Task {
                let placemark = try? await CLGeocoder().geocodeAddressString(target.address).first
                if let c = placemark?.location?.coordinate { engine.start(to: c, name: target.name) } else { engine.status = "Couldn't find that address." }
            }
        }
    }

    private func report(_ kind: RoadReport.Kind) {
        guard let c = engine.location?.coordinate else { return }
        context.insert(RoadReport(kind: kind, coordinate: c))
        try? context.save()
        EventRecorder.log(.note, title: "Reported: \(kind.title)", coordinate: c, context: context, settings: s)
    }

    /// Moves the camera with you: behind the lorry in 3D (zooming out as speed rises), heading up, north up, or the whole route.
    private func follow(_ loc: CLLocation?, animated: Bool = false, force: Bool = false) {
        if position.positionedByUser && !force { return }
        if view == .overview, let route = engine.route {
            let rect = route.polyline.boundingMapRect
            withAnimation(.easeInOut(duration: 0.6)) { position = .rect(rect.insetBy(dx: -rect.size.width * 0.15, dy: -rect.size.height * 0.25)) }
            return
        }
        guard let loc else { return }
        let heading = engine.heading
        let kmh = max(0, loc.speed * 3.6)
        let centre = engine.displayCoordinate ?? loc.coordinate
        let zoom = max(0.3, s.navZoom)
        let pitch = max(0, min(75, s.navPitch))
        let camera: MapCamera
        switch view {
        case .follow3D:
            // Look ahead of the lorry; the steeper the tilt, the further ahead the centre.
            let ahead = NavigationEngine.offset(centre, metres: (60 + kmh * 2) * (0.5 + pitch / 60) * zoom, bearing: heading)
            camera = MapCamera(centerCoordinate: ahead, distance: (420 + kmh * 9) * zoom, heading: heading, pitch: pitch)
        case .headingUp:
            camera = MapCamera(centerCoordinate: centre, distance: (900 + kmh * 15) * zoom, heading: heading, pitch: 0)
        case .northUp, .overview:
            camera = MapCamera(centerCoordinate: centre, distance: (1100 + kmh * 15) * zoom, heading: 0, pitch: 0)
        }
        withAnimation(animated ? .easeInOut(duration: 0.5) : .linear(duration: 1.0)) { position = .camera(camera) }
    }

    private func driveLeftNow() -> TimeInterval {
        let settings = store.settings
        let snaps = ActivityController.recentSnapshots(context: context, settings: settings)
        let st = RulesEngine.status(snaps, now: .now, config: settings.ruleConfig)
        if let world = WorldRulesCache.refresh(snaps, now: .now, settings: settings) { return world.driveLeft }
        return st.currentShift == nil ? .infinity : st.drivingLeftToday
    }

    /// Arrow for a plain-text instruction (kept for Apple-style instructions).
    static func maneuverSymbol(_ text: String) -> String {
        let p = TruckRouter.parse(text)
        return NavStep.symbol(type: p.type, modifier: p.modifier)
    }
}

/// Lane arrows for the next junction: lanes you can use are bright, others dimmed.
struct LaneHelper: View {
    var lanes: [NavLane]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                Image(systemName: lane.symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(lane.valid ? .white : .white.opacity(0.3))
                    .frame(width: 38, height: 40)
                    .background(lane.valid ? Color.green.opacity(0.9) : Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(6)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Use lane \(lanes.enumerated().filter { $0.element.valid }.map { "\($0.offset + 1)" }.joined(separator: ", ")) of \(lanes.count)")
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
        .animation(.linear(duration: 0.15), value: rotation)
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
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, large ? 10 : 6).padding(.vertical, large ? 4 : 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(motorway ? Color.blue : (green ? Color(red: 0, green: 0.42, blue: 0.24) : .white)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 2))
            .shadow(radius: 1)
            .accessibilityLabel("Road \(t)")
    }
}

/// Settings → Navigation: routing, voice, what's shown and where.
struct NavSettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("Routing", selection: $store.settings.navRouting) {
                    Text("Lorry route (OpenStreetMap)").tag("valhalla")
                    Text("Apple Maps").tag("apple")
                }
                Toggle("Prefer motorways and A-roads", isOn: $store.settings.navPreferMotorways)
                Toggle("Avoid tolls", isOn: $store.settings.navAvoidTolls)
            } header: {
                Text("Route")
            } footer: {
                Text("Lorry routing (Valhalla, free OpenStreetMap server) uses your vehicle's height, width, length, weight and axles to avoid low bridges, weight limits and lorry bans, and gives lane guidance. It needs internet. If it can't be reached, Apple Maps is used (not checked for lorries). Live traffic delays come from Apple Maps.")
            }
            Section("Voice") {
                Toggle("Spoken directions", isOn: $store.settings.navVoiceOn)
                Picker("Say", selection: $store.settings.navVoiceLevel) {
                    Text("All prompts").tag("all")
                    Text("Turns only").tag("turns")
                }
                Toggle("Speed camera warnings", isOn: $store.settings.navCameraAlerts)
            }
            Section {
                Picker("Speedometer size", selection: $store.settings.navSpeedoSize) {
                    Text("Small").tag("s"); Text("Medium").tag("m"); Text("Large").tag("l")
                }
                Picker("Speedometer side", selection: $store.settings.navSpeedoSide) {
                    Text("Left").tag("left"); Text("Right").tag("right")
                }
                Picker("Directions banner", selection: $store.settings.navBannerSize) {
                    Text("Normal").tag("m"); Text("Large").tag("l")
                }
                Toggle("Road you're on", isOn: $store.settings.navShowRoad)
                Toggle("Lane guidance", isOn: $store.settings.navShowLanes)
                Toggle("Big turn arrow (right side)", isOn: $store.settings.navSideArrow)
                if store.settings.navSideArrow {
                    VStack(alignment: .leading) {
                        Text("Arrow see-through: \(Int((1 - store.settings.navSideArrowOpacity) * 100))%").font(.caption)
                        Slider(value: $store.settings.navSideArrowOpacity, in: 0.15...0.8)
                    }
                }
                Picker("View", selection: $store.settings.navViewMode) {
                    ForEach(NavigationModeView.ViewMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                VStack(alignment: .leading) {
                    Text("3D tilt: \(Int(store.settings.navPitch))°").font(.caption)
                    Slider(value: $store.settings.navPitch, in: 0...75, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("Zoom: \(store.settings.navZoom < 0.9 ? "close" : store.settings.navZoom > 1.2 ? "far" : "normal") (×\(String(format: "%.1f", store.settings.navZoom)))").font(.caption)
                    Slider(value: $store.settings.navZoom, in: 0.4...2.5, step: 0.1)
                }
                Picker("Map", selection: $store.settings.navMapStyle) {
                    Text("Standard").tag("standard"); Text("Satellite").tag("hybrid")
                }
            } header: {
                Text("Screen")
            }
            Section {
                Toggle("Road speed limits (OpenStreetMap)", isOn: $store.settings.onlineSpeedLimits)
                Toggle("Speed cameras on the map", isOn: $store.settings.navShowCameras)
                Toggle("Traffic lights on the map", isOn: $store.settings.navShowTrafficLights)
                Toggle("Parking suggestions", isOn: $store.settings.navShowParking)
                Toggle("Your road reports", isOn: $store.settings.navShowReports)
            } header: {
                Text("On the map")
            } footer: {
                Text("Speed cameras and traffic lights come from OpenStreetMap. Reports (accident, closure, police, low bridge…) are the ones you add with the ⚠︎ button; they're kept on your iPhone.")
            }
        }
        .navigationTitle("Navigation")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
