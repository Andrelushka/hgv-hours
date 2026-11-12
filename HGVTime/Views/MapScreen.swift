import SwiftUI
import SwiftData
import MapKit

/// Map of a day: the route driven, every event with where it happened, job stops, and navigation to the next stop.
/// Holds the day; the map below reloads only that day's route and events when the day changes.
struct MapScreen: View {
    typealias NavTarget = MapDayView.NavTarget
    @State private var day: Date
    var isLive: Bool

    init(day: Date = .now, isLive: Bool = false) {
        _day = State(initialValue: Calendar.hgv.startOfDay(for: day))
        self.isLive = isLive
    }

    var body: some View {
        MapDayView(day: $day, isLive: isLive).id(day)
    }
}

struct MapDayView: View {
    @Environment(SettingsStore.self) private var store
    // Only this day's route and events are loaded (not every point ever recorded).
    @Query private var track: [TrackPoint]
    @Query private var events: [EventLog]
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    @Binding var day: Date
    @State private var position: MapCameraPosition = .automatic
    @State private var showingFilters = false
    @State private var selected: EventLog?
    @State private var showingList = false
    @State private var navigating: NavTarget?
    @State private var navigatingInApp: NavTarget?
    @State private var geocoded: [UUID: CLLocationCoordinate2D] = [:]
    @State private var plannedRoutes: [MKRoute] = []
    @State private var live = LiveLocation()
    @State private var cameraHeading: CLLocationDirection = 0

    struct NavTarget: Identifiable, Hashable {
        static func == (a: NavTarget, b: NavTarget) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
        let id = UUID()
        var name: String
        var coordinate: CLLocationCoordinate2D?
        var address: String
    }

    /// The main map (from Today): shows activities and events but not problems — those are on the driver log's day map.
    var isLive = false
    @State private var nav = NavigationEngine.shared
    @State private var resumingNav = false

