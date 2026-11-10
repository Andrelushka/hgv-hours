import Foundation

struct PayLine: Identifiable {
    let id = UUID()
    var label: String
    var hours: Double?
    var amount: Double
    /// Shown for information only (e.g. holiday pay already inside the rate); not added to the total.
    var isInfo = false
}

struct PayBreakdown {
    var lines: [PayLine] = []
    var paidHours: Double = 0
    var total: Double { lines.filter { !$0.isInfo }.reduce(0) { $0 + $1.amount } }
}

/// Estimates gross pay for a set of shifts.
///
/// Hourly: each paid minute is paid at the highest rate that applies (overtime, Saturday, Sunday,
/// bank holiday) — premiums don't stack. Each rate is either a multiplier of the basic rate or a typed-in £/hour.
/// Day rate: each shift is paid the day rate (or the Saturday/Sunday/bank holiday day rate), and paid hours
/// beyond the hours the day rate covers are paid as overtime.
/// Night premium, holiday pay, bonuses and allowances are added on top.
enum PayCalculator {
    static func calculate(shifts: [ShiftSummary], nightOuts: Int, settings p: PaySettings,
                          items: [PayItemSnapshot] = [], holidayDayValue: Double = 0,
                          calendar cal: Calendar = .hgv) -> PayBreakdown {
        var result = PayBreakdown()
        var buckets: [String: (hours: Double, amount: Double, order: Int)] = [:]
        func add(_ label: String, _ hours: Double, _ amount: Double, order: Int) {
            let current = buckets[label] ?? (0, 0, order)
            buckets[label] = (current.hours + hours, current.amount + amount, order)
        }

        var nightHours = 0.0
        var paidHours = 0.0
        var weekPaid: [Date: Double] = [:]
        let otRateHourly = p.overtimeFixedRate > 0
            ? p.overtimeFixedRate
            : (p.basis == .daily ? (p.dayRateHours > 0 ? p.dayRate / p.dayRateHours : 0) : p.baseRate) * p.overtimeMultiplier
        let otLabel = p.overtimeFixedRate > 0
            ? "Overtime \(p.currencySymbol)\(String(format: "%.2f", p.overtimeFixedRate))/h"
            : "Overtime ×\(trim(p.overtimeMultiplier))"

        for shift in shifts.sorted(by: { $0.period.start < $1.period.start }) {
            let weekKey = cal.startOfFixedWeek(for: shift.period.start)
            var shiftPaid = 0.0

            for segment in shift.period.segments {
                let weight = paidWeight(for: segment, settings: p)
                guard weight > 0 else { continue }
                var minute = segment.start
                while minute < segment.end {
                    let next = min(minute.addingTimeInterval(60), segment.end)
                    let hours = next.timeIntervalSince(minute) / 3600 * weight
                    let hour = cal.component(.hour, from: minute)
                    let inNight = p.nightPremiumStartHour > p.nightPremiumEndHour
                        ? (hour >= p.nightPremiumStartHour || hour < p.nightPremiumEndHour)
                        : (hour >= p.nightPremiumStartHour && hour < p.nightPremiumEndHour)
                    if inNight && p.nightPremiumPerHour > 0 { nightHours += hours }

                    if p.basis == .hourly {
                        let dailyOT = p.dailyOvertimeAfterHours > 0 && shiftPaid >= p.dailyOvertimeAfterHours - 0.0001
                        let weeklyOT = p.weeklyOvertimeAfterHours > 0 && weekPaid[weekKey, default: 0] >= p.weeklyOvertimeAfterHours - 0.0001
                        let day = dayRate(for: minute, settings: p, calendar: cal, base: p.baseRate)
                        if (dailyOT || weeklyOT) && otRateHourly > day.rate {
                            add(otLabel, hours, hours * otRateHourly, order: 4)
                        } else {
                            add(day.label, hours, hours * day.rate, order: day.order)
                        }
                    }
                    shiftPaid += hours
                    weekPaid[weekKey, default: 0] += hours
                    minute = next
                }
            }

            if p.basis == .daily {
                let day = dayRate(for: shift.period.start, settings: p, calendar: cal, base: p.dayRate)
                add(day.label == "Basic" ? "Day rate" : day.label + " day rate", 1, day.rate, order: day.order)
                let threshold = p.dailyOvertimeAfterHours > 0 ? p.dailyOvertimeAfterHours : p.dayRateHours
                if threshold > 0 && shiftPaid > threshold {
                    let extra = shiftPaid - threshold
                    add(otLabel, extra, extra * otRateHourly, order: 4)
                }
            } else if p.minimumPaidHoursPerShift > 0 && shiftPaid < p.minimumPaidHoursPerShift {
                let topUp = p.minimumPaidHoursPerShift - shiftPaid
                add("Guaranteed hours top-up", topUp, topUp * p.baseRate, order: 6)
                shiftPaid += topUp
            }
            paidHours += shiftPaid
        }

        for (label, value) in buckets.sorted(by: { ($0.value.order, $0.key) < ($1.value.order, $1.key) }) {
            let isDayCount = p.basis == .daily && label.hasSuffix("ay rate")
            result.lines.append(PayLine(label: isDayCount ? "\(label) × \(Int(value.hours.rounded()))" : label,
                                        hours: isDayCount ? nil : value.hours, amount: value.amount))
        }
        if result.lines.isEmpty { result.lines.append(PayLine(label: p.basis == .daily ? "Day rate" : "Basic", hours: 0, amount: 0)) }

        if nightHours > 0 {
            result.lines.append(PayLine(label: "Night premium", hours: nightHours, amount: nightHours * p.nightPremiumPerHour))
        }

        // Holiday days taken (from the calendar / Weeks screen), paid at the average day's pay.
        let holidays = items.filter { $0.kind == .holiday }
        if !holidays.isEmpty {
            let fallback = p.basis == .daily ? p.dayRate : p.baseRate * p.holidayDayHours
            let perDay = holidayDayValue > 0 ? holidayDayValue : fallback
            let hours = holidays.reduce(0) { $0 + ($1.hours > 0 ? $1.hours : p.holidayDayHours) }
            if p.holiday == .included {
                result.lines.append(PayLine(label: "Holiday × \(holidays.count) (already in your rate)", hours: nil, amount: 0, isInfo: true))
            } else {
                result.lines.append(PayLine(label: "Holiday pay × \(holidays.count) day\(holidays.count == 1 ? "" : "s")", hours: nil,
                                            amount: Double(holidays.count) * perDay))
            }
            paidHours += hours
        }

        // Holiday pay on worked time.
        let earnings = result.total
        let workedHours = paidHours - holidays.reduce(0) { $0 + ($1.hours > 0 ? $1.hours : p.holidayDayHours) }
        switch p.holiday {
        case .included:
            let rate = HolidayMode.ukRate
            result.lines.append(PayLine(label: "of which holiday pay (\(trim(rate))%)", hours: nil,
                                        amount: earnings * rate / (100 + rate), isInfo: true))
        case .separate:
            result.lines.append(PayLine(label: "Holiday earned (\(trim(HolidayMode.ukRate))% of hours)",
                                        hours: max(0, workedHours) * HolidayMode.ukRate / 100, amount: 0, isInfo: true))
        case .none:
            break
        }

        // Regular extras.
        let weeks = Set(shifts.map { cal.startOfFixedWeek(for: $0.period.start) }).count
        for extra in p.extras where extra.amount != 0 {
            let count: Int
            switch extra.per {
            case .shift: count = shifts.count
            case .week: count = weeks
            case .nightOut: count = nightOuts
            }
            if count > 0 {
                let name = extra.name.isEmpty ? "Extra" : extra.name
                result.lines.append(PayLine(label: count > 1 ? "\(name) × \(count)" : name, hours: nil, amount: Double(count) * extra.amount))
            }
        }

        // One-off bonuses.
        for bonus in items where bonus.kind == .bonus && bonus.amount != 0 {
            result.lines.append(PayLine(label: bonus.title.isEmpty ? "Bonus" : bonus.title, hours: nil, amount: bonus.amount))
        }

        if nightOuts > 0 && p.nightOutAllowance > 0 {
            result.lines.append(PayLine(label: "Night-out allowance × \(nightOuts)", hours: nil, amount: Double(nightOuts) * p.nightOutAllowance))
        }
        result.paidHours = paidHours
        return result
    }

