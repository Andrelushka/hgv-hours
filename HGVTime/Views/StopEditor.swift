import MapKit
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
    @State var stop: PlanStop
    var isNew: Bool
    var onSave: (PlanStop) -> Void
    var onDelete: (() -> Void)?

    @State private var search = AddressSearch()
    @State private var searching = false
    @State private var hasBooking: Bool

    init(stop: PlanStop, isNew: Bool, onSave: @escaping (PlanStop) -> Void, onDelete: (() -> Void)? = nil) {
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
                    Picker("Type", selection: $stop.kind) {
                        ForEach(PlanStop.Kind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    row("Company / site", text: Binding(get: { stop.company ?? "" }, set: { stop.company = $0 }), prompt: "e.g. Tesco Daventry DC")
                } header: {
                    Text("Stop")
                }

                Section {
                    TextField("Search postcode, address or company", text: Binding(get: { search.query }, set: { search.query = $0; searching = !$0.isEmpty }))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if searching {
                        ForEach(search.results, id: \.self) { r in
                            Button {
                                Task { await choose(r) }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.title).font(.subheadline.weight(.semibold))
                                    if !r.subtitle.isEmpty { Text(r.subtitle).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        if search.results.isEmpty { Text("No matches yet — keep typing, or fill in below.").font(.caption).foregroundStyle(.secondary) }
                    }
                    row("Address", text: Binding(get: { stop.address ?? stop.place }, set: { stop.address = $0; stop.place = $0 }), prompt: "Street, town", axis: .vertical)
                    row("Postcode", text: Binding(get: { stop.postcode ?? "" }, set: { stop.postcode = $0.uppercased() }), prompt: "NN11 8XX")
                    if stop.latitude != nil {
                        Label("Location found", systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.green)
                    }
                } header: {
                    Text("Address")
                } footer: {
                    Text("Search uses Apple Maps. Pick a result to fill the address and map location, or type it yourself.")
                }

                Section("Booking") {
                    Toggle("Booked time", isOn: $hasBooking)
                    if hasBooking {
                        DatePicker("Time", selection: Binding(get: { stop.bookingTime ?? .now }, set: { stop.bookingTime = $0 }))
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

    private func choose(_ completion: MKLocalSearchCompletion) async {
        searching = false
        guard let item = await search.resolve(completion) else {
            stop.address = [completion.title, completion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
            stop.place = stop.address ?? ""
            return
        }
        let pm = item.placemark
        if (stop.company ?? "").isEmpty, let name = item.name, name != pm.thoroughfare { stop.company = name }
        let street = [pm.subThoroughfare, pm.thoroughfare].compactMap { $0 }.joined(separator: " ")
        stop.address = [street, pm.locality ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        if (stop.address ?? "").isEmpty { stop.address = completion.subtitle.isEmpty ? completion.title : completion.subtitle }
        stop.place = stop.address ?? ""
        stop.postcode = pm.postalCode ?? stop.postcode
        stop.latitude = pm.coordinate.latitude
        stop.longitude = pm.coordinate.longitude
        search.query = ""
    }
}

/// Summary row for a stop in the plan editor.
struct StopRow: View {
    var stop: PlanStop
    var number: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(stop.kind == .collection ? Color.orange : .indigo).frame(width: 28, height: 28)
                Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(stop.displayName).font(.subheadline.weight(.semibold))
                    Spacer()
                    if !stop.bookingText.isEmpty { Text(stop.bookingText).font(.caption.weight(.semibold).monospacedDigit()) }
                }
                Text(stop.kind.title + (stop.fullAddress.isEmpty ? "" : " · " + stop.fullAddress)).font(.caption).foregroundStyle(.secondary)
                let refs = [stop.reference.isEmpty ? "" : "Booking \(stop.reference)", (stop.orderReference ?? "").isEmpty ? "" : "Ref \(stop.orderReference!)",
                            stop.pallets.isEmpty ? "" : "\(stop.pallets) plt", stop.weight ?? ""].filter { !$0.isEmpty }
                if !refs.isEmpty { Text(refs.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}
