import SwiftUI
import SwiftData

/// Totals for one calendar day (activities clipped to 00:00–24:00).
struct DayTotals {
    var driving: TimeInterval = 0
    var otherWork: TimeInterval = 0
    var availability: TimeInterval = 0
    var breaks: TimeInterval = 0
    var dailyRest: TimeInterval = 0
    var weeklyRest: TimeInterval = 0
    var working: TimeInterval { driving + otherWork }
    var hasDuty: Bool { driving + otherWork + availability > 0 }

    static func compute(_ entries: [ActivityEntry], day: Date, now: Date = .now) -> DayTotals {
        let start = Calendar.hgv.startOfDay(for: day)
        let end = start.addingTimeInterval(86_400)
        var t = DayTotals()
        for entry in entries {
            let s = max(entry.start, start)
            let e = min(entry.end ?? now, end)
            guard e > s else { continue }
            let d = e.timeIntervalSince(s)
            switch entry.restType {
            case .breakTime: t.breaks += d
            case .daily: t.dailyRest += d
            case .weekly: t.weeklyRest += d
            case nil:
                switch entry.kind {
                case .drive: t.driving += d
                case .otherWork: t.otherWork += d
                case .availability: t.availability += d
                case .rest: t.breaks += d
                }
            }
        }
        return t
    }
}

