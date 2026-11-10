import SwiftUI
import SwiftData

/// Live earnings for the current shift and this week. Tap for the full Weeks & pay breakdown.
struct PayCounterCard: View {
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \NightOut.date) private var nightOuts: [NightOut]
    @Query(sort: \PayItem.date) private var payItems: [PayItem]

    var now: Date
    var currentShiftStart: Date?

    var body: some View {
        let cal = Calendar.hgv
        let settings = store.settings
        let p = settings.pay
        let weekStart = cal.startOfFixedWeek(for: now)
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? now
        // Include the day before so a shift that started Sunday night is analysed whole.
        let from = weekStart.addingTimeInterval(-86_400 * 2)
        let snapshots = entries.filter { ($0.end ?? now) > from }.map(\.snapshot)
        let analysis = RulesEngine.analyze(snapshots, now: now, config: settings.ruleConfig)
        let weekShifts = analysis.shifts.filter { $0.period.start >= weekStart && $0.period.start < weekEnd }
        let nights = nightOuts.filter { $0.date >= weekStart && $0.date < weekEnd }.count
        let items = payItems.filter { $0.date >= weekStart && $0.date < weekEnd }.map(\.snapshot)
        let holidayValue = items.contains { $0.kind == .holiday }
            ? PayCalculator.averageDayPay(shifts: RulesEngine.analyze(entries.map(\.snapshot), now: now, config: settings.ruleConfig).shifts,
                                          before: weekStart, settings: p)
            : 0
        let week = PayCalculator.calculate(shifts: weekShifts, nightOuts: nights, settings: p, items: items, holidayDayValue: holidayValue)

        let shift = currentShiftStart.flatMap { start in analysis.shifts.first { abs($0.period.start.timeIntervalSince(start)) < 60 } }
            ?? analysis.shifts.last.flatMap { cal.isDate($0.period.start, inSameDayAs: now) ? $0 : nil }
        let shiftPay = shift.map { PayCalculator.calculate(shifts: [$0], nightOuts: 0, settings: p) }

        return NavigationLink {
            EarningsView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(currentShiftStart != nil ? "Earned this shift" : "Earned today", systemImage: "sterlingsign.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Details").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.money(shiftPay?.total ?? 0, symbol: p.currencySymbol))
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(.green)
                    if let hours = shiftPay?.paidHours, hours > 0 {
                        Text(String(format: "%.2f h paid", hours)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week").font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.money(week.total, symbol: p.currencySymbol))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Paid hours").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.1f h", week.paidHours)).font(.title3.weight(.semibold).monospacedDigit())
                    }
                }
                if p.basis == .hourly && p.baseRate == 0 || p.basis == .daily && p.dayRate == 0 {
                    Text("Set your rate in Settings → Pay rates to see your earnings.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding()
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .animation(.default, value: shiftPay?.total)
        }
        .buttonStyle(.plain)
    }
}