    /// Average pay for a worked day over the 52 weeks before `date` (UK holiday pay for variable pay),
    /// excluding holiday pay and one-off bonuses.
    static func averageDayPay(shifts: [ShiftSummary], before date: Date, settings p: PaySettings, calendar cal: Calendar = .hgv) -> Double {
        let from = date.addingTimeInterval(-52 * 7 * 86_400)
        let worked = shifts.filter { $0.period.start >= from && $0.period.start < date && !$0.period.isOpen }
        guard !worked.isEmpty else { return 0 }
        var p2 = p
        p2.holidayMode = HolidayMode.none.rawValue
        p2.extras = p.extras.filter { $0.per == .shift }
        let total = calculate(shifts: worked, nightOuts: 0, settings: p2, calendar: cal).total
        return total / Double(worked.count)
    }

    /// The rate for a day: bank holiday, Sunday, Saturday or normal. `base` is £/h (hourly) or £/day (day rate).
    static func dayRate(for date: Date, settings p: PaySettings, calendar cal: Calendar, base: Double) -> (label: String, rate: Double, order: Int) {
        func rate(_ fixed: Double, _ multiplier: Double) -> Double { fixed > 0 ? fixed : base * multiplier }
        if BankHolidays.isBankHoliday(date, calendar: cal) {
            let r = rate(p.bankHolidayFixedRate, p.bankHolidayMultiplier)
            if r != base { return ("Bank holiday", r, 3) }
        }
        let weekday = cal.component(.weekday, from: date) // 1 = Sunday, 7 = Saturday
        if weekday == 1 {
            let r = rate(p.sundayFixedRate, p.sundayMultiplier)
            if r != base { return ("Sunday", r, 2) }
        }
        if weekday == 7 {
            let r = rate(p.saturdayFixedRate, p.saturdayMultiplier)
            if r != base { return ("Saturday", r, 1) }
        }
        return ("Basic", base, 0)
    }

