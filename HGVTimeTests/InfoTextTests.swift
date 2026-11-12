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
        XCTAssertEqual(s.hiddenEvents(on: .main), Set(EventKind.allCases).subtracting([.activity]), "main map: activities only")
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

/// Trailer and vehicle pick-up / drop-off stops.
@MainActor
final class EquipmentStopTests: XCTestCase {
    func testEquipmentStops() throws {
        var stop = PlanStop(kind: .trailerPickup)
        XCTAssertTrue(stop.isEquipmentStop)
        XCTAssertTrue(stop.isTrailerStop)
        stop.equipmentRef = "T1234"
        XCTAssertEqual(stop.equipmentName(in: []), "T1234")
        XCTAssertEqual(PlanStop(kind: .delivery).equipmentName(in: []), "")
        XCTAssertFalse(PlanStop(kind: .vehicleDrop).isTrailerStop)
        // Stops saved before 3.14 (no equipment fields) still load.
        let old = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"delivery","place":"Tesco","time":"","reference":"","pallets":"","notes":""}]"#
        let decoded = try JSONDecoder().decode([PlanStop].self, from: Data(old.utf8))
        XCTAssertNil(decoded.first?.equipmentID)
    }
}

/// The trailer follows the cab through a turn and straightens afterwards.
@MainActor
final class TrailerSwingTests: XCTestCase {
    func testTrailerSwingsAndStraightens() {
        var trailer = 0.0
        // Cab turns to 40° at 10 m/s: the trailer lags behind, then catches up.
        NavigationEngine.followTrailer(&trailer, cab: 40, speed: 10, dt: 0.2)
        XCTAssertGreaterThan(trailer, 0)
        XCTAssertLessThan(trailer, 40)
        for _ in 0..<100 { NavigationEngine.followTrailer(&trailer, cab: 40, speed: 10, dt: 0.2) }
        XCTAssertEqual(trailer, 40, accuracy: 1)
        // Standing still: no swing.
        var still = 0.0
        NavigationEngine.followTrailer(&still, cab: 30, speed: 0, dt: 0.2)
        XCTAssertEqual(still, 0)
        var h = 350.0
        NavigationEngine.ease(&h, to: 10, factor: 0.5)
        XCTAssertEqual(h, 0, accuracy: 0.001, "eases across north the short way")
    }
}
