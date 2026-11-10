import SwiftUI
import SwiftData
import MapKit

/// Today's job with Arrived / Departed buttons for each stop.
struct TodayJobCard: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Bindable var plan: WorkPlan
    var onEdit: () -> Void
    @State private var busy: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onEdit) { PlanCard(plan: plan, title: "Today's job", showChecks: false) }
                .buttonStyle(.plain)
            ForEach(plan.stops) { stop in
                HStack(spacing: 8) {
                    Image(systemName: stop.kind.symbol).foregroundStyle(stop.kind == .collection ? .orange : .blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stop.place.isEmpty ? stop.kind.title : stop.place).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(statusText(stop)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if busy == stop.id {
                        ProgressView()
                    } else if stop.arrivedAt == nil {
                        Button("Arrived") { mark(stop.id, arrived: true) }.buttonStyle(.borderedProminent).tint(.green)
                    } else if stop.departedAt == nil {
                        Button("Departed") { mark(stop.id, arrived: false) }.buttonStyle(.borderedProminent).tint(.blue)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                .font(.caption)
            }
            HStack {
                Button { addUnplannedStop() } label: { Label("Arrived somewhere else", systemImage: "mappin.and.ellipse") }
                Spacer()
                NavigationLink { DebriefView(day: plan.plannedStart) } label: { Label("Debrief", systemImage: "tablecells") }
            }
            .buttonStyle(.bordered)
            .font(.caption.weight(.semibold))
        }
    }

    private func statusText(_ stop: PlanStop) -> String {
        var parts: [String] = []
        if !stop.time.isEmpty { parts.append("Booked \(stop.time)") }
        if let a = stop.arrivedAt { parts.append("Arrived \(Fmt.time(a))") }
        if let d = stop.departedAt {
            parts.append("Left \(Fmt.time(d))")
            if let a = stop.arrivedAt { parts.append("on site \(Fmt.hm(d.timeIntervalSince(a)))") }
        }
        return parts.isEmpty ? "Not arrived yet" : parts.joined(separator: " · ")
    }

    private func mark(_ id: UUID, arrived: Bool) {
        busy = id
        let now = Date.now
        Task {
            let location = await LocationOnce.shared.current()
            var stops = plan.stops
            if let i = stops.firstIndex(where: { $0.id == id }) {
                if arrived {
                    stops[i].arrivedAt = now
                    ReminderService.shared.fire(.arrived, context: context)
                } else {
                    stops[i].departedAt = now
                }
                if let location, stops[i].latitude == nil {
                    stops[i].latitude = location.coordinate.latitude
                    stops[i].longitude = location.coordinate.longitude
                }
                plan.stops = stops
                try? context.save()
            }
            busy = nil
        }
    }

    private func addUnplannedStop() {
        let now = Date.now
        var stop = PlanStop(kind: .other)
        stop.arrivedAt = now
        stop.place = "Locating…"
        plan.stops.append(stop)
        try? context.save()
        ReminderService.shared.fire(.arrived, context: context)
        let id = stop.id
        Task {
            guard let location = await LocationOnce.shared.current() else {
                updateStop(id) { $0.place = "Unplanned stop" }
                return
            }
            let name = await LocationOnce.shared.placeName(for: location)
            updateStop(id) {
                $0.place = name
                $0.latitude = location.coordinate.latitude
                $0.longitude = location.coordinate.longitude
            }
        }
    }

    private func updateStop(_ id: UUID, _ change: (inout PlanStop) -> Void) {
        var stops = plan.stops
        if let i = stops.firstIndex(where: { $0.id == id }) {
            change(&stops[i])
            plan.stops = stops
            try? context.save()
        }
    }
}

