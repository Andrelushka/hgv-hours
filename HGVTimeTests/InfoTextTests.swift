import XCTest
@testable import HGVTime

/// Every tile with an ⓘ button has an explanation that fits it.
@MainActor
final class InfoTextTests: XCTestCase {
    func testEveryTileTitleHasInfo() {
        let titles = ["Driving left", "Working left", "Before break", "Before 6h break", "Break due in", "Daily driving",
                      "Driven today", "This week", "Fortnight", "Week working", "Night shift work", "Worked today",
                      "Shift working time", "Shift time left", "Start daily rest by", "Daily rest", "Resting for",
                      "Next shift can start", "Reduced rests", "Weekly rest", "Weekly rest by", "Compensation owed",
                      "GB driving", "GB duty", "17-week average"]
        for t in titles { XCTAssertNotNil(RuleInfo.text(for: t), t) }
    }

    func testTextsMatchTheirTile() {
        XCTAssertTrue(RuleInfo.text(for: "Driving left")!.contains("4h30"))
        XCTAssertTrue(RuleInfo.text(for: "Working left")!.contains("6 hours"))
        XCTAssertTrue(RuleInfo.text(for: "Before 6h break")!.contains("15 minutes or more resets"))
        XCTAssertTrue(RuleInfo.text(for: "GB driving")!.contains("10 hours of driving"))
        XCTAssertTrue(RuleInfo.text(for: "GB duty")!.contains("11 hours on duty"))
        XCTAssertTrue(RuleInfo.text(for: "Fortnight")!.contains("90 hours"))
    }

    func testOtherCountriesDontGetUKTexts() {
        XCTAssertNil(RuleInfo.text(for: "On duty (14h)"))
        XCTAssertNil(RuleInfo.text(for: "14-hour window"))
        XCTAssertNil(RuleInfo.text(for: "Driving before 30-min break"))
    }
}

/// Map filters start from the right defaults for where the map was opened.
@MainActor
final class MapFilterDefaultsTests: XCTestCase {
    func testDefaultsPerMap() {
        var s = AppSettings()
        XCTAssertEqual(s.hiddenEvents(on: .main), Set(EventKind.allCases), "main map: everything off")
        XCTAssertEqual(s.hiddenEvents(on: .day), Set(EventKind.allCases))
        XCTAssertEqual(s.hiddenEvents(on: .events), [.activity], "events map: only events on")
        XCTAssertFalse(s.hiddenEvents(on: .activities).contains(.activity), "activities map: activities on")
        XCTAssertTrue(s.hiddenEvents(on: .activities).contains(.overspeed))
        // A change on one map doesn't affect another.
        s.setHiddenEvents([], on: .main)
        XCTAssertTrue(s.hiddenEvents(on: .main).isEmpty)
        XCTAssertEqual(s.hiddenEvents(on: .day), Set(EventKind.allCases))
    }
}
