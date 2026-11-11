import SwiftUI
import SwiftData

/// The fleet list: saved vehicles and trailers to add, edit or delete. (Pick today's vehicle on the Today screen or in a plan.)
struct VehiclesView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var editing: Vehicle?
    @State private var adding: VehicleKind?
    @State private var scanning = false
    @State private var addingScanned: ScannedReg?
    @State private var matchMessage: String?

    var body: some View {
        let units = vehicles.filter { $0.kind != .trailer }
        let trailers = vehicles.filter { $0.kind == .trailer }
        List {
            Section {
                ForEach(units) { v in row(v) }
                .onDelete { delete(units, $0) }
                Button { adding = .tractor } label: { Label("Add vehicle", systemImage: "plus.circle.fill") }
            } header: {
                Text("Vehicles")
            } footer: {
                Text("Your fleet list. Tap a vehicle to edit it. Choose the one you're driving on the Today screen or in a job plan.")
            }
            Section("Trailers") {
                ForEach(trailers) { v in row(v) }
                .onDelete { delete(trailers, $0) }
                Button { adding = .trailer } label: { Label("Add trailer", systemImage: "plus.circle.fill") }
            }
        }
        .navigationTitle("Vehicles & trailers")
        .toolbar {
            Button { scanning = true } label: { Label("Scan number plate", systemImage: "camera.viewfinder") }
        }
        .sheet(item: $editing) { VehicleEditor(vehicle: $0) }
        .sheet(item: $adding) { VehicleEditor(vehicle: nil, newKind: $0) }
        .sheet(isPresented: $scanning) { PlateScanSheet { reg in found(reg) } }
        .sheet(item: $addingScanned) { VehicleEditor(vehicle: nil, newKind: .tractor, registration: $0.reg) }
        .alert(matchMessage ?? "", isPresented: Binding(get: { matchMessage != nil }, set: { if !$0 { matchMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func row(_ v: Vehicle) -> some View {
        HStack(spacing: 8) {
            Button { editing = v } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(v.displayName, systemImage: v.kind.symbol).font(.subheadline.weight(.semibold))
                    if !v.specsLine.isEmpty {
                        Text(v.specsLine).font(.caption).foregroundStyle(.secondary)
                    }
                    if let r = v.rules {
                        Text(r == .exempt ? "Exempt from drivers' hours" : r.title).font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Button("Edit", systemImage: "pencil") { editing = v }
                Button("Delete", systemImage: "trash", role: .destructive) { remove(v) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { remove(v) }
            Button("Edit", systemImage: "pencil") { editing = v }.tint(.blue)
        }
    }

    /// Opens a saved vehicle/trailer with this registration, or offers to add it.
    private func found(_ reg: String) {
        if let match = vehicles.first(where: { normalisedReg($0.registration) == reg || normalisedReg($0.fleetNumber) == reg }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { editing = match }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { addingScanned = ScannedReg(reg: reg) }
        }
    }

    private func delete(_ list: [Vehicle], _ offsets: IndexSet) {
        for i in offsets { remove(list[i]) }
    }

    private func remove(_ v: Vehicle) {
        if store.settings.currentVehicleID == v.id.uuidString { store.settings.currentVehicleID = "" }
        if store.settings.currentTrailerID == v.id.uuidString { store.settings.currentTrailerID = "" }
        context.delete(v)
        try? context.save()
    }
}

struct VehicleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store

    private let vehicle: Vehicle?
    @State private var kind: VehicleKind
    @State private var registration: String
    @State private var fleetNumber: String
    @State private var make: String
    @State private var model: String
    @State private var height: Double
    @State private var width: Double
    @State private var length: Double
    @State private var weight: Double
    @State private var axles: Int
    @State private var fuel: FuelType
    @State private var trailerBody: String
    @State private var notes: String
    @State private var confirmDelete = false

    @State private var odometer: Double
    @State private var rules: Regime?
    @State private var speedLimit: Double
    @State private var inFeet = false
    @State private var lookingUp = false
    @State private var lookupMessage: String?

    init(vehicle: Vehicle?, newKind: VehicleKind = .tractor, registration: String = "") {
        self.vehicle = vehicle
        let k = vehicle?.kind ?? newKind
        _kind = State(initialValue: k)
        _registration = State(initialValue: vehicle?.registration ?? registration)
        _odometer = State(initialValue: vehicle?.odometerKm ?? 0)
        _rules = State(initialValue: vehicle?.rules)
        _speedLimit = State(initialValue: vehicle?.speedLimitKmh ?? 0)
        _fleetNumber = State(initialValue: vehicle?.fleetNumber ?? "")
        _make = State(initialValue: vehicle?.make ?? "")
        _model = State(initialValue: vehicle?.model ?? "")
        _height = State(initialValue: vehicle?.height ?? 0)
        _width = State(initialValue: vehicle?.width ?? (k == .van ? 0 : 2.55))
        _length = State(initialValue: vehicle?.length ?? 0)
        _weight = State(initialValue: vehicle?.weight ?? 0)
        _axles = State(initialValue: vehicle?.axles ?? 0)
        _fuel = State(initialValue: vehicle?.fuel ?? .dieselAdBlue)
        _trailerBody = State(initialValue: vehicle?.body ?? "")
        _notes = State(initialValue: vehicle?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(VehicleKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    HStack {
                        TextField(kind == .trailer ? "Trailer number / ID" : "Registration", text: $registration)
                            .textInputAutocapitalization(.characters)
                        if kind != .trailer {
                            Button {
                                Task { await lookUp() }
                            } label: {
                                if lookingUp { ProgressView() } else { Label("Look up", systemImage: "magnifyingglass") }
                            }
                            .buttonStyle(.bordered)
                            .disabled(normalisedReg(registration).count < 2 || lookingUp)
                        }
                    }
                    if let lookupMessage {
                        Text(lookupMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Fleet number", text: $fleetNumber)
                    if kind != .trailer {
                        TextField("Make, e.g. DAF", text: $make)
                        TextField("Model, e.g. XF 480", text: $model)
                    } else {
                        Picker("Body", selection: $trailerBody) {
                            ForEach(["", "Curtainsider", "Box", "Fridge", "Flatbed", "Tipper", "Tanker", "Double deck", "Low loader", "Skeletal", "Walking floor"], id: \.self) {
                                Text($0.isEmpty ? "Not set" : $0).tag($0)
                            }
                        }
                    }
                }
                Section {
                    Picker("Enter in", selection: $inFeet) {
                        Text("Metres").tag(false)
                        Text("Feet & inches").tag(true)
                    }
                    .pickerStyle(.segmented)
                    measure("Height", value: $height, unit: "m")
                    measure("Width", value: $width, unit: "m")
                    measure("Length", value: $length, unit: "m")
                    measure("Gross weight", value: $weight, unit: "t")
                    Stepper(value: $axles, in: 0...8) {
                        LabeledContent("Axles", value: axles == 0 ? "Not set" : "\(axles)")
                    }
                } header: {
                    Text("Dimensions")
                } footer: {
                    Text("Check the height plate in the cab. Height shows on the Today screen as a reminder for low bridges.")
                }
                if kind != .trailer {
                    Section {
                        Picker("Fuel", selection: $fuel) {
                            ForEach(FuelType.allCases) { Text($0.title).tag($0) }
                        }
                        LabeledContent("Odometer") {
                            HStack(spacing: 4) {
                                TextField("0", value: Binding(
                                    get: { store.settings.useMiles ? (odometer / 1.609344).rounded() : odometer.rounded() },
                                    set: { odometer = store.settings.useMiles ? $0 * 1.609344 : $0 }).emptyIfZero,
                                          format: .number.precision(.fractionLength(0)))
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 110)
                                Text(store.settings.useMiles ? "mi" : "km").foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Fuel & mileage")
                    } footer: {
                        Text("The odometer updates when you enter end-of-day mileage on the Today screen.")
                    }
                }
                if kind != .trailer {
                    Section {
                        Picker("Drivers' hours rules", selection: $rules) {
                            Text("My usual rules (\(store.settings.primaryRegime.shortTitle))").tag(Regime?.none)
                            Text("Tacho (assimilated / AETR)").tag(Regime?.some(.assimilated))
                            Text("GB domestic (exempt from tacho)").tag(Regime?.some(.gbDomestic))
                            Text("Exempt — no drivers' hours rules").tag(Regime?.some(.exempt))
                        }
                        LabeledContent("Overspeed above") {
                            HStack(spacing: 4) {
                                TextField("Auto", value: $speedLimit.emptyIfZero, format: .number.precision(.fractionLength(0)))
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 60)
                                Text("km/h").foregroundStyle(.secondary)
                            }
                        }
                        if speedLimit == 0 {
                            Text("Automatic: \(SpeedLimits.describe(SpeedLimits.defaultKmh(kind: kind, weightT: weight, region: store.settings.region))) for this vehicle in \(store.settings.region.title).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Rules & speed")
                    } footer: {
                        Text("When you choose this vehicle, new activities follow its rules. Exempt vehicles (e.g. vans up to 3.5 t, or exempt uses) don't count towards driving limits — the time is still working time.")
                    }
                }
                Section("Notes") {
                    TextField("e.g. tail lift, tacho calibration date, MOT", text: $notes, axis: .vertical)
                }
                if vehicle != nil {
                    Section {
                        Button("Delete", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(vehicle == nil ? "Add \(kind == .trailer ? "trailer" : "vehicle")" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .confirmationDialog("Delete this \(kind == .trailer ? "trailer" : "vehicle")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let vehicle { context.delete(vehicle); try? context.save() }
                    dismiss()
                }
            }
        }
    }

    private func measure(_ title: String, value: Binding<Double>, unit: String) -> some View {
        LabeledContent(title) {
            if unit == "m" && inFeet {
                HStack(spacing: 4) {
                    TextField("ft", value: Binding(
                        get: { Double(Int((value.wrappedValue / 0.0254).rounded()) / 12) },
                        set: { ft in
                            let inches = Double(Int((value.wrappedValue / 0.0254).rounded()) % 12)
                            value.wrappedValue = (ft * 12 + inches) * 0.0254
                        }).emptyIfZero, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 44)
                    Text("ft").foregroundStyle(.secondary)
                    TextField("in", value: Binding(
                        get: { Double(Int((value.wrappedValue / 0.0254).rounded()) % 12) },
                        set: { inches in
                            let ft = Double(Int((value.wrappedValue / 0.0254).rounded()) / 12)
                            value.wrappedValue = (ft * 12 + min(max(inches, 0), 11)) * 0.0254
                        }).emptyIfZero, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 40)
                    Text("in").foregroundStyle(.secondary)
                    Text(value.wrappedValue > 0 ? String(format: "%.2f m", value.wrappedValue) : "")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    TextField("0.00", value: value.emptyIfZero, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                    Text(unit).foregroundStyle(.secondary)
                    if unit == "m" && value.wrappedValue > 0 {
                        Text(Fmt.feetInches(value.wrappedValue)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Fills in details from the DVLA (UK registrations).
    private func lookUp() async {
        lookingUp = true
        defer { lookingUp = false }
        do {
            let info = try await DVLALookup.lookup(registration)
            registration = normalisedReg(registration)
            if !info.make.isEmpty { make = info.make.capitalized }
            if let f = info.fuel { fuel = f }
            if info.revenueWeightKg > 0 { weight = Double(info.revenueWeightKg) / 1000 }
            let summary = info.summary
            if !summary.isEmpty && !notes.contains(summary) { notes = notes.isEmpty ? summary : notes + "\n" + summary }
            lookupMessage = "Found: \(info.make.capitalized) · \(summary)"
        } catch {
            lookupMessage = error.localizedDescription
        }
    }

    private func save() {
        let v = vehicle ?? Vehicle(kind: kind)
        if vehicle == nil { context.insert(v) }
        v.kind = kind
        v.registration = registration.trimmingCharacters(in: .whitespaces)
        v.fleetNumber = fleetNumber
        v.make = make
        v.model = model
        v.height = height
        v.width = width
        v.length = length
        v.weight = weight
        v.axles = axles
        v.fuel = fuel
        v.body = trailerBody
        v.notes = notes
        v.odometerKm = odometer
        v.rules = kind == .trailer ? nil : rules
        v.speedLimitKmh = speedLimit
        try? context.save()
        if v.id.uuidString == store.settings.currentVehicleID {
            VehicleLog.applyRules(v.id.uuidString, context: context, store: store)
            AutoDriveDetector.shared.update(settings: store.settings)
        }
        // First vehicle/trailer added becomes the current one.
        if kind == .trailer, store.settings.currentTrailerID.isEmpty { store.settings.currentTrailerID = v.id.uuidString }
        if kind != .trailer, store.settings.currentVehicleID.isEmpty { store.settings.currentVehicleID = v.id.uuidString }
        dismiss()
    }
}

/// The vehicle and trailer in use, on Today: choose, change mid-shift (each vehicle's mileage is kept
/// separately), edit, or add a new one. Shows height, rules and overspeed threshold.
struct CurrentVehicleCard: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \VehicleUse.start) private var uses: [VehicleUse]
    @State private var editing: Vehicle?
    @State private var adding: VehicleKind?

    var body: some View {
        let unit = vehicles.first { $0.id.uuidString == store.settings.currentVehicleID }
        let trailer = vehicles.first { $0.id.uuidString == store.settings.currentTrailerID }
        let maxHeight = max(unit?.height ?? 0, trailer?.height ?? 0)
        let shiftUses = uses.filter { ($0.end ?? .now) > Date.now.addingTimeInterval(-16 * 3600) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if maxHeight > 0 {
                    VStack(spacing: 0) {
                        Text(String(format: "%.2f m", maxHeight)).font(.caption.weight(.heavy).monospacedDigit())
                        Text(Fmt.feetInches(maxHeight)).font(.caption2.weight(.bold).monospacedDigit())
                    }
                    .foregroundStyle(.black)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(.white))
                    .overlay(Circle().stroke(.red, lineWidth: 5))
                    .accessibilityLabel(String(format: "Height %.2f metres", maxHeight))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(unit == nil ? "No vehicle chosen" : "Driving").font(.caption).foregroundStyle(.secondary)
                    Text(unit?.displayName ?? "Choose your vehicle").font(.headline).lineLimit(1)
                    if let trailer { Label(trailer.displayName, systemImage: "shippingbox").font(.caption).lineLimit(1) }
                    HStack(spacing: 6) {
                        let rules = store.settings.currentRegime
                        Text(rules == .exempt ? "Exempt" : rules.shortTitle)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((rules == .assimilated ? Color.blue : Color.orange).opacity(0.15), in: Capsule())
                        Text("Overspeed \(Int(AutoDriveDetector.shared.speedLimitKmh)) km/h").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Menu {
                    Section(unit == nil ? "Choose vehicle" : "Change to") {
                        ForEach(vehicles.filter { $0.kind != .trailer && $0.id.uuidString != store.settings.currentVehicleID }) { v in
                            Button(v.displayName) { choose(v.id.uuidString) }
                        }
                    }
                    Button("Add a new vehicle", systemImage: "plus") { adding = .tractor }
                    if unit != nil { Button("No vehicle", systemImage: "xmark") { choose("") } }
                } label: {
                    Label(unit == nil ? "Choose" : "Change vehicle", systemImage: "arrow.triangle.2.circlepath")
                }
                Menu {
                    ForEach(vehicles.filter { $0.kind == .trailer }) { v in
                        Button(v.displayName) { store.settings.currentTrailerID = v.id.uuidString }
                    }
                    Button("Add a new trailer", systemImage: "plus") { adding = .trailer }
                    Button("No trailer") { store.settings.currentTrailerID = "" }
                } label: {
                    Label("Trailer", systemImage: "shippingbox")
                }
                if let unit {
                    Button { editing = unit } label: { Label("Edit", systemImage: "pencil") }
                }
            }
            .buttonStyle(.bordered)
            .font(.caption.weight(.semibold))
            if shiftUses.count > 1 {
                Text("This shift: " + shiftUses.map { u in
                    (vehicles.first { $0.id.uuidString == u.vehicleID }?.registration ?? "Vehicle") + " " + Fmt.time(u.start)
                }.joined(separator: " → "))
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(item: $editing) { VehicleEditor(vehicle: $0) }
        .sheet(item: $adding) { VehicleEditor(vehicle: nil, newKind: $0) }
    }

    private func choose(_ id: String) {
        VehicleLog.select(id, context: context, store: store)
        AutoDriveDetector.shared.update(settings: store.settings)
    }
}

struct ScannedReg: Identifiable {
    var reg: String
    var id: String { reg }
}
