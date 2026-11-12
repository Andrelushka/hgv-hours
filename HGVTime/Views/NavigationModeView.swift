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
    @State private var userMovedAt = Date.distantPast
    @Environment(\.scenePhase) private var scenePhase
    @State private var limits = RoadSpeedLimit()
    @State private var roadLimit: RoadSpeedLimit.Result?
    /// Speed used for the zoom, eased so the map doesn't pump in and out with every speed change.
    @State private var zoomKmh: Double = 0
    /// Where you've driven this shift: the navigation trail and the in-cab recorded route.
    @State private var driven: [CLLocationCoordinate2D] = []
    @State private var recorded: [CLLocationCoordinate2D] = []
    @State private var shiftStart: Date?
    /// Hazards and reports to draw, refreshed now and then rather than on every frame.
    @State private var shownHazards: [RoadHazards.Point] = []
    @State private var shownReports: [RoadReport] = []
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
        // Each part reads the navigation engine in its own view (Isolated), so the 5-times-a-second
        // position updates only redraw the map — not the banner, buttons and panel.
        attachSheets(ZStack(alignment: .top) {
            Isolated { map }
            VStack(spacing: 8) {
                Isolated { instructionBanner }
                Isolated { if s.navShowLanes, let lanes = upcomingLanes { LaneHelper(lanes: lanes) } }
                HStack(alignment: .top) {
                    if s.navSpeedoSide == "left" { Isolated { speedColumn }; Spacer() } else { Isolated { buttonColumn }; Spacer() }
                    if s.navSpeedoSide == "left" { Isolated { buttonColumn } } else { Isolated { speedColumn } }
                }
                Spacer()
                Isolated { sideArrow }
                Isolated { bottomPanel }
            }
            .padding()
        })
        .onAppear {
            begin()
            refreshOverlays()
            follow(engine.location, animated: true, force: true)
        }
        .task {
            // Hazards, reports and the recorded route change slowly: refresh every 10 s.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                refreshOverlays()
            }
        }
    }

    @ViewBuilder
    private var sideArrow: some View {
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
    }

    /// Sheets and alerts (kept apart so they don't depend on the moving parts).
    private func attachSheets<C: View>(_ content: C) -> some View {
        content
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
    }

    /// Hazards and reports near you, and where you've driven this shift.
    private func refreshOverlays() {
        let settings = store.settings
        shownHazards = hazards.nearby.filter {
            $0.kind == .camera ? settings.navShowCameras : (settings.navShowTrafficLights && cameraDistance < 3000)
        }
        shownReports = settings.navShowReports ? reports.filter { $0.expiresAt > .now } : []
        shiftStart = ActivityController.currentShiftStart(context: context)
        refreshDriven()
        if let start = shiftStart, settings.navShowDriven {
            let since = start
            let points = (try? context.fetch(FetchDescriptor<TrackPoint>(predicate: #Predicate { $0.time >= since },
                                                                        sortBy: [SortDescriptor(\.time)]))) ?? []
            recorded = Self.thin(points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }, metres: 25)
        } else {
            recorded = []
        }
    }

    private func refreshDriven() {
        guard let start = shiftStart, store.settings.navShowDriven else { driven = []; return }
        driven = engine.trail(since: start)
    }

    /// Drops points closer than `metres` to the last kept one, so long routes stay light to draw.
    static func thin(_ coords: [CLLocationCoordinate2D], metres: Double) -> [CLLocationCoordinate2D] {
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(coords.count / 2)
        for c in coords {
            if let last = out.last, NavigationEngine.metres(last, c) < metres { continue }
            out.append(c)
        }
        return out
    }

    // MARK: Map

    private var map: some View {
        Map(position: $position) {
            // Where you've driven this shift (under the route).
            if recorded.count > 1 {
                MapPolyline(coordinates: recorded)
                    .stroke(Color.gray.opacity(0.7), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if driven.count > 1 {
                MapPolyline(coordinates: driven)
                    .stroke(Color.gray.opacity(0.7), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let c = engine.displayCoordinate ?? engine.location?.coordinate {
                Annotation("", coordinate: c, anchor: .center) {
                    // The camera turns with you in 3D / heading-up, so the cab points up; north-up shows the real heading.
                    TruckMarker(rotation: view == .northUp || view == .overview ? engine.displayHeading : 0,
                                trailerAngle: Self.angleDiff(engine.trailerHeading, engine.displayHeading),
                                tilt: view == .follow3D ? s.navPitch : 0)
                        .environment(store)
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
            ForEach(shownHazards) { p in
                Annotation("", coordinate: p.coordinate) {
                    Image(systemName: p.kind == .camera ? "camera.fill" : "light.beacon.max.fill")
                        .font(.system(size: p.kind == .camera ? 13 : 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(p.kind == .camera ? Color.orange : Color.red.opacity(0.85), in: Circle())
                }
            }
            if !shownReports.isEmpty {
                ForEach(shownReports) { r in
                    Annotation(r.kind.title, coordinate: r.coordinate) {
                        Image(systemName: r.kind.symbol).font(.caption.weight(.bold)).foregroundStyle(.white)
                            .padding(6).background(Color.red, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                }
            }
        }
        .mapStyle(s.navMapStyle == "hybrid"
                  ? .hybrid(elevation: view == .follow3D && s.navRealistic3D ? .realistic : .flat, pointsOfInterest: .including([.parking, .gasStation]), showsTraffic: true)
                  : .standard(elevation: view == .follow3D && s.navRealistic3D ? .realistic : .flat,
                              pointsOfInterest: .including([.parking, .gasStation, .restroom]), showsTraffic: true))
        .mapControls { MapCompass(); MapScaleView() }
        .ignoresSafeArea()
        .onMapCameraChange(frequency: .onEnd) { ctx in
            cameraHeading = ctx.camera.heading
            cameraDistance = ctx.camera.distance
        }
        // Follow the smoothed position (5 times a second) so the map glides with the lorry.
        .onChange(of: engine.displayCoordinate?.latitude) { _, _ in follow(engine.location) }
        .onChange(of: position.positionedByUser) { _, moved in if moved { userMovedAt = .now } }
        .onChange(of: engine.trailVersion) { _, _ in refreshDriven() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { follow(engine.location, animated: true, force: true) } }
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

    /// Arrival, time left and distance in big type; destination; Hide / End.
    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                stat("Arrive", engine.eta.map(Fmt.time) ?? "—", .primary)
                Divider().frame(height: 44)
                stat("Time left", Fmt.hm(engine.remainingTime), engine.trafficDelay > 120 ? .orange : .primary)
                Divider().frame(height: 44)
                stat("Distance", NavigationEngine.distanceText(engine.remainingDistance)
                    .replacingOccurrences(of: " miles", with: " mi").replacingOccurrences(of: " metres", with: " m"), .primary)
            }
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered").foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.destinationName).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(engine.route?.source ?? engine.status).lineLimit(1)
                        if engine.trafficDelay > 120 {
                            Text("+\(Int(engine.trafficDelay / 60)) min traffic").fontWeight(.semibold).foregroundStyle(.orange)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Text("Hide").font(.headline).padding(.horizontal, 6) }
                    .buttonStyle(.bordered).controlSize(.large)
                Button(role: .destructive) { engine.stop(); dismiss() } label: { Text("End").font(.headline).padding(.horizontal, 8) }
                    .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            }
            if let h = heightText, engine.route?.isTruckRoute != true {
                Label(h, systemImage: "exclamationmark.triangle.fill").font(.footnote.weight(.semibold)).foregroundStyle(.orange)
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
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(value).font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit()).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
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
        .overlay(alignment: limitAlignment) {
            // Speed limit: white circle with a red ring, on the corner of the speedometer you choose.
            let text = limitSignText ?? vehicleLimitText
            Text(text)
                .font(.system(size: size * (text.count > 2 ? 0.2 : 0.25), weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.black)
                .minimumScaleFactor(0.6)
                .frame(width: size * 0.52, height: size * 0.52)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(.red, lineWidth: size * 0.07))
                .opacity(limitSignText == nil ? 0.75 : 1)
                .shadow(radius: 2)
                .offset(x: s.navLimitCorner.hasSuffix("r") ? size * 0.2 : -size * 0.2,
                        y: s.navLimitCorner.hasPrefix("t") ? -size * 0.16 : size * 0.16)
                .accessibilityLabel("Speed limit \(text)")
        }
        .overlay(alignment: .bottom) {
            if limiterKmh > 0 && kmh > limiterKmh - 3 {
                Text("Limiter").font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.thinMaterial, in: Capsule()).offset(y: 6)
            }
        }
        .animation(.snappy, value: Int(kmh))
    }

    private var limitAlignment: Alignment {
        switch s.navLimitCorner {
        case "tl": .topLeading
        case "bl": .bottomLeading
        case "br": .bottomTrailing
        default: .topTrailing
        }
    }

    /// Your vehicle's own limit, shown (faded) when the road's limit isn't known.
    private var vehicleLimitText: String {
        let kmh = AutoDriveDetector.shared.speedLimitKmh
        return "\(Int((s.useMiles ? kmh / 1.609344 : kmh).rounded()))"
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
        // Your road reports, read from the database at most every 30 s (not on every GPS fix).
        final class ReportCache { var items: [RoadReport] = []; var at = Date.distantPast }
        let cache = ReportCache()
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
            if Date.now.timeIntervalSince(cache.at) > 30 {
                cache.items = ((try? ctx.fetch(FetchDescriptor<RoadReport>())) ?? []).filter { $0.expiresAt > .now }
                cache.at = .now
            }
            hazards.warnAhead(engine: NavigationEngine.shared, reports: cache.items, cameras: cameras)
        }
        if engine.displayHeading == 0 { engine.displayHeading = engine.heading; engine.trailerHeading = engine.heading }
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
        // You looked around the map: carry on following by itself after 6 seconds — no need to re-centre.
        if position.positionedByUser && !force && Date.now.timeIntervalSince(userMovedAt) < 6 { return }
        if view == .overview, let route = engine.route {
            let rect = route.polyline.boundingMapRect
            withAnimation(.easeInOut(duration: 0.6)) { position = .rect(rect.insetBy(dx: -rect.size.width * 0.15, dy: -rect.size.height * 0.25)) }
            return
        }
        guard let loc else { return }
        let heading = engine.displayHeading
        // Ease the speed used for zoom, and ignore small changes, so the map stays calm.
        let rawKmh = max(0, loc.speed * 3.6)
        let eased = zoomKmh + (rawKmh - zoomKmh) * 0.06
        if abs(eased - zoomKmh) > 0.3 || force { zoomKmh = force ? rawKmh : eased }
        let kmh = zoomKmh
        let centre = engine.displayCoordinate ?? loc.coordinate
        let zoom = max(0.3, s.navZoom)
        let pitch = max(0, min(75, s.navPitch))
        let camera: MapCamera
        switch view {
        case .follow3D:
            // The camera centre sits ahead of (or behind) the lorry so the pin appears where you set it on screen.
            let distance = (420 + kmh * 9) * zoom
            let ahead = NavigationEngine.offset(centre, metres: distance * (0.5 - s.navPinPosition) * (0.6 + pitch / 90), bearing: heading)
            camera = MapCamera(centerCoordinate: ahead, distance: distance, heading: heading, pitch: pitch)
        case .headingUp:
            let distance = (900 + kmh * 15) * zoom
            let ahead = NavigationEngine.offset(centre, metres: distance * (0.5 - s.navPinPosition) * 0.6, bearing: heading)
            camera = MapCamera(centerCoordinate: ahead, distance: distance, heading: heading, pitch: 0)
        case .northUp, .overview:
            camera = MapCamera(centerCoordinate: centre, distance: (1100 + kmh * 15) * zoom, heading: 0, pitch: 0)
        }
        withAnimation(animated ? .easeInOut(duration: 0.5) : .linear(duration: 0.22)) { position = .camera(camera) }
    }

    private func driveLeftNow() -> TimeInterval {
        let settings = store.settings
        let snaps = ActivityController.recentSnapshots(context: context, settings: settings)
        let st = RulesEngine.status(snaps, now: .now, config: settings.ruleConfig)
        if let world = WorldRulesCache.refresh(snaps, now: .now, settings: settings) { return world.driveLeft }
        return st.currentShift == nil ? .infinity : st.drivingLeftToday
    }

    /// Signed difference a − b in degrees (−180…180).
    static func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
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

/// Your position on the map: a lorry seen from above (artic with a trailer that swings on turns, rigid, van),
/// a navigation arrow or a dot — style, size, colour, 3D tilt and animation set in Settings → Navigation → Lorry pin.
struct TruckMarker: View {
    /// Optional: map pins are drawn outside the normal view tree, where the settings may not be passed down.
    /// Callers inside a Map add `.environment(store)`; without it the pin uses the default look instead of crashing.
    @Environment(SettingsStore.self) private var store: SettingsStore?
    /// Direction of the cab on screen (degrees).
    var rotation: Double
    /// Trailer angle relative to the cab (degrees, + = trailer swung clockwise).
    var trailerAngle: Double = 0
    /// Camera tilt, for the 3D look (degrees).
    var tilt: Double = 0

    var body: some View {
        let s = store?.settings ?? AppSettings()
        let scale: CGFloat = s.navPinSize == "s" ? 0.8 : s.navPinSize == "l" ? 1.35 : 1.05
        let tint = Self.color(s.navPinColor)
        Group {
            switch s.navPinStyle {
            case "arrow": arrow(tint)
            case "dot": dot(tint)
            case "van": body(tint, cab: 18, length: 26, trailer: 0)
            case "rigid": body(tint, cab: 18, length: 0, trailer: 0, rigidBox: 30)
            default: body(tint, cab: 17, length: 0, trailer: 38)
            }
        }
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation))
        .rotation3DEffect(.degrees(s.navPin3D ? min(55, tilt * 0.8) : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: s.navPin3D ? 3 : 1)
        .animation(s.navPinAnimate ? .linear(duration: 0.2) : nil, value: rotation)
        .animation(s.navPinAnimate ? .linear(duration: 0.2) : nil, value: trailerAngle)
        .accessibilityLabel("Your lorry")
    }

    static func color(_ name: String) -> Color {
        switch name {
        case "red": .red
        case "green": .green
        case "orange": .orange
        case "black": Color(white: 0.15)
        case "yellow": .yellow
        default: .blue
        }
    }

    /// Cab (with windscreen and mirrors), optional rigid box, optional articulated trailer.
    private func body(_ tint: Color, cab: CGFloat, length: CGFloat, trailer: CGFloat, rigidBox: CGFloat = 0) -> some View {
        VStack(spacing: 1) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4).fill(tint.gradient)
                    .frame(width: 20, height: cab + length)
                RoundedRectangle(cornerRadius: 2).fill(.black.opacity(0.55))
                    .frame(width: 15, height: 4).padding(.top, 2)
                HStack(spacing: 18) {
                    Capsule().fill(tint).frame(width: 3, height: 5)
                    Capsule().fill(tint).frame(width: 3, height: 5)
                }
                .padding(.top, 3)
            }
            if rigidBox > 0 {
                box(tint, height: rigidBox)
            }
            if trailer > 0 {
                box(tint, height: trailer)
                    .rotationEffect(.degrees((store?.settings.navPinAnimate ?? true) ? trailerAngle : 0), anchor: .top)
            }
        }
        .padding(3)
    }

    private func box(_ tint: Color, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2.5).fill(Color(white: 0.94))
                .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(tint, lineWidth: 2))
            HStack(spacing: 15) {
                VStack(spacing: 1.5) { wheel; wheel; wheel }
                VStack(spacing: 1.5) { wheel; wheel; wheel }
            }
            .padding(.bottom, 2)
        }
        .frame(width: 21, height: height)
    }

    private var wheel: some View { RoundedRectangle(cornerRadius: 1).fill(.black.opacity(0.75)).frame(width: 3, height: 4) }

    private func arrow(_ tint: Color) -> some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(tint.gradient)
            .overlay(Image(systemName: "location.north").font(.system(size: 34, weight: .bold)).foregroundStyle(.white))
    }

    private func dot(_ tint: Color) -> some View {
        ZStack {
            Image(systemName: "arrowtriangle.up.fill").font(.system(size: 12)).foregroundStyle(tint.opacity(0.7)).offset(y: -16)
            Circle().fill(.white).frame(width: 24, height: 24)
            Circle().fill(tint).frame(width: 18, height: 18)
        }
    }
}

