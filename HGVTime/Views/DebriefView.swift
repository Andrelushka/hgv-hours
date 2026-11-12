import SwiftUI
import SwiftData
import MapKit

/// Today's job with Arrived / Departed buttons for each stop.
struct TodayJobCard: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Bindable var plan: WorkPlan
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    var onEdit: () -> Void
    @State private var busy: UUID?
    @State private var reason = ""
    @State private var pendingOutcome: (id: UUID, outcome: PlanStop.Outcome)?
    @State private var editingStop: PlanStop?
    @State private var deletingStop: PlanStop?
    @State private var pickupCheck: VehicleCheck?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onEdit) { PlanCard(plan: plan, title: "Today's job", showChecks: false, showStops: false) }
                .buttonStyle(.plain)
                .opacity(plan.cancelled ? 0.5 : 1)
            if plan.cancelled {
                HStack {
                    Label("Cancelled\(plan.cancelledAt.map { " at \(Fmt.time($0))" } ?? "")\(plan.cancelReason.isEmpty ? "" : " — \(plan.cancelReason)")",
                          systemImage: "xmark.octagon.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.red)
                    Spacer()
                    Button("Restore") { setCancelled(false) }.buttonStyle(.bordered).font(.caption.weight(.semibold))
                }
            } else {
                jobStops
            }
        }
        .sheet(item: $pickupCheck) { c in NavigationStack { VehicleCheckView(check: c) } }
        .sheet(item: $editingStop) { stop in
            StopEditor(stop: stop, isNew: false, onSave: { saved in
                updateStop(saved.id) { $0 = saved }
            }, onDelete: {
                removeStop(stop.id)
            })
        }
        .confirmationDialog(deletingStop.map { "Delete \($0.displayName)?" } ?? "",
                            isPresented: Binding(get: { deletingStop != nil }, set: { if !$0 { deletingStop = nil } }),
                            titleVisibility: .visible) {
            Button("Delete stop", role: .destructive) { if let s = deletingStop { removeStop(s.id) } }
        } message: {
            Text("To keep it in your records instead, mark it cancelled, failed or rejected.")
        }
        .alert(pendingOutcome.map { "Mark stop as \($0.outcome.title.lowercased())?" } ?? "",
               isPresented: Binding(get: { pendingOutcome != nil }, set: { if !$0 { pendingOutcome = nil } })) {
            TextField("Reason (optional)", text: $reason)
            Button(pendingOutcome?.outcome.title ?? "OK", role: .destructive) {
                if let p = pendingOutcome { setOutcome(p.id, p.outcome) }
            }
            Button("Back", role: .cancel) { reason = "" }
        } message: {
            Text(pendingOutcome?.outcome.detail ?? "")
        }
    }

    private func setCancelled(_ on: Bool) {
        plan.cancelled = on
        plan.cancelledAt = on ? .now : nil
        plan.cancelReason = on ? reason.trimmingCharacters(in: .whitespaces) : ""
        reason = ""
        try? context.save()
        EventRecorder.log(.note, title: on ? "Job cancelled" : "Job restored",
                          detail: [plan.company, plan.reference].filter { !$0.isEmpty }.joined(separator: " · "),
                          context: context, settings: store.settings)
    }

    @ViewBuilder
    private var jobStops: some View {
            ForEach(plan.stops) { stop in
                let index = plan.stops.firstIndex { $0.id == stop.id } ?? 0
                let blocker = plan.stops.arrivalBlocker(for: index)
                HStack(spacing: 8) {
                    Image(systemName: stop.kind.symbol).foregroundStyle(stop.kind.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text([stop.kind == .other ? stop.kindTitle : "", stop.displayName].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption.weight(.semibold)).lineLimit(1)
                        let details = [stop.equipmentName(in: vehicles), stop.trailerChangeText(in: vehicles), stop.fullAddress, stop.reference.isEmpty ? "" : "Booking \(stop.reference)",
                                       (stop.orderReference ?? "").isEmpty ? "" : "Ref \(stop.orderReference!)",
                                       stop.pallets.isEmpty ? "" : "\(stop.pallets) plt"].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !details.isEmpty { Text(details).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                        Text(statusText(stop)).font(.caption2).foregroundStyle(.secondary)
                        if stop.arrivedAt == nil, stop.outcome == nil, let b = blocker {
                            Label("Finish stop \(b + 1) first — or move, swap or edit the stops",
                                  systemImage: "lock.fill")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if let o = stop.outcome {
                        Label(o.title, systemImage: o.symbol).labelStyle(.titleAndIcon)
                            .font(.caption2.weight(.bold)).foregroundStyle(.red)
                    } else if busy == stop.id {
                        ProgressView()
                    } else if stop.arrivedAt == nil {
                        Button("Arrived") { mark(stop.id, arrived: true) }.buttonStyle(.borderedProminent).tint(.green)
                            .disabled(blocker != nil)
                    } else if stop.departedAt == nil {
                        if store.settings.vehicleCheckAtPickup, picked(stop) != nil {
                            Button { openPickupCheck(stop) } label: { Image(systemName: "checklist.checked") }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Vehicle check")
                        }
                        Button("Departed") { mark(stop.id, arrived: false) }.buttonStyle(.borderedProminent).tint(.blue)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Menu {
                        Button("Edit stop", systemImage: "pencil") { editingStop = stop }
                        if store.settings.vehicleCheckAtPickup, picked(stop) != nil {
                            Button("Vehicle check", systemImage: "checklist.checked") { openPickupCheck(stop) }
                        }
                        let i = plan.stops.firstIndex { $0.id == stop.id } ?? 0
                        if i > 0 { Button("Move up", systemImage: "arrow.up") { moveStop(from: i, to: i - 1) } }
                        if i < plan.stops.count - 1 { Button("Move down", systemImage: "arrow.down") { moveStop(from: i, to: i + 1) } }
                        if plan.stops.count > 1 {
                            Menu("Swap with…", systemImage: "arrow.up.arrow.down") {
                                ForEach(Array(plan.stops.enumerated()).filter { $0.element.id != stop.id }, id: \.element.id) { j, other in
                                    Button("\(j + 1). \(other.displayName)") { swapStops(i, j) }
                                }
                            }
                        }
                        Divider()
                        if stop.outcome != nil {
                            Button("Back to normal", systemImage: "arrow.uturn.backward") { setOutcome(stop.id, nil) }
                        }
                        ForEach(PlanStop.Outcome.allCases) { o in
                            Button("Stop \(o.title.lowercased())", systemImage: o.symbol, role: .destructive) {
                                reason = ""
                                pendingOutcome = (stop.id, o)
                            }
                        }
                        Divider()
                        Button("Delete stop", systemImage: "trash", role: .destructive) { deletingStop = stop }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel("Stop options")
                }
                .font(.caption)
                .opacity(stop.outcome == nil ? 1 : 0.6)
            }
            HStack {
                Button { addUnplannedStop() } label: { Label("Arrived somewhere else", systemImage: "mappin.and.ellipse") }
                    .disabled(plan.stops.currentStopIndex != nil)
                Spacer()
                NavigationLink { DebriefView(day: plan.plannedStart) } label: { Label("Debrief", systemImage: "tablecells") }
            }
            .buttonStyle(.bordered)
            .font(.caption.weight(.semibold))
    }

    /// The vehicle or trailer collected at this stop: its check column name, whether it's a trailer, and its height.
    private func picked(_ stop: PlanStop) -> (name: String, trailer: Bool, height: Double)? {
        func lookup(_ id: String?, ref: String?, trailer: Bool) -> (String, Bool, Double)? {
            if let id, !id.isEmpty, let v = vehicles.first(where: { $0.id.uuidString == id }) {
                return (VehicleCheck.columnName(v), trailer, v.height)
            }
            if let ref, !ref.isEmpty { return (ref, trailer, 0) }
            return nil
        }
        switch stop.kind {
        case .trailerPickup: return lookup(stop.equipmentID, ref: stop.equipmentRef, trailer: true)
        case .vehiclePickup: return lookup(stop.equipmentID, ref: stop.equipmentRef, trailer: false)
        default: return lookup(stop.pickTrailerID, ref: stop.pickTrailerRef, trailer: true)
        }
    }

    /// Adds the collected vehicle/trailer to today's check and opens it.
    private func openPickupCheck(_ stop: PlanStop, onlyIfOpen: Bool = false) {
        guard let p = picked(stop) else { return }
        let check = VehicleCheck.today(in: context, settings: store.settings)
        let column = check.addColumn(p.name, trailer: p.trailer, height: p.height)
        try? context.save()
        if onlyIfOpen, let column, check.openCount(column: column) == 0 { return }
        pickupCheck = check
    }

    /// Leaving a pick-up or drop-off stop changes the current trailer or vehicle (and logs it).
    private func applyEquipment(_ stop: PlanStop, at time: Date) {
        let id = stop.equipmentID ?? ""
        switch stop.kind {
        case .trailerPickup where !id.isEmpty:
            VehicleLog.selectTrailer(id, context: context, store: store, at: time)
        case .trailerDrop where id.isEmpty || store.settings.currentTrailerID == id:
            VehicleLog.selectTrailer("", context: context, store: store, at: time)
        case .vehiclePickup where !id.isEmpty:
            VehicleLog.select(id, context: context, store: store, at: time)
            AutoDriveDetector.shared.update(settings: store.settings)
        case .vehicleDrop where id.isEmpty || store.settings.currentVehicleID == id:
            VehicleLog.select("", context: context, store: store, at: time)
        default:
            break
        }
        // Trailer swap at an ordinary stop: drop first, then pick up.
        if let drop = stop.dropTrailerID, drop == "current" || drop == store.settings.currentTrailerID,
           !store.settings.currentTrailerID.isEmpty {
            VehicleLog.selectTrailer("", context: context, store: store, at: time)
        }
        if let pick = stop.pickTrailerID, !pick.isEmpty {
            VehicleLog.selectTrailer(pick, context: context, store: store, at: time)
        }
    }

    private func moveStop(from: Int, to: Int) {
        var stops = plan.stops
        guard stops.indices.contains(from), stops.indices.contains(to) else { return }
        withAnimation { stops.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to) }
        plan.stops = stops
        try? context.save()
    }

    private func swapStops(_ a: Int, _ b: Int) {
        var stops = plan.stops
        guard stops.indices.contains(a), stops.indices.contains(b) else { return }
        withAnimation { stops.swapAt(a, b) }
        plan.stops = stops
        try? context.save()
    }

    private func removeStop(_ id: UUID) {
        withAnimation { plan.stops.removeAll { $0.id == id } }
        try? context.save()
        deletingStop = nil
    }

    private func setOutcome(_ id: UUID, _ outcome: PlanStop.Outcome?) {
        var place = ""
        updateStop(id) {
            $0.outcome = outcome
            $0.outcomeReason = outcome == nil ? nil : reason.trimmingCharacters(in: .whitespaces)
            place = $0.displayName
        }
        EventRecorder.log(.note, title: outcome.map { "Stop \($0.title.lowercased())" } ?? "Stop back to normal",
                          detail: [place, reason].filter { !$0.isEmpty }.joined(separator: " — "),
                          context: context, settings: store.settings)
        reason = ""
        pendingOutcome = nil
    }

    private func statusText(_ stop: PlanStop) -> String {
        var parts: [String] = []
        if let o = stop.outcome {
            parts.append("\(o.title)\(stop.outcomeAt.map { " at \(Fmt.time($0))" } ?? "")\((stop.outcomeReason ?? "").isEmpty ? "" : " — \(stop.outcomeReason!)")")
        }
        if !stop.bookingText.isEmpty { parts.append("Booked \(stop.bookingText)") }
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
                if arrived, stops.arrivalBlocker(for: i) != nil { busy = nil; return }
                if arrived {
                    stops[i].arrivedAt = now
                    ReminderService.shared.fire(.arrived, context: context)
                } else {
                    stops[i].departedAt = now
                    applyEquipment(stops[i], at: now)
                    if store.settings.vehicleCheckAtPickup { openPickupCheck(stops[i], onlyIfOpen: true) }
                }
                EventRecorder.log(arrived ? .arrived : .departed, detail: stops[i].place, at: now,
                                  coordinate: location?.coordinate, context: context, settings: store.settings)
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
        EventRecorder.log(.arrived, detail: "Unplanned stop", context: context, settings: store.settings)
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

/// End-of-day debrief as tables: the job, vehicle check, every stop, activity totals, mileage, resources, events and pay.
/// Blocks can be reordered and hidden with Edit layout.
struct DebriefView: View {
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \DayRecord.day) private var records: [DayRecord]
    @Query(sort: \ResourceLog.date) private var resources: [ResourceLog]
    @Query(sort: \CardEvent.time) private var cardEvents: [CardEvent]
    @Query(sort: \SpeedEvent.start) private var speedEvents: [SpeedEvent]
    @Query(sort: \VehicleUse.start) private var uses: [VehicleUse]
    @Query(sort: \EventLog.time) private var eventLog: [EventLog]
    @Query(sort: \VehicleCheck.date) private var checks: [VehicleCheck]
    var day: Date

    var body: some View {
        let d = DebriefData.make(day: day, entries: entries, plans: plans, vehicles: vehicles, records: records,
                                 resources: resources, cardEvents: cardEvents, speedEvents: speedEvents, settings: store.settings,
                                 uses: uses, eventLog: eventLog, checks: checks)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(store.settings.blocks(.debrief), id: \.self) { block in
                    switch block {
                    case "job":
                        SheetTable(title: String(localized: "Job"), symbol: "shippingbox.fill", rows: d.job, keyValue: true)
                    case "vehicleCheck":
                        if !d.checkRows.isEmpty {
                            SheetTable(title: String(localized: "Vehicle check"), symbol: "checklist.checked",
                                       header: DebriefData.checkHeader, rows: d.checkRows, note: d.checkNote)
                        }
                    case "stops":
                        VStack(alignment: .leading, spacing: 6) {
                            SheetTable(title: String(localized: "Stops"), symbol: "mappin.and.ellipse", header: DebriefData.stopHeader,
                                       rows: d.stops, wide: true,
                                       empty: String(localized: "No stops recorded. Add stops to the day's plan and tap Arrived / Departed."))
                            if !d.mapPoints.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(d.mapPoints.indices, id: \.self) { i in
                                            let p = d.mapPoints[i]
                                            Button {
                                                let item = MKMapItem(placemark: MKPlacemark(coordinate: p.coordinate))
                                                item.name = p.name
                                                item.openInMaps()
                                            } label: { Label(p.name, systemImage: "map") }
                                        }
                                    }
                                    .buttonStyle(.bordered).font(.caption)
                                }
                            }
                        }
                    case "activities":
                        SheetTable(title: String(localized: "Activities"), symbol: "clock.fill",
                                   header: d.totals.map(\.0), rows: [d.totals.map(\.1)], wide: true)
                    case "mileage":
                        VStack(alignment: .leading, spacing: 12) {
                            SheetTable(title: String(localized: "Mileage"), symbol: "road.lanes", rows: d.mileage.map { [$0.0, $0.1] }, keyValue: true,
                                       empty: String(localized: "No mileage recorded."))
                            if !d.resources.isEmpty {
                                SheetTable(title: String(localized: "Fuel & resources"), symbol: "fuelpump.fill",
                                           header: DebriefData.resourceHeader, rows: d.resources)
                            }
                        }
                    case "events":
                        SheetTable(title: String(localized: "Events"), symbol: "exclamationmark.triangle.fill",
                                   header: DebriefData.eventHeader, rows: d.events, empty: String(localized: "No events."))
                    case "pay":
                        SheetTable(title: String(localized: "Pay"), symbol: "sterlingsign.circle.fill",
                                   rows: [[String(localized: "Estimated gross"), d.pay]], keyValue: true)
                    default:
                        EmptyView()
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Debrief \(Fmt.day(day))")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditLayoutButton(pages: [.debrief]) }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: d.text, subject: Text("Debrief \(Fmt.day(day))")) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }
}

/// A spreadsheet-style table with a heading: header row, striped rows and grid lines.
/// Key/value tables fill the width; wide tables scroll sideways.
struct SheetTable: View {
    var title: String
    var symbol: String
    var header: [String]? = nil
    var rows: [[String]]
    var keyValue = false
    var wide = false
    var note: String? = nil
    var empty: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.headline)
            if rows.isEmpty {
                Text(empty ?? "—").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            } else if wide {
                ScrollView(.horizontal, showsIndicators: true) { grid }
            } else {
                grid
            }
            if let note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            if let header {
                GridRow { ForEach(header.indices, id: \.self) { cell(header[$0], row: -1, col: $0) } }
            }
            ForEach(rows.indices, id: \.self) { r in
                GridRow { ForEach(rows[r].indices, id: \.self) { c in cell(rows[r][c], row: r, col: c) } }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.separator)))
    }

    private func cell(_ text: String, row: Int, col: Int) -> some View {
        let isHeader = row < 0
        let isKey = keyValue && col == 0
        return Text(text.isEmpty ? "—" : text)
            .font(isHeader ? .caption.weight(.bold) : (isKey ? .subheadline.weight(.semibold) : .subheadline.monospacedDigit()))
            .foregroundStyle(isHeader ? Color.accentColor : (text.isEmpty ? .secondary : (isKey ? .secondary : .primary)))
            .lineLimit(isHeader ? 2 : 3)
            .minimumScaleFactor(isHeader ? 0.8 : 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(minWidth: wide ? 44 : 0, maxWidth: wide ? 220 : (keyValue && col == 0 ? 140 : .infinity),
                   maxHeight: .infinity, alignment: .leading)
            .frame(maxWidth: keyValue && col == 0 ? nil : .infinity, alignment: .leading)
            .background(isHeader ? Color.accentColor.opacity(0.14) : (row.isMultiple(of: 2) ? Color.clear : Color(.tertiarySystemFill).opacity(0.5)))
            .overlay(Rectangle().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
    }
}

/// Everything shown in a debrief, also as plain text for sharing.
struct DebriefData {
    static var stopHeader: [String] {
        ["#", String(localized: "Type"), String(localized: "Site"), String(localized: "Address"), String(localized: "Booked"),
         String(localized: "Arrived"), String(localized: "Left"), String(localized: "On site"), String(localized: "Booking ref"),
         String(localized: "Order ref"), String(localized: "Pallets"), String(localized: "Trailer"), String(localized: "Outcome")]
    }
    static var checkHeader: [String] {
        [String(localized: "Vehicle / trailer"), String(localized: "Answered"), String(localized: "Defects"), String(localized: "Height")]
    }
    static var resourceHeader: [String] { [String(localized: "Item"), String(localized: "Amount"), String(localized: "Where")] }
    static var eventHeader: [String] { [String(localized: "Time"), String(localized: "Event"), String(localized: "Details")] }

    var vehicle = "", trailer = "", pay = ""
    var job: [[String]] = []
    var stops: [[String]] = []
    var checkRows: [[String]] = []
    var checkNote = ""
    var mapPoints: [(name: String, coordinate: CLLocationCoordinate2D)] = []
    var totals: [(String, String)] = []
    var mileage: [(String, String)] = []
    var resources: [[String]] = []
    var events: [[String]] = []
    var text = ""

    static func make(day: Date, entries: [ActivityEntry], plans: [WorkPlan], vehicles: [Vehicle], records: [DayRecord],
                     resources: [ResourceLog], cardEvents: [CardEvent], speedEvents: [SpeedEvent], settings: AppSettings,
                     uses: [VehicleUse] = [], eventLog: [EventLog] = [], checks: [VehicleCheck] = []) -> DebriefData {
        let cal = Calendar.hgv
        let start = cal.startOfDay(for: day), end = start.addingTimeInterval(86_400)
        var d = DebriefData()
        let plan = plans.first { cal.isDate($0.plannedStart, inSameDayAs: day) }
        let name: (String) -> String = { id in vehicles.first { $0.id.uuidString == id }?.displayName ?? "" }
        d.vehicle = name(plan?.vehicleID ?? records.first { cal.isDate($0.day, inSameDayAs: day) }?.vehicleID ?? "")
        d.trailer = name(plan?.trailerID ?? "")

        let dayEntries = entries.filter { ($0.end ?? .now) > start && $0.start < end }
        let analysis = RulesEngine.analyze(entries.map(\.snapshot), now: .now, config: settings.ruleConfig)
        let shifts = analysis.shifts.filter { $0.period.start >= start && $0.period.start < end }
        var shift = ""
        if let first = shifts.first, let last = shifts.last {
            shift = "\(Fmt.time(first.period.start))–\(last.period.isOpen ? String(localized: "now") : Fmt.time(last.period.end))"
        }
        let cards = cardEvents.filter { $0.time >= start && $0.time < end }
        let card = cards.map { "\($0.inserted ? String(localized: "In") : String(localized: "Out")) \(Fmt.time($0.time))" }.joined(separator: " · ")

        for (i, s) in (plan?.stops ?? []).enumerated() {
            let onSite = (s.arrivedAt != nil && s.departedAt != nil) ? Fmt.hm(s.departedAt!.timeIntervalSince(s.arrivedAt!)) : ""
            let trailer = [s.equipmentName(in: vehicles), s.trailerChangeText(in: vehicles)].filter { !$0.isEmpty }.joined(separator: " · ")
            d.stops.append(["\(i + 1)", s.kindTitle, s.displayName, s.fullAddress, s.bookingText, s.arrivedAt.map(Fmt.time) ?? "",
                            s.departedAt.map(Fmt.time) ?? "", onSite, s.reference, s.orderReference ?? "", s.pallets, trailer,
                            s.outcome.map { "\($0.title)\((s.outcomeReason ?? "").isEmpty ? "" : ": \(s.outcomeReason!)")" } ?? ""])
            if let lat = s.latitude, let lon = s.longitude {
                d.mapPoints.append((s.place.isEmpty ? "Stop \(i + 1)" : s.place, CLLocationCoordinate2D(latitude: lat, longitude: lon)))
            }
        }

        let t = DayTotals.compute(dayEntries, day: day)
        d.totals = [(String(localized: "Driving"), Fmt.hm(t.driving)), (String(localized: "Other work"), Fmt.hm(t.otherWork)),
                    (String(localized: "POA"), Fmt.hm(t.availability)), (String(localized: "Breaks"), Fmt.hm(t.breaks)),
                    (String(localized: "Working time"), Fmt.hm(t.working)),
                    (String(localized: "Infringements"), "\(shifts.flatMap(\.issues).count)")]

        let miles = settings.useMiles
        let dayUses = uses.filter { $0.start < end && ($0.end ?? .now) > start }
        if !dayUses.isEmpty {
            // One line per vehicle driven (a shift can use several).
            for u in dayUses {
                let v = name(u.vehicleID).isEmpty ? String(localized: "Vehicle") : name(u.vehicleID)
                d.mileage.append(("\(v) \(Fmt.time(u.start))–\(u.end.map(Fmt.time) ?? String(localized: "now"))",
                                  "\(Fmt.odometer(u.startOdometerKm, miles: miles)) → \(Fmt.odometer(u.effectiveEndKm, miles: miles)) · \(Fmt.distance(u.distanceKm, miles: miles))"))
            }
            d.mileage.append((String(localized: "Total distance"), Fmt.distance(dayUses.reduce(0) { $0 + $1.distanceKm }, miles: miles)))
            let names = dayUses.map { name($0.vehicleID) }.filter { !$0.isEmpty }
            if !names.isEmpty { d.vehicle = Array(NSOrderedSet(array: names)).compactMap { $0 as? String }.joined(separator: " · ") }
        } else if let r = records.first(where: { cal.isDate($0.day, inSameDayAs: day) }) {
            d.mileage = [(String(localized: "Start odometer"), Fmt.odometer(r.startOdometerKm, miles: miles)),
                         (String(localized: "End odometer"), Fmt.odometer(r.endOdometerKm, miles: miles)),
                         (String(localized: "Distance"), Fmt.distance(r.distanceKm, miles: miles))]
            if r.gpsKm > 0 { d.mileage.append((String(localized: "GPS distance"), Fmt.distance(r.gpsKm, miles: miles))) }
        }
        d.resources = resources.filter { $0.date >= start && $0.date < end }.map {
            [$0.kind.title, "\(String(format: "%g", $0.quantity)) \($0.kind.unit)", $0.location]
        }

        // Events: the event log (arrived, departed, card, fuel, overspeed…); older days without it use the speed records.
        let logged = eventLog.filter { $0.time >= start && $0.time < end && $0.kind != .activity }
        if !logged.isEmpty {
            d.events = logged.map { [Fmt.time($0.time), $0.title, $0.detail] }
        } else {
            d.events = speedEvents.filter { $0.start >= start && $0.start < end }.map {
                [Fmt.time($0.start), String(localized: "Overspeed"),
                 "\(Int($0.maxKmh)) km/h · \(Int($0.duration)) s\($0.isInfringement ? " · " + String(localized: "infringement") : "")"]
            }
        }

        // Vehicle check done that day: one row per vehicle / trailer.
        if let check = checks.last(where: { $0.date >= start && $0.date < end }) {
            for (c, col) in check.columns.enumerated() {
                let trailer = c < check.trailerColumns.count && check.trailerColumns[c]
                let lines = CheckItem.all.filter { $0.applies(toTrailer: trailer) }.count
                let defects = check.answers.filter { $0.key.hasSuffix("|\(c)") && ($0.value == "defect" || $0.value == "no") }.count
                let height = c < check.heights.count && check.heights[c] > 0 ? Fmt.length(check.heights[c]) : ""
                d.checkRows.append([col, "\(lines - check.openCount(column: c))/\(lines)", "\(defects)", height])
            }
            d.checkNote = check.signed
                ? String(localized: "Signed \(check.signedAt.map(Fmt.time) ?? "")") + (check.defectBookRef.isEmpty ? "" : " · " + String(localized: "Defect book ref \(check.defectBookRef)"))
                : String(localized: "Not signed")
        }

        d.pay = Fmt.money(PayCalculator.calculate(shifts: shifts, nightOuts: 0, settings: settings.pay, salaryDays: 1).total,
                          symbol: settings.pay.currencySymbol)
        d.job = [[String(localized: "Date"), Fmt.day(day)], [String(localized: "Driver"), settings.driverName],
                 [String(localized: "Company"), plan?.company ?? ""], [String(localized: "Vehicle"), d.vehicle],
                 [String(localized: "Trailer"), d.trailer], [String(localized: "Shift"), shift], [String(localized: "Driver card"), card]]

        // Plain text for sharing (comma-separated tables).
        func csv(_ row: [String]) -> String { row.map { $0.contains(",") ? "\"\($0)\"" : $0 }.joined(separator: ", ") }
        var out = "Debrief \(Fmt.day(day))\n"
        out += d.job.filter { !$0[1].isEmpty }.map { "\($0[0]): \($0[1])" }.joined(separator: "\n")
        if !d.checkRows.isEmpty {
            out += "\n\nVehicle check\n" + csv(checkHeader) + "\n" + d.checkRows.map(csv).joined(separator: "\n") + "\n" + d.checkNote
        }
        out += "\n\nStops\n" + csv(stopHeader) + "\n" + d.stops.map(csv).joined(separator: "\n")
        out += "\n\nActivities\n" + csv(d.totals.map(\.0)) + "\n" + csv(d.totals.map(\.1))
        if !d.mileage.isEmpty { out += "\n\n" + d.mileage.map { "\($0.0): \($0.1)" }.joined(separator: "\n") }
        if !d.resources.isEmpty { out += "\n\n" + csv(resourceHeader) + "\n" + d.resources.map(csv).joined(separator: "\n") }
        if !d.events.isEmpty { out += "\n\nEvents\n" + d.events.map(csv).joined(separator: "\n") }
        out += "\n\nEstimated gross: \(d.pay)\n"
        d.text = out
        return d
    }
}
