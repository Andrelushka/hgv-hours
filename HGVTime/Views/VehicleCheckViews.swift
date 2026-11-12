import SwiftData
import SwiftUI

/// Today: the full vehicle (walk-round) check — optional: skip it for today, delete it, or hide the tile.
struct VehicleCheckTile: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \VehicleCheck.date, order: .reverse) private var checks: [VehicleCheck]
    @State private var opening: VehicleCheck?
    @State private var showingList = false
    @State private var confirmDelete = false

    var body: some View {
        let today = checks.first { Calendar.hgv.isDateInToday($0.date) }
        let skipped = store.settings.vehicleCheckSkippedToday && today == nil
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                if let today {
                    Circle().trim(from: 0, to: today.progress)
                        .stroke(statusColor(today).gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: skipped ? "forward.fill" : (today?.signed == true ? "checkmark" : "checklist.checked"))
                    .font(.headline).foregroundStyle(today.map(statusColor) ?? .secondary)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vehicle check").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let today {
                    Text(today.signed
                         ? (today.defectCount > 0 ? "Done · \(today.defectCount) defect(s) reported" : "Done · no defects")
                         : "In progress · \(today.openCount) left")
                        .font(.headline)
                    Text(today.columns.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if skipped {
                    Text("Not needed today").font(.headline).foregroundStyle(.secondary)
                } else {
                    Text("Not done today").font(.headline)
                }
            }
            Spacer(minLength: 0)
            if !skipped {
                Button(today == nil ? "Start" : "Open") { opening = today ?? VehicleCheck.today(in: context, settings: store.settings) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            Menu {
                if skipped {
                    Button("Do the check after all", systemImage: "arrow.uturn.backward") { store.settings.skipVehicleCheckToday(false) }
                } else if today == nil {
                    Button("Not needed today", systemImage: "forward") { store.settings.skipVehicleCheckToday(true) }
                }
                if today != nil {
                    Button("Delete today's check", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
                Button("History", systemImage: "clock.arrow.circlepath") { showingList = true }
                Button("Hide this tile", systemImage: "eye.slash") { store.settings.setTile(.vehicleCheck, visible: false, on: .today) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary).frame(width: 32, height: 32)
            }
            .accessibilityLabel("Vehicle check options")
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(item: $opening) { c in NavigationStack { VehicleCheckView(check: c) } }
        .sheet(isPresented: $showingList) { NavigationStack { VehicleCheckListView() } }
        .confirmationDialog("Delete today's vehicle check?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let today { context.delete(today); try? context.save() }
            }
        } message: {
            Text("Everything ticked in it is removed. This can't be undone.")
        }
    }

    private func statusColor(_ c: VehicleCheck) -> Color {
        c.signed ? (c.defectCount > 0 ? .orange : .green) : .blue
    }
}

/// The check: pick the vehicle or a trailer at the top, then work down the walk round — cab, front, sides,
/// coupling, rear — answering each line with ✓ / ✗ / N/A.
struct VehicleCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Bindable var check: VehicleCheck
    @State private var column = 0
    @State private var addingTrailer = false
    @State private var trailerText = ""
    @State private var confirmDelete = false
    @State private var collapsed: Set<CheckArea> = []

    var body: some View {
        let c = min(column, max(0, check.columns.count - 1))
        let trailer = c < check.trailerColumns.count && check.trailerColumns[c]
        let groups = CheckItem.walkRound(trailer: trailer)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                columnPicker(selected: c)
                ForEach(groups, id: \.area) { group in
                    areaCard(group.area, items: group.items, column: c)
                }
                heightCard(column: c)
                declarationCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Vehicle check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { try? context.save(); dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: shareText) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button("Delete this check", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { finish() }.fontWeight(.semibold)
            }
        }
        .confirmationDialog("Delete this vehicle check?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(check)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("Everything ticked in it is removed. This can't be undone.")
        }
        .alert("Trailer number", isPresented: $addingTrailer) {
            TextField("e.g. T1234", text: $trailerText)
            Button("Add") { if !trailerText.isEmpty, let i = check.addColumn(trailerText, trailer: true, height: 0) { column = i } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Vehicle / trailer picker

    private func columnPicker(selected: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(check.columns.enumerated()), id: \.offset) { i, name in
                    let trailer = i < check.trailerColumns.count && check.trailerColumns[i]
                    let open = check.openCount(column: i)
                    let defects = check.answers.filter { $0.key.hasSuffix("|\(i)") && ($0.value == "defect" || $0.value == "no") }.count
                    Button { withAnimation(.snappy) { column = i } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: trailer ? "shippingbox.fill" : "truck.box.fill")
                            VStack(alignment: .leading, spacing: 0) {
                                Text(name).font(.subheadline.weight(.bold)).lineLimit(1)
                                Text(open == 0 ? String(localized: "All answered") : String(localized: "\(open) left"))
                                    .font(.caption2)
                            }
                            if defects > 0 {
                                Text("\(defects)").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2).background(.red, in: Capsule())
                            } else if open == 0 {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(i == selected ? .white : .green)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(i == selected ? .white : .primary)
                        .background(i == selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if i > 0 {
                            Button("Remove \(name)", systemImage: "trash", role: .destructive) { removeColumn(i) }
                        }
                    }
                }
                if check.columns.count < 7 {
                    Menu {
                        ForEach(vehicles.filter { $0.kind == .trailer }) { t in
                            Button(t.displayName) {
                                if let i = check.addColumn(VehicleCheck.columnName(t), trailer: true, height: t.height) { column = i }
                            }
                        }
                        Button("Type a trailer number…") { trailerText = ""; addingTrailer = true }
                    } label: {
                        Label("Trailer", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 14)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    // MARK: One area of the walk round

    private func areaCard(_ area: CheckArea, items: [CheckItem], column c: Int) -> some View {
        let answered = items.filter { check.answers[VehicleCheck.key($0.id, c)] != nil }.count
        let isCollapsed = collapsed.contains(area)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: area.symbol).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(area.color.gradient, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 0) {
                    Text(area.title).font(.headline)
                    Text("\(answered) of \(items.count)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if answered < items.count {
                    Button("All OK") { tickAll(items, column: c) }
                        .buttonStyle(.bordered).controlSize(.small).tint(.green)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                }
                Button { withAnimation(.snappy) { if isCollapsed { collapsed.remove(area) } else { collapsed.insert(area) } } } label: {
                    Image(systemName: "chevron.down").rotationEffect(.degrees(isCollapsed ? -90 : 0)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCollapsed ? "Show" : "Hide")
            }
            .padding(12)
            if !isCollapsed {
                ForEach(items) { item in
                    Divider().padding(.leading, 12)
                    itemRow(item, column: c)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(area.color).frame(width: 4).padding(.vertical, 14)
        }
    }

    private func itemRow(_ item: CheckItem, column c: Int) -> some View {
        let key = VehicleCheck.key(item.id, c)
        let answer = check.answers[key]
        let options: [(value: String, label: String, color: Color)] = item.answer == .yesNo
            ? [("yes", String(localized: "Yes"), .green), ("no", String(localized: "No"), .red), ("na", "N/A", .gray)]
            : [("ok", "✓", .green), ("defect", "✗", .red), ("na", "N/A", .gray)]
        let isDefect = answer == "defect" || answer == "no"
        return VStack(alignment: .leading, spacing: 8) {
            Text(item.title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(options, id: \.value) { o in
                    let on = answer == o.value
                    Button {
                        set(key, on ? nil : o.value)
                    } label: {
                        Text(o.label)
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(on ? .white : o.color)
                            .background(on ? AnyShapeStyle(o.color.gradient) : AnyShapeStyle(o.color.opacity(0.12)),
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(o.value == "ok" ? String(localized: "Satisfactory") : o.value == "defect" ? String(localized: "Action required") : o.label)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if isDefect {
                TextField("What's wrong? (optional)", text: Binding(get: { check.defects[key] ?? "" },
                                                                    set: { var d = check.defects; d[key] = $0; check.defects = d }),
                          axis: .vertical)
                    .font(.subheadline)
                    .padding(8)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(isDefect ? Color.red.opacity(0.04) : .clear)
    }

    // MARK: Height and declaration

    private func heightCard(column c: Int) -> some View {
        HStack {
            Image(systemName: "arrow.up.and.down").foregroundStyle(.white)
                .frame(width: 32, height: 32).background(Color.purple.gradient, in: RoundedRectangle(cornerRadius: 9))
            Text("Height when leaving").font(.subheadline.weight(.semibold))
            Spacer()
            TextField("m", value: Binding(
                get: { c < check.heights.count && check.heights[c] > 0 ? check.heights[c] : nil },
                set: { v in var h = check.heights; while h.count <= c { h.append(0) }; h[c] = v ?? 0; check.heights = h }),
                      format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 64)
                .padding(6).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            Text("m").foregroundStyle(.secondary)
            if c < check.heights.count, check.heights[c] > 0 {
                Text(Fmt.feetInches(check.heights[c])).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var declarationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Declaration", systemImage: "signature").font(.headline)
            TextField("Driver name", text: $check.driverName)
                .padding(8).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            TextField("Defect book reference", text: $check.defectBookRef)
                .padding(8).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            TextField("Notes", text: $check.notes, axis: .vertical)
                .padding(8).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            Toggle("I've followed the check procedure and reported all defects", isOn: Binding(
                get: { check.signed },
                set: { check.signed = $0; check.signedAt = $0 ? .now : nil }))
                .font(.subheadline)
            Text(check.openCount > 0 ? "\(check.openCount) line(s) not answered yet." : "Every line answered.")
                .font(.caption).foregroundStyle(check.openCount > 0 ? .orange : .green)
            Text("Date: \(Fmt.dayTime(check.date))").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Actions

    private func set(_ key: String, _ value: String?) {
        var all = check.answers
        all[key] = value
        check.answers = all
        if value != "defect" && value != "no", check.defects[key] != nil {
            var d = check.defects; d[key] = nil; check.defects = d
        }
    }

    private func tickAll(_ items: [CheckItem], column c: Int) {
        var all = check.answers
        for item in items where all[VehicleCheck.key(item.id, c)] == nil {
            all[VehicleCheck.key(item.id, c)] = item.answer == .yesNo ? "yes" : "ok"
        }
        withAnimation(.snappy) { check.answers = all }
    }

    private func finish() {
        try? context.save()
        if check.signed {
            EventRecorder.log(.note, title: String(localized: "Vehicle check done"),
                              detail: check.defectCount > 0 ? "\(check.defectCount) defect(s)" : String(localized: "No defects"),
                              context: context, settings: store.settings)
        }
        dismiss()
    }

    private func removeColumn(_ c: Int) {
        var cols = check.columns, tr = check.trailerColumns, h = check.heights
        guard c < cols.count else { return }
        cols.remove(at: c)
        if c < tr.count { tr.remove(at: c) }
        if c < h.count { h.remove(at: c) }
        // Answers for later columns move left.
        func shifted(_ dict: [String: String]) -> [String: String] {
            var out: [String: String] = [:]
            for (k, v) in dict {
                let parts = k.split(separator: "|"); guard parts.count == 2, let col = Int(parts[1]) else { continue }
                if col == c { continue }
                out[VehicleCheck.key(String(parts[0]), col > c ? col - 1 : col)] = v
            }
            return out
        }
        check.columns = cols; check.trailerColumns = tr; check.heights = h
        check.answers = shifted(check.answers)
        check.defects = shifted(check.defects)
        column = max(0, min(column, cols.count - 1))
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
            for group in CheckItem.walkRound(trailer: trailer) {
                out += "— \(group.area.title)\n"
                for item in group.items {
                    let a = check.answers[VehicleCheck.key(item.id, c)] ?? "—"
                    let mark = ["ok": "✓", "defect": "✗", "yes": "Yes", "no": "No", "na": "N/A"][a] ?? "—"
                    out += "\(mark)  \(item.title)\n"
                }
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
                .swipeActions {
                    Button("Delete", role: .destructive) { context.delete(c); try? context.save() }
                }
            }
        }
        .navigationTitle("Vehicle checks")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $opening) { c in NavigationStack { VehicleCheckView(check: c) } }
    }
}
