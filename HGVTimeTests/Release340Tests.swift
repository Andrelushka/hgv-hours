import XCTest
@testable import HGVTime

/// 3.4.0: earnings kept after the shift ends, agent tool parsing, speed-limit and road-number parsing.
@MainActor
final class Release340Tests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar.hgv
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    private func t(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
        let base = cal.date(from: DateComponents(year: 2025, month: 11, day: 3))!
        return cal.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: base)!
    }

    private func analysis(now: Date, _ blocks: [(DutyKind, Date, Date)]) -> Analysis {
        var config = RuleConfig()
        config.calendar = cal
        let snaps = blocks.map { EntrySnapshot(kind: $0.0, regime: .assimilated, start: $0.1, end: $0.2, multiManned: false) }
        return RulesEngine.analyze(snaps, now: now, config: config)
    }

    func testDayShiftStillCountedAfterEndShiftUntilMidnight() {
        // 06:00–16:00 work, then resting. At 18:00 (2h into rest) and 23:30 the day's shift is still today's.
        let blocks: [(DutyKind, Date, Date)] = [(.otherWork, t(6), t(7)), (.drive, t(7), t(11)), (.rest, t(11), t(11, 45)), (.drive, t(11, 45), t(16))]
        XCTAssertEqual(analysis(now: t(18), blocks).shifts.workedOn(t(18), calendar: cal).count, 1)
        XCTAssertEqual(analysis(now: t(23, 30), blocks).shifts.workedOn(t(23, 30), calendar: cal).count, 1)
        // Next morning it starts again at zero.
        XCTAssertEqual(analysis(now: t(1, day: 1), blocks).shifts.workedOn(t(1, day: 1), calendar: cal).count, 0)
    }

    func testNightShiftCountsOnTheDayItFinishes() {
        let blocks: [(DutyKind, Date, Date)] = [(.otherWork, t(20), t(21)), (.drive, t(21), t(1, day: 1)), (.otherWork, t(1, day: 1), t(4, day: 1))]
        XCTAssertEqual(analysis(now: t(9, day: 1), blocks).shifts.workedOn(t(9, day: 1), calendar: cal).count, 1)
    }

    func testParseStop() {
        let s = AgentTools.parseStop("collection: DHL Northampton NN4 7PB at 06:30 ref 12345")
        XCTAssertEqual(s.kind, .collection)
        XCTAssertEqual(s.place, "DHL Northampton")
        XCTAssertEqual(s.postcode, "NN4 7PB")
        XCTAssertEqual(s.time, "06:30")
        XCTAssertEqual(s.reference, "12345")
        let d = AgentTools.parseStop("Tesco Daventry, NN11 8XX")
        XCTAssertEqual(d.kind, .delivery)
        XCTAssertEqual(d.place, "Tesco Daventry")
        XCTAssertEqual(d.postcode, "NN11 8XX")
    }

    func testParseDatesAndTimes() {
        let d = AgentTools.day("2026-11-12")!
        XCTAssertEqual(Calendar.hgv.component(.day, from: d), 12)
        XCTAssertEqual(AgentTools.day("tomorrow"), Calendar.hgv.date(byAdding: .day, value: 1, to: Calendar.hgv.startOfDay(for: .now)))
        let at = AgentTools.time("6.45", on: d)!
        XCTAssertEqual(Calendar.hgv.component(.hour, from: at), 6)
        XCTAssertEqual(Calendar.hgv.component(.minute, from: at), 45)
        XCTAssertNil(AgentTools.time("25:00", on: d))
    }

    func testSpeedLimitTags() {
        XCTAssertEqual(RoadSpeedLimit.parse("30 mph")?.text, "30")
        XCTAssertEqual(RoadSpeedLimit.parse("30 mph")!.kmh, 48.28, accuracy: 0.1)
        XCTAssertEqual(RoadSpeedLimit.parse("80")?.kmh, 80)
        XCTAssertEqual(RoadSpeedLimit.parse("GB:nsl_single")?.text, "60")
        XCTAssertNil(RoadSpeedLimit.parse("signals"))
    }

    func testRoadNumbersAndMajorRoads() {
        XCTAssertEqual(RoadSpeedLimit.roadNumber(in: "Take exit 16 onto the M1 toward Northampton"), "M1")
        XCTAssertEqual(RoadSpeedLimit.roadNumber(in: "Turn left onto A45"), "A45")
        XCTAssertTrue(RoadSpeedLimit.isMajor("Merge onto M6"))
        XCTAssertTrue(RoadSpeedLimit.isMajor("Continue on A14"))
        XCTAssertFalse(RoadSpeedLimit.isMajor("Turn right onto High Street"))
        XCTAssertFalse(RoadSpeedLimit.isMajor("Turn left onto B4525"))
    }

    func testAgentToolsHaveUniqueNamesAndSchemas() {
        let names = AgentTools.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(AgentTools.def("delete_job")!.needsConfirm)
        XCTAssertNotNil(AgentTools.def("create_job")!.claudeSchema["input_schema"])
    }
}