    static func paidWeight(for segment: Segment, settings p: PaySettings) -> Double {
        switch segment.kind {
        case .drive: return p.payDriving ? 1 : 0
        case .otherWork: return p.payOtherWork ? 1 : 0
        case .availability: return p.payAvailability ? p.availabilityPercent / 100 : 0
        case .rest:
            // Only short breaks inside a shift are ever paid; never the first part of a split rest.
            return p.payBreaks && segment.duration < Limits.splitRestFirstPart ? 1 : 0
        }
    }

    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }
}

/// England & Wales bank holidays, calculated for any year.
enum BankHolidays {
    static func isBankHoliday(_ date: Date, calendar cal: Calendar = .hgv) -> Bool {
        let year = cal.component(.year, from: date)
        return dates(year: year, calendar: cal).contains { cal.isDate($0, inSameDayAs: date) }
    }

    static func dates(year: Int, calendar cal: Calendar = .hgv) -> [Date] {
        func day(_ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: year, month: m, day: d)) ?? .distantPast }
        func weekday(_ date: Date) -> Int { cal.component(.weekday, from: date) }
        /// Moves a Saturday/Sunday holiday to the next free weekday.
        func substitute(_ date: Date, taken: [Date]) -> Date {
            var d = date
            while weekday(d) == 1 || weekday(d) == 7 || taken.contains(where: { cal.isDate($0, inSameDayAs: d) }) {
                d = cal.date(byAdding: .day, value: 1, to: d) ?? d
            }
            return d
        }
        func firstMonday(_ m: Int) -> Date {
            var d = day(m, 1)
            while weekday(d) != 2 { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            return d
        }
        func lastMonday(_ m: Int) -> Date {
            var d = cal.date(byAdding: .day, value: -1, to: day(m + 1, 1)) ?? day(m, 28)
            while weekday(d) != 2 { d = cal.date(byAdding: .day, value: -1, to: d) ?? d }
            return d
        }
        // Easter Sunday (anonymous Gregorian algorithm).
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, dayOfMonth = (h + l - 7 * m + 114) % 31 + 1
        let easter = day(month, dayOfMonth)

        var result: [Date] = []
        result.append(substitute(day(1, 1), taken: []))
        result.append(cal.date(byAdding: .day, value: -2, to: easter) ?? easter)
        result.append(cal.date(byAdding: .day, value: 1, to: easter) ?? easter)
        result.append(firstMonday(5))
        result.append(lastMonday(5))
        result.append(lastMonday(8))
        let christmas = substitute(day(12, 25), taken: [])
        result.append(christmas)
        result.append(substitute(day(12, 26), taken: [christmas]))
        return result
    }
}
