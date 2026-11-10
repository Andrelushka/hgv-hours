import Foundation

enum EarningsPeriod: String, CaseIterable, Identifiable {
    case week, month, year
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Earnings for a week, month or year, with a bar per day/week/month and an estimate for the full period.
struct PeriodEarnings {
    var period: EarningsPeriod
    var start: Date
    var end: Date
    var breakdown: PayBreakdown
    var shiftCount: Int
    var bars: [(label: String, amount: Double)]
    /// Projected total for the whole period (only for the current period).
    var estimate: Double?
    var estimateNote: String = ""
}

enum Earnings {
    static func interval(_ period: EarningsPeriod, containing date: Date, calendar cal: Calendar = .hgv) -> (Date, Date) {
        switch period {
        case .week:
            let s = cal.startOfFixedWeek(for: date)
            return (s, cal.date(byAdding: .day, value: 7, to: s) ?? s)
        case .month:
            let s = cal.dateInterval(of: .month, for: date)?.start ?? date
            return (s, cal.date(byAdding: .month, value: 1, to: s) ?? s)
        case .year:
            let s = cal.dateInterval(of: .year, for: date)?.start ?? date
            return (s, cal.date(byAdding: .year, value: 1, to: s) ?? s)
        }
    }

    /// Pay for shifts starting in [from, to).
    static func pay(from: Date, to: Date, shifts: [ShiftSummary], nights: [Date], items: [PayItemSnapshot],
                    settings p: PaySettings, holidayValue: Double, monthly: Bool, now: Date) -> (PayBreakdown, Int) {
        let inRange = shifts.filter { $0.period.start >= from && $0.period.start < to }
        let n = nights.filter { $0 >= from && $0 < to }.count
        let its = items.filter { $0.date >= from && $0.date < to }
        // Salary accrues day by day up to today.
        let salaryDays = max(0, min(to, max(from, now)).timeIntervalSince(from) / 86_400)
        let b = PayCalculator.calculate(shifts: inRange, nightOuts: n, settings: p, items: its, holidayDayValue: holidayValue,
                                        salaryDays: salaryDays, applyMonthlyGuarantee: monthly)
        return (b, inRange.count)
    }

    static func compute(_ period: EarningsPeriod, anchor: Date, shifts: [ShiftSummary], nights: [Date], items: [PayItemSnapshot],
                        plannedStarts: [(start: Date, hours: Double)], settings p: PaySettings, now: Date = .now,
                        calendar cal: Calendar = .hgv) -> PeriodEarnings {
        let (start, end) = interval(period, containing: anchor, calendar: cal)
        let holidayValue = PayCalculator.averageDayPay(shifts: shifts, before: start, settings: p)

        // Totals: a year is the sum of its months so monthly guarantees apply.
        var breakdown: PayBreakdown
        var count = 0
        if period == .year {
            breakdown = PayBreakdown()
            var merged: [String: (Double?, Double, Bool)] = [:]
            var order: [String] = []
            var m = start
            while m < end {
                let next = cal.date(byAdding: .month, value: 1, to: m) ?? end
                let (b, c) = pay(from: m, to: next, shifts: shifts, nights: nights, items: items, settings: p,
                                 holidayValue: holidayValue, monthly: true, now: now)
                count += c
                breakdown.paidHours += b.paidHours
                for line in b.lines where line.amount != 0 || line.hours ?? 0 != 0 {
                    let key = line.label
                    if merged[key] == nil { order.append(key) }
                    let cur = merged[key] ?? (nil, 0, line.isInfo)
                    let hours = (cur.0 ?? 0) + (line.hours ?? 0)
                    merged[key] = (line.hours == nil && cur.0 == nil ? nil : hours, cur.1 + line.amount, line.isInfo)
                }
                m = next
            }
            breakdown.lines = order.map { PayLine(label: $0, hours: merged[$0]?.0, amount: merged[$0]?.1 ?? 0, isInfo: merged[$0]?.2 ?? false) }
        } else {
            (breakdown, count) = pay(from: start, to: end, shifts: shifts, nights: nights, items: items, settings: p,
                                     holidayValue: holidayValue, monthly: period == .month, now: now)
        }

        // Bars: days of a week, weeks of a month, months of a year.
        var bars: [(String, Double)] = []
        var cursor = start
        let step: Calendar.Component = period == .week ? .day : (period == .month ? .weekOfYear : .month)
        if period == .month { cursor = cal.startOfFixedWeek(for: start) }
        while cursor < end {
            let next = cal.date(byAdding: step, value: 1, to: cursor) ?? end
            let from = max(cursor, start), to = min(next, end)
            let (b, _) = pay(from: from, to: to, shifts: shifts, nights: nights, items: items, settings: p,
                             holidayValue: holidayValue, monthly: period == .year, now: now)
            let label: String
            switch period {
            case .week: label = cursor.formatted(.dateTime.weekday(.abbreviated))
            case .month: label = from.formatted(.dateTime.day().month(.abbreviated))
            case .year: label = cursor.formatted(.dateTime.month(.abbreviated))
            }
            bars.append((label, b.total))
            cursor = next
        }

        var result = PeriodEarnings(period: period, start: start, end: end, breakdown: breakdown, shiftCount: count, bars: bars)

        // Estimate for the period we're in.
        if now >= start && now < end {
            let recent = shifts.filter { !$0.period.isOpen && $0.period.start >= now.addingTimeInterval(-56 * 86_400) && $0.period.start < now }
            let avgShiftPay: Double = {
                guard !recent.isEmpty else { return p.basis == .daily ? p.dayRate : p.baseRate * 9 }
                var q = p
                q.extras = p.extras.filter { $0.per == .shift }
                q.minimumPaidHoursPerWeek = 0
                if q.basis == .salary { q.salaryAmount = 0 }
                return PayCalculator.calculate(shifts: recent, nightOuts: 0, settings: q, salaryDays: 0).total / Double(recent.count)
            }()
            let remainingPlans = plannedStarts.filter { $0.start > now && $0.start < end }
            var projected: Double
            var expectedShifts: Double
            if !remainingPlans.isEmpty {
                expectedShifts = Double(remainingPlans.count)
                projected = expectedShifts * avgShiftPay
                result.estimateNote = "Includes \(remainingPlans.count) planned shift\(remainingPlans.count == 1 ? "" : "s") at your average shift pay."
            } else {
                let perDay = Double(recent.count) / 56
                let daysLeft = end.timeIntervalSince(now) / 86_400
                expectedShifts = perDay * daysLeft
                projected = expectedShifts * avgShiftPay
                result.estimateNote = recent.isEmpty
                    ? "Not enough history yet — plan your work in the Calendar for a better estimate."
                    : String(format: "Based on your last 8 weeks (%.1f shifts a week).", perDay * 7)
            }
            if p.basis == .salary {
                // Salary for the rest of the period is certain; only overtime is estimated.
                let restDays = end.timeIntervalSince(now) / 86_400
                projected += p.salaryPer == .day ? expectedShifts * p.salaryAmount : p.weeklySalary * restDays / 7
            }
            result.estimate = breakdown.total + projected
        }
        return result
    }
}
