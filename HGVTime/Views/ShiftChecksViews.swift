import SwiftData
import SwiftUI

/// Today: the start- and end-of-shift checks still to do.
struct ShiftChecksTile: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \CheckRecord.doneAt, order: .reverse) private var records: [CheckRecord]
    var shiftStart: Date?
    var company: String
    @State private var editing = false

    var body: some View {
        let start = shiftStart ?? .now
        let templates = store.settings.shiftChecks
        let startDue = ShiftChecks.due(templates, phase: .start, shiftStart: start, company: company, records: records)
        let endDue = shiftStart == nil ? [] : ShiftChecks.due(templates, phase: .end, shiftStart: start, company: company, records: records)
        let doneThisShift = records.filter { $0.doneAt >= start.addingTimeInterval(-3 * 3600) && !$0.skipped }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(shiftStart == nil ? "Checks for your next shift" : "Shift checks", systemImage: "checklist")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { editing = true } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit shift checks")
            }
            if templates.isEmpty {
                Text("Add checks you do at the start or end of a shift: agency forms, licence checks, card downloads, signing the register…")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Set up shift checks") { editing = true }.buttonStyle(.bordered).font(.caption.weight(.semibold))
            } else if startDue.isEmpty && endDue.isEmpty {
                Label(doneThisShift > 0 ? "All done (\(doneThisShift) this shift)" : "Nothing due", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).foregroundStyle(.green)
            } else {
                if !startDue.isEmpty {
                    Text("Start of shift").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    ForEach(startDue) { row($0) }
                }
                if !endDue.isEmpty {
                    Text("Before you finish").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    ForEach(endDue) { row($0) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $editing) { NavigationStack { ShiftChecksSettingsView() } }
    }

    private func row(_ t: ShiftCheckTemplate) -> some View {
        HStack(spacing: 10) {
            Button { mark(t, skipped: false) } label: {
                Image(systemName: "circle").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Mark \(t.title) done")
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(.subheadline.weight(.medium))
                Text([t.schedule == .everyShift ? "" : t.scheduleText, t.note].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if let url = URL(string: t.link), !t.link.isEmpty {
                Button { openURL(url) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open \(t.title) link")
            }
            Menu {
                Button("Done", systemImage: "checkmark") { mark(t, skipped: false) }
                Button("Not needed this time", systemImage: "forward") { mark(t, skipped: true) }
            } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
        }
    }

    private func mark(_ t: ShiftCheckTemplate, skipped: Bool) {
        withAnimation {
            context.insert(CheckRecord(template: t, skipped: skipped))
            try? context.save()
        }
        EventRecorder.log(.note, title: skipped ? "Check skipped" : "Check done", detail: t.title,
                          context: context, settings: store.settings)
    }
}

/// Settings → Shift checks: add, edit, reorder and remove your checks.
struct ShiftChecksSettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CheckRecord.doneAt, order: .reverse) private var records: [CheckRecord]
    @State private var editing: ShiftCheckTemplate?
    @State private var isNew = false

    var body: some View {
        Form {
            ForEach(ShiftCheckTemplate.Phase.allCases) { phase in
                Section {
                    let items = store.settings.shiftChecks.filter { $0.phase == phase }
                    ForEach(items) { t in
                        Button { isNew = false; editing = t } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).foregroundStyle(t.enabled ? .primary : .secondary)
                                    Text([t.scheduleText, t.company.isEmpty ? "" : "Only \(t.company)"].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !t.enabled { Text("Off").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .tint(.primary)
                    }
                    .onDelete { idx in
                        let ids = idx.map { items[$0].id }
                        store.settings.shiftChecks.removeAll { ids.contains($0.id) }
                    }
                    .onMove { from, to in
                        var list = items
                        list.move(fromOffsets: from, toOffset: to)
                        store.settings.shiftChecks = store.settings.shiftChecks.filter { $0.phase != phase } + list
                    }
                    Menu {
                        ForEach(ShiftCheckTemplate.presets.filter { p in p.phase == phase && !store.settings.shiftChecks.contains { $0.title == p.title } }, id: \.title) { p in
                            Button(p.title) { var c = p; c.id = UUID(); store.settings.shiftChecks.append(c) }
                        }
                        Divider()
                        Button("Your own check…", systemImage: "square.and.pencil") {
                            isNew = true
                            editing = ShiftCheckTemplate(title: "", phase: phase)
                        }
                    } label: {
                        Label("Add check", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text(phase.title)
                } footer: {
                    Text(phase == .start
                         ? "Shown on Today when you start a shift (and before, for your next shift)."
                         : "Shown on Today during the shift, and you're reminded if any are left when you end it.")
                }
            }
            if !records.isEmpty {
                Section("Recently done") {
                    ForEach(records.prefix(10)) { r in
                        LabeledContent(r.title, value: "\(r.skipped ? "Skipped" : "Done") \(Fmt.dayTime(r.doneAt))")
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Shift checks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .sheet(item: $editing) { t in
            NavigationStack {
                ShiftCheckEditor(check: t, isNew: isNew) { saved in
                    if let i = store.settings.shiftChecks.firstIndex(where: { $0.id == saved.id }) {
                        store.settings.shiftChecks[i] = saved
                    } else {
                        store.settings.shiftChecks.append(saved)
                    }
                } onDelete: {
                    store.settings.shiftChecks.removeAll { $0.id == t.id }
                }
            }
        }
    }
}

struct ShiftCheckEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var check: ShiftCheckTemplate
    var isNew: Bool
    var onSave: (ShiftCheckTemplate) -> Void
    var onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("What to do", text: $check.title)
                TextField("Note (optional)", text: $check.note, axis: .vertical)
                TextField("Link (optional), e.g. agency form", text: $check.link)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section("When") {
                Picker("Shift", selection: $check.phase) {
                    ForEach(ShiftCheckTemplate.Phase.allCases) { Text($0.title).tag($0) }
                }
                Picker("How often", selection: $check.schedule) {
                    ForEach(ShiftCheckTemplate.Schedule.allCases) { Text($0.title).tag($0) }
                }
                if check.schedule == .days {
                    let names = Calendar.current.weekdaySymbols
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                        Toggle(names[d - 1], isOn: Binding(
                            get: { check.weekdays.contains(d) },
                            set: { on in if on { check.weekdays.append(d) } else { check.weekdays.removeAll { $0 == d } } }))
                    }
                }
            }
            Section {
                TextField("Only for company / agency client", text: $check.company)
                Toggle("Turned on", isOn: $check.enabled)
            } footer: {
                Text("Leave the company empty to show the check for every job.")
            }
            if !isNew {
                Section { Button("Delete check", role: .destructive) { onDelete(); dismiss() } }
            }
        }
        .navigationTitle(isNew ? "New check" : "Edit check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave(check); dismiss() }
                    .disabled(check.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
