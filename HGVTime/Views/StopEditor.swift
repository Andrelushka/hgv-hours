import MapKit
import SwiftData
import SwiftUI

/// Address / postcode search using Apple Maps as you type.
@MainActor
@Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    var query = "" {
        didSet { completer.queryFragment = query }
    }
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        // Bias results towards Great Britain.
        completer.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 54.0, longitude: -2.5),
                                              span: MKCoordinateSpan(latitudeDelta: 11, longitudeDelta: 11))
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = completer.results
        Task { @MainActor in self.results = Array(r.prefix(12)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    /// Full details for a chosen result.
    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        let response = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        return response?.mapItems.first
    }
}

/// One stop on a job, with room for every detail.
struct StopEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Vehicle.createdAt, order: .reverse) private var vehicles: [Vehicle]
    @State var stop: PlanStop
    var isNew: Bool
    var onSave: (PlanStop) -> Void
    var onDelete: (() -> Void)?
    /// The trailer you'll have when you get here, by the plan (for the drop choices).
    var onBoard: TrailerRef?

    @State private var hasBooking: Bool

    init(stop: PlanStop, isNew: Bool, onBoard: TrailerRef? = nil, onSave: @escaping (PlanStop) -> Void, onDelete: (() -> Void)? = nil) {
        self.onBoard = onBoard
        var stop = stop
        // Dropping a trailer: start from the one you'll have.
        if isNew, stop.kind == .trailerDrop, stop.equipmentID == nil, stop.equipmentRef == nil, let onBoard {
            stop.equipmentID = onBoard.id.isEmpty ? nil : onBoard.id
            stop.equipmentRef = onBoard.ref.isEmpty ? nil : onBoard.ref
        }
        // New collections usually leave loaded, deliveries empty — change it if not.
        if isNew, stop.loadAfter == nil {
            if stop.kind == .collection { stop.loadAfter = "loaded" } else if stop.kind == .delivery { stop.loadAfter = "empty" }
        }
        _stop = State(initialValue: stop)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _hasBooking = State(initialValue: stop.bookingTime != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(PlanStop.Kind.allCases) { k in
                                let on = stop.kind == k
                                Button { stop.kind = k } label: {
                                    Label(k.title, systemImage: k.symbol)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .foregroundStyle(on ? .white : k.color)
                                        .background(on ? AnyShapeStyle(k.color) : AnyShapeStyle(k.color.opacity(0.12)), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    if stop.kind == .other {
                        row("Custom stop name", text: Binding(get: { stop.customTitle ?? "" }, set: { stop.customTitle = $0 }),
                            prompt: "e.g. Weighbridge, Customs, Wash, Tip")
                    }
                } header: {
                    Text("Stop type")
                }

                if stop.kind != .vehiclePickup && stop.kind != .vehicleDrop {
                    Section {
                        Picker("Trailer when you leave", selection: Binding(get: { stop.loadAfter ?? "" },
                                                                            set: { stop.loadAfter = $0.isEmpty ? nil : $0 })) {
                            Text("Not set").tag("")
                            Text("Loaded").tag("loaded")
                            Text("Empty").tag("empty")
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Loaded or empty")
                    } footer: {
                        Text("When you tap Departed, the app switches to running loaded or empty, so your mileage is split.")
                    }
                }

                if !stop.isEquipmentStop {
                    let trailers = vehicles.filter { $0.kind == .trailer }
                    Section {
                        Picker("Drop trailer", selection: Binding(get: { stop.dropTrailerID ?? "" },
                                                                  set: { stop.dropTrailerID = $0.isEmpty ? nil : $0 })) {
                            Text("No").tag("")
                            if let onBoard {
                                Text("The trailer I'll have: \(onBoard.name(in: vehicles))").tag("current")
                            } else {
                                Text("The trailer I have").tag("current")
                            }
                            ForEach(trailers.filter { $0.id.uuidString != onBoard?.id }) { Text($0.displayName).tag($0.id.uuidString) }
                        }
                        Picker("Pick up trailer", selection: Binding(get: { stop.pickTrailerID ?? "" },
                                                                     set: { stop.pickTrailerID = $0.isEmpty ? nil : $0 })) {
                            Text("No / not in my list").tag("")
                            ForEach(trailers) { Text($0.displayName).tag($0.id.uuidString) }
                        }
                        if (stop.pickTrailerID ?? "").isEmpty {
                            row("Trailer to pick up (number)", text: Binding(get: { stop.pickTrailerRef ?? "" }, set: { stop.pickTrailerRef = $0 }),
                                prompt: "e.g. T1234")
                        }
                        Picker("Swap vehicle", selection: Binding(get: { stop.pickVehicleID ?? "" },
                                                                  set: { stop.pickVehicleID = $0.isEmpty ? nil : $0 })) {
                            Text("No / not in my list").tag("")
                            ForEach(vehicles.filter { $0.kind != .trailer }) { Text($0.displayName).tag($0.id.uuidString) }
                        }
                        if (stop.pickVehicleID ?? "").isEmpty {
                            row("Vehicle to swap to (registration)", text: Binding(get: { stop.pickVehicleRef ?? "" }, set: { stop.pickVehicleRef = $0 }),
                                prompt: "e.g. AB12 CDE")
                        }
                    } header: {
                        Text("Trailer and vehicle at this stop")
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(onBoard.map { String(localized: "By the plan you'll arrive here with \($0.name(in: vehicles)).") } ?? String(localized: "By the plan you won't have a trailer when you get here."))
                            Text("Swap trailers here: drop the one you have and/or pick up another (or leave both on No to run solo). When you tap Departed, your current trailer is updated.")
                        }
                    }
                }

                if stop.isEquipmentStop {
                    let trailer = stop.isTrailerStop
                    let list = vehicles.filter { trailer ? $0.kind == .trailer : $0.kind != .trailer }
                    Section {
                        Picker(trailer ? "Trailer" : "Vehicle", selection: Binding(get: { stop.equipmentID ?? "" },
                                                                                  set: { stop.equipmentID = $0.isEmpty ? nil : $0 })) {
                            Text("Not in my list").tag("")
                            // When dropping, the trailer you'll have comes first.
                            let first = stop.kind == .trailerDrop ? list.filter { $0.id.uuidString == onBoard?.id } : []
                            ForEach(first) { Text("\($0.displayName) — on board").tag($0.id.uuidString) }
                            ForEach(list.filter { v in !first.contains { $0.id == v.id } }) { Text($0.displayName).tag($0.id.uuidString) }
                        }
                        if stop.kind == .trailerDrop, let onBoard {
                            Text("On board by the plan: \(onBoard.name(in: vehicles))").font(.caption).foregroundStyle(.secondary)
                        } else if stop.kind == .trailerDrop {
                            Label("By the plan you won't have a trailer here.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if (stop.equipmentID ?? "").isEmpty {
                            row(trailer ? "Trailer number" : "Registration",
                                text: Binding(get: { stop.equipmentRef ?? "" }, set: { stop.equipmentRef = $0 }),
                                prompt: trailer ? "e.g. T1234" : "e.g. AB12 CDE")
                        }
                    } header: {
                        Text(trailer ? "Which trailer" : "Which vehicle")
                    } footer: {
                        switch stop.kind {
                        case .trailerPickup: Text("When you tap Departed here, this trailer becomes your current trailer (if it's in your list).")
                        case .trailerDrop: Text("When you tap Departed here, this trailer is taken off as your current trailer.")
                        case .vehiclePickup: Text("When you tap Departed here, this vehicle becomes your current vehicle (if it's in your list).")
                        default: Text("When you tap Departed here, this vehicle is taken off as your current vehicle.")
                        }
                    }
                }

                Section {
                    AddressLookupFields(
                        address: Binding(get: { stop.address ?? stop.place }, set: { stop.address = $0; stop.place = $0 }),
                        postcode: Binding(get: { stop.postcode ?? "" }, set: { stop.postcode = $0 }),
                        latitude: $stop.latitude, longitude: $stop.longitude,
                        name: Binding(get: { stop.company ?? "" }, set: { stop.company = $0 }),
                        houseNumber: Binding(get: { stop.houseNumber ?? "" }, set: { stop.houseNumber = $0 }),
                        houseName: Binding(get: { stop.houseName ?? "" }, set: { stop.houseName = $0 }),
                        flat: Binding(get: { stop.flat ?? "" }, set: { stop.flat = $0 }))
                } header: {
                    Text("Address")
                } footer: {
                    Text("Search by postcode and pick the address from the list, type it yourself, or pinpoint the exact gate or bay on the map.")
                }

                Section("Booking") {
                    Toggle("Booked time", isOn: $hasBooking)
                    if hasBooking {
                        NowDatePicker("Time", selection: Binding(get: { stop.bookingTime ?? .now }, set: { stop.bookingTime = $0 }))
                    }
                    row("Booking reference", text: $stop.reference, prompt: "e.g. BK123456")
                }

                Section("Load") {
                    row(stop.kind == .collection ? "Collection ref" : "Delivery / order ref",
                        text: Binding(get: { stop.orderReference ?? "" }, set: { stop.orderReference = $0 }), prompt: "PO / consignment no.")
                    row("Pallets", text: $stop.pallets, prompt: "e.g. 26", keyboard: .numberPad)
                    row("Weight", text: Binding(get: { stop.weight ?? "" }, set: { stop.weight = $0 }), prompt: "e.g. 18 t")
                }

                Section("Contact") {
                    row("Name", text: Binding(get: { stop.contactName ?? "" }, set: { stop.contactName = $0 }), prompt: "Goods-in / transport office")
                    row("Phone", text: Binding(get: { stop.contactPhone ?? "" }, set: { stop.contactPhone = $0 }), prompt: "", keyboard: .phonePad)
                    if let phone = stop.contactPhone, !phone.isEmpty, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                        Link(destination: url) { Label("Call", systemImage: "phone.fill") }
                    }
                }

                Section("Notes") {
                    TextField("Gate code, bay, instructions…", text: $stop.notes, axis: .vertical).lineLimit(2...6)
                }

                if let onDelete, !isNew {
                    Section {
                        Button("Delete stop", role: .destructive) { onDelete(); dismiss() }
                    }
                }
            }
            .navigationTitle(isNew ? "New stop" : "Stop")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !hasBooking { stop.bookingTime = nil }
                        if let b = stop.bookingTime { stop.time = Fmt.time(b) }
                        onSave(stop)
                        dismiss()
                    }
                }
            }
        }
    }

    private func row(_ label: String, text: Binding<String>, prompt: String, axis: Axis = .horizontal, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: text, axis: axis).keyboardType(keyboard)
        }
    }
}

