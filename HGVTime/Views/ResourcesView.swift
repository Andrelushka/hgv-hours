import SwiftUI
import SwiftData

/// Fuel, AdBlue, tacho rolls and other things used, with monthly totals.
struct ResourcesView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ResourceLog.date, order: .reverse) private var logs: [ResourceLog]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var editing: ResourceLog?
    @State private var adding: ResourceKind?

    var body: some View {
        let cal = Calendar.hgv
        let months = Dictionary(grouping: logs) { cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        List {
            Section {
                HStack {
                    ForEach([ResourceKind.diesel, .adblue, .tachoRoll], id: \.self) { kind in
                        Button { adding = kind } label: {
                            VStack(spacing: 4) {
                                Image(systemName: kind.symbol).font(.title3)
                                Text(kind.title).font(.caption2.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    Menu {
                        ForEach(ResourceKind.allCases) { kind in
                            Button(kind.title, systemImage: kind.symbol) { adding = kind }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus").font(.title3)
                            Text("Other").font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            if logs.isEmpty {
                ContentUnavailableView("Nothing logged yet", systemImage: "fuelpump",
                                       description: Text("Log fuel, AdBlue and tacho rolls as you use them. Totals per month appear here."))
            }
            ForEach(months.keys.sorted(by: >), id: \.self) { month in
                let items = months[month] ?? []
                Section {
                    ForEach(items) { log in
                        Button { editing = log } label: { row(log) }
                            .foregroundStyle(.primary)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    context.delete(log)
                                    try? context.save()
                                }
                            }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(month.formatted(.dateTime.month(.wide).year()))
                        Text(totals(items)).font(.caption2).textCase(nil)
                    }
                }
            }
        }
        .navigationTitle("Fuel & resources")
        .sheet(item: $editing) { ResourceEditor(log: $0) }
        .sheet(item: $adding) { ResourceEditor(log: nil, kind: $0) }
    }

    private func row(_ log: ResourceLog) -> some View {
        HStack(spacing: 12) {
            Image(systemName: log.kind.symbol).foregroundStyle(.blue).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(log.kind.title) · \(String(format: "%g", log.quantity)) \(log.kind.unit)").font(.subheadline.weight(.semibold))
                Text([Fmt.dayTime(log.date), log.location, log.odometerKm > 0 ? Fmt.odometer(log.odometerKm, miles: store.settings.useMiles) : ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if log.cost > 0 { Text(Fmt.money(log.cost, symbol: store.settings.pay.currencySymbol)).monospacedDigit() }
        }
    }

    private func totals(_ items: [ResourceLog]) -> String {
        let byKind = Dictionary(grouping: items, by: \.kind)
        var parts = ResourceKind.allCases.compactMap { kind -> String? in
            guard let list = byKind[kind] else { return nil }
            return "\(kind.title) \(String(format: "%g", list.reduce(0) { $0 + $1.quantity })) \(kind.unit)"
        }
        let cost = items.reduce(0) { $0 + $1.cost }
        if cost > 0 { parts.append("cost \(Fmt.money(cost, symbol: store.settings.pay.currencySymbol))") }
        return parts.joined(separator: " · ")
    }
}

struct ResourceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    private let log: ResourceLog?
    @State private var kind: ResourceKind
    @State private var date: Date
    @State private var quantity: Double
    @State private var cost: Double
    @State private var odometer: Double
    @State private var location: String
    @State private var vehicleID: String
    @State private var notes: String

    init(log: ResourceLog?, kind: ResourceKind = .diesel) {
        self.log = log
        _kind = State(initialValue: log?.kind ?? kind)
        _date = State(initialValue: log?.date ?? .now)
        _quantity = State(initialValue: log?.quantity ?? (kind == .tachoRoll ? 1 : 0))
        _cost = State(initialValue: log?.cost ?? 0)
        _odometer = State(initialValue: log?.odometerKm ?? 0)
        _location = State(initialValue: log?.location ?? "")
        _vehicleID = State(initialValue: log?.vehicleID ?? "")
        _notes = State(initialValue: log?.notes ?? "")
    }

    var body: some View {
        let miles = store.settings.useMiles
        NavigationStack {
            Form {
                Section {
                    Picker("What", selection: $kind) {
                        ForEach(ResourceKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    NowDatePicker("When", selection: $date)
                    LabeledContent("Quantity") {
                        HStack(spacing: 4) {
                            TextField("0", value: $quantity.emptyIfZero, format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 90)
                            Text(kind.unit).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Cost") {
                        HStack(spacing: 2) {
                            Text(store.settings.pay.currencySymbol).foregroundStyle(.secondary)
                            TextField("0.00", value: $cost.emptyIfZero, format: .number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 90)
                        }
                    }
                }
                Section {
                    Picker("Vehicle", selection: $vehicleID) {
                        Text("Not set").tag("")
                        ForEach(vehicles.filter { $0.kind != .trailer }) { Text($0.displayName).tag($0.id.uuidString) }
                    }
                    LabeledContent("Odometer") {
                        HStack(spacing: 4) {
                            TextField("0", value: Binding(
                                get: { miles ? (odometer / 1.609344).rounded() : odometer.rounded() },
                                set: { odometer = miles ? $0 * 1.609344 : $0 }).emptyIfZero, format: .number.precision(.fractionLength(0)))
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
                            Text(miles ? "mi" : "km").foregroundStyle(.secondary)
                        }
                    }
                    TextField("Location, e.g. fuel station", text: $location)
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle(log == nil ? "Log \(kind.title.lowercased())" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .onAppear {
                if log == nil && vehicleID.isEmpty { vehicleID = store.settings.currentVehicleID }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let l = log ?? ResourceLog(date: date, kind: kind)
                        if log == nil {
                            context.insert(l)
                            EventRecorder.log(.fuel, title: kind.title, detail: "\(String(format: "%g", quantity)) \(kind.unit)\(location.isEmpty ? "" : " at \(location)")",
                                              at: date, context: context, settings: store.settings)
                        }
                        l.kind = kind
                        l.date = date
                        l.quantity = quantity
                        l.cost = cost
                        l.odometerKm = odometer
                        l.location = location
                        l.vehicleID = vehicleID
                        l.notes = notes
                        if odometer > 0, let v = vehicles.first(where: { $0.id.uuidString == vehicleID }), odometer > v.odometerKm {
                            v.odometerKm = odometer
                        }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(quantity <= 0)
                }
            }
        }
    }
}

/// Today's mileage (start/end odometer and GPS distance) and quick fuel logging.
/// Today's mileage: one block per vehicle used (start, end and distance), with the end reading
/// worked out from GPS until you type it. Readings go into the summary and day reports.
struct DayMileageCard: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \DayRecord.day) private var records: [DayRecord]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \VehicleUse.start) private var allUses: [VehicleUse]
    var now: Date
    @State private var entering: Reading?
    @State private var value: Double = 0
    @State private var adding: ResourceKind?

    /// Which reading is being typed: a vehicle use's start/end, or the day record (no vehicle chosen).
    struct Reading: Identifiable {
        var use: VehicleUse?
        var start: Bool
        var id: String { (use?.id.uuidString ?? "day") + (start ? "s" : "e") }
    }

    /// Uses of the same vehicle one after another (split only by trailer changes) shown as one block.
    struct VehicleBlock: Identifiable {
        var uses: [VehicleUse]
        var id: UUID { uses[0].id }
        var first: VehicleUse { uses[0] }
        var last: VehicleUse { uses[uses.count - 1] }
        var distanceKm: Double { uses.reduce(0) { $0 + $1.distanceKm } }
    }

    static func blocks(_ uses: [VehicleUse]) -> [VehicleBlock] {
        var out: [VehicleBlock] = []
        for u in uses {
            if let lastBlock = out.last, lastBlock.last.vehicleID == u.vehicleID { out[out.count - 1].uses.append(u) } else { out.append(VehicleBlock(uses: [u])) }
        }
        return out
    }

    var body: some View {
        let miles = store.settings.useMiles
        let cal = Calendar.hgv
        let dayStart = cal.startOfDay(for: now)
        let uses = allUses.filter { $0.start < dayStart.addingTimeInterval(86_400) && ($0.end ?? .now) > dayStart }
        let blocks = Self.blocks(uses)
        let record = records.first { cal.isDate($0.day, inSameDayAs: now) }
        // Readings typed before a vehicle was chosen still count (unless they're for a vehicle listed below).
        let recordCounts = record.map { r in r.distanceKm > 0 && !uses.contains { $0.vehicleID == r.vehicleID && !r.vehicleID.isEmpty } } ?? false
        let total = blocks.reduce(0) { $0 + $1.distanceKm } + (uses.isEmpty || recordCounts ? (record?.distanceKm ?? 0) : 0)
        // After a vehicle change: ask for the readings that are missing.
        let missing = blocks.enumerated().flatMap { i, b -> [String] in
            let name = vehicles.first { $0.id.uuidString == b.first.vehicleID }?.displayName ?? String(localized: "Vehicle")
            var m: [String] = []
            if b.first.startOdometerKm == 0 { m.append(String(localized: "start of \(name)")) }
            if i < blocks.count - 1, !b.last.endEdited { m.append(String(localized: "end of \(name)")) }
            return m
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Mileage today", systemImage: "road.lanes").font(.subheadline.weight(.semibold))
                Spacer()
                Text(Fmt.distance(total, miles: miles)).font(.headline.monospacedDigit())
            }
            if blocks.count > 1, !missing.isEmpty {
                Label("Vehicle changed — enter the mileage: \(missing.joined(separator: ", "))", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            if uses.isEmpty || recordCounts {
                if !uses.isEmpty { Text("Before choosing a vehicle").font(.caption.weight(.semibold)) }
                HStack(spacing: 8) {
                    odometerButton("Start", km: record?.startOdometerKm ?? 0, auto: false, reading: Reading(use: nil, start: true), miles: miles)
                    odometerButton("End", km: record?.endOdometerKm ?? 0, auto: false, reading: Reading(use: nil, start: false), miles: miles)
                }
                if let gps = record?.gpsKm, gps > 0 {
                    Text("GPS (in-cab mode): \(Fmt.distance(gps, miles: miles))").font(.caption).foregroundStyle(.secondary)
                }
                if !uses.isEmpty { Divider() }
            }
            ForEach(Array(blocks.enumerated()), id: \.element.id) { i, b in
                let v = vehicles.first { $0.id.uuidString == b.first.vehicleID }
                let trailers = b.uses.compactMap { u in vehicles.first { $0.id.uuidString == u.trailerID } }
                let trailerNames = Array(NSOrderedSet(array: trailers.map { $0.registration.isEmpty ? $0.displayName : $0.registration })).compactMap { $0 as? String }
                let gps = b.uses.reduce(0) { $0 + $1.gpsKm }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label { Text((v?.displayName ?? "Vehicle") + (trailerNames.isEmpty ? "" : " + " + trailerNames.joined(separator: ", "))) }
                              icon: { (v?.kind ?? .rigid).icon }
                              .font(.caption.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text("\(Fmt.time(b.first.start))–\(b.last.end.map(Fmt.time) ?? "now") · \(Fmt.distance(b.distanceKm, miles: miles))")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        odometerButton("Start", km: b.first.startOdometerKm, auto: false, reading: Reading(use: b.first, start: true), miles: miles,
                                       needed: blocks.count > 1 && b.first.startOdometerKm == 0)
                        odometerButton(b.last.endEdited ? "End" : "End (auto)", km: b.last.effectiveEndKm, auto: !b.last.endEdited,
                                       reading: Reading(use: b.last, start: false), miles: miles,
                                       needed: i < blocks.count - 1 && !b.last.endEdited)
                    }
                    if gps > 0 {
                        Text("GPS: \(Fmt.distance(gps, miles: miles))\(b.last.endEdited ? "" : " — end worked out from GPS, tap to correct")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if b.id != blocks.last?.id { Divider() }
            }
            if blocks.count > 1 {
                Text("Each vehicle's miles are added together for the day.").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button { adding = .diesel } label: { Label("Fuel", systemImage: "fuelpump.fill") }
                Button { adding = .adblue } label: { Label("AdBlue", systemImage: "drop.fill") }
                Button { adding = .tachoRoll } label: { Label("Tacho roll", systemImage: "scroll.fill") }
            }
            .buttonStyle(.bordered)
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(item: $adding) { ResourceEditor(log: nil, kind: $0) }
        .alert(entering?.start == true ? "Start odometer" : "End odometer",
               isPresented: Binding(get: { entering != nil }, set: { if !$0 { entering = nil } })) {
            TextField(miles ? "Miles" : "km", value: $value.emptyIfZero, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
            Button("Save") { save(miles: miles) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the reading in \(miles ? "miles" : "km"). It goes into the summary and day reports.")
        }
    }

    private func odometerButton(_ title: String, km: Double, auto: Bool, reading: Reading, miles: Bool, needed: Bool = false) -> some View {
        Button {
            let fallback = vehicles.first { $0.id.uuidString == (reading.use?.vehicleID ?? store.settings.currentVehicleID) }?.odometerKm ?? 0
            let current = km > 0 ? km : fallback
            value = miles ? (current / 1.609344).rounded() : current.rounded()
            entering = reading
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title)).font(.caption2).foregroundStyle(.secondary)
                Text(km > 0 ? Fmt.odometer(km, miles: miles) : "Enter")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(auto ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(needed ? .orange : nil)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(needed ? Color.orange : .clear, lineWidth: 1.5))
    }

    private func save(miles: Bool) {
        guard let reading = entering else { return }
        let km = miles ? value * 1.609344 : value
        if let use = reading.use {
            VehicleLog.setReading(use, start: reading.start, km: km, context: context)
        } else {
            let record = ActivityController.dayRecord(for: now, context: context)
            if record.vehicleID.isEmpty { record.vehicleID = store.settings.currentVehicleID }
            if reading.start { record.startOdometerKm = km } else { record.endOdometerKm = km }
            if let v = vehicles.first(where: { $0.id.uuidString == record.vehicleID }), km > v.odometerKm { v.odometerKm = km }
            try? context.save()
        }
        entering = nil
    }
}
