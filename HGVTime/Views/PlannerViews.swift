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
    @State private var stops: [PlanStop]
    @State private var load: String
    @State private var pallets: String
    @State private var reference: String
    @State private var lines: [PlanLine]
    @State private var notes: String
    @State private var confirmDelete = false

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
                    TextField("Start location / depot", text: $startLocation)
                } header: {
                    Text("Job")
                } footer: {
                    if vehicles.isEmpty { Text("Add vehicles and trailers in Settings → Vehicles & trailers.") }
                }

                Section("Stops") {
                    ForEach($stops) { $stop in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Picker("", selection: $stop.kind) {
                                    ForEach(PlanStop.Kind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                                }
                                .labelsHidden()
                                .fixedSize()
                                TextField("Time", text: $stop.time).frame(maxWidth: 70)
                            }
                            TextField("Place / address / postcode", text: $stop.place)
                            HStack {
                                TextField("Reference", text: $stop.reference)
                                TextField("Pallets", text: $stop.pallets).frame(maxWidth: 80)
                            }
                            TextField("Notes", text: $stop.notes)
                        }
                        .font(.subheadline)
                    }
                    .onDelete { stops.remove(atOffsets: $0) }
                    .onMove { stops.move(fromOffsets: $0, toOffset: $1) }
                    Button { stops.append(PlanStop()) } label: { Label("Add stop", systemImage: "plus.circle.fill") }
                }

                Section("Load") {
                    TextField("Load / goods", text: $load)
                    TextField("Pallets", text: $pallets)
                    TextField("Reference / job number", text: $reference)
                }

                Section {
                    ForEach($lines) { $line in
                        HStack {
                            TextField("Label", text: $line.label).frame(maxWidth: 130)
                            Divider()
                            TextField("Value", text: $line.value)
                        }
                    }
                    .onDelete { lines.remove(atOffsets: $0) }
                    Button { lines.append(PlanLine()) } label: { Label("Add line", systemImage: "plus.circle.fill") }
                } header: {
                    Text("Custom lines")
                } footer: {
                    Text("Anything else: seal number, gate code, contact, booking-in number…")
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
                Spacer()
                Text("\(Fmt.time(plan.plannedStart))–\(Fmt.time(plan.plannedEnd)) · \(Fmt.hm(plan.length))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if !plan.company.isEmpty { Text(plan.company).font(.headline) }
            if vehicle != nil || trailer != nil {
                Text([vehicle?.displayName, trailer.map { "Trailer \($0.displayName)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !plan.startLocation.isEmpty { Label(plan.startLocation, systemImage: "building.2").font(.caption) }
            ForEach(plan.stops) { stop in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: stop.kind.symbol).foregroundStyle(stop.kind == .collection ? .orange : .blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text([stop.time, stop.place].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption.weight(.semibold))
                        let extra = [stop.reference.isEmpty ? "" : "Ref \(stop.reference)", stop.pallets.isEmpty ? "" : "\(stop.pallets) plt", stop.notes]
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
