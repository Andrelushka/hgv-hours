import XCTest
@testable import HGVTime

final class RulesEngineTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar.hgv
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    private lazy var config: RuleConfig = {
        var c = RuleConfig()
        c.calendar = cal
        return c
    }()

    /// Monday 3 November 2025 at the given hour/minute (+ dayOffset days).
    private func t(_ hour: Int, _ minute: Int = 0, day dayOffset: Int = 0) -> Date {
        let base = cal.date(from: DateComponents(year: 2025, month: 11, day: 3, hour: 0, minute: 0))!
        return cal.date(byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute), to: base)!
    }

    private func e(_ kind: DutyKind, _ start: Date, _ end: Date?, regime: Regime = .assimilated, multi: Bool = false) -> EntrySnapshot {
        EntrySnapshot(kind: kind, regime: regime, start: start, end: end, multiManned: multi)
    }

    // MARK: Timeline

    func testGapsBecomeRestAndOverlapsAreClipped() {
        let entries = [
            e(.drive, t(6), t(8)),
            e(.otherWork, t(7, 30), t(9)),   // overlaps: drive is clipped to 07:30
            e(.drive, t(10), t(11))          // 09:00–10:00 gap becomes rest
        ]
        let segments = Timeline.build(entries, now: t(11))
        XCTAssertEqual(segments.map(\.kind), [.drive, .otherWork, .rest, .drive])
        XCTAssertEqual(segments[0].end, t(7, 30))
        XCTAssertEqual(segments[2].duration, 3600)
    }

    // MARK: Breaks

    func testFourAndAHalfHoursDrivingIsOK() {
        let entries = [e(.drive, t(6), t(10, 30)), e(.rest, t(10, 30), t(11, 15)), e(.drive, t(11, 15), t(12))]
        let a = RulesEngine.analyze(entries, now: t(12), config: config)
        XCTAssertTrue(a.shifts[0].issues.filter { $0.title.contains("4h30") }.isEmpty)
        XCTAssertEqual(a.shifts[0].stats.continuousDriving, 45 * 60, accuracy: 1)
    }

    func testOverFourAndAHalfHoursIsInfringement() {
        let entries = [e(.drive, t(6), t(10, 40))]
        let a = RulesEngine.analyze(entries, now: t(10, 40), config: config)
        XCTAssertTrue(a.shifts[0].issues.contains { $0.title.contains("4h30") })
    }

    func testSplitBreak15Then30Resets() {
        let entries = [
            e(.drive, t(6), t(8)), e(.rest, t(8), t(8, 15)),
            e(.drive, t(8, 15), t(10, 30)), e(.rest, t(10, 30), t(11)),
            e(.drive, t(11), t(12))
        ]
        let s = RulesEngine.status(entries, now: t(12), config: config)
        XCTAssertEqual(s.stats.continuousDriving, 3600, accuracy: 1)
    }

    func testSplitBreak30Then15DoesNotReset() {
        let entries = [
            e(.drive, t(6), t(8)), e(.rest, t(8), t(8, 30)),
            e(.drive, t(8, 30), t(10)), e(.rest, t(10), t(10, 15)),
            e(.drive, t(10, 15), t(11))
        ]
        let s = RulesEngine.status(entries, now: t(11), config: config)
        // 30 counts as a first part, the 15 doesn't complete it → 2h + 1h30 + 45m.
        XCTAssertEqual(s.stats.continuousDriving, 4.25 * 3600, accuracy: 1)
    }

    // MARK: Daily driving & extensions

    func testThirdTenHourDayInAWeekIsFlagged() {
        var entries: [EntrySnapshot] = []
        for day in 0..<3 {
            entries += [
                e(.drive, t(6, day: day), t(10, 30, day: day)),
                e(.rest, t(10, 30, day: day), t(11, 15, day: day)),
                e(.drive, t(11, 15, day: day), t(15, 45, day: day)),
                e(.rest, t(15, 45, day: day), t(16, 30, day: day)),
                e(.drive, t(16, 30, day: day), t(17, 30, day: day)),
                e(.rest, t(17, 30, day: day), t(6, day: day + 1))
            ]
        }
        let a = RulesEngine.analyze(entries, now: t(12, day: 3), config: config)
        XCTAssertEqual(a.shifts.count, 3)
        XCTAssertTrue(a.weeks[0].issues.contains { $0.title.contains("10h driving days") })
    }

    func testDailyLimitDropsToNineAfterTwoExtensions() {
        var entries: [EntrySnapshot] = []
        for day in 0..<2 {
            entries += [
                e(.drive, t(6, day: day), t(10, 30, day: day)),
                e(.rest, t(10, 30, day: day), t(11, 15, day: day)),
                e(.drive, t(11, 15, day: day), t(15, 45, day: day)),
                e(.rest, t(15, 45, day: day), t(16, 30, day: day)),
                e(.drive, t(16, 30, day: day), t(17, 30, day: day)),
                e(.rest, t(17, 30, day: day), t(6, day: day + 1))
            ]
        }
        entries.append(e(.drive, t(6, day: 2), nil))
        let s = RulesEngine.status(entries, now: t(7, day: 2), config: config)
        XCTAssertEqual(s.extensionsUsed, 2)
        XCTAssertEqual(s.dailyDrivingLimit, 9 * 3600)
    }

    // MARK: Daily rest

    func testRestDeadlines() {
        let entries = [e(.drive, t(6), nil)]
        let s = RulesEngine.status(entries, now: t(8), config: config)
        XCTAssertEqual(s.restStartByFull, t(19))      // 11h rest inside 24h
        XCTAssertEqual(s.restStartByLatest, t(21))    // 9h reduced rest
    }

    func testMultiMannedRestDeadline() {
        let entries = [e(.drive, t(6), nil, multi: true)]
        let s = RulesEngine.status(entries, now: t(8), config: config)
        XCTAssertEqual(s.restStartByLatest, t(3, day: 1)) // 06:00 + 30h − 9h
    }

    func testShortRestIsInsufficient() {
        let entries = [
            e(.drive, t(6), t(10)),
            e(.otherWork, t(10), t(20)),           // finishes at 20:00, rest 20:00–05:00 next day = 9h
            e(.rest, t(20), t(5, day: 1)),
            e(.drive, t(5, day: 1), t(6, day: 1))
        ]
        let a = RulesEngine.analyze(entries, now: t(6, day: 1), config: config)
        XCTAssertEqual(a.shifts.first?.restKind, .reduced)

        let late = [
            e(.drive, t(6), t(10)),
            e(.otherWork, t(10), t(22)),           // 9h rest must finish by 06:00 → only 8h fits
            e(.rest, t(22), t(7, day: 1)),
            e(.drive, t(7, day: 1), t(8, day: 1))
        ]
        let b = RulesEngine.analyze(late, now: t(8, day: 1), config: config)
        XCTAssertEqual(b.shifts.first?.restKind, .insufficient)
    }

    // MARK: Working time

    func testWorkingSixHoursWithoutBreakIsFlagged() {
        let entries = [e(.otherWork, t(6), t(9)), e(.drive, t(9), t(12, 10))]
        let a = RulesEngine.analyze(entries, now: t(12, 10), config: config)
        XCTAssertTrue(a.shifts[0].issues.contains { $0.family == .workingTime && $0.title.contains("6h") })
    }

    func testPOADoesNotCountAsWork() {
        let entries = [e(.otherWork, t(6), t(10)), e(.availability, t(10), t(13)), e(.otherWork, t(13), t(14))]
        let a = RulesEngine.analyze(entries, now: t(14), config: config)
        XCTAssertEqual(a.shifts[0].stats.workingTime, 5 * 3600, accuracy: 1)
    }

    func testNightWorkLimit() {
        let entries = [
            e(.otherWork, t(2), t(6)), e(.rest, t(6), t(6, 45)),
            e(.drive, t(6, 45), t(10)), e(.rest, t(10), t(10, 45)),
            e(.drive, t(10, 45), t(14, 45))
        ]
        let a = RulesEngine.analyze(entries, now: t(15), config: config)
        XCTAssertTrue(a.shifts[0].stats.nightWork)
        XCTAssertTrue(a.shifts[0].issues.contains { $0.title.contains("Night work") })
    }

    // MARK: GB domestic

    func testGBDutyLimit() {
        var gb = config
        gb.primaryRegime = .gbDomestic
        let entries = [e(.drive, t(6), t(12), regime: .gbDomestic), e(.otherWork, t(12), t(17, 30), regime: .gbDomestic)]
        let a = RulesEngine.analyze(entries, now: t(18), config: gb)
        XCTAssertTrue(a.shifts[0].issues.contains { $0.title.contains("Duty over 11h") })
        // GB driving doesn't count towards the tacho 4h30 rule.
        XCTAssertFalse(a.shifts[0].issues.contains { $0.title.contains("4h30") })
    }

    // MARK: Pay

    func testPayWithOvertimeAndUnpaidBreak() {
        var pay = PaySettings()
        pay.baseRate = 10
        pay.dailyOvertimeAfterHours = 8
        pay.overtimeMultiplier = 1.5
        // Mon 06:00–16:45 with a 45 min unpaid break → 10h paid: 8h basic + 2h overtime.
        let entries = [e(.drive, t(6), t(10, 30)), e(.rest, t(10, 30), t(11, 15)), e(.otherWork, t(11, 15), t(16, 45))]
        let a = RulesEngine.analyze(entries, now: t(17), config: config)
        let result = PayCalculator.calculate(shifts: a.shifts, nightOuts: 1, settings: pay, calendar: cal)
        XCTAssertEqual(result.paidHours, 10, accuracy: 0.01)
        XCTAssertEqual(result.total, 8 * 10 + 2 * 15, accuracy: 0.05)
    }

    func testDayRateWithOvertime() {
        var pay = PaySettings()
        pay.payBasis = PayBasis.daily.rawValue
        pay.dayRate = 150
        pay.dayRateHours = 10
        pay.overtimeFixedRate = 20
        // Mon 06:00–18:00 all paid = 12h → day rate + 2h overtime at £20.
        let entries = [e(.drive, t(6), t(12)), e(.otherWork, t(12), t(18))]
        let a = RulesEngine.analyze(entries, now: t(19), config: config)
        let result = PayCalculator.calculate(shifts: a.shifts, nightOuts: 0, settings: pay, calendar: cal)
        XCTAssertEqual(result.total, 150 + 2 * 20, accuracy: 0.05)
    }

    func testTypedSundayRateAndHolidayPaidSeparately() {
        var pay = PaySettings()
        pay.baseRate = 10
        pay.sundayFixedRate = 18
        pay.holidayMode = HolidayMode.separate.rawValue
        // Sunday 9 Nov 2025 08:00–12:00 → 4h × £18 = 72. Holiday is only accrued (info), not added.
        let entries = [e(.drive, t(8, day: 6), t(12, day: 6))]
        let a = RulesEngine.analyze(entries, now: t(13, day: 6), config: config)
        let result = PayCalculator.calculate(shifts: a.shifts, nightOuts: 0, settings: pay, calendar: cal)
        XCTAssertEqual(result.total, 72, accuracy: 0.05)
        XCTAssertEqual(result.lines.first { $0.label.hasPrefix("Holiday earned") }?.hours ?? 0, 4 * 0.1207, accuracy: 0.001)
    }

    func testHolidayDayPaidAtAverageDayPay() {
        var pay = PaySettings()
        pay.baseRate = 10
        pay.holidayMode = HolidayMode.separate.rawValue
        // Two past shifts: 8h and 10h → average day £90.
        let history = [e(.drive, t(8), t(16)), e(.drive, t(8, day: 1), t(18, day: 1))]
        let a = RulesEngine.analyze(history, now: t(12, day: 3), config: config)
        let avg = PayCalculator.averageDayPay(shifts: a.shifts, before: t(0, day: 7), settings: pay, calendar: cal)
        XCTAssertEqual(avg, 90, accuracy: 0.05)
        let items = [PayItemSnapshot(date: t(12, day: 8), kind: .holiday, title: "", amount: 0, hours: 0)]
        let result = PayCalculator.calculate(shifts: [], nightOuts: 0, settings: pay, items: items, holidayDayValue: avg, calendar: cal)
        XCTAssertEqual(result.total, 90, accuracy: 0.05)
    }

    func testHolidayIncludedIsInfoOnly() {
        var pay = PaySettings()
        pay.baseRate = 11.207
        pay.holidayMode = HolidayMode.included.rawValue
        let entries = [e(.drive, t(8), t(18))]
        let a = RulesEngine.analyze(entries, now: t(19), config: config)
        let result = PayCalculator.calculate(shifts: a.shifts, nightOuts: 0, settings: pay, calendar: cal)
        XCTAssertEqual(result.total, 112.07, accuracy: 0.05)
        XCTAssertEqual(result.lines.first { $0.isInfo }?.amount ?? 0, 12.07, accuracy: 0.05)
    }

    func testExtrasHolidayDaysAndBonuses() {
        var pay = PaySettings()
        pay.baseRate = 10
        pay.holidayMode = HolidayMode.separate.rawValue
        pay.extras = [PayExtra(name: "Tipper bonus", amount: 20, per: .shift), PayExtra(name: "Phone", amount: 5, per: .week)]
        let entries = [e(.drive, t(8), t(10)), e(.drive, t(8, day: 1), t(10, day: 1))]
        let a = RulesEngine.analyze(entries, now: t(11, day: 1), config: config)
        let items = [PayItemSnapshot(date: t(12, day: 2), kind: .holiday, title: "", amount: 0, hours: 8),
                     PayItemSnapshot(date: t(12, day: 2), kind: .bonus, title: "Xmas", amount: 50, hours: 0)]
        let result = PayCalculator.calculate(shifts: a.shifts, nightOuts: 0, settings: pay, items: items, holidayDayValue: 80, calendar: cal)
        // 4h × 10 + holiday day £80 + 2 × 20 + 5 + 50
        XCTAssertEqual(result.total, 40 + 80 + 40 + 5 + 50, accuracy: 0.05)
    }

    func testEnglandBankHolidays() {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(BankHolidays.dates(year: 2026, calendar: cal).map(f.string(from:)),
                       ["2026-01-01", "2026-04-03", "2026-04-06", "2026-05-04", "2026-05-25", "2026-08-31", "2026-12-25", "2026-12-28"])
        XCTAssertEqual(BankHolidays.dates(year: 2027, calendar: cal).map(f.string(from:)),
                       ["2027-01-01", "2027-03-26", "2027-03-29", "2027-05-03", "2027-05-31", "2027-08-30", "2027-12-27", "2027-12-28"])
    }
}