/// Lorry pin set-up: style, size, colour, 3D and animation.
struct PinSettingsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                HStack {
                    Spacer()
                    TruckMarker(rotation: 20, trailerAngle: -18, tilt: 45)
                        .frame(height: 110)
                    Spacer()
                }
            }
            Section("Pin") {
                Picker("Style", selection: $store.settings.navPinStyle) {
                    Text("Artic (cab + trailer)").tag("artic")
                    Text("Rigid lorry").tag("rigid")
                    Text("Van").tag("van")
                    Text("Navigation arrow").tag("arrow")
                    Text("Dot").tag("dot")
                }
                Picker("Size", selection: $store.settings.navPinSize) {
                    Text("Small").tag("s"); Text("Medium").tag("m"); Text("Large").tag("l")
                }
                Picker("Colour", selection: $store.settings.navPinColor) {
                    ForEach(["blue", "red", "green", "orange", "yellow", "black"], id: \.self) { c in
                        Label(LocalizedStringKey(c.capitalized), systemImage: "circle.fill").foregroundStyle(TruckMarker.color(c)).tag(c)
                    }
                }
                Toggle("3D (tilts with the map)", isOn: $store.settings.navPin3D)
                Toggle("Animation (smooth turns, trailer swings)", isOn: $store.settings.navPinAnimate)
            }
            Section {
                VStack(alignment: .leading) {
                    Text("Position on screen: \(Int(store.settings.navPinPosition * 100))% from the bottom").font(.caption)
                    Slider(value: $store.settings.navPinPosition, in: 0.15...0.7)
                }
            } header: {
                Text("Where the pin sits")
            } footer: {
                Text("Lower shows more road ahead; higher keeps the pin clear of the bottom panel.")
            }
        }
        .navigationTitle("Lorry pin")
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
                Picker("Speed limit sign", selection: $store.settings.navLimitCorner) {
                    Text("Top right").tag("tr"); Text("Top left").tag("tl")
                    Text("Bottom right").tag("br"); Text("Bottom left").tag("bl")
                }
                NavigationLink { PinSettingsView() } label: { Label("Lorry pin", systemImage: "box.truck.fill") }
                Picker("Directions banner", selection: $store.settings.navBannerSize) {
                    Text("Normal").tag("m"); Text("Large").tag("l")
                }
                Toggle("Road you're on", isOn: $store.settings.navShowRoad)
                Toggle("Lane guidance", isOn: $store.settings.navShowLanes)
                Toggle("Show where I've driven this shift", isOn: $store.settings.navShowDriven)
                Toggle("3D buildings (slower map)", isOn: $store.settings.navRealistic3D)
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


/// Runs its content's body on its own, so whatever the content reads (e.g. the navigation engine)
/// only redraws this part of the screen.
struct Isolated<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { content() }
}
