import SwiftUI
import SwiftData

struct WeeksView: View {
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \NightOut.date) private var nightOuts: [NightOut]
    @Query(sort: \PayItem.date) private var payItems: [PayItem]
    @Environment(\.modelContext) private var context
    @State private var weekOffset: Int

    init(initialOffset: Int = 0) {
        _weekOffset = State(initialValue: initialOffset)
    }
    @State private var addingItem = false
    @State private var exporting = false

    private var cal: Calendar { .hgv }

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
            let settings = store.settings
            let analysis = RulesEngine.analyze(entries.map(\.snapshot), now: .now, config: settings.ruleConfig)
            let weekStart = cal.date(byAdding: .day, value: 7 * weekOffset, to: cal.startOfFixedWeek(for: .now)) ?? .now
            let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let week = analysis.weeks.first { $0.weekStart == weekStart }
            let referenceWeeks = analysis.weeks.filter { $0.weekStart <= weekStart }.suffix(settings.wtdReferenceWeeks)
            let average = referenceWeeks.isEmpty ? 0 : referenceWeeks.reduce(0) { $0 + $1.workingTime } / Double(referenceWeeks.count)
            let nights = nightOuts.filter { $0.date >= weekStart && $0.date < weekEnd }.count
            let weekItems = payItems.filter { $0.date >= weekStart && $0.date < weekEnd }
            let holidayValue = PayCalculator.averageDayPay(shifts: analysis.shifts, before: weekStart, settings: settings.pay)
            let pay = PayCalculator.calculate(shifts: week?.shifts ?? [], nightOuts: nights, settings: settings.pay,
                                              items: weekItems.map(\.snapshot), holidayDayValue: holidayValue)

            List {
                Section {
                    HStack {
                        Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        VStack {
                            Text("Week commencing").font(.caption).foregroundStyle(.secondary)
                            Text(Fmt.day(weekStart)).font(.headline)
                        }
                        Spacer()
                        Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                            .disabled(weekOffset >= 0)
                    }
                    .buttonStyle(.borderless)
                }

                Section("Limits") {
                    limitRow("Driving (tacho)", week?.euDriving ?? 0, Limits.weeklyDriving)
                    limitRow("Fortnight driving", week?.fortnightDriving ?? 0, Limits.fortnightlyDriving)
                    if (week?.allDriving ?? 0) > (week?.euDriving ?? 0) {
                        LabeledContent("GB domestic driving", value: Fmt.hm((week?.allDriving ?? 0) - (week?.euDriving ?? 0)))
                    }
                    if settings.applyWorkingTime {
                        limitRow("Working time", week?.workingTime ?? 0, Limits.wtdWeeklyMaximum)
                        limitRow("\(referenceWeeks.count)-week average", average, Limits.wtdWeeklyAverage)
                    }
                    LabeledContent("POA", value: Fmt.hm(week?.availability ?? 0))
                    LabeledContent("Shifts", value: "\(week?.shifts.count ?? 0)")
                    let extensions = week?.shifts.filter { $0.stats.euDriving > Limits.dailyDriving + Limits.tolerance }.count ?? 0
                    LabeledContent("10h driving days", value: "\(extensions) of 2")
                    LabeledContent("Reduced daily rests", value: "\(week?.shifts.filter { $0.restKind == .reduced }.count ?? 0)")
                    ForEach(week?.weeklyRests ?? [], id: \.start) { rest in
                        LabeledContent(rest.duration >= Limits.regularWeeklyRest - Limits.tolerance ? "Regular weekly rest" : "Reduced weekly rest",
                                       value: "\(Fmt.dayTime(rest.start)) · \(Fmt.hm(rest.duration))")
                    }
                }

                let issues = week?.allIssues ?? []
                if !issues.isEmpty {
                    Section("Infringements") {
                        ForEach(issues) { IssueRow(issue: $0, showDate: true) }
                    }
                }

                Section {
                    ForEach(pay.lines) { line in
                        LabeledContent {
                            Text(Fmt.money(line.amount, symbol: settings.pay.currencySymbol)).monospacedDigit()
                                .foregroundStyle(line.isInfo ? .secondary : .primary)
                        } label: {
                            Text(line.label).foregroundStyle(line.isInfo ? .secondary : .primary)
                            if let hours = line.hours { Text(String(format: "%.2f h", hours)) }
                        }
                    }
                    LabeledContent {
                        Text(Fmt.money(pay.total, symbol: settings.pay.currencySymbol)).bold().monospacedDigit()
                    } label: {
                        Text("Estimated gross").bold()
                        Text(String(format: "%.2f paid hours", pay.paidHours))
                    }
                    NavigationLink("Pay settings") { PaySettingsView() }
                    NavigationLink("Overtime") { OvertimeSettingsView() }
                } header: {
                    Text("Pay")
                } footer: {
                    Text("Estimate before tax and deductions. Set your rates in Pay settings so it matches your payslip.")
                }

                Section {
                    ForEach(weekItems) { item in
                        LabeledContent {
                            Text(item.kind == .holiday
                                 ? String(format: "%.1f h", item.hours > 0 ? item.hours : settings.pay.holidayDayHours)
                                 : Fmt.money(item.amount, symbol: settings.pay.currencySymbol))
                                .monospacedDigit()
                        } label: {
                            Label(item.title.isEmpty ? item.kind.title : item.title, systemImage: item.kind.symbol)
                            Text(Fmt.day(item.date))
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                context.delete(item)
                                try? context.save()
                            }
                        }
                    }
                    Button { addingItem = true } label: { Label("Add holiday, bonus or extra", systemImage: "plus.circle.fill") }
                } header: {
                    Text("Holidays & bonuses")
                } footer: {
                    Text("Regular bonuses and allowances are set once in Settings → Pay rates. Swipe to delete.")
                }

                Section("Shifts") {
                    if let shifts = week?.shifts, !shifts.isEmpty {
                        ForEach(shifts) { shift in
                            NavigationLink { ShiftDetailView(shiftStart: shift.period.start) } label: { ShiftRow(shift: shift) }
                        }
                    } else {
                        Text("No shifts this week").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Weeks & pay")
            .toolbar {
                Button { exporting = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
            }
            .sheet(isPresented: $addingItem) {
                PayItemEditor(defaultDate: max(weekStart, min(.now, weekEnd.addingTimeInterval(-3600))))
            }
            .sheet(isPresented: $exporting) {
                ExportView(initialFrom: weekStart, initialTo: cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart)
            }
    }

    private func limitRow(_ title: String, _ value: TimeInterval, _ limit: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: "\(Fmt.hm(value)) / \(Fmt.hm(limit))")
            ProgressView(value: min(value / limit, 1))
                .tint(value > limit ? .red : (value / limit > 0.9 ? .orange : .accentColor))
        }
    }
}
