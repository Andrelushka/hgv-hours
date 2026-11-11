import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.modelContext) private var context
    @State private var deletingShift: ShiftSummary?
    @State private var addingAt: Date?
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @State private var addingEntry = false
    @State private var exporting = false

    /// Shown inside the Driver log (no own navigation stack or title).
    var embedded = false

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content.navigationTitle("History") }
        }
    }

    private var content: some View {
        shiftList
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { exporting = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addingEntry = true } label: { Label("Add activity", systemImage: "plus") }
                }
            }
            .sheet(item: Binding(get: { addingAt.map(HistoryDate.init) }, set: { addingAt = $0?.date })) { item in
                EntryEditor(entry: nil, defaultStart: item.date, defaultRegime: store.settings.currentRegime)
            }
            .confirmationDialog("Delete this shift?", isPresented: Binding(get: { deletingShift != nil }, set: { if !$0 { deletingShift = nil } }),
                                titleVisibility: .visible, presenting: deletingShift) { shift in
                Button("Delete shift \(Fmt.day(shift.period.start))", role: .destructive) {
                    ActivityController.deleteRange(from: shift.period.start, to: shift.period.isOpen ? .distantFuture : shift.period.end,
                                                   context: context, settings: store.settings)
                }
            } message: { shift in
                Text("All activities from \(Fmt.dayTime(shift.period.start)) to \(shift.period.isOpen ? "now" : Fmt.dayTime(shift.period.end)) will be removed. The deletion is recorded under Changes.")
            }
            .sheet(isPresented: $addingEntry) {
                EntryEditor(entry: nil, defaultStart: Date.now.addingTimeInterval(-3600), defaultRegime: store.settings.currentRegime)
            }
            .sheet(isPresented: $exporting) {
                ExportView()
            }
    }

    private var shiftList: some View {
            let analysis = RulesEngine.analyze(entries.map(\.snapshot), now: .now, config: store.settings.ruleConfig)
            return List {
                if analysis.weeks.isEmpty {
                    ContentUnavailableView("No activity yet", systemImage: "clock.badge.questionmark",
                                           description: Text("Shifts you record on the Today tab appear here, grouped by week."))
                }
                ForEach(analysis.weeks.reversed()) { week in
                    Section {
                        ForEach(week.shifts.reversed()) { shift in
                            HStack(spacing: 4) {
                                NavigationLink {
                                    ShiftDetailView(shiftStart: shift.period.start)
                                } label: {
                                    ShiftRow(shift: shift)
                                }
                                Menu {
                                    NavigationLink {
                                        ShiftDetailView(shiftStart: shift.period.start)
                                    } label: { Label("Open and edit activities", systemImage: "pencil") }
                                    Button("Add activity", systemImage: "plus") { addingAt = shift.period.end }
                                    Button("Delete shift", systemImage: "trash", role: .destructive) { deletingShift = shift }
                                } label: {
                                    Image(systemName: "ellipsis.circle").font(.title3).frame(width: 34, height: 34)
                                }
                                .buttonStyle(.borderless)
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { deletingShift = shift }
                            }
                        }
                        ForEach(week.issues) { IssueRow(issue: $0, showDate: true) }
                    } header: {
                        HStack {
                            Text("w/c \(Fmt.day(week.weekStart))")
                            Spacer()
                            Text("Drive \(Fmt.hm(week.allDriving)) · Work \(Fmt.hm(week.workingTime))")
                                .monospacedDigit()
                        }
                    }
                }
            }
    }
}

struct ShiftRow: View {
    var shift: ShiftSummary

