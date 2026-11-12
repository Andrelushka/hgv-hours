import XCTest
import SwiftData
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

    func testPayStopsAtEndOfShift() {
        var pay = PaySettings()
        pay.baseRate = 10
        pay.payBreaks = true
        // Work 06:00–14:00, then End shift (rest). An hour later, pay must still be 8h — the rest isn't a paid break.
        let entries = [e(.otherWork, t(6), t(14)), e(.rest, t(14), nil)]
        let a = RulesEngine.analyze(entries, now: t(15), config: config)
        let result = PayCalculator.calculate(shifts: a.shifts, nightOuts: 0, settings: pay, calendar: cal)
        XCTAssertEqual(result.paidHours, 8, accuracy: 0.01)
        // A short break followed by work is still paid when breaks are paid.
        let withBreak = [e(.otherWork, t(6), t(10)), e(.rest, t(10), t(10, 30)), e(.otherWork, t(10, 30), t(14))]
        let b = RulesEngine.analyze(withBreak, now: t(15), config: config)
        XCTAssertEqual(PayCalculator.calculate(shifts: b.shifts, nightOuts: 0, settings: pay, calendar: cal).paidHours, 8, accuracy: 0.01)
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

    // MARK: Combined driving + working time

    func testDrivingLeftIsCappedByWorkingTime() {
        // 4h other work, then 1h driving: drivers' hours allow 3h30 more driving,
        // but working time allows only 1h more before a 6h break is due.
        let entries = [e(.otherWork, t(6), t(10)), e(.drive, t(10), nil)]
        let s = RulesEngine.status(entries, now: t(11), config: config)
        XCTAssertEqual(s.driveAvailableBeforeWorkingTime, 3.5 * 3600, accuracy: 61)
        XCTAssertEqual(s.driveAvailableNow, 1 * 3600, accuracy: 61)
    }

    func testBreakPlanPicksWorkingTimeWhenItComesFirst() {
        let entries = [e(.otherWork, t(6), t(10)), e(.drive, t(10), nil)]
        let s = RulesEngine.status(entries, now: t(11), config: config)
        let plan = Deadlines.breakPlan(s, applyWorkingTime: true)
        XCTAssertEqual(plan?.reason, "6h working time")
        XCTAssertEqual(plan?.dueBy ?? .distantPast, t(12), "due after 6h of work")
        XCTAssertGreaterThanOrEqual(plan?.recommended ?? 0, 30 * 60, "a 6–9h day needs 30 min of breaks")
    }

    func testBreakPlanPicksDrivingWhenItComesFirst() {
        let entries = [e(.drive, t(6), nil)]
        let s = RulesEngine.status(entries, now: t(9), config: config)
        let plan = Deadlines.breakPlan(s, applyWorkingTime: true)
        XCTAssertEqual(plan?.reason, "4h30 driving")
        XCTAssertEqual(plan?.dueBy ?? .distantPast, t(10, 30))
        XCTAssertEqual(plan?.recommended ?? 0, 45 * 60, accuracy: 1)
    }

    // MARK: Tachograph minute rule

    @MainActor
    func testMinuteRule() {
        let start20 = t(10, 15).addingTimeInterval(20)
        let start40 = t(10, 15).addingTimeInterval(40)
        XCTAssertEqual(AutoDriveDetector.minuteRuleStart(start20), t(10, 15), "40 s of driving in the minute → whole minute is driving")
        XCTAssertEqual(AutoDriveDetector.minuteRuleStart(start40), t(10, 16), "only 20 s of driving → starts next minute")
        XCTAssertEqual(AutoDriveDetector.minuteRuleEnd(start20), t(10, 15), "stopped at :20 → driving ends at start of minute")
        XCTAssertEqual(AutoDriveDetector.minuteRuleEnd(start40), t(10, 16), "stopped at :40 → driving fills the minute")
        // 10:15:20 → 10:15:25: inside one minute, mostly rest → no driving.
        XCTAssertLessThanOrEqual(AutoDriveDetector.minuteRuleEnd(t(10, 15).addingTimeInterval(25)), AutoDriveDetector.minuteRuleStart(start20).addingTimeInterval(0))
        // 10:15:58 → 10:16:03 crosses two minutes, each mostly rest → no driving.
        let a = AutoDriveDetector.minuteRuleStart(t(10, 15).addingTimeInterval(58))
        let b = AutoDriveDetector.minuteRuleEnd(t(10, 16).addingTimeInterval(3))
        XCTAssertLessThanOrEqual(b, a)
    }

    // MARK: V1.2 pay

    func testWeeklyGuaranteeTopsUp() {
        var pay = PaySettings()
        pay.baseRate = 10
        pay.minimumPaidHoursPerWeek = 40
        let entries = [e(.drive, t(8), t(18))] // 10h in the week
        let a = RulesEngine.analyze(entries, now: t(20, day: 2), config: config)
        let r = PayCalculator.calculate(shifts: a.shifts, nightOuts: 0, settings: pay, calendar: cal)
        XCTAssertEqual(r.total, 400, accuracy: 0.05)
        XCTAssertEqual(r.paidHours, 40, accuracy: 0.01)
    }

    func testMonthlyGuaranteeOnlyWhenAsked() {
        var pay = PaySettings()
        pay.baseRate = 10
        pay.minimumPaidHoursPerMonth = 100
        let entries = [e(.drive, t(8), t(18))]
        let a = RulesEngine.analyze(entries, now: t(20, day: 2), config: config)
        XCTAssertEqual(PayCalculator.calculate(shifts: a.shifts, nightOuts: 0, settings: pay, calendar: cal).total, 100, accuracy: 0.05)
        XCTAssertEqual(PayCalculator.calculate(shifts: a.shifts, nightOuts: 0, settings: pay, applyMonthlyGuarantee: true, calendar: cal).total,
                       1000, accuracy: 0.05)
    }

    func testSalaryWithOvertime() {
        var pay = PaySettings()
        pay.payBasis = PayBasis.salary.rawValue
        pay.salaryAmount = 52_000          // £1,000 a week
        pay.salaryPeriod = SalaryPeriod.year.rawValue
        pay.contractedHoursPerWeek = 40    // £25/h
        pay.overtimeMultiplier = 1.5
        // Mon–Thu 11h a day = 44h → 4h overtime at £37.50.
        let entries = (0..<4).map { e(.drive, t(6, day: $0), t(17, day: $0)) }
        let a = RulesEngine.analyze(entries, now: t(20, day: 4), config: config)
        let r = PayCalculator.calculate(shifts: a.shifts, nightOuts: 0, settings: pay, salaryDays: 7, calendar: cal)
        XCTAssertEqual(r.total, 1000 + 4 * 37.5, accuracy: 0.1)
    }

    func testPlateMatching() {
        XCTAssertEqual(normalisedReg("ab12 cde"), "AB12CDE")
        XCTAssertTrue(looksLikePlate("AB12 CDE"))
        XCTAssertFalse(looksLikePlate("STOP"))
    }

    // MARK: 2.1 backup and profile

    @MainActor
    func testBackupRoundTrip() throws {
        let schema = StoreSetup.schema
        let a = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let ctx = ModelContext(a)
        ctx.insert(ActivityEntry(kind: .drive, regime: .assimilated, start: t(8), end: t(10)))
        let v = Vehicle(kind: .tractor); v.registration = "AB12CDE"; v.height = 4.95
        ctx.insert(v)
        let plan = WorkPlan(start: t(6, day: 1), end: t(16, day: 1)); plan.company = "ACME"
        plan.stops = [PlanStop(kind: .delivery, place: "Daventry")]
        ctx.insert(plan)
        ctx.insert(EventLog(kind: .cardIn))
        try ctx.save()
        var settings = AppSettings(); settings.driverName = "Test Driver"
        let url = try BackupService.export(context: ctx, settings: settings)
        let backup = try BackupService.read(url)
        XCTAssertEqual(backup.entries.count, 1)

        let b = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let ctx2 = ModelContext(b)
        let store = SettingsStore(defaults: UserDefaults(suiteName: "hgv.test.\(UUID())")!)
        try BackupService.restore(backup, context: ctx2, store: store)
        XCTAssertEqual(try ctx2.fetch(FetchDescriptor<ActivityEntry>()).first?.start, t(8))
        XCTAssertEqual(try ctx2.fetch(FetchDescriptor<Vehicle>()).first?.height ?? 0, 4.95, accuracy: 0.001)
        XCTAssertEqual(try ctx2.fetch(FetchDescriptor<WorkPlan>()).first?.stops.first?.place, "Daventry")
        XCTAssertEqual(try ctx2.fetch(FetchDescriptor<EventLog>()).count, 1)
        XCTAssertEqual(store.settings.driverName, "Test Driver")
    }

    func testExpiriesDueSoon() {
        var s = AppSettings()
        s.expiryWarningDays = 30
        s.cardExpiry = Date.now.addingTimeInterval(10 * 86_400).timeIntervalSince1970
        s.cpcExpiry = Date.now.addingTimeInterval(200 * 86_400).timeIntervalSince1970
        XCTAssertEqual(s.expiries.count, 2)
        XCTAssertEqual(s.expiriesDueSoon.map(\.title), ["Tacho driver card"])
    }

    // MARK: 3.0 world rules and assistant

    func testUSAThirtyMinuteBreakAndElevenHours() {
        // 7h30 driving since 06:00 → 30 min left before the 8h break rule; 3h30 left of 11h.
        let entries = [e(.drive, t(6), nil)]
        let w = WorldRules.status(entries, now: t(13, 30), region: .usa)
        XCTAssertEqual(w.limits[2].remaining, 30 * 60, accuracy: 61)
        XCTAssertEqual(w.limits[0].remaining, 3.5 * 3600, accuracy: 61)
        XCTAssertEqual(w.driveLeft, 30 * 60, accuracy: 61)
    }

    func testUSAFourteenHourWindowIgnoresBreaks() {
        // Started 05:00, 2h break in the middle: window still ends 19:00.
        let entries = [e(.drive, t(5), t(10)), e(.rest, t(10), t(12)), e(.drive, t(12), nil)]
        let w = WorldRules.status(entries, now: t(16), region: .usa)
        XCTAssertEqual(w.limits[1].remaining, 3 * 3600, accuracy: 61)
    }

    func testCanadaThirteenHoursDriving() {
        let entries = [e(.drive, t(5), nil)]
        let w = WorldRules.status(entries, now: t(16), region: .canada)
        XCTAssertEqual(w.limits[0].remaining, 2 * 3600, accuracy: 61)
    }

    func testAustraliaShortRestCountsAsWork() {
        // 5h work with a 10-min stop in the middle: the stop is under 15 min, so 5h10 counts as work → 5 min left of 5h15.
        let entries = [e(.drive, t(6), t(8, 30)), e(.rest, t(8, 30), t(8, 40)), e(.drive, t(8, 40), nil)]
        let w = WorldRules.status(entries, now: t(11, 10), region: .australia)
        XCTAssertEqual(w.limits[0].remaining, 5 * 60, accuracy: 61)
    }

    func testNewZealandFiveAndAHalfHours() {
        let entries = [e(.otherWork, t(6), t(7)), e(.drive, t(7), nil)]
        let w = WorldRules.status(entries, now: t(10), region: .newZealand)
        XCTAssertEqual(w.limits[0].remaining, 1.5 * 3600, accuracy: 61)
        XCTAssertEqual(w.breakLength, 30 * 60)
    }

    @MainActor
    func testOfflineAssistantAnswersDrivingQuestion() {
        let entries = [e(.drive, t(6), nil)]
        let s = RulesEngine.status(entries, now: t(9), config: config)
        var d = Dashboard()
        d.hasData = true; d.onShift = true; d.kind = .drive; d.driveLeft = 1.5 * 3600; d.driveLeftReason = "Then: 45 min break due"
        let f = AssistantFacts(now: t(9), region: .uk, dash: d, status: s, world: nil, weekPay: 120, currency: "£",
                               nextPlan: nil, vehicleHeight: 4.95, recentDays: [])
        XCTAssertTrue(OfflineAssistant.answer("How long can I drive?", f)?.contains("1h30") ?? false)
        XCTAssertTrue(OfflineAssistant.answer("how much have I earned this week", f)?.contains("£120.00") ?? false)
        XCTAssertTrue(OfflineAssistant.answer("what's my height", f)?.contains("4.95") ?? false)
        XCTAssertNil(OfflineAssistant.answer("what's the weather in Leeds", f))
        XCTAssertTrue(f.summary.contains("Driving left: 1h30"))
    }

    // MARK: 3.1

    func testVoiceCommands() {
        XCTAssertEqual(VoiceCommand.parse("Start driving"), .activity(.drive))
        XCTAssertEqual(VoiceCommand.parse("take a break"), .activity(.rest))
        XCTAssertEqual(VoiceCommand.parse("I'm loading now"), .subtype(.loading))
        XCTAssertEqual(VoiceCommand.parse("unloading"), .subtype(.unloading))
        XCTAssertEqual(VoiceCommand.parse("waiting to tip"), .subtype(.waitingUnload))
        XCTAssertEqual(VoiceCommand.parse("end shift weekly rest"), .endShift(.weekly))
        XCTAssertEqual(VoiceCommand.parse("start shift"), .startShift)
        XCTAssertEqual(VoiceCommand.parse("insert card"), .cardIn)
        XCTAssertNil(VoiceCommand.parse("How long can I drive?"), "questions go to the assistant, not commands")
    }

    func testTodayTilesOrderAndHidden() {
        var s = AppSettings()
        s.todayOrder = ["earnings", "status", "buttons"]
        s.todayHidden = ["card"]
        // Navigation tiles only appear while navigating; check the rest of the order.
        let order = s.tileOrder(.today).filter { !$0.rawValue.hasPrefix("nav") && $0 != .heightCheck }
        XCTAssertEqual(Array(s.tileOrder(.today).drop { $0 != .navTurn }.prefix(7)).last, .buttons, "nav tiles go above the buttons")
        let hidden = s.tileHidden(.today)
        XCTAssertEqual(order.first, .date, "older layouts get the date tile at the top")
        XCTAssertEqual(Array(order[1...3]), [.earnings, .status, .buttons])
        XCTAssertEqual(Array(order[4...5]), [.driveLeft, .workLeft], "countdowns go after the buttons")
        XCTAssertTrue(hidden.contains(.card))
        XCTAssertFalse(hidden.contains(.inCab), "tiles shown by default stay visible")
        XCTAssertTrue(hidden.contains(.restBy), "extra hours tiles start hidden on Today")

        s.moveTile(.workLeft, before: .earnings, on: .today)
        XCTAssertEqual(s.tileOrder(.today).filter { $0 != .heightCheck }[1], .workLeft)
        s.setTile(.card, visible: true, on: .today)
        XCTAssertFalse(s.tileHidden(.today).contains(.card))
        XCTAssertTrue(s.tileHidden(.hours).isEmpty, "every Hours tile shows by default")
    }

    func testTableDocKeepsStyleAlignedWhenMoving() {
        var doc = TableDoc(cells: [["A", "B"], ["1", "2"], ["3", "4"]], style: TableStyle())
        doc.style.rowColors[2] = "red"
        doc.style.colColors[1] = "blue"
        doc.moveRows(from: [2], to: 1)
        XCTAssertEqual(doc.cells[1], ["3", "4"])
        XCTAssertEqual(doc.style.rowColors[1], "red")
        doc.moveColumns(from: [1], to: 0)
        XCTAssertEqual(doc.cells[0], ["B", "A"])
        XCTAssertEqual(doc.style.colColors[0], "blue")
        doc.insertRow(at: 0)
        XCTAssertEqual(doc.style.headerRows, 2, "inserting above the header grows the header")
        XCTAssertEqual(doc.rows, 4)
        doc.deleteColumn(0)
        XCTAssertEqual(doc.cols, 1)
        XCTAssertEqual(doc.style.colColors.count, 1)
        XCTAssertEqual(TableDoc.columnName(27), "AB")
    }

    func testNewActivitiesByVoice() {
        XCTAssertEqual(VoiceCommand.parse("yard check"), .subtype(.yardCheck))
        XCTAssertEqual(VoiceCommand.parse("on spare"), .subtype(.spare))
        XCTAssertEqual(VoiceCommand.parse("waiting for shift"), .subtype(.waitingShift))
        XCTAssertEqual(ActivitySubtype.waitingJob.kind, .availability)
        XCTAssertEqual(ActivitySubtype.yardCheck.kind, .otherWork)
    }

    @MainActor
    func testEndOfShiftResetClearsVehicleAndCompletesJob() throws {
        let schema = StoreSetup.schema
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        let plan = WorkPlan(start: Date.now.addingTimeInterval(-3 * 3600), end: Date.now.addingTimeInterval(3600))
        ctx.insert(plan)
        try ctx.save()
        let store = SettingsStore(defaults: UserDefaults(suiteName: "hgv.test.\(UUID())")!)
        store.settings.currentVehicleID = "abc"
        store.settings.currentTrailerID = "def"
        ActivityController.resetAfterShift(context: ctx, store: store, shiftStart: Date.now.addingTimeInterval(-4 * 3600))
        XCTAssertEqual(store.settings.currentVehicleID, "")
        XCTAssertEqual(store.settings.currentTrailerID, "")
        XCTAssertTrue(plan.completed)
    }

    func testRuleInfoExplainsCards() {
        XCTAssertNotNil(RuleInfo.text(for: "Before break"))
        XCTAssertNotNil(RuleInfo.text(for: "Daily driving"))
        XCTAssertNotNil(RuleInfo.text(for: "Week working"))
    }
}