    init(day: Binding<Date>, isLive: Bool = false) {
        let start = Calendar.hgv.startOfDay(for: day.wrappedValue)
        let end = start.addingTimeInterval(86_400)
        _day = day
        self.isLive = isLive
        _track = Query(filter: #Predicate<TrackPoint> { $0.time >= start && $0.time < end }, sort: \TrackPoint.time)
        // The main map shows no events at all (they're on the driver log's day map) — less to draw, no lag.
        let none = isLive
        _events = Query(filter: #Predicate<EventLog> { !none && $0.time >= start && $0.time < end }, sort: \EventLog.time)
    }

    var body: some View {
        let cal = Calendar.hgv
        let end = day.addingTimeInterval(86_400)
        let route = track.filter { $0.time >= day && $0.time < end }
        let dayEvents = events.filter { $0.time >= day && $0.time < end && $0.hasLocation }
            .filter { !store.settings.mapProblemsOnly || $0.kind.isProblem }
            .filter { !store.settings.mapHiddenEvents.contains($0.kind.rawValue) }
            .filter { !isLive || !$0.kind.isProblem }
        let plan = plans.first { cal.isDate($0.plannedStart, inSameDayAs: day) }
        let planStops: [(stop: PlanStop, index: Int, coordinate: CLLocationCoordinate2D)] = (plan?.stops ?? []).enumerated().compactMap { i, st in
            if let lat = st.latitude, let lon = st.longitude { return (st, i, CLLocationCoordinate2D(latitude: lat, longitude: lon)) }
            if let c = geocoded[st.id] { return (st, i, c) }
            return nil
        }

        Map(position: $position, selection: .constant(nil as Int?)) {
            if let loc = live.location {
                Annotation("", coordinate: loc.coordinate, anchor: .center) {
                    TruckMarker(rotation: live.heading - cameraHeading)
                }
            } else {
                UserAnnotation()
            }
            if store.settings.mapShowRoute && route.count > 1 {
                MapPolyline(coordinates: route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                    .stroke(.blue.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if store.settings.mapShowPlanned {
                ForEach(Array(plannedRoutes.enumerated()), id: \.offset) { _, r in
                    MapPolyline(r.polyline).stroke(.indigo.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 6]))
                }
            }
            if store.settings.mapShowStops, let plan, let lat = plan.startLatitude, let lon = plan.startLongitude {
                Annotation("Start: \(plan.startLocation.isEmpty ? plan.startPostcode : plan.startLocation)",
                           coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                    Image(systemName: "flag.fill").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Color.green, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            ForEach(store.settings.mapShowStops ? planStops : [], id: \.stop.id) { item in
                Annotation("\(item.index + 1). \(item.stop.displayName)", coordinate: item.coordinate) {
                    ZStack {
                        Circle().fill(item.stop.departedAt != nil ? Color.gray : item.stop.kind.color).frame(width: 30, height: 30)
                        Text("\(item.index + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                    }
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            ForEach(dayEvents) { e in
                Annotation(e.title, coordinate: CLLocationCoordinate2D(latitude: e.latitude, longitude: e.longitude)) {
                    Button { selected = e } label: { EventPin(event: e) }
                }
            }
        }
        // Only when the camera stops moving: updating on every frame re-drew the whole map and made it stutter.
        .onMapCameraChange(frequency: .onEnd) { ctx in cameraHeading = ctx.camera.heading }
        .onAppear { live.start() }
        .onDisappear { live.stop() }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            bottomPanel(route: route, events: dayEvents, plan: plan)
        }
        .navigationTitle(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingFilters = true } label: {
                    Image(systemName: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Map filters")
            }
        }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                MapFilterView(isLive: isLive, counts: Dictionary(grouping: events.filter(\.hasLocation), by: \.kind).mapValues(\.count))
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selected) { e in
            EventDetailSheet(event: e).presentationDetents([.fraction(0.3), .medium])
        }
        .sheet(isPresented: $showingList) {
            NavigationStack { EventLogView(day: day) }
        }
        .confirmationDialog(navigating.map { "Navigate to \($0.name)" } ?? "", isPresented: Binding(get: { navigating != nil }, set: { if !$0 { navigating = nil } }),
                            titleVisibility: .visible, presenting: navigating) { target in
            Button("Apple Maps") { openApple(target) }
            Button("Google Maps") { openURL(googleURL(target)) }
            Button("Waze") { openURL(wazeURL(target)) }
        } message: { _ in
            Text(heightWarning)
        }
        .onChange(of: day) { _, _ in position = .automatic; plannedRoutes = [] }
        .task(id: day) { await preparePlan(plan) }
        .fullScreenCover(item: $navigatingInApp) { NavigationModeView(target: $0) }
        .fullScreenCover(isPresented: $resumingNav) { NavigationModeView(target: nil) }
        .safeAreaInset(edge: .top) {
            if nav.isRunning {
                Button { resumingNav = true } label: {
                    HStack {
                        Image(systemName: nav.nextStep?.symbol ?? "location.north.line.fill").font(.title3.weight(.bold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Navigating to \(nav.destinationName)").font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(nav.distanceToNextManeuver.map { "\(NavigationEngine.distanceText($0)) · \(nav.nextInstruction)" } ?? nav.status)
                                .font(.caption).lineLimit(1)
                        }
                        Spacer()
                        Text("Open").font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filtersActive: Bool {
        let st = store.settings
        return !st.mapShowRoute || !st.mapShowPlanned || !st.mapShowStops || (!isLive && (st.mapProblemsOnly || !st.mapHiddenEvents.isEmpty))
    }

    // MARK: Panel

    private func bottomPanel(route: [TrackPoint], events: [EventLog], plan: WorkPlan?) -> some View {
        let km = zip(route, route.dropFirst()).reduce(0.0) { sum, pair in
            sum + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)) / 1000
        }
        let problems = events.filter { $0.kind.isProblem }.count
        let next = plan?.stops.first { $0.departedAt == nil }
        let plannedKm = plannedRoutes.reduce(0) { $0 + $1.distance } / 1000
        let plannedTime = plannedRoutes.reduce(0) { $0 + $1.expectedTravelTime }
        return VStack(spacing: 8) {
            HStack {
                Button { day = Calendar.hgv.date(byAdding: .day, value: -1, to: day) ?? day } label: { Image(systemName: "chevron.left") }
                Spacer()
                VStack(spacing: 1) {
                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.subheadline.weight(.semibold))
                    Text(isLive ? "\(Fmt.distance(km, miles: store.settings.useMiles)) route"
                         : "\(Fmt.distance(km, miles: store.settings.useMiles)) route · \(events.count) event\(events.count == 1 ? "" : "s")\(problems > 0 ? " · \(problems) problem\(problems == 1 ? "" : "s")" : "")")
                        .font(.caption).foregroundStyle(problems > 0 ? .red : .secondary)
                }
                Spacer()
                Button { day = Calendar.hgv.date(byAdding: .day, value: 1, to: day) ?? day } label: { Image(systemName: "chevron.right") }
                    .disabled(Calendar.hgv.isDateInToday(day))
            }
            HStack(spacing: 8) {
                if !isLive { Button { showingList = true } label: { Label("Event log", systemImage: "list.bullet") } }
                if let next {
                    let target = NavTarget(name: next.displayName,
                                           coordinate: next.latitude.map { CLLocationCoordinate2D(latitude: $0, longitude: next.longitude ?? 0) } ?? geocoded[next.id],
                                           address: next.fullAddress)
                    Button { navigatingInApp = target } label: {
                        Label("Navigate", systemImage: "location.north.line.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    Button { navigating = target } label: { Label("Other app", systemImage: "arrow.up.forward.app") }
                }
            }
            .buttonStyle(.bordered)
            .font(.caption.weight(.semibold))
            if plannedKm > 0 {
                Text("Planned: \(plan?.stops.count ?? 0) stops · \(Fmt.distance(plannedKm, miles: store.settings.useMiles)) · about \(Fmt.hm(plannedTime)) driving")
                    .font(.caption).foregroundStyle(.indigo)
            }
            if route.isEmpty && events.isEmpty && plannedKm == 0 {
                Text("Nothing with a location on this day. Turn on In cab mode to record your route; events are pinned where they happen.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    /// Looks up stops without a map location, saves it to the plan, and draws the planned route between stops.
    private func preparePlan(_ plan: WorkPlan?) async {
        guard let plan else { return }
        var stops = plan.stops
        var changed = false
        for i in stops.indices where stops[i].latitude == nil && !stops[i].fullAddress.isEmpty {
            if let c = try? await CLGeocoder().geocodeAddressString(stops[i].fullAddress).first?.location?.coordinate {
                geocoded[stops[i].id] = c
                stops[i].latitude = c.latitude
                stops[i].longitude = c.longitude
                changed = true
            }
        }
        if changed { plan.stops = stops }
        // Start location / depot: geocode once from the postcode or address.
        if plan.startLatitude == nil, !plan.startLocation.isEmpty || !plan.startPostcode.isEmpty {
            let text = [plan.startLocation, plan.startPostcode].filter { !$0.isEmpty }.joined(separator: ", ")
            if let c = try? await CLGeocoder().geocodeAddressString(text).first?.location?.coordinate {
                plan.startLatitude = c.latitude
                plan.startLongitude = c.longitude
            }
        }
        var coords = stops.compactMap { s in s.latitude.map { CLLocationCoordinate2D(latitude: $0, longitude: s.longitude ?? 0) } }
        if let lat = plan.startLatitude, let lon = plan.startLongitude {
            coords.insert(CLLocationCoordinate2D(latitude: lat, longitude: lon), at: 0)
        }
        guard coords.count >= 2 else { return }
        var routes: [MKRoute] = []
        for (a, b) in zip(coords, coords.dropFirst()) {
            let r = MKDirections.Request()
            r.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
            r.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
            r.transportType = .automobile
            if let route = try? await MKDirections(request: r).calculate().routes.first { routes.append(route) }
        }
        plannedRoutes = routes
    }

    // MARK: Navigation

    private var heightWarning: String {
        let ids = [store.settings.currentVehicleID, store.settings.currentTrailerID]
        let h = vehicles.filter { ids.contains($0.id.uuidString) }.map(\.height).max() ?? 0
        let height = h > 0 ? "Your vehicle is \(Fmt.length(h, feet: true)) high. " : ""
        return "\(height)These apps don't route by lorry height or weight — follow the road signs and use a truck sat-nav for low bridges and restrictions."
    }

    private func openApple(_ t: NavTarget) {
        if let c = t.coordinate {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
            item.name = t.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        } else {
            var comps = URLComponents(string: "https://maps.apple.com/")!
            comps.queryItems = [URLQueryItem(name: "daddr", value: t.address), URLQueryItem(name: "dirflg", value: "d")]
            if let url = comps.url { openURL(url) }
        }
    }

    private func googleURL(_ t: NavTarget) -> URL {
        var comps = URLComponents(string: "https://www.google.com/maps/dir/")!
        let dest = t.coordinate.map { "\($0.latitude),\($0.longitude)" } ?? t.address
        comps.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "destination", value: dest),
                            URLQueryItem(name: "travelmode", value: "driving")]
        return comps.url!
    }

    private func wazeURL(_ t: NavTarget) -> URL {
        var comps = URLComponents(string: "https://waze.com/ul")!
        if let c = t.coordinate {
            comps.queryItems = [URLQueryItem(name: "ll", value: "\(c.latitude),\(c.longitude)"), URLQueryItem(name: "navigate", value: "yes")]
        } else {
            comps.queryItems = [URLQueryItem(name: "q", value: t.address), URLQueryItem(name: "navigate", value: "yes")]
        }
        return comps.url!
    }

    private func openURL(_ url: URL) { UIApplication.shared.open(url) }
}

/// A coloured pin for an event.
struct EventPin: View {
    var event: EventLog
    var body: some View {
        Image(systemName: event.activitySubtype?.symbol ?? (event.kind == .activity ? (event.activityKind?.symbol ?? event.kind.symbol) : event.kind.symbol))
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(6)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(radius: 2)
    }

    var color: Color {
        switch event.kind {
        case .overspeed, .infringement, .cardOut, .harshBraking: .red
        case .cardIn, .shiftStart: .green
        case .shiftEnd: .teal
        case .arrived, .departed: .indigo
        case .fuel: .orange
        case .activity:
            switch event.activityKind {
            case .drive: .blue
            case .otherWork: .orange
            case .availability: .purple
            case .rest: .green
            case nil: .blue
            }
        case .note: .gray
        case .correction: .gray
        }
    }
}

struct EventDetailSheet: View {
    @Environment(SettingsStore.self) private var store
    var event: EventLog
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                EventPin(event: event)
                Text(event.title).font(.headline)
                Spacer()
                Text(Fmt.dayTime(event.time)).font(.subheadline).foregroundStyle(.secondary)
            }
            if !event.detail.isEmpty { Text(event.detail).font(.subheadline) }
            if event.speedKmh > 0 {
                Text("Speed: \(Int(event.speedKmh.rounded())) km/h (\(Int((event.speedKmh / 1.609).rounded())) mph)").font(.caption)
            }
            if event.duration > 0 { Text("Lasted \(Int(event.duration)) s").font(.caption) }
            if event.hasLocation {
                Text(String(format: "%.5f, %.5f", event.latitude, event.longitude)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}


/// Map filters: what to show on the map (remembered).
struct MapFilterView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var isLive: Bool
    /// Events of each type on this day.
    var counts: [EventKind: Int]

    var body: some View {
        @Bindable var store = store
        Form {
            Section("On the map") {
                Toggle(isOn: $store.settings.mapShowRoute) { Label("Route driven", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                Toggle(isOn: $store.settings.mapShowPlanned) { Label("Planned route", systemImage: "arrow.triangle.turn.up.right.diamond") }
                Toggle(isOn: $store.settings.mapShowStops) { Label("Job start and stops", systemImage: "mappin.and.ellipse") }
            }
            if !isLive {
                Section {
                    Toggle(isOn: $store.settings.mapProblemsOnly) { Label("Problems only", systemImage: "exclamationmark.triangle.fill") }
                    ForEach(EventKind.allCases) { kind in
                        Toggle(isOn: Binding(
                            get: { !store.settings.mapHiddenEvents.contains(kind.rawValue) },
                            set: { on in
                                store.settings.mapHiddenEvents.removeAll { $0 == kind.rawValue }
                                if !on { store.settings.mapHiddenEvents.append(kind.rawValue) }
                            })) {
                            HStack {
                                Label(LocalizedStringKey(kind.title), systemImage: kind.symbol)
                                    .foregroundStyle(kind.isProblem ? .red : .primary)
                                Spacer()
                                if let n = counts[kind], n > 0 {
                                    Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(store.settings.mapProblemsOnly && !kind.isProblem)
                    }
                } header: {
                    HStack {
                        Text("Events")
                        Spacer()
                        Button("All") { store.settings.mapHiddenEvents = []; store.settings.mapProblemsOnly = false }
                            .font(.caption.weight(.semibold)).textCase(nil)
                        Button("None") { store.settings.mapHiddenEvents = EventKind.allCases.map(\.rawValue) }
                            .font(.caption.weight(.semibold)).textCase(nil)
                    }
                }
            } else {
                Section {
                    Text("Events are shown on the driver log's day map.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Map filters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
