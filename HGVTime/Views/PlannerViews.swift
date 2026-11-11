import SwiftUI
import SwiftData

/// Plan (book) a working day: times, company, vehicle, stops, loads, references and custom lines.
struct PlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    private let plan: WorkPlan?
    @State private var start: Date
    @State private var end: Date
    @State private var company: String
    @State private var vehicleID: String
    @State private var trailerID: String
    @State private var startLocation: String
    @State private var startPostcode: String
    @State private var startFlat: String
    @State private var startHouseName: String
    @State private var startHouseNumber: String
    @State private var startName: String
    @State private var startLatitude: Double?
    @State private var startLongitude: Double?
    @State private var editingLine: PlanLine?
    @State private var stops: [PlanStop]
    @State private var load: String
    @State private var pallets: String
    @State private var reference: String
    @State private var lines: [PlanLine]
    @State private var notes: String
    @State private var confirmDelete = false
    @State private var editingStop: EditableStop?

    struct EditableStop: Identifiable {
        var stop: PlanStop
        var isNew: Bool
        var id: UUID { stop.id }
    }

    init(plan: WorkPlan?, day: Date = .now, defaultVehicleID: String = "", defaultTrailerID: String = "") {
        self.plan = plan
        let cal = Calendar.hgv
        let s = plan?.plannedStart ?? (cal.date(bySettingHour: 6, minute: 0, second: 0, of: day) ?? day)
        _start = State(initialValue: s)
        _end = State(initialValue: plan?.plannedEnd ?? s.addingTimeInterval(11 * 3600))
        _company = State(initialValue: plan?.company ?? "")
        _vehicleID = State(initialValue: plan?.vehicleID ?? defaultVehicleID)
        _trailerID = State(initialValue: plan?.trailerID ?? defaultTrailerID)
        _startLocation = State(initialValue: plan?.startLocation ?? "")
        _startPostcode = State(initialValue: plan?.startPostcode ?? "")
        _startFlat = State(initialValue: plan?.startFlat ?? "")
        _startHouseName = State(initialValue: plan?.startHouseName ?? "")
        _startHouseNumber = State(initialValue: plan?.startHouseNumber ?? "")
        _startName = State(initialValue: plan?.startName ?? "")
        _startLatitude = State(initialValue: plan?.startLatitude)
        _startLongitude = State(initialValue: plan?.startLongitude)
        _stops = State(initialValue: plan?.stops ?? [])
        _load = State(initialValue: plan?.load ?? "")
        _pallets = State(initialValue: plan?.pallets ?? "")
        _reference = State(initialValue: plan?.reference ?? "")
        _lines = State(initialValue: plan?.lines ?? [])
        _notes = State(initialValue: plan?.notes ?? "")
    }

    var body: some View {
        let issues = PlanCheck.check(start: start, end: end, excluding: plan?.id, plans: plans,
                                     entries: entries.map(\.snapshot), settings: store.settings)
        let companies = Array(Set(plans.map(\.company).filter { !$0.isEmpty })).sorted()
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start", selection: $start)
                    DatePicker("Finish", selection: $end, in: start...)
                    LabeledContent("Shift length", value: Fmt.hm(end.timeIntervalSince(start)))
                } header: {
                    Text("When")
                }
                Section("Rest check") {
                    ForEach(issues) { PlanIssueRow(issue: $0) }
                }

                Section {
                    TextField("Company / agency client", text: $company)
                    if !companies.isEmpty && company.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(companies, id: \.self) { name in
                                    Button(name) { company = name }.buttonStyle(.bordered).font(.caption)
                                }
                            }
                        }
                    }
                    Picker("Vehicle", selection: $vehicleID) {
                        Text("Not set").tag("")
                        ForEach(vehicles.filter { $0.kind != .trailer }) { Text($0.displayName).tag($0.id.uuidString) }
                    }
                    Picker("Trailer", selection: $trailerID) {
                        Text("None").tag("")
                        ForEach(vehicles.filter { $0.kind == .trailer }) { Text($0.displayName).tag($0.id.uuidString) }
                    }
                } header: {
                    Text("Job")
                } footer: {
                    if vehicles.isEmpty { Text("Add vehicles and trailers in Jobs → Vehicles.") }
                }

                Section {
                    AddressLookupFields(address: $startLocation, postcode: $startPostcode,
                                        latitude: $startLatitude, longitude: $startLongitude,
                                        name: $startName, addressLabel: "Start location / depot",
                                        houseNumber: $startHouseNumber, houseName: $startHouseName, flat: $startFlat)
                } header: {
                    Text("Start location")
                } footer: {
                    Text("Search the depot postcode and pick the address, type it, or pinpoint it on the map. The route on the map starts here.")
                }

                Section {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { i, stop in
                        HStack(spacing: 6) {
                            Button { editingStop = EditableStop(stop: stop, isNew: false) } label: { StopRow(stop: stop, number: i + 1) }
                                .foregroundStyle(.primary)
                                .buttonStyle(.plain)
                            Menu {
                                Button("Edit", systemImage: "pencil") { editingStop = EditableStop(stop: stop, isNew: false) }
                                Button("Duplicate", systemImage: "plus.square.on.square") {
                                    var copy = stop
                                    copy.id = UUID()
                                    copy.arrivedAt = nil
                                    copy.departedAt = nil
                                    stops.insert(copy, at: i + 1)
                                }
                                if i > 0 { Button("Move up", systemImage: "arrow.up") { stops.swapAt(i, i - 1) } }
                                if i < stops.count - 1 { Button("Move down", systemImage: "arrow.down") { stops.swapAt(i, i + 1) } }
                                Button("Delete", systemImage: "trash", role: .destructive) { stops.removeAll { $0.id == stop.id } }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.title3).frame(width: 32, height: 32)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onDelete { stops.remove(atOffsets: $0) }
                    .onMove { stops.move(fromOffsets: $0, toOffset: $1) }
                    Menu {
                        ForEach(PlanStop.Kind.allCases.filter { $0 != .other }) { k in
                            Button(k.title, systemImage: k.symbol) { editingStop = EditableStop(stop: PlanStop(kind: k), isNew: true) }
                        }
                        Divider()
                        Button("Custom stop…", systemImage: PlanStop.Kind.other.symbol) {
                            editingStop = EditableStop(stop: PlanStop(kind: .other), isNew: true)
                        }
                    } label: {
                        Label("Add stop", systemImage: "plus.circle.fill")
                    } primaryAction: {
                        editingStop = EditableStop(stop: PlanStop(kind: stops.isEmpty ? .collection : .delivery), isNew: true)
                    }
                    Button {
                        editingStop = EditableStop(stop: PlanStop(kind: .other), isNew: true)
                    } label: { Label("Add custom stop", systemImage: "mappin.and.ellipse") }
                } header: {
                    Text("Stops")
                } footer: {
                    Text("Tap a stop to edit it, or use ⋯ to edit, duplicate, move or delete. Hold Add stop to pick the type (collection, delivery, depot, fuel, parking, trailer swap). A custom stop can be anything — name it yourself.")
                }

                Section("Load") {
                    TextField("Load / goods", text: $load)
                    TextField("Pallets", text: $pallets)
                    TextField("Reference / job number", text: $reference)
                }

                Section {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                        HStack(spacing: 6) {
                            Button { editingLine = line } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(line.label.isEmpty ? "No label" : line.label).font(.caption).foregroundStyle(.secondary)
                                    Text(line.value.isEmpty ? "—" : line.value).font(.subheadline)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Menu {
                                Button("Edit", systemImage: "pencil") { editingLine = line }
                                if i > 0 { Button("Move up", systemImage: "arrow.up") { lines.swapAt(i, i - 1) } }
                                if i < lines.count - 1 { Button("Move down", systemImage: "arrow.down") { lines.swapAt(i, i + 1) } }
                                Button("Delete", systemImage: "trash", role: .destructive) { lines.removeAll { $0.id == line.id } }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.title3).frame(width: 32, height: 32)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onDelete { lines.remove(atOffsets: $0) }
                    .onMove { lines.move(fromOffsets: $0, toOffset: $1) }
                    Button { editingLine = PlanLine() } label: { Label("Add line", systemImage: "plus.circle.fill") }
                } header: {
                    Text("Custom lines")
                } footer: {
                    Text("Anything else: seal number, gate code, contact, booking-in number… Tap a line or use ⋯ to edit, move or delete it.")
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                if !plans.filter({ $0.id != plan?.id }).isEmpty && plan == nil {
                    Section {
                        Menu {
                            ForEach(plans.filter { $0.id != plan?.id }.suffix(8).reversed()) { p in
                                Button("\(Fmt.day(p.plannedStart)) · \(p.company.isEmpty ? "No company" : p.company)") { copy(from: p) }
                            }
                        } label: {
                            Label("Copy details from a previous plan", systemImage: "doc.on.doc")
                        }
                    }
                }

                if plan != nil {
                    Section {
                        Button("Delete plan", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(plan == nil ? "Plan work" : "Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .sheet(item: $editingStop) { item in
                StopEditor(stop: item.stop, isNew: item.isNew, onSave: { saved in
                    if let i = stops.firstIndex(where: { $0.id == saved.id }) { stops[i] = saved } else { stops.append(saved) }
                }, onDelete: {
                    stops.removeAll { $0.id == item.stop.id }
                })
            }
            .sheet(item: $editingLine) { line in
                PlanLineEditor(line: line, isNew: !lines.contains { $0.id == line.id }) { saved in
                    if let i = lines.firstIndex(where: { $0.id == saved.id }) { lines[i] = saved } else { lines.append(saved) }
                } onDelete: {
                    lines.removeAll { $0.id == line.id }
                }
            }
            .confirmationDialog("Delete this plan?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let plan { context.delete(plan); try? context.save() }
                    dismiss()
                }
            }
        }
    }

    private func copy(from p: WorkPlan) {
        company = p.company
        vehicleID = p.vehicleID
        trailerID = p.trailerID
        startLocation = p.startLocation
        startPostcode = p.startPostcode
        startFlat = p.startFlat
        startHouseName = p.startHouseName
        startHouseNumber = p.startHouseNumber
        startName = p.startName
        startLatitude = p.startLatitude
        startLongitude = p.startLongitude
        stops = p.stops.map { var s = $0; s.id = UUID(); return s }
        load = p.load
        pallets = p.pallets
        reference = p.reference
        lines = p.lines.map { var l = $0; l.id = UUID(); return l }
        notes = p.notes
        // Same times of day on this plan's date.
        let cal = Calendar.hgv
        let length = p.length
        let comps = cal.dateComponents([.hour, .minute], from: p.plannedStart)
        if let s = cal.date(bySettingHour: comps.hour ?? 6, minute: comps.minute ?? 0, second: 0, of: start) {
            start = s
            end = s.addingTimeInterval(length)
        }
    }

    private func save() {
        let p = plan ?? WorkPlan(start: start, end: end)
        if plan == nil { context.insert(p) }
        p.plannedStart = start
        p.plannedEnd = end
        p.company = company
        p.vehicleID = vehicleID
        p.trailerID = trailerID
        p.startLocation = startLocation
        p.startPostcode = startPostcode
        p.startFlat = startFlat
        p.startHouseName = startHouseName
        p.startHouseNumber = startHouseNumber
        p.startName = startName
        p.startLatitude = startLatitude
        p.startLongitude = startLongitude
        p.stops = stops
        p.load = load
        p.pallets = pallets
        p.reference = reference
        p.lines = lines.filter { !$0.label.isEmpty || !$0.value.isEmpty }
        p.notes = notes
        try? context.save()
        dismiss()
    }
}

/// Edit one custom line of a plan.
struct PlanLineEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var line: PlanLine
    var isNew: Bool
    var onSave: (PlanLine) -> Void
    var onDelete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label, e.g. Seal number", text: $line.label)
                    TextField("Value", text: $line.value, axis: .vertical).lineLimit(1...6)
                } footer: {
                    Text("Quick labels:")
                }
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(["Seal number", "Gate code", "Booking-in no.", "Trailer no.", "Contact", "Bay", "Temperature", "Customs ref"], id: \.self) { l in
                                Button(l) { line.label = l }.buttonStyle(.bordered).font(.caption)
                            }
                        }
                    }
                }
                if !isNew {
                    Section { Button("Delete line", role: .destructive) { onDelete(); dismiss() } }
                }
            }
            .navigationTitle(isNew ? "New line" : "Edit line")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(line); dismiss() }
                        .disabled(line.label.isEmpty && line.value.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct PlanIssueRow: View {
    var issue: PlanIssue
    var body: some View {
        Label {
            Text(issue.text).font(.caption).fixedSize(horizontal: false, vertical: true)
        } icon: {
            switch issue.level {
            case .error: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }
}

/// A planned day shown in the calendar and on Today.
struct PlanCard: View {
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    var plan: WorkPlan
    var title = "Planned"
    var showChecks = true
    /// Off on Today, where the stops are listed with Arrived/Departed buttons instead.
    var showStops = true

    var body: some View {
        let issues = showChecks
            ? PlanCheck.check(start: plan.plannedStart, end: plan.plannedEnd, excluding: plan.id, plans: plans,
                              entries: entries.map(\.snapshot), settings: store.settings).filter { $0.level != .ok }
            : []
        let vehicle = vehicles.first { $0.id.uuidString == plan.vehicleID }
        let trailer = vehicles.first { $0.id.uuidString == plan.trailerID }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: "calendar.badge.clock").font(.caption.weight(.bold)).foregroundStyle(.indigo)
                if plan.cancelled {
                    Text("CANCELLED").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.red, in: Capsule())
                }
                Spacer()
                Text("\(Fmt.time(plan.plannedStart))–\(Fmt.time(plan.plannedEnd)) · \(Fmt.hm(plan.length))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if !plan.company.isEmpty { Text(plan.company).font(.headline) }
            if vehicle != nil || trailer != nil {
                Text([vehicle?.displayName, trailer.map { "Trailer \($0.displayName)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            let startText = [plan.startName, AddressParts.join(flat: plan.startFlat, houseName: plan.startHouseName, houseNumber: plan.startHouseNumber,
                                                                street: plan.startLocation, postcode: plan.startPostcode)].filter { !$0.isEmpty }.joined(separator: ", ")
            if !startText.isEmpty { Label("Start: \(startText)", systemImage: "flag.fill").font(.caption) }
            ForEach(showStops ? plan.stops : []) { stop in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: stop.kind.symbol).foregroundStyle(stop.kind.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text([stop.bookingText, stop.kind == .other ? stop.kindTitle : "", stop.displayName].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption.weight(.semibold))
                        let extra = [stop.fullAddress, stop.reference.isEmpty ? "" : "Booking \(stop.reference)",
                                     (stop.orderReference ?? "").isEmpty ? "" : "Ref \(stop.orderReference!)",
                                     stop.pallets.isEmpty ? "" : "\(stop.pallets) plt", stop.notes]
                            .filter { !$0.isEmpty }.joined(separator: " · ")
                        if !extra.isEmpty { Text(extra).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            let loadLine = [plan.load, plan.pallets.isEmpty ? "" : "\(plan.pallets) pallets", plan.reference.isEmpty ? "" : "Ref \(plan.reference)"]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            if !loadLine.isEmpty { Label(loadLine, systemImage: "shippingbox").font(.caption) }
            ForEach(plan.lines) { line in
                Text("\(line.label): \(line.value)").font(.caption).foregroundStyle(.secondary)
            }
            if !plan.notes.isEmpty { Text(plan.notes).font(.caption).foregroundStyle(.secondary) }
            ForEach(issues) { PlanIssueRow(issue: $0) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.indigo.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
    }
}