/// End-of-day debrief: the job, every stop with times, activity totals, mileage, resources, events and pay.
struct DebriefView: View {
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \DayRecord.day) private var records: [DayRecord]
    @Query(sort: \ResourceLog.date) private var resources: [ResourceLog]
    @Query(sort: \CardEvent.time) private var cardEvents: [CardEvent]
    @Query(sort: \SpeedEvent.start) private var speedEvents: [SpeedEvent]
    var day: Date

    var body: some View {
        let d = DebriefData.make(day: day, entries: entries, plans: plans, vehicles: vehicles, records: records,
                                 resources: resources, cardEvents: cardEvents, speedEvents: speedEvents, settings: store.settings)
        List {
            Section("Job") {
                row("Company", d.company)
                row("Vehicle", d.vehicle)
                row("Trailer", d.trailer)
                row("Shift", d.shift)
                row("Driver card", d.card)
            }
            Section("Stops") {
                if d.stops.isEmpty {
                    Text("No stops recorded. Add stops to the day's plan and tap Arrived / Departed.").foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                ForEach(DebriefData.stopHeader, id: \.self) { Text($0).font(.caption.weight(.bold)) }
                            }
                            Divider()
                            ForEach(d.stops.indices, id: \.self) { i in
                                GridRow {
                                    ForEach(d.stops[i].indices, id: \.self) { c in
                                        Text(d.stops[i][c]).font(.caption.monospacedDigit()).lineLimit(2)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                ForEach(d.mapPoints.indices, id: \.self) { i in
                    let p = d.mapPoints[i]
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: p.coordinate))
                        item.name = p.name
                        item.openInMaps()
                    } label: { Label("Show \(p.name) on map", systemImage: "map") }
                    .font(.caption)
                }
            }
            Section("Activities") {
                ForEach(d.totals, id: \.0) { row($0.0, $0.1) }
            }
            Section("Mileage & resources") {
                ForEach(d.mileage, id: \.0) { row($0.0, $0.1) }
                ForEach(d.resources, id: \.self) { Text($0).font(.subheadline) }
            }
            if !d.events.isEmpty {
                Section("Events") {
                    ForEach(d.events, id: \.self) { Text($0).font(.subheadline) }
                }
            }
            Section("Pay") {
                row("Estimated gross", d.pay)
            }
        }
        .navigationTitle("Debrief \(Fmt.day(day))")
        .toolbar {
            ShareLink(item: d.text, subject: Text("Debrief \(Fmt.day(day))")) { Image(systemName: "square.and.arrow.up") }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value.isEmpty ? "—" : value)
    }
}

/// Everything shown in a debrief, also as plain text for sharing.
struct DebriefData {
    static let stopHeader = ["#", "Type", "Place", "Booked", "Arrived", "Left", "On site", "Ref", "Pallets"]

    var company = "", vehicle = "", trailer = "", shift = "", card = "", pay = ""
    var stops: [[String]] = []
    var mapPoints: [(name: String, coordinate: CLLocationCoordinate2D)] = []
    var totals: [(String, String)] = []
    var mileage: [(String, String)] = []
    var resources: [String] = []
    var events: [String] = []
    var text = ""

