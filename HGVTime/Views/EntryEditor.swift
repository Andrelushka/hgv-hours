import SwiftUI
import SwiftData

/// Add or edit one activity. Used for corrections ("I forgot to press Break")
/// and for manual entries copied from a tacho printout.
struct EntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store

    private let entry: ActivityEntry?

    @State private var kind: DutyKind
    @State private var regime: Regime
    @State private var start: Date
    @State private var end: Date
    @State private var isOpen: Bool
    @State private var multiManned: Bool
    @State private var restType: RestType
    @State private var note: String
    @State private var subtype: ActivitySubtype?
    @State private var confirmDelete = false

    init(entry: ActivityEntry?, defaultStart: Date = .now, defaultRegime: Regime = .assimilated) {
        self.entry = entry
        _kind = State(initialValue: entry?.kind ?? .drive)
        _regime = State(initialValue: entry?.regime ?? defaultRegime)
        let start = entry?.start ?? defaultStart
        _start = State(initialValue: start)
        _end = State(initialValue: entry?.end ?? (entry == nil ? start.addingTimeInterval(3600) : .now))
        _isOpen = State(initialValue: entry != nil && entry?.end == nil)
        _multiManned = State(initialValue: entry?.multiManned ?? false)
        _restType = State(initialValue: entry?.restType ?? .breakTime)
        _note = State(initialValue: entry?.note ?? "")
        _subtype = State(initialValue: entry?.subtype)
    }

    private var isValid: Bool { isOpen ? start <= .now : end > start }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activity", selection: $kind) {
                        ForEach(DutyKind.allCases) { Label($0 == .rest ? "Break / rest" : $0.title, systemImage: $0.symbol).tag($0) }
                    }
                    if kind == .rest {
                        Picker("Type of rest", selection: $restType) {
                            ForEach(RestType.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if kind == .otherWork || kind == .availability {
                        Picker("What", selection: $subtype) {
                            Text(kind == .otherWork ? "Other work" : "Period of availability").tag(ActivitySubtype?.none)
                            ForEach(ActivitySubtype.options(for: kind)) { Label($0.title, systemImage: $0.symbol).tag(ActivitySubtype?.some($0)) }
                        }
                    }
                    Picker("Rules", selection: $regime) {
                        ForEach(Regime.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Double-manned", isOn: $multiManned)
                } footer: {
                    if kind == .rest {
                        Text("Break = inside a shift. Daily rest = between shifts (9h or 11h). Weekly rest = the long rest (24h or 45h). Choosing daily or weekly rest ends the shift.")
                    }
                }
                Section {
                    NowDatePicker("Start", selection: $start, in: ...Date.now)
                    if entry != nil && entry?.end == nil {
                        Toggle("Still in progress", isOn: $isOpen)
                    }
                    if !isOpen {
                        NowDatePicker("End", selection: $end, in: start...)
                        LabeledContent("Duration", value: Fmt.hm(end.timeIntervalSince(start)))
                    }
                } header: {
                    Text("Time")
                } footer: {
                    Text("Other activities that overlap these times are shortened or removed so the day adds up.")
                }
                Section("Note") {
                    TextField("e.g. ferry, defect check, loading at RDC", text: $note, axis: .vertical)
                        .submitLabel(.done)
                        .onChange(of: note) { _, value in
                            // A multi-line field puts a newline on Return: treat it as "done".
                            if value.hasSuffix("\n") {
                                note = String(value.dropLast())
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                }
                if entry != nil {
                    Section {
                        Button("Delete activity", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(entry == nil ? "Add activity" : "Edit activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!isValid) }
            }
            .confirmationDialog("Delete this activity?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let entry { context.delete(entry) }
                    finish()
                }
            }
        }
    }

    private func save() {
        let target: ActivityEntry
        if let entry {
            let before = "\(entry.displayTitle) \(Fmt.dayTime(entry.start))–\(entry.end.map(Fmt.time) ?? "now")"
            let after = "\(kind == .rest ? restType.title : kind.title) \(Fmt.dayTime(start))–\(isOpen ? "now" : Fmt.time(end))"
            if before != after {
                EventRecorder.log(.correction, title: "Edited activity", detail: "\(before) → \(after)", context: context, settings: store.settings)
            }
            target = entry
        } else {
            target = ActivityEntry(kind: kind, regime: regime, start: start)
            context.insert(target)
            EventRecorder.log(.correction, title: "Added activity by hand",
                              detail: "\(kind == .rest ? restType.title : kind.title) \(Fmt.dayTime(start))–\(isOpen ? "now" : Fmt.time(end))",
                              context: context, settings: store.settings)
        }
        target.kind = kind
        target.regime = regime
        target.start = start
        target.end = isOpen ? nil : end
        target.multiManned = multiManned
        target.endsShift = kind == .rest && restType != .breakTime
        target.plannedRestRaw = target.endsShift ? restType.rawValue : ""
        target.note = note
        target.subtypeRaw = (subtype?.kind == kind ? subtype?.rawValue : nil) ?? ""

        // Make the other activities fit around this one.
        let descriptor = FetchDescriptor<ActivityEntry>(sortBy: [SortDescriptor(\.start)])
        let all = (try? context.fetch(descriptor)) ?? []
        let newEnd = target.end ?? .distantFuture
        for other in all where other !== target {
            let otherEnd = other.end ?? .distantFuture
            guard otherEnd > start, other.start < newEnd else { continue }
            if other.start < start {
                // Starts before: cut it off where this one starts.
                if otherEnd > newEnd, let end = target.end {
                    // It also runs past this one: keep the tail as a separate activity.
                    let tail = ActivityEntry(kind: other.kind, regime: other.regime, start: end, end: other.end,
                                             multiManned: other.multiManned, note: other.note, endsShift: other.endsShift)
                    tail.plannedRestRaw = other.plannedRestRaw
                    tail.subtypeRaw = other.subtypeRaw
                    context.insert(tail)
                }
                other.end = start
            } else if otherEnd <= newEnd {
                // Completely covered by this one.
                context.delete(other)
            } else if let end = target.end {
                // Starts inside, ends after: move its start.
                other.start = end
            }
        }
        finish()
    }

    private func finish() {
        try? context.save()
        ActivityController.refreshSideEffects(context: context, settings: store.settings)
        dismiss()
    }
}
