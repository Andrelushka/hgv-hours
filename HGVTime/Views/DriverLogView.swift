import SwiftUI
import SwiftData

/// All activity tracking in one place, kept separately from planning:
/// each day's activities and events (shifts are in Jobs → Planner), the full event log, and every change made to the records.
struct DriverLogView: View {
    enum Section: String, CaseIterable, Identifiable {
        case days = "Days", events = "Events", changes = "Changes"
        var id: String { rawValue }
    }

    @State private var section: Section = .days
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Show", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)
                switch section {
                case .days: DriverDayView()
                case .events: EventLogView(day: nil, kinds: nil)
                case .changes: EventLogView(day: nil, kinds: [.correction])
                }
            }
            .navigationTitle("Driver log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink { SummaryView() } label: { Label("Summary table", systemImage: "tablecells") }
                        NavigationLink { MapScreen(day: .now) } label: { Label("Map", systemImage: "map") }
                        Button { showingSettings = true } label: { Label("Recording settings", systemImage: "gearshape") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    InCabSettingsView()
                        .toolbar { Button("Done") { showingSettings = false } }
                }
            }
        }
    }
}

/// One day of the driver log: chart, activities, events and overspeed, with editing.
struct DriverDayView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \EventLog.time) private var events: [EventLog]
    @State private var day: Date
    @State private var editing: ActivityEntry?
    @State private var adding = false
    @State private var confirmDeleteDay = false

    init(day: Date = .now) {
        _day = State(initialValue: Calendar.hgv.startOfDay(for: day))
    }

    var body: some View {
        let cal = Calendar.hgv
        let end = day.addingTimeInterval(86_400)
        // Newest first: what you just did is at the top.
        let dayEntries = entries.filter { ($0.end ?? .now) > day && $0.start < end }.reversed().map { $0 }
        let dayEvents = events.filter { $0.time >= day && $0.time < end && $0.kind != .activity }
        let totals = DayTotals.compute(dayEntries, day: day)
        List {
            Section {
                HStack {
                    Button { day = cal.date(byAdding: .day, value: -1, to: day) ?? day } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    DatePicker("", selection: $day, in: ...Date.now, displayedComponents: .date).labelsHidden()
                        .onChange(of: day) { _, d in day = cal.startOfDay(for: d) }
                    Spacer()
                    Button { day = cal.date(byAdding: .day, value: 1, to: day) ?? day } label: { Image(systemName: "chevron.right") }
                        .disabled(cal.isDateInToday(day))
                }
                .buttonStyle(.borderless)
                if !dayEntries.isEmpty {
                    DayTimelineBar(entries: dayEntries, day: day, height: 28)
                    HStack(spacing: 6) {
                        MiniStat(title: "Drive", value: Fmt.hm(totals.driving), tint: DutyKind.drive.color)
                        MiniStat(title: "Work", value: Fmt.hm(totals.otherWork), tint: DutyKind.otherWork.color)
                        MiniStat(title: "POA", value: Fmt.hm(totals.availability), tint: DutyKind.availability.color)
                        MiniStat(title: "Breaks", value: Fmt.hm(totals.breaks), tint: RestType.breakTime.color)
                    }
                }
            }
            Section {
                if dayEntries.isEmpty {
                    Text("Nothing recorded on this day.").foregroundStyle(.secondary)
                }
                ForEach(dayEntries) { entry in
                    HStack(spacing: 6) {
                        Button { editing = entry } label: { EntryRow(entry: entry) }.buttonStyle(.plain)
                        Menu {
                            Button("Edit", systemImage: "pencil") { editing = entry }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                ActivityController.delete(entry, context: context, settings: store.settings)
                            }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 30, height: 30) }
                        .buttonStyle(.borderless)
                    }
                }
                Button { adding = true } label: { Label("Add activity", systemImage: "plus.circle.fill") }
            } header: {
                Text("Activities")
            }
            Section {
                // One list: overspeed is logged here too, so the separate overspeed box isn't repeated.
                ForEach(dayEvents.reversed()) { e in
                    HStack(spacing: 10) {
                        EventPin(event: e)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.title).font(.subheadline.weight(.semibold)).foregroundStyle(e.kind.isProblem ? .red : .primary)
                            if !e.detail.isEmpty { Text(e.detail).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(Fmt.time(e.time)).font(.caption.monospacedDigit())
                    }
                }
                if dayEvents.isEmpty { Text("No events.").foregroundStyle(.secondary) }
            } header: {
                Text("Events")
            }
            Section {
                NavigationLink { MapScreen(day: day) } label: { Label("Map of this day", systemImage: "map") }
                NavigationLink { DebriefView(day: day) } label: { Label("Day debrief", systemImage: "tablecells") }
                if !dayEntries.isEmpty {
                    Button("Delete everything on this day", role: .destructive) { confirmDeleteDay = true }
                }
            }
        }
        .sheet(item: $editing) { EntryEditor(entry: $0) }
        .sheet(isPresented: $adding) {
            EntryEditor(entry: nil, defaultStart: cal.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day,
                        defaultRegime: store.settings.currentRegime)
        }
        .confirmationDialog("Delete everything recorded on \(Fmt.day(day))?", isPresented: $confirmDeleteDay, titleVisibility: .visible) {
            Button("Delete day", role: .destructive) { ActivityController.deleteDay(day, context: context, settings: store.settings) }
        } message: {
            Text("The deletion is recorded under Changes.")
        }
    }
}