    static func make(day: Date, entries: [ActivityEntry], plans: [WorkPlan], vehicles: [Vehicle], records: [DayRecord],
                     resources: [ResourceLog], cardEvents: [CardEvent], speedEvents: [SpeedEvent], settings: AppSettings) -> DebriefData {
        let cal = Calendar.hgv
        let start = cal.startOfDay(for: day), end = start.addingTimeInterval(86_400)
        var d = DebriefData()
        let plan = plans.first { cal.isDate($0.plannedStart, inSameDayAs: day) }
        let name: (String) -> String = { id in vehicles.first { $0.id.uuidString == id }?.displayName ?? "" }
        d.company = plan?.company ?? ""
        d.vehicle = name(plan?.vehicleID ?? records.first { cal.isDate($0.day, inSameDayAs: day) }?.vehicleID ?? "")
        d.trailer = name(plan?.trailerID ?? "")

        let dayEntries = entries.filter { ($0.end ?? .now) > start && $0.start < end }
        let analysis = RulesEngine.analyze(entries.map(\.snapshot), now: .now, config: settings.ruleConfig)
        let shifts = analysis.shifts.filter { $0.period.start >= start && $0.period.start < end }
        if let first = shifts.first, let last = shifts.last {
            d.shift = "\(Fmt.time(first.period.start))–\(last.period.isOpen ? "now" : Fmt.time(last.period.end))"
        }
        let cards = cardEvents.filter { $0.time >= start && $0.time < end }
        d.card = cards.map { "\($0.inserted ? "In" : "Out") \(Fmt.time($0.time))" }.joined(separator: " · ")

        for (i, s) in (plan?.stops ?? []).enumerated() {
            let onSite = (s.arrivedAt != nil && s.departedAt != nil) ? Fmt.hm(s.departedAt!.timeIntervalSince(s.arrivedAt!)) : ""
            d.stops.append(["\(i + 1)", s.kind.title, s.place, s.time, s.arrivedAt.map(Fmt.time) ?? "", s.departedAt.map(Fmt.time) ?? "",
                            onSite, s.reference, s.pallets])
            if let lat = s.latitude, let lon = s.longitude {
                d.mapPoints.append((s.place.isEmpty ? "Stop \(i + 1)" : s.place, CLLocationCoordinate2D(latitude: lat, longitude: lon)))
            }
        }

        let t = DayTotals.compute(dayEntries, day: day)
        d.totals = [("Driving", Fmt.hm(t.driving)), ("Other work", Fmt.hm(t.otherWork)), ("POA", Fmt.hm(t.availability)),
                    ("Breaks", Fmt.hm(t.breaks)), ("Working time", Fmt.hm(t.working)),
                    ("Infringements", "\(shifts.flatMap(\.issues).count)")]

        let miles = settings.useMiles
        if let r = records.first(where: { cal.isDate($0.day, inSameDayAs: day) }) {
            d.mileage = [("Start odometer", Fmt.odometer(r.startOdometerKm, miles: miles)),
                         ("End odometer", Fmt.odometer(r.endOdometerKm, miles: miles)),
                         ("Distance", Fmt.distance(r.distanceKm, miles: miles))]
            if r.gpsKm > 0 { d.mileage.append(("GPS distance", Fmt.distance(r.gpsKm, miles: miles))) }
        }
        d.resources = resources.filter { $0.date >= start && $0.date < end }.map {
            "\($0.kind.title): \(String(format: "%g", $0.quantity)) \($0.kind.unit)\($0.location.isEmpty ? "" : " at \($0.location)")"
        }
        d.events = speedEvents.filter { $0.start >= start && $0.start < end }.map {
            "Overspeed \(Fmt.time($0.start)): \(Int($0.maxKmh)) km/h for \(Int($0.duration)) s\($0.isInfringement ? " (infringement)" : "")"
        }
        d.pay = Fmt.money(PayCalculator.calculate(shifts: shifts, nightOuts: 0, settings: settings.pay, salaryDays: 1).total,
                          symbol: settings.pay.currencySymbol)

        // Plain text for sharing.
        var out = "Debrief \(Fmt.day(day))\n"
        out += [("Driver", settings.driverName), ("Company", d.company), ("Vehicle", d.vehicle), ("Trailer", d.trailer),
                ("Shift", d.shift), ("Card", d.card)].filter { !$0.1.isEmpty }.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        out += "\n\nStops\n" + stopHeader.joined(separator: ", ") + "\n"
        out += d.stops.map { $0.map { $0.contains(",") ? "\"\($0)\"" : $0 }.joined(separator: ", ") }.joined(separator: "\n")
        out += "\n\n" + (d.totals + d.mileage).map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        if !d.resources.isEmpty { out += "\n\n" + d.resources.joined(separator: "\n") }
        if !d.events.isEmpty { out += "\n\n" + d.events.joined(separator: "\n") }
        out += "\n\nEstimated gross: \(d.pay)\n"
        d.text = out
        return d
    }
}
