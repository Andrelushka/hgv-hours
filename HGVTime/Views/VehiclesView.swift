import SwiftUI
import SwiftData

/// Saved vehicles and trailers: add once, then select, edit or delete.
struct VehiclesView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var editing: Vehicle?
    @State private var adding: VehicleKind?

    var body: some View {
        let units = vehicles.filter { $0.kind != .trailer }
        let trailers = vehicles.filter { $0.kind == .trailer }
        List {
            Section {
                ForEach(units) { v in row(v, current: store.settings.currentVehicleID == v.id.uuidString) {
                    store.settings.currentVehicleID = store.settings.currentVehicleID == v.id.uuidString ? "" : v.id.uuidString
                } }
                .onDelete { delete(units, $0) }
                Button { adding = .tractor } label: { Label("Add vehicle", systemImage: "plus.circle.fill") }
            } header: {
                Text("Vehicles")
            } footer: {
                Text("Tap the circle to choose the vehicle you're driving. Its height shows on the Today screen.")
            }
            Section("Trailers") {
                ForEach(trailers) { v in row(v, current: store.settings.currentTrailerID == v.id.uuidString) {
                    store.settings.currentTrailerID = store.settings.currentTrailerID == v.id.uuidString ? "" : v.id.uuidString
                } }
                .onDelete { delete(trailers, $0) }
                Button { adding = .trailer } label: { Label("Add trailer", systemImage: "plus.circle.fill") }
            }
        }
        .navigationTitle("Vehicles & trailers")
        .sheet(item: $editing) { VehicleEditor(vehicle: $0) }
        .sheet(item: $adding) { VehicleEditor(vehicle: nil, newKind: $0) }
    }

    private func row(_ v: Vehicle, current: Bool, select: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: select) {
                Image(systemName: current ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(current ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            Button { editing = v } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(v.displayName, systemImage: v.kind.symbol).font(.subheadline.weight(.semibold))
                    if !v.specsLine.isEmpty {
                        Text(v.specsLine).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { remove(v) }
            Button("Edit", systemImage: "pencil") { editing = v }.tint(.blue)
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

    init(vehicle: Vehicle?, newKind: VehicleKind = .tractor) {
        self.vehicle = vehicle
        let k = vehicle?.kind ?? newKind
        _kind = State(initialValue: k)
        _registration = State(initialValue: vehicle?.registration ?? "")
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
                    TextField(kind == .trailer ? "Trailer number / ID" : "Registration", text: $registration)
                        .textInputAutocapitalization(.characters)
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
                    Section("Fuel") {
                        Picker("Fuel", selection: $fuel) {
                            ForEach(FuelType.allCases) { Text($0.title).tag($0) }
                        }
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
            HStack(spacing: 4) {
                TextField("0.00", value: value, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                Text(unit).foregroundStyle(.secondary)
            }
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
        try? context.save()
        // First vehicle/trailer added becomes the current one.
        if kind == .trailer, store.settings.currentTrailerID.isEmpty { store.settings.currentTrailerID = v.id.uuidString }
        if kind != .trailer, store.settings.currentVehicleID.isEmpty { store.settings.currentVehicleID = v.id.uuidString }
        dismiss()
    }
}

/// Shows the current vehicle and trailer on Today, with quick switching.
struct CurrentVehicleCard: View {
    @Environment(SettingsStore.self) private var store
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    var body: some View {
        let unit = vehicles.first { $0.id.uuidString == store.settings.currentVehicleID }
        let trailer = vehicles.first { $0.id.uuidString == store.settings.currentTrailerID }
        let maxHeight = max(unit?.height ?? 0, trailer?.height ?? 0)
        HStack(spacing: 10) {
            if maxHeight > 0 {
                VStack(spacing: 0) {
                    Text(String(format: "%.2f", maxHeight)).font(.headline.weight(.heavy).monospacedDigit())
                    Text("m").font(.caption2.weight(.bold))
                }
                .foregroundStyle(.black)
                .frame(width: 54, height: 54)
                .background(Circle().fill(.white))
                .overlay(Circle().stroke(.red, lineWidth: 5))
                .accessibilityLabel(String(format: "Height %.2f metres", maxHeight))
            }
            VStack(alignment: .leading, spacing: 2) {
                Menu {
                    ForEach(vehicles.filter { $0.kind != .trailer }) { v in
                        Button(v.displayName) { store.settings.currentVehicleID = v.id.uuidString }
                    }
                    Button("None") { store.settings.currentVehicleID = "" }
                } label: {
                    Label(unit?.displayName ?? "Choose vehicle", systemImage: unit?.kind.symbol ?? "box.truck")
                        .font(.subheadline.weight(.semibold))
                }
                Menu {
                    ForEach(vehicles.filter { $0.kind == .trailer }) { v in
                        Button(v.displayName) { store.settings.currentTrailerID = v.id.uuidString }
                    }
                    Button("No trailer") { store.settings.currentTrailerID = "" }
                } label: {
                    Label(trailer?.displayName ?? "No trailer", systemImage: "shippingbox")
                        .font(.caption)
                }
                if let specs = unit?.specsLine, !specs.isEmpty {
                    Text(specs).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            NavigationLink { VehiclesView() } label: {
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
