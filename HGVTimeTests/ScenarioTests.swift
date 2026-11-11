import XCTest
import SwiftData
@testable import HGVTime

/// Whole-day and whole-week work patterns run through the rules, checked against the law for each country.
final class ScenarioTests: XCTestCase {

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

    /// Monday 3 November 2025 at hour:minute, plus `day` days.
    private func t(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
        let base = cal.date(from: DateComponents(year: 2025, month: 11, day: 3))!
        return cal.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: base)!
    }

    /// One shift: blocks of (activity, minutes) back to back from `hour` on `day`. Gaps between shifts become rest.
    private func shift(day: Int, from hour: Int, minute: Int = 0, _ blocks: [(DutyKind, Int)],
                       regime: Regime = .assimilated, multi: Bool = false) -> [EntrySnapshot] {
        var at = t(hour, minute, day: day)
        return blocks.map { kind, mins in
            let end = at.addingTimeInterval(Double(mins) * 60)
            defer { at = end }
            return EntrySnapshot(kind: kind, regime: regime, start: at, end: end, multiManned: multi)
        }
    }

    /// 9h driving: check 15, drive 4h30, break 45, drive 4h30, work 30 (06:00–16:30).
    private let nineHourDay: [(DutyKind, Int)] = [(.otherWork, 15), (.drive, 270), (.rest, 45), (.drive, 270), (.otherWork, 30)]
    /// 10h driving: 06:00–18:00.
    private let tenHourDay: [(DutyKind, Int)] = [(.otherWork, 15), (.drive, 270), (.rest, 45), (.drive, 270), (.rest, 45), (.drive, 60), (.otherWork, 15)]

    private func issues(_ a: Analysis) -> [ComplianceIssue] { a.shifts.flatMap(\.issues) + a.weeks.flatMap(\.issues) }
    private func has(_ a: Analysis, _ text: String) -> Bool { issues(a).contains { $0.title.contains(text) } }

    // MARK: UK / EU / AETR

    func testCompliantFiveDayWeekHasNoInfringements() {
        var entries: [EntrySnapshot] = []
        for d in 0..<5 { entries += shift(day: d, from: 6, nineHourDay) }
        let a = RulesEngine.analyze(entries, now: t(12, day: 6), config: config)
        XCTAssertEqual(a.shifts.count, 5)
        XCTAssertTrue(issues(a).isEmpty, "Unexpected: \(issues(a).map(\.title))")
        XCTAssertEqual(a.weeks.first?.euDriving ?? 0, 45 * 3600, accuracy: 1)
    }

    func testOtherWorkDoesNotCountAsABreak() {
        let entries = shift(day: 0, from: 6, [(.drive, 240), (.otherWork, 60), (.drive, 60)])
        let a = RulesEngine.analyze(entries, now: t(12), config: config)
        XCTAssertTrue(has(a, "4h30"), "5h driving with only other work between needs a 45-min break")
    }

    func testCountdownsMidShift() {
        let entries = shift(day: 0, from: 6, [(.drive, 270), (.rest, 45)]) + [EntrySnapshot(kind: .drive, regime: .assimilated, start: t(11, 15), end: nil, multiManned: false)]
        let s = RulesEngine.status(entries, now: t(12, 15), config: config)
        XCTAssertEqual(s.continuousDrivingRemaining, 3.5 * 3600, accuracy: 61)
        XCTAssertEqual(s.driveAvailableNow, 3.5 * 3600, accuracy: 61)
        XCTAssertEqual(s.dailyDrivingLimit, 10 * 3600, "both 10h extensions still available")
        XCTAssertEqual(s.dailyDrivingRemaining, 4.5 * 3600, accuracy: 61)
        XCTAssertEqual(s.wtdWorkBeforeBreak, 5 * 3600, accuracy: 61)
    }

    func testFortnightOver90Hours() {
        var entries: [EntrySnapshot] = []
        for week in 0..<2 {
            for d in 0..<6 { entries += shift(day: week * 7 + d, from: 6, d < 2 ? tenHourDay : nineHourDay) }
        }
        let a = RulesEngine.analyze(entries, now: t(12, day: 14), config: config)
        XCTAssertGreaterThanOrEqual(a.weeks.count, 2)
        XCTAssertEqual(a.weeks[0].euDriving, 56 * 3600, accuracy: 1)
        XCTAssertFalse(a.weeks[0].issues.contains { $0.title.contains("56h") }, "exactly 56h is allowed")
        XCTAssertTrue(a.weeks[1].issues.contains { $0.title.contains("90h") }, "56h + 56h breaks the 90h fortnight")
    }

    func testSevenDaysDrivingBreaks56HoursAndWeeklyRest() {
        var entries: [EntrySnapshot] = []
        for d in 0..<7 { entries += shift(day: d, from: 6, nineHourDay) }
        let a = RulesEngine.analyze(entries, now: t(20, day: 6), config: config)
        XCTAssertTrue(has(a, "Weekly driving over 56h"))
        let s = RulesEngine.status(entries, now: t(20, day: 6), config: config)
        let late = has(a, "Weekly rest") || s.warnings.contains { $0.title.contains("Weekly rest overdue") }
        XCTAssertTrue(late, "7 days without a weekly rest must be flagged")
    }

    func testFourReducedDailyRestsIsTooMany() {
        // 15h days (06:00–21:00) leave only 9h rest each night.
        let fifteen: [(DutyKind, Int)] = [(.otherWork, 15), (.drive, 270), (.rest, 45), (.drive, 270), (.rest, 45), (.otherWork, 120), (.availability, 135)]
        var entries: [EntrySnapshot] = []
        for d in 0..<5 { entries += shift(day: d, from: 6, fifteen) }
        let a = RulesEngine.analyze(entries, now: t(12, day: 5), config: config)
        XCTAssertEqual(a.shifts.prefix(4).filter { $0.restKind == .reduced }.count, 4)
        XCTAssertTrue(has(a, "More than 3 reduced daily rests"))
    }

    func testThreeReducedDailyRestsAreAllowed() {
        let fifteen: [(DutyKind, Int)] = [(.otherWork, 15), (.drive, 270), (.rest, 45), (.drive, 270), (.rest, 45), (.otherWork, 120), (.availability, 135)]
        // A 15h day can only fit 9h rest inside 24h, so three 15h days = three reduced rests; then a normal day.
        var entries: [EntrySnapshot] = []
        for d in 0..<3 { entries += shift(day: d, from: 6, fifteen) }
        entries += shift(day: 3, from: 6, nineHourDay)
        let a = RulesEngine.analyze(entries, now: t(12, day: 4), config: config)
        XCTAssertFalse(has(a, "More than 3 reduced daily rests"))
        let s = RulesEngine.status(entries, now: t(12, day: 4), config: config)
        XCTAssertEqual(s.reducedRestsUsed, 3)
    }

    func testSplitDailyRestThreePlusNine() {
        var entries = shift(day: 0, from: 6, [(.drive, 270), (.rest, 180), (.drive, 270)])   // 06:00–10:30, rest 3h, 13:30–18:00
        entries += shift(day: 1, from: 3, [(.drive, 60)])                                     // 9h rest 18:00–03:00
        let a = RulesEngine.analyze(entries, now: t(4, day: 1), config: config)
        XCTAssertEqual(a.shifts.first?.restKind, .split)
        XCTAssertFalse(has(a, "Daily rest too short"))
    }

    func testDoubleMannedRestWithin30Hours() {
        // 21h duty, then 9h rest, inside 30h.
        let entries = shift(day: 0, from: 6, [(.drive, 270), (.availability, 270), (.drive, 270), (.availability, 270), (.drive, 180), (.rest, 540)],
                            multi: true) + shift(day: 1, from: 12, [(.drive, 60)], multi: true)
        let a = RulesEngine.analyze(entries, now: t(13, day: 1), config: config)
        XCTAssertFalse(has(a, "Daily rest too short"), "\(issues(a).map(\.title))")
        XCTAssertFalse(has(a, "4h30"), "with two drivers, the co-driver's time in the moving cab can count as the break")
    }

    func testExemptVehicleDoesNotCountTowardsDrivingLimits() {
        let entries = shift(day: 0, from: 6, [(.drive, 360), (.rest, 30), (.drive, 300)], regime: .exempt)
        let a = RulesEngine.analyze(entries, now: t(18), config: config)
        XCTAssertFalse(has(a, "4h30"))
        XCTAssertFalse(has(a, "Daily driving"))
        XCTAssertEqual(a.shifts[0].stats.euDriving, 0)
        XCTAssertEqual(a.shifts[0].stats.exemptDriving, 11 * 3600, accuracy: 1)
        XCTAssertEqual(a.shifts[0].stats.workingTime, 11 * 3600, accuracy: 1, "still working time")
    }

    func testMixedTachoAndGBDomesticDay() {
        var gb = config
        gb.primaryRegime = .assimilated
        let entries = shift(day: 0, from: 6, [(.drive, 240)]) + shift(day: 0, from: 10, [(.drive, 120)], regime: .gbDomestic)
        let a = RulesEngine.analyze(entries, now: t(12, 30), config: gb)
        XCTAssertFalse(has(a, "4h30"), "GB domestic driving counts as other work under the tacho rules")
        XCTAssertEqual(a.shifts[0].stats.euDriving, 4 * 3600, accuracy: 1)
        XCTAssertEqual(a.shifts[0].stats.gbDriving, 2 * 3600, accuracy: 1)
        let s = RulesEngine.status(entries, now: t(12, 30), config: gb)
        XCTAssertTrue(s.gbApplies)
    }

    func testGBDomesticOverTenHoursDriving() {
        var gb = config
        gb.primaryRegime = .gbDomestic
        let entries = shift(day: 0, from: 5, [(.drive, 330), (.rest, 30), (.drive, 300)], regime: .gbDomestic)
        let a = RulesEngine.analyze(entries, now: t(17), config: gb)
        XCTAssertTrue(has(a, "Driving over 10h (GB domestic)"))
    }

    func testSixtyHourWorkingWeek() {
        // 9h driving + 1h45 other work a day, 6 days = 64h30 working time.
        let long: [(DutyKind, Int)] = [(.otherWork, 15), (.drive, 270), (.rest, 45), (.drive, 270), (.rest, 30), (.otherWork, 90)]
        var entries: [EntrySnapshot] = []
        for d in 0..<6 { entries += shift(day: d, from: 6, long) }
        let a = RulesEngine.analyze(entries, now: t(12, day: 6), config: config)
        XCTAssertTrue(has(a, "Working time over 60h"))
        XCTAssertFalse(has(a, "Weekly driving over 56h"), "54h driving is fine")
    }

    func testNineHourWorkingDayNeeds45MinutesOfBreaks() {
        let entries = shift(day: 0, from: 6, [(.otherWork, 270), (.rest, 30), (.otherWork, 300)])
        let a = RulesEngine.analyze(entries, now: t(17), config: config)
        XCTAssertTrue(has(a, "Under 45 min breaks"), "\(issues(a).map(\.title)) work \(a.shifts.map { $0.stats.workingTime / 3600 }) breaks \(a.shifts.map { $0.stats.wtdBreakTotal / 60 })")
    }

    // MARK: USA, Canada, Australia, New Zealand

    func testUSAElevenHoursDrivingExceeded() {
        let entries = shift(day: 0, from: 6, [(.drive, 420), (.rest, 30), (.drive, 270)])
        let w = WorldRules.status(entries, now: t(18), region: .usa)
        XCTAssertTrue(w.violations.contains { $0.title.contains("Driving (11h)") })
    }

    func testUSA34HourRestartResetsTheCycle() {
        var entries: [EntrySnapshot] = []
        for d in 0..<7 { entries += shift(day: d, from: 6, [(.drive, 300), (.rest, 30), (.drive, 180), (.otherWork, 120)]) }   // 10h on duty a day
        let before = WorldRules.status(entries, now: t(17, day: 6), region: .usa)
        XCTAssertEqual(before.limits[3].remaining, 0, accuracy: 61, "70 hours in 8 days used up")
        entries += shift(day: 8, from: 3, [(.drive, 60)])   // 34h+ off from day 6 16:30 to day 8 03:00
        let after = WorldRules.status(entries, now: t(4, day: 8), region: .usa)
        XCTAssertEqual(after.limits[3].used, 3600, accuracy: 61)
    }

    func testCanadaSixteenHourWindow() {
        let entries = shift(day: 0, from: 5, [(.drive, 300), (.rest, 120), (.drive, 480)])
        let w = WorldRules.status(entries, now: t(20), region: .canada)
        XCTAssertEqual(w.limits[2].remaining, 3600, accuracy: 61)
        XCTAssertEqual(w.limits[1].used, 13 * 3600, accuracy: 61, "break time isn't on duty")
    }

    func testAustraliaTwelveHoursInTwentyFour() {
        let entries = shift(day: 0, from: 6, [(.drive, 300), (.rest, 15), (.drive, 120), (.rest, 30), (.drive, 120), (.rest, 60), (.drive, 240)])
        let w = WorldRules.status(entries, now: t(20, 45), region: .australia)
        XCTAssertTrue(w.violations.contains { $0.title.contains("12h work in any 24 hours") }, "\(w.violations.map(\.title))")
    }

    func testNewZealandThirteenHourDay() {
        let entries = shift(day: 0, from: 6, [(.drive, 300), (.rest, 30), (.drive, 300), (.rest, 30), (.otherWork, 180)])
        let w = WorldRules.status(entries, now: t(20), region: .newZealand)
        XCTAssertEqual(w.limits[1].remaining, 0, accuracy: 61)
        XCTAssertTrue(w.violations.isEmpty)
    }

    // MARK: Vehicles, speed limits, addresses, sub-activities

    private func memoryContext() throws -> ModelContext {
        let schema = StoreSetup.schema
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    @MainActor
    func testChangingVehicleMidShiftKeepsSeparateMileage() throws {
        let ctx = try memoryContext()
        let store = SettingsStore(defaults: UserDefaults(suiteName: "scenario.\(UUID().uuidString)")!)
        let a = Vehicle(kind: .tractor); a.registration = "AA11 AAA"; a.odometerKm = 100_000
        let b = Vehicle(kind: .rigid); b.registration = "BB22 BBB"; b.odometerKm = 50_000; b.rules = .exempt
        ctx.insert(a); ctx.insert(b)
        ctx.insert(ActivityEntry(kind: .drive, regime: .assimilated, start: .now.addingTimeInterval(-3600)))
        try ctx.save()

        VehicleLog.select(a.id.uuidString, context: ctx, store: store)
        VehicleLog.addGPS(50, context: ctx)
        XCTAssertEqual(store.settings.currentRegime, store.settings.primaryRegime)
        VehicleLog.select(b.id.uuidString, context: ctx, store: store)
        XCTAssertEqual(store.settings.currentRegime, .exempt, "vehicle's own rules apply when chosen")
        VehicleLog.addGPS(20, context: ctx)
        VehicleLog.shiftEnded(context: ctx)

        let uses = try ctx.fetch(FetchDescriptor<VehicleUse>(sortBy: [SortDescriptor(\.start)]))
        XCTAssertEqual(uses.count, 2)
        XCTAssertEqual(uses[0].distanceKm, 50, accuracy: 0.01)
        XCTAssertEqual(uses[0].endOdometerKm, 100_050, accuracy: 0.01, "end reading worked out from GPS")
        XCTAssertEqual(uses[1].distanceKm, 20, accuracy: 0.01)
        XCTAssertEqual(a.odometerKm, 100_050, accuracy: 0.01)
        XCTAssertEqual(VehicleLog.distance(on: .now, context: ctx), 70, accuracy: 0.01)

        // Typing the real end reading overrides GPS.
        VehicleLog.setReading(uses[1], start: false, km: 50_025, context: ctx)
        XCTAssertEqual(uses[1].distanceKm, 25, accuracy: 0.01)
    }

    func testSpeedLimitsByVehicleAndCountry() {
        XCTAssertEqual(SpeedLimits.defaultKmh(kind: .tractor, weightT: 44, region: .uk), 90)
        XCTAssertEqual(SpeedLimits.defaultKmh(kind: .van, weightT: 3.5, region: .uk), 113)
        XCTAssertEqual(SpeedLimits.defaultKmh(kind: .rigid, weightT: 18, region: .australia), 100)
        XCTAssertEqual(SpeedLimits.defaultKmh(kind: .tractor, weightT: 36, region: .usa), 105)
        let v = Vehicle(kind: .tractor); v.speedLimitKmh = 85
        XCTAssertEqual(SpeedLimits.limitKmh(vehicle: v, region: .uk, manual: 90, automatic: true), 85, "a speed set on the vehicle wins")
        XCTAssertEqual(SpeedLimits.limitKmh(vehicle: nil, region: .eu, manual: 80, automatic: false), 80)
    }

    func testAddressParts() {
        XCTAssertEqual(AddressParts.join(flat: "2", houseName: "Rose House", houseNumber: "14", street: "High Street, Daventry", postcode: "NN11 4XX"),
                       "Flat 2, Rose House, 14 High Street, Daventry, NN11 4XX")
        XCTAssertEqual(AddressParts.join(flat: nil, houseName: nil, houseNumber: "14", street: "14 High Street", postcode: nil), "14 High Street")
        var stop = PlanStop(kind: .service)
        stop.company = "DAF Truck Centre"
        XCTAssertEqual(stop.displayName, "DAF Truck Centre")
        XCTAssertEqual(stop.kind.title, "Vehicle service")
    }

    @MainActor
    func testSubActivitiesGetTheirOwnTimes() throws {
        let ctx = try memoryContext()
        let settings = AppSettings()
        ctx.insert(ActivityEntry(kind: .otherWork, regime: .assimilated, start: .now.addingTimeInterval(-600)))
        try ctx.save()
        ActivityController.setSubtype(.loading, context: ctx, settings: settings)
        var all = try ctx.fetch(FetchDescriptor<ActivityEntry>(sortBy: [SortDescriptor(\.start)]))
        XCTAssertEqual(all.count, 2, "loading starts its own activity")
        XCTAssertNotNil(all[0].end)
        XCTAssertEqual(all[1].subtype, .loading)
        // Changing straight away just relabels it.
        ActivityController.setSubtype(.unloading, context: ctx, settings: settings)
        all = try ctx.fetch(FetchDescriptor<ActivityEntry>(sortBy: [SortDescriptor(\.start)]))
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[1].subtype, .unloading)
    }
}