struct CalendarHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \PayItem.date) private var payItems: [PayItem]
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]

    @State private var editingPlan: WorkPlan?
    @State private var planningDay: Date?
    @State private var month = Calendar.hgv.startOfMonth(for: .now)
    @State private var selectedDay = Calendar.hgv.startOfDay(for: .now)
    @State private var editing: ActivityEntry?
    @State private var addingOn: Date?
    @State private var confirmDeleteDay = false
    @State private var addingBonusOn: Date?

    private var cal: Calendar { .hgv }

    var body: some View {
        let analysis = RulesEngine.analyze(entries.map(\.snapshot), now: .now, config: store.settings.ruleConfig)
        let issueDays = Set(analysis.shifts.filter { !$0.issues.isEmpty }.map { cal.startOfDay(for: $0.period.start) })
        ScrollView {
            VStack(spacing: 12) {
                monthHeader
                monthGrid(issueDays: issueDays)
                ActivityLegend().padding(.horizontal, 4)
                dayDetail(analysis: analysis)
                upcoming
            }
            .padding()
        }
        .sheet(item: $editing) { EntryEditor(entry: $0) }
        .sheet(item: $editingPlan) { PlanEditor(plan: $0) }
        .sheet(item: Binding(get: { planningDay.map(IdentifiedDate.init) }, set: { planningDay = $0?.date })) { item in
            PlanEditor(plan: nil, day: item.date, defaultVehicleID: store.settings.currentVehicleID,
                       defaultTrailerID: store.settings.currentTrailerID)
        }
        .sheet(item: Binding(get: { addingOn.map(IdentifiedDate.init) }, set: { addingOn = $0?.date })) { item in
            EntryEditor(entry: nil, defaultStart: item.date, defaultRegime: store.settings.currentRegime)
        }
        .sheet(item: Binding(get: { addingBonusOn.map(IdentifiedDate.init) }, set: { addingBonusOn = $0?.date })) { item in
            PayItemEditor(defaultDate: item.date, kind: .bonus)
        }
        .confirmationDialog("Delete everything recorded on \(Fmt.day(selectedDay))?", isPresented: $confirmDeleteDay, titleVisibility: .visible) {
            Button("Delete day", role: .destructive) {
                ActivityController.deleteDay(selectedDay, context: context, settings: store.settings)
            }
        } message: {
            Text("Activities that run past midnight are shortened, not deleted. This can't be undone.")
        }
    }

    // MARK: Month

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").font(.headline) }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year())).font(.title3.weight(.bold))
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").font(.headline) }
        }
        .buttonStyle(.borderless)
        .overlay(alignment: .center) { EmptyView() }
    }

    private func shiftMonth(_ by: Int) {
        if let next = cal.date(byAdding: .month, value: by, to: month) { month = next }
    }

    private func monthGrid(issueDays: Set<Date>) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let days = cal.daysForMonthGrid(month)
        let symbols = ["M", "T", "W", "T", "F", "S", "S"]
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(days, id: \.self) { day in
                let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
                let totals = DayTotals.compute(entriesTouching(day), day: day)
                DayCell(day: day, totals: totals, inMonth: inMonth,
                        isToday: cal.isDateInToday(day),
                        isSelected: cal.isDate(day, inSameDayAs: selectedDay),
                        hasIssue: issueDays.contains(cal.startOfDay(for: day)),
                        isHoliday: payItems.contains { $0.kind == .holiday && cal.isDate($0.date, inSameDayAs: day) },
                        isBankHoliday: BankHolidays.isBankHoliday(day),
                        isPlanned: plans.contains { cal.isDate($0.plannedStart, inSameDayAs: day) })
                    .onTapGesture { selectedDay = day }
            }
        }
    }

    private func entriesTouching(_ day: Date) -> [ActivityEntry] {
        let start = cal.startOfDay(for: day)
        let end = start.addingTimeInterval(86_400)
        return entries.filter { ($0.end ?? .now) > start && $0.start < end }
    }

    // MARK: Selected day

    @ViewBuilder
    private func dayDetail(analysis: Analysis) -> some View {
        let dayEntries = entriesTouching(selectedDay)
        let totals = DayTotals.compute(dayEntries, day: selectedDay)
        let shifts = analysis.shifts.filter { cal.isDate($0.period.start, inSameDayAs: selectedDay) }
        let dayItems = payItems.filter { cal.isDate($0.date, inSameDayAs: selectedDay) }
        let holiday = dayItems.first { $0.kind == .holiday }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.headline)
                Spacer()
                Menu {
                    Button("Plan work", systemImage: "calendar.badge.plus") { planningDay = selectedDay }
                    NavigationLink { DebriefView(day: selectedDay) } label: { Label("Day debrief", systemImage: "tablecells") }
                    NavigationLink { MapScreen(day: selectedDay) } label: { Label("Day map", systemImage: "map") }
                    NavigationLink { EventLogView(day: selectedDay) } label: { Label("Day events", systemImage: "list.bullet") }
                    Button("Add activity", systemImage: "plus") {
                        addingOn = cal.date(bySettingHour: 8, minute: 0, second: 0, of: selectedDay)
                    }
                    if let holiday {
                        Button("Remove holiday", systemImage: "sun.horizon") {
                            context.delete(holiday)
                            try? context.save()
                        }
                    } else {
                        Button("Mark as holiday", systemImage: "sun.horizon.fill") {
                            context.insert(PayItem(date: cal.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDay) ?? selectedDay,
                                                   kind: .holiday, hours: store.settings.pay.holidayDayHours))
                            try? context.save()
                        }
                    }
                    Button("Add bonus", systemImage: "gift") { addingBonusOn = selectedDay }
                    if !dayEntries.isEmpty {
                        Button("Delete whole day", systemImage: "trash", role: .destructive) { confirmDeleteDay = true }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
            }
            ForEach(plans.filter { cal.isDate($0.plannedStart, inSameDayAs: selectedDay) }) { plan in
                PlanCard(plan: plan)
                    .onTapGesture { editingPlan = plan }
                    .contextMenu {
                        Button("Edit plan", systemImage: "pencil") { editingPlan = plan }
                        Button("Delete plan", systemImage: "trash", role: .destructive) {
                            context.delete(plan)
                            try? context.save()
                        }
                    }
            }
            if selectedDay >= cal.startOfDay(for: .now), !plans.contains(where: { cal.isDate($0.plannedStart, inSameDayAs: selectedDay) }) {
                Button { planningDay = selectedDay } label: {
                    Label("Plan work for this day", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
            }
            if BankHolidays.isBankHoliday(selectedDay) {
                Label("Bank holiday", systemImage: "flag.fill").font(.subheadline).foregroundStyle(.red)
            }
            ForEach(dayItems) { item in
                HStack {
                    Label(item.kind == .holiday ? "Holiday (\(String(format: "%.1f", item.hours)) h paid)" : (item.title.isEmpty ? "Bonus" : item.title),
                          systemImage: item.kind.symbol)
                    Spacer()
                    if item.kind == .bonus { Text(Fmt.money(item.amount, symbol: store.settings.pay.currencySymbol)).monospacedDigit() }
                    Button(role: .destructive) {
                        context.delete(item)
                        try? context.save()
                    } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                }
                .font(.subheadline)
                .foregroundStyle(.orange)
            }
            if dayEntries.isEmpty {
                Text(holiday == nil ? "Nothing recorded." : "No driving or work recorded.").foregroundStyle(.secondary)
                Button {
                    addingOn = cal.date(bySettingHour: 8, minute: 0, second: 0, of: selectedDay)
                } label: {
                    Label("Add activity", systemImage: "plus.circle.fill")
                }
            } else {
                DayTimelineBar(entries: dayEntries, day: selectedDay, height: 28)
                SpeedEventsSection(from: cal.startOfDay(for: selectedDay), to: cal.startOfDay(for: selectedDay).addingTimeInterval(86_400))
                HStack(spacing: 6) {
                    MiniStat(title: "Drive", value: Fmt.hm(totals.driving), tint: DutyKind.drive.color)
                    MiniStat(title: "Work", value: Fmt.hm(totals.otherWork), tint: DutyKind.otherWork.color)
                    MiniStat(title: "POA", value: Fmt.hm(totals.availability), tint: DutyKind.availability.color)
                    MiniStat(title: "Breaks", value: Fmt.hm(totals.breaks), tint: RestType.breakTime.color)
                }
                if totals.dailyRest + totals.weeklyRest > 0 {
                    HStack(spacing: 6) {
                        if totals.dailyRest > 0 { MiniStat(title: "Daily rest", value: Fmt.hm(totals.dailyRest), tint: RestType.daily.color) }
                        if totals.weeklyRest > 0 { MiniStat(title: "Weekly rest", value: Fmt.hm(totals.weeklyRest), tint: RestType.weekly.color) }
                    }
                }
                ForEach(shifts) { shift in
                    NavigationLink {
                        ShiftDetailView(shiftStart: shift.period.start)
                    } label: {
                        HStack {
                            Image(systemName: shift.issues.isEmpty ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                                .foregroundStyle(shift.issues.isEmpty ? .green : .red)
                            Text("Shift \(Fmt.time(shift.period.start))–\(shift.period.isOpen ? "now" : Fmt.time(shift.period.end))")
                            Spacer()
                            if !shift.issues.isEmpty { Text("\(shift.issues.count) issue\(shift.issues.count == 1 ? "" : "s")").foregroundStyle(.red) }
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }
                Divider()
                ForEach(dayEntries) { entry in
                    HStack(spacing: 8) {
                        Button { editing = entry } label: { EntryRow(entry: entry) }
                            .buttonStyle(.plain)
                        Menu {
                            Button("Edit", systemImage: "pencil") { editing = entry }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                ActivityController.delete(entry, context: context, settings: store.settings)
                            }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 28, height: 28)
                        }
                    }
                    Divider()
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

extension CalendarHistoryView {
    @ViewBuilder
    var upcoming: some View {
        let next = plans.filter { $0.plannedEnd >= .now }.prefix(10)
        if !next.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Upcoming work").font(.headline)
                ForEach(Array(next)) { plan in
                    Button {
                        selectedDay = cal.startOfDay(for: plan.plannedStart)
                        month = cal.startOfMonth(for: plan.plannedStart)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(plan.plannedStart.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.subheadline.weight(.semibold))
                                Text([plan.company, "\(Fmt.time(plan.plannedStart))–\(Fmt.time(plan.plannedEnd))"].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            let bad = PlanCheck.check(start: plan.plannedStart, end: plan.plannedEnd, excluding: plan.id, plans: plans,
                                                      entries: entries.map(\.snapshot), settings: store.settings)
                            if bad.contains(where: { $0.level == .error }) {
                                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            } else if bad.contains(where: { $0.level == .warning }) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct IdentifiedDate: Identifiable {
    var date: Date
    var id: Date { date }
}

struct DayCell: View {
    var day: Date
    var totals: DayTotals
    var inMonth: Bool
    var isToday: Bool
    var isSelected: Bool
    var hasIssue: Bool
    var isHoliday = false
    var isBankHoliday = false
    var isPlanned = false

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                Text("\(Calendar.hgv.component(.day, from: day))")
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : (inMonth ? .primary : .secondary))
                    .frame(width: 22, height: 22)
                    .background(isToday ? Color.accentColor : .clear, in: Circle())
                if hasIssue {
                    Circle().fill(.red).frame(width: 5, height: 5)
                }
            }
            // Stacked bar of the day's duty, scaled to 15h.
            GeometryReader { geo in
                let scale = geo.size.width / (15 * 3600)
                HStack(spacing: 0) {
                    Rectangle().fill(DutyKind.drive.color).frame(width: min(geo.size.width, totals.driving * scale))
                    Rectangle().fill(DutyKind.otherWork.color).frame(width: totals.otherWork * scale)
                    Rectangle().fill(DutyKind.availability.color).frame(width: totals.availability * scale)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 5)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
            Group {
                if totals.driving > 0 {
                    Text(Fmt.hm(totals.driving)).foregroundStyle(DutyKind.drive.color)
                } else if isHoliday {
                    Text("Holiday").foregroundStyle(.orange)
                } else if isPlanned {
                    Text("Planned").foregroundStyle(.indigo)
                } else if isBankHoliday {
                    Text("Bank hol").foregroundStyle(.red)
                } else if totals.weeklyRest > 6 * 3600 {
                    Text("Rest").foregroundStyle(RestType.weekly.color)
                } else {
                    Text(" ")
                }
            }
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.indigo.opacity(isPlanned ? 0.7 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [4, 2])))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .opacity(inMonth ? 1 : 0.45)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isHoliday && !totals.hasDuty { return Color.orange.opacity(0.12) }
        if totals.weeklyRest > 6 * 3600 && !totals.hasDuty { return RestType.weekly.color.opacity(0.12) }
        return totals.hasDuty ? Color(.secondarySystemBackground) : Color(.systemBackground)
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }

    /// Days shown in a Monday-first month grid, including leading/trailing days of nearby months.
    func daysForMonthGrid(_ month: Date) -> [Date] {
        let first = startOfMonth(for: month)
        let gridStart = startOfFixedWeek(for: first)
        guard let monthEnd = date(byAdding: .month, value: 1, to: first) else { return [] }
        var days: [Date] = []
        var day = gridStart
        while day < monthEnd || days.count % 7 != 0 {
            days.append(day)
            guard let next = date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}