/// Summary row for a stop in the plan editor.
struct StopRow: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    var stop: PlanStop
    var number: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StopNumberBadge(text: "\(number)", color: stop.kind.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(stop.displayName).font(.subheadline.weight(.semibold))
                    Spacer()
                    if !stop.bookingText.isEmpty { Text(stop.bookingText).font(.caption.weight(.semibold).monospacedDigit()) }
                }
                let equipment = stop.equipmentName(in: vehicles)
                Text([stop.kindTitle, equipment, stop.trailerChangeText(in: vehicles), stop.vehicleSwapText(in: vehicles),
                      stop.loadAfter == nil ? "" : "→ " + LoadState.title(stop.loadAfter), stop.fullAddress].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                let refs = [stop.reference.isEmpty ? "" : "Booking \(stop.reference)", (stop.orderReference ?? "").isEmpty ? "" : "Ref \(stop.orderReference!)",
                            stop.pallets.isEmpty ? "" : "\(stop.pallets) plt", stop.weight ?? ""].filter { !$0.isEmpty }
                if !refs.isEmpty { Text(refs.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}


/// Stop number in a coloured circle (or S / F for start and finish).
struct StopNumberBadge: View {
    var text: String
    var color: Color
    var size: CGFloat = 28
    var done = false

    var body: some View {
        ZStack {
            Circle().fill(done ? Color.green : color).frame(width: size, height: size)
            if done {
                Image(systemName: "checkmark").font(.system(size: size * 0.42, weight: .heavy)).foregroundStyle(.white)
            } else {
                Text(text).font(.system(size: size * 0.45, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
            }
        }
        .accessibilityLabel(text)
    }
}