    var body: some View {
        let st = shift.stats
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Fmt.day(shift.period.start)).font(.headline)
                Text("\(Fmt.time(shift.period.start))–\(shift.period.isOpen ? "now" : Fmt.time(shift.period.end))")
                    .foregroundStyle(.secondary)
                Spacer()
                if shift.issues.isEmpty {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    Label("\(shift.issues.count)", systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                        .labelStyle(.titleAndIcon)
                }
            }
            HStack(spacing: 8) {
                stat("steeringwheel", st.allDriving, .blue)
                stat("hammer.fill", st.otherWork, .orange)
                stat("hourglass", st.availability, .purple)
                stat("cup.and.saucer.fill", st.breaks, .green)
            }
            .font(.caption.monospacedDigit())
            if let kind = shift.restKind {
                Text(kind.rawValue + (shift.period.restAfter.map { " · \(Fmt.hm($0.duration))" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(kind == .insufficient ? .red : .secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func stat(_ symbol: String, _ value: TimeInterval, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol).font(.caption2)
            Text(Fmt.hm(value)).lineLimit(1).fixedSize()
        }
        .foregroundStyle(color)
    }
}

struct ShiftDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    var shiftStart: Date
    @State private var editing: ActivityEntry?
    @State private var adding = false

    var body: some View {
        let analysis = RulesEngine.analyze(entries.map(\.snapshot), now: .now, config: store.settings.ruleConfig)
        let shift = analysis.shifts.first { abs($0.period.start.timeIntervalSince(shiftStart)) < 1 }
            ?? analysis.shifts.min { abs($0.period.start.timeIntervalSince(shiftStart)) < abs($1.period.start.timeIntervalSince(shiftStart)) }

        List {
            if let shift {
                let st = shift.stats
                let shiftEnd = shift.period.restAfter?.start ?? .now
                Section("Summary") {
                    LabeledContent("Start", value: Fmt.dayTime(shift.period.start))
                    LabeledContent("Finish", value: shift.period.isOpen ? "In progress" : Fmt.dayTime(shift.period.end))
                    LabeledContent("Driving (tacho)", value: Fmt.hm(st.euDriving))
                    if st.gbDriving > 0 { LabeledContent("Driving (GB domestic)", value: Fmt.hm(st.gbDriving)) }
                    LabeledContent("Other work", value: Fmt.hm(st.otherWork))
                    LabeledContent("POA", value: Fmt.hm(st.availability))
                    LabeledContent("Breaks", value: Fmt.hm(st.breaks))
                    LabeledContent("Working time", value: Fmt.hm(st.workingTime))
                    LabeledContent("Spread-over", value: Fmt.hm(shift.period.end.timeIntervalSince(shift.period.start)))
                    LabeledContent("Longest drive without break", value: Fmt.hm(st.maxContinuousDriving))
                    if st.nightWork { LabeledContent("Night work", value: "Yes (00:00–04:00)") }
                    if let kind = shift.restKind, let rest = shift.period.restAfter {
                        LabeledContent("Rest after", value: "\(kind.rawValue) · \(Fmt.hm(rest.duration))")
                    }
                }
                Section {
                    SpeedEventsSection(from: shift.period.start, to: shift.period.isOpen ? .distantFuture : shift.period.end)
                }
                if !shift.issues.isEmpty {
                    Section("Infringements") {
                        ForEach(shift.issues) { IssueRow(issue: $0) }
                    }
                }
                Section("Activities") {
                    let shiftEntries = entries.filter { ($0.end ?? .now) > shift.period.start && $0.start < shiftEnd }.reversed().map { $0 }
                    ForEach(shiftEntries) { entry in
                        HStack(spacing: 6) {
                            Button { editing = entry } label: { EntryRow(entry: entry) }
                                .buttonStyle(.plain)
                            Menu {
                                Button("Edit", systemImage: "pencil") { editing = entry }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    ActivityController.delete(entry, context: context, settings: store.settings)
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.title3).frame(width: 30, height: 30)
                            }
                            .buttonStyle(.borderless)
                        }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    ActivityController.delete(entry, context: context, settings: store.settings)
                                }
                                Button("Edit", systemImage: "pencil") { editing = entry }
                                    .tint(.blue)
                            }
                    }
                }
            } else {
                ContentUnavailableView("Shift not found", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle(shift.map { Fmt.day($0.period.start) } ?? "Shift")
        .toolbar {
            Menu {
                Button("Add activity", systemImage: "plus") { adding = true }
                if let shift {
                    Button("Delete whole shift", systemImage: "trash", role: .destructive) {
                        ActivityController.deleteRange(from: shift.period.start, to: shift.period.isOpen ? .distantFuture : shift.period.end,
                                                       context: context, settings: store.settings)
                        dismiss()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .sheet(item: $editing) { EntryEditor(entry: $0) }
        .sheet(isPresented: $adding) {
            EntryEditor(entry: nil, defaultStart: shift?.period.end ?? shiftStart, defaultRegime: store.settings.currentRegime)
        }
    }
}

struct EntryRow: View {
    var entry: ActivityEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.displaySymbol)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(entry.displayColor.gradient, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle).font(.subheadline.weight(.semibold))
                Text("\(Fmt.time(entry.start)) – \(entry.end.map(Fmt.time) ?? "now")  ·  \(entry.regime.shortTitle)\(entry.multiManned ? " · 2-man" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !entry.note.isEmpty {
                    Text(entry.note).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Fmt.hm((entry.end ?? .now).timeIntervalSince(entry.start)))
                .font(.subheadline.monospacedDigit())
        }
        .contentShape(Rectangle())
    }
}

/// The Calendar tab.
struct CalendarTab: View {
    @Environment(SettingsStore.self) private var store
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            CalendarHistoryView()
                .navigationTitle("Calendar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button { exporting = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                }
                .sheet(isPresented: $exporting) { ExportView() }
        }
    }
}

private struct HistoryDate: Identifiable {
    var date: Date
    var id: Date { date }
}
