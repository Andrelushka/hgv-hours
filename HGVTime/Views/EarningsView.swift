import SwiftUI
import SwiftData
import Charts

/// Earnings per week, month or year, with a chart and an estimate for the full period.
struct EarningsView: View {
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \NightOut.date) private var nightOuts: [NightOut]
    @Query(sort: \PayItem.date) private var payItems: [PayItem]
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]

    @State private var period: EarningsPeriod = .week
    @State private var offset = 0

    var body: some View {
        let cal = Calendar.hgv
        let settings = store.settings
        let p = settings.pay
        let component: Calendar.Component = period == .week ? .weekOfYear : (period == .month ? .month : .year)
        let anchor = cal.date(byAdding: component, value: offset, to: .now) ?? .now
        let analysis = RulesEngine.analyze(entries.map(\.snapshot), now: .now, config: settings.ruleConfig)
        let e = Earnings.compute(period, anchor: anchor, shifts: analysis.shifts, nights: nightOuts.map(\.date),
                                 items: payItems.map(\.snapshot),
                                 plannedStarts: plans.map { ($0.plannedStart, $0.length / 3600) }, settings: p)
        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(EarningsPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: period) { _, _ in offset = 0 }
                HStack {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(title(e)).font(.headline)
                    Spacer()
                    Button { offset += 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(offset >= 0)
                }
                .buttonStyle(.borderless)
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(offset == 0 ? "Earned so far" : "Earned").font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.money(e.breakdown.total, symbol: p.currencySymbol))
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(e.shiftCount) shift\(e.shiftCount == 1 ? "" : "s")").font(.subheadline.weight(.semibold))
                        Text(String(format: "%.1f paid h", e.breakdown.paidHours)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let estimate = e.estimate {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Label("Estimated by end of \(period.rawValue)", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(Fmt.money(estimate, symbol: p.currencySymbol)).font(.title3.weight(.bold).monospacedDigit())
                        }
                        Text(e.estimateNote).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Chart(Array(e.bars.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("When", item.element.label), y: .value("Earned", item.element.amount))
                        .foregroundStyle(Color.green.gradient)
                        .cornerRadius(4)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 160)
                .padding(.vertical, 4)
            }

            Section("Breakdown") {
                ForEach(e.breakdown.lines.filter { $0.amount != 0 || $0.isInfo }) { line in
                    LabeledContent {
                        Text(line.isInfo && line.amount == 0 && line.hours != nil
                             ? String(format: "%.2f h", line.hours ?? 0)
                             : Fmt.money(line.amount, symbol: p.currencySymbol))
                            .monospacedDigit()
                            .foregroundStyle(line.isInfo ? .secondary : .primary)
                    } label: {
                        Text(line.label).foregroundStyle(line.isInfo ? .secondary : .primary)
                        if let hours = line.hours, !line.isInfo, hours > 0 { Text(String(format: "%.2f h", hours)) }
                    }
                }
                LabeledContent {
                    Text(Fmt.money(e.breakdown.total, symbol: p.currencySymbol)).bold().monospacedDigit()
                } label: {
                    Text("Estimated gross").bold()
                }
            }

            Section {
                if period == .week {
                    NavigationLink { WeeksView(initialOffset: offset) } label: {
                        Label("Week details: limits, holidays, bonuses, shifts", systemImage: "calendar")
                    }
                }
                NavigationLink { SummaryView() } label: { Label("Summary table of every day", systemImage: "tablecells") }
                NavigationLink { PaySettingsView() } label: { Label("Pay rates", systemImage: "sterlingsign.circle") }
                NavigationLink { OvertimeSettingsView() } label: { Label("Overtime", systemImage: "clock.badge.checkmark") }
            } footer: {
                Text("Estimates are before tax and deductions.")
            }
        }
        .navigationTitle("Earnings")
    }

    private func title(_ e: PeriodEarnings) -> String {
        switch e.period {
        case .week: "w/c \(Fmt.day(e.start))"
        case .month: e.start.formatted(.dateTime.month(.wide).year())
        case .year: e.start.formatted(.dateTime.year())
        }
    }
}
