import XCTest
@testable import HGVTime

/// 3.9.0: shift checks, loaded/empty split, Today circles per period.
@MainActor
final class Release390Tests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar.hgv
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "Europe/London")
        return f.date(from: s)!
    }

    func testShiftChecksSchedules() {
        let every = ShiftCheckTemplate(title: "Agency form", phase: .start)
        let weekly = ShiftCheckTemplate(title: "Card download", phase: .end, schedule: .weekly)
        let tueThu = ShiftCheckTemplate(title: "Licence", phase: .start, schedule: .days, weekdays: [3, 5])
        let tesco = ShiftCheckTemplate(title: "Tesco sign-in", phase: .start, company: "Tesco")
        let all = [every, weekly, tueThu, tesco]
        let tuesday = date("2026-11-10 06:00")   // a Tuesday

        var due = ShiftChecks.due(all, phase: .start, shiftStart: tuesday, company: "Tesco", records: [], calendar: cal)
        XCTAssertEqual(Set(due.map(\.title)), ["Agency form", "Licence", "Tesco sign-in"])
        due = ShiftChecks.due(all, phase: .start, shiftStart: date("2026-11-11 06:00"), company: "Asda", records: [], calendar: cal)
        XCTAssertEqual(due.map(\.title), ["Agency form"])

        // Done 30 min before Start shift still counts for that shift.
        let early = CheckRecord(template: every, at: tuesday.addingTimeInterval(-1800))
        due = ShiftChecks.due([every], phase: .start, shiftStart: tuesday, company: "", records: [early], calendar: cal)
        XCTAssertTrue(due.isEmpty)
        // …but not for the next day's shift.
        due = ShiftChecks.due([every], phase: .start, shiftStart: date("2026-11-11 06:00"), company: "", records: [early], calendar: cal)
        XCTAssertEqual(due.count, 1)

        // Weekly: done on Monday covers the rest of the week, due again next week.
        let monday = CheckRecord(template: weekly, at: date("2026-11-09 17:00"))
        XCTAssertTrue(ShiftChecks.due([weekly], phase: .end, shiftStart: date("2026-11-13 06:00"), company: "", records: [monday], calendar: cal).isEmpty)
        XCTAssertEqual(ShiftChecks.due([weekly], phase: .end, shiftStart: date("2026-11-16 06:00"), company: "", records: [monday], calendar: cal).count, 1)
    }

    func testLoadedEmptySplit() {
        let a = VehicleUse(vehicleID: "v", trailerID: "t", start: .now, startOdometerKm: 1000); a.endOdometerKm = 1080; a.end = .now; a.loadStateRaw = "loaded"
        let b = VehicleUse(vehicleID: "v", trailerID: "t", start: .now, startOdometerKm: 1080); b.endOdometerKm = 1100; b.end = .now; b.loadStateRaw = "empty"
        let c = VehicleUse(vehicleID: "v", trailerID: "t", start: .now, startOdometerKm: 1100); c.endOdometerKm = 1110; c.end = .now
        let split = VehicleLog.loadSplit([a, b, c])
        XCTAssertEqual(split.loaded, 80, accuracy: 0.01)
        XCTAssertEqual(split.empty, 20, accuracy: 0.01)
    }

    func testTodayCirclesArePerPeriod() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let e = [EntrySnapshot(kind: .otherWork, regime: .assimilated, start: t0, end: t0.addingTimeInterval(3600)),
                 EntrySnapshot(kind: .drive, regime: .assimilated, start: t0.addingTimeInterval(3600), end: nil)]
        let now = t0.addingTimeInterval(3 * 3600)
        var settings = AppSettings()
        settings.applyWorkingTime = true
        let s = RulesEngine.status(e, now: now, config: settings.ruleConfig)
        let d = Dashboard.make(status: s, settings: settings, openEntry: nil)
        XCTAssertEqual(d.driveLeft, .hours(2.5), accuracy: 1)   // 4h30 − 2h driving (not capped by the 6h clock)
        XCTAssertEqual(d.workLeft, .hours(3), accuracy: 1)      // 6h − 3h working
    }
}
