import SwiftData
import SwiftUI

/// Today: the full vehicle (walk-round) check — optional, hide it in Customise Today.
struct VehicleCheckTile: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \VehicleCheck.date, order: .reverse) private var checks: [VehicleCheck]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var opening: VehicleCheck?
    @State private var showingList = false

    var body: some View {
        let today = checks.first { Calendar.hgv.isDateInToday($0.date) }
        HStack(spacing: 12) {
            Image(systemName: "checklist.checked")
                .font(.title2).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background((today?.signed == true ? (today!.defectCount > 0 ? Color.orange : Color.green) : Color.gray).gradient,
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("Vehicle check").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let today {
                    Text(today.signed
                         ? (today.defectCount > 0 ? "Done · \(today.defectCount) defect(s) reported" : "Done · no defects")
                         : "In progress · \(today.openCount) left")
                        .font(.headline)
                    Text(today.columns.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Not done today").font(.headline)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Button(today == nil ? "Start" : "Open") { opening = today ?? newCheck() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button("History") { showingList = true }.font(.caption)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(item: $opening) { c in NavigationStack { VehicleCheckView(check: c) } }
        .sheet(isPresented: $showingList) { NavigationStack { VehicleCheckListView() } }
    }

    /// Today's check with your current vehicle and trailer as columns.
    private func newCheck() -> VehicleCheck {
        let c = VehicleCheck(driverName: store.settings.driverName)
        let unit = vehicles.first { $0.id.uuidString == store.settings.currentVehicleID }
        let trailer = vehicles.first { $0.id.uuidString == store.settings.currentTrailerID }
        var cols = [unit?.registration.isEmpty == false ? unit!.registration : String(localized: "Vehicle")]
        var trailers = [false]
        var heights = [unit?.height ?? 0]
        if let trailer {
            cols.append(trailer.registration.isEmpty ? trailer.fleetNumber : trailer.registration)
            trailers.append(true)
            heights.append(trailer.height)
        }
        c.columns = cols
        c.trailerColumns = trailers
        c.heights = heights
        context.insert(c)
        try? context.save()
        return c
    }
}

/// The check itself: one section per vehicle / trailer, tap each line to cycle ✓ → ✗ → N/A.
struct VehicleCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Bindable var check: VehicleCheck
    @State private var defectFor: (key: String, title: String)?
    @State private var defectText = ""
    @State private var addingTrailer = false
    @State private var trailerText = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Date", value: Fmt.dayTime(check.date))
                TextField("Driver name", text: $check.driverName)
            }
            ForEach(Array(check.columns.enumerated()), id: \.offset) { c, name in
                column(c, name: name)
            }
            Section {
                Menu {
                    ForEach(vehicles.filter { $0.kind == .trailer }) { t in
                        Button(t.displayName) { addColumn(t.registration.isEmpty ? t.fleetNumber : t.registration, trailer: true, height: t.height) }
                    }
                    Button("Type a trailer number…") { trailerText = ""; addingTrailer = true }
                } label: {
                    Label("Add a trailer", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Add every trailer you use today (up to 6), like the paper sheet.")
            }
            if !check.defects.isEmpty {
                Section("Defects reported") {
                    ForEach(check.defects.sorted { $0.key < $1.key }, id: \.key) { key, note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(forKey: key)).font(.subheadline.weight(.semibold))
                            Text(note.isEmpty ? "—" : note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                TextField("Defect book reference", text: $check.defectBookRef)
                TextField("Notes", text: $check.notes, axis: .vertical)
                Toggle("I've followed the check procedure and reported all defects", isOn: Binding(
                    get: { check.signed },
                    set: { check.signed = $0; check.signedAt = $0 ? .now : nil }))
            } header: {
                Text("Declaration")
            } footer: {
                Text(check.openCount > 0 ? "\(check.openCount) line(s) not answered yet." : "Every line answered.")
            }
        }
        .navigationTitle("Vehicle check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    try? context.save()
                    if check.signed {
                        EventRecorder.log(.note, title: String(localized: "Vehicle check done"),
                                          detail: check.defectCount > 0 ? "\(check.defectCount) defect(s)" : String(localized: "No defects"),
                                          context: context, settings: store.settings)
                    }
                    dismiss()
                }
            }
        }
        .alert("What's the defect?", isPresented: Binding(get: { defectFor != nil }, set: { if !$0 { defectFor = nil } })) {
            TextField("Describe it (optional)", text: $defectText)
            Button("Save") {
                if let d = defectFor { var all = check.defects; all[d.key] = defectText; check.defects = all }
                defectFor = nil
            }
        } message: {
            Text(defectFor?.title ?? "")
        }
        .alert("Trailer number", isPresented: $addingTrailer) {
            TextField("e.g. T1234", text: $trailerText)
            Button("Add") { if !trailerText.isEmpty { addColumn(trailerText, trailer: true, height: 0) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func column(_ c: Int, name: String) -> some View {
        let trailer = c < check.trailerColumns.count ? check.trailerColumns[c] : false
        let items = CheckItem.all.filter { $0.applies(toTrailer: trailer) }
        Section {
            ForEach(items) { item in
                let key = VehicleCheck.key(item.id, c)
                Button { cycle(item, key: key) } label: {
                    HStack(alignment: .top) {
                        Text(item.title).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        answerBadge(check.answers[key], yesNo: item.answer == .yesNo)
                    }
                }
            }
            HStack {
                Text("Height when leaving").font(.subheadline)
                Spacer()
                TextField("m", value: Binding(
                    get: { c < check.heights.count && check.heights[c] > 0 ? check.heights[c] : nil },
                    set: { v in var h = check.heights; while h.count <= c { h.append(0) }; h[c] = v ?? 0; check.heights = h }),
                          format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
                Text("m").foregroundStyle(.secondary)
                if c < check.heights.count, check.heights[c] > 0 {
                    Text(Fmt.feetInches(check.heights[c])).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Label(name, systemImage: trailer ? "shippingbox.fill" : "box.truck.fill")
                Spacer()
                Button("All ✓") { tickAll(items, column: c) }.font(.caption.weight(.semibold)).textCase(nil)
                if c > 0 {
                    Button(role: .destructive) { removeColumn(c) } label: { Image(systemName: "trash") }
                        .font(.caption).textCase(nil)
                }
            }
        } footer: {
            Text("Tap a line: ✓ satisfactory → ✗ action required → N/A. Yes/No lines: Yes → No → N/A.")
        }
    }

    private func answerBadge(_ a: String?, yesNo: Bool) -> some View {
        let (text, color): (String, Color) = switch a {
        case "ok": ("✓", .green)
        case "defect": ("✗", .red)
        case "yes": (String(localized: "Yes"), .green)
        case "no": (String(localized: "No"), .red)
        case "na": ("N/A", .secondary)
        default: (yesNo ? "Y/N" : "—", .secondary)
        }
        return Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(a == nil ? Color.secondary : .white)
            .frame(minWidth: 44, minHeight: 30)
            .background(a == nil ? Color(.tertiarySystemFill) : (color == .secondary ? Color.gray : color), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cycle(_ item: CheckItem, key: String) {
        var all = check.answers
        let order = item.answer == .yesNo ? ["yes", "no", "na"] : ["ok", "defect", "na"]
        let next: String? = {
            guard let current = all[key], let i = order.firstIndex(of: current) else { return order[0] }
            return i + 1 < order.count ? order[i + 1] : nil
        }()
        all[key] = next
        check.answers = all
        if next == "defect" || next == "no" {
            defectText = check.defects[key] ?? ""
            defectFor = (key, item.title)
        } else if check.defects[key] != nil {
            var d = check.defects; d[key] = nil; check.defects = d
        }
    }

    private func tickAll(_ items: [CheckItem], column c: Int) {
        var all = check.answers
        for item in items where all[VehicleCheck.key(item.id, c)] == nil {
            all[VehicleCheck.key(item.id, c)] = item.answer == .yesNo ? "yes" : "ok"
        }
        check.answers = all
    }

    private func addColumn(_ name: String, trailer: Bool, height: Double) {
        guard check.columns.count < 7 else { return }
        check.columns += [name]
        check.trailerColumns += [trailer]
        var h = check.heights; while h.count < check.columns.count - 1 { h.append(0) }; h.append(height); check.heights = h
    }

    private func removeColumn(_ c: Int) {
        var cols = check.columns, tr = check.trailerColumns, h = check.heights
        guard c < cols.count else { return }
        cols.remove(at: c)
        if c < tr.count { tr.remove(at: c) }
        if c < h.count { h.remove(at: c) }
        // Answers for later columns move left.
        var answers: [String: String] = [:]
        for (k, v) in check.answers {
            let parts = k.split(separator: "|"); guard parts.count == 2, let col = Int(parts[1]) else { continue }
            if col == c { continue }
            answers[VehicleCheck.key(String(parts[0]), col > c ? col - 1 : col)] = v
        }
        check.columns = cols; check.trailerColumns = tr; check.heights = h; check.answers = answers
        check.defects = check.defects.filter { !$0.key.hasSuffix("|\(c)") }
    }

    private func title(forKey key: String) -> String {
        let parts = key.split(separator: "|")
        let item = CheckItem.all.first { $0.id == parts.first.map(String.init) }?.title ?? key
        let col = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return (col < check.columns.count ? check.columns[col] + ": " : "") + item
    }

    private var shareText: String {
        var out = "Vehicle check \(Fmt.dayTime(check.date)) — \(check.driverName)\n"
        for (c, name) in check.columns.enumerated() {
            let trailer = c < check.trailerColumns.count && check.trailerColumns[c]
            out += "\n\(trailer ? "Trailer" : "Vehicle") \(name)"
            if c < check.heights.count, check.heights[c] > 0 { out += " · height \(Fmt.length(check.heights[c]))" }
            out += "\n"
            for item in CheckItem.all where item.applies(toTrailer: trailer) {
                let a = check.answers[VehicleCheck.key(item.id, c)] ?? "—"
                let mark = ["ok": "✓", "defect": "✗", "yes": "Yes", "no": "No", "na": "N/A"][a] ?? "—"
                out += "\(mark)  \(item.title)\n"
            }
        }
        if !check.defects.isEmpty {
            out += "\nDefects:\n" + check.defects.map { "• \(title(forKey: $0.key)) — \($0.value)" }.joined(separator: "\n") + "\n"
        }
        if !check.defectBookRef.isEmpty { out += "Defect book ref: \(check.defectBookRef)\n" }
        out += check.signed ? "\nDeclared by \(check.driverName) at \(check.signedAt.map(Fmt.time) ?? "")\n" : "\nNot signed\n"
        return out
    }
}

/// Past vehicle checks.
struct VehicleCheckListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \VehicleCheck.date, order: .reverse) private var checks: [VehicleCheck]
    @State private var opening: VehicleCheck?

    var body: some View {
        List {
            if checks.isEmpty {
                ContentUnavailableView("No checks yet", systemImage: "checklist", description: Text("Start today's check from the Vehicle check tile on Today."))
            }
            ForEach(checks) { c in
                Button { opening = c } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fmt.dayTime(c.date)).font(.subheadline.weight(.semibold))
                        Text(c.columns.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        Text(c.signed ? (c.defectCount > 0 ? "\(c.defectCount) defect(s)" : "No defects") : "Not signed")
                            .font(.caption.weight(.semibold)).foregroundStyle(c.defectCount > 0 ? .orange : (c.signed ? .green : .secondary))
                    }
                }
                .tint(.primary)
            }
            .onDelete { idx in idx.map { checks[$0] }.forEach(context.delete); try? context.save() }
        }
        .navigationTitle("Vehicle checks")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $opening) { c in NavigationStack { VehicleCheckView(check: c) } }
    }
}
