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

/// 3.16: trailer swap at an ordinary stop, the vehicle check counts and tile sizes.
@MainActor
final class VehicleCheckAndTileTests: XCTestCase {
    func testTrailerSwapText() {
        var stop = PlanStop(kind: .delivery)
        XCTAssertEqual(stop.trailerChangeText(in: []), "")
        stop.dropTrailerID = "current"
        stop.pickTrailerRef = "T42"
        let text = stop.trailerChangeText(in: [])
        XCTAssertTrue(text.contains("T42"))
        XCTAssertTrue(text.contains("·"))
    }

    func testVehicleCheckCounts() {
        let check = VehicleCheck()
        check.columns = ["AB12 CDE", "T42"]
        check.trailerColumns = [false, true]
        let vehicleLines = CheckItem.all.filter { $0.applies(toTrailer: false) }.count
        let trailerLines = CheckItem.all.filter { $0.applies(toTrailer: true) }.count
        XCTAssertEqual(check.openCount, vehicleLines + trailerLines)
        var a = check.answers
        a[VehicleCheck.key("tyres", 0)] = "ok"
        a[VehicleCheck.key("lights", 1)] = "defect"
        a[VehicleCheck.key("coupling", 1)] = "no"
        check.answers = a
        XCTAssertEqual(check.defectCount, 2)
        XCTAssertEqual(check.openCount, vehicleLines + trailerLines - 3)
        XCTAssertEqual(Set(CheckItem.all.map(\.id)).count, CheckItem.all.count, "item ids are unique")
    }

    func testTileSizes() {
        var s = AppSettings()
        let tile = Tile.vehicle
        let original = s.isWide(tile)
        s.setWide(tile, !original)
        XCTAssertEqual(s.isWide(tile), !original)
        s.setWide(tile, original)
        XCTAssertTrue(s.tileSizes.isEmpty, "default size is not stored")
        s.setWide(.buttons, !s.isWide(.buttons))
        XCTAssertEqual(s.isWide(.buttons), Tile.buttons.isWide, "buttons can't be resized")
    }
}

/// 3.17: tile groups, page blocks and adding pick-ups to the vehicle check.
@MainActor
final class LayoutAndGroupsTests: XCTestCase {
    func testTileGroups() {
        var s = AppSettings()
        XCTAssertEqual(s.group(of: .dailyRest), .rest)
        s.setGroup(.dailyRest, .now)
        XCTAssertEqual(s.group(of: .dailyRest), .now)
        s.setGroup(.dailyRest, .rest)
        XCTAssertTrue(s.tileGroups.isEmpty, "back in its own group is not stored")
        s.moveGroup(.alerts, by: -100)
        XCTAssertEqual(s.orderedGroups.first, .alerts)
        XCTAssertEqual(Set(s.orderedGroups), Set(TileGroup.allCases))
        s.groupNames[TileGroup.rest.rawValue] = "Sleep"
        XCTAssertEqual(s.groupTitle(.rest), "Sleep")
    }

    func testPageBlocks() {
        var s = AppSettings()
        XCTAssertEqual(s.blocks(.debrief), LayoutPage.debrief.blocks.map(\.id))
        s.moveBlocks(.debrief, from: IndexSet(integer: 6), to: 0)
        XCTAssertEqual(s.blocks(.debrief).first, "pay")
        s.setBlock("pay", visible: false, on: .debrief)
        XCTAssertFalse(s.blocks(.debrief).contains("pay"))
        // A section switcher always keeps one section.
        for b in LayoutPage.jobsTabs.blocks { s.setBlock(b.id, visible: false, on: .jobsTabs) }
        XCTAssertFalse(s.blocks(.jobsTabs).isEmpty)
    }

    func testCheckAddColumn() {
        let c = VehicleCheck()
        c.columns = ["AB12 CDE"]; c.trailerColumns = [false]; c.heights = [4]
        XCTAssertEqual(c.addColumn("T42", trailer: true, height: 4.2), 1)
        XCTAssertEqual(c.addColumn("t42", trailer: true, height: 4.2), 1, "same trailer isn't added twice")
        XCTAssertEqual(c.heights, [4, 4.2])
        XCTAssertGreaterThan(c.openCount(column: 1), 0)
    }
}

/// 3.18: stops in order, phone links and company profiles.
@MainActor
final class StopOrderAndContactsTests: XCTestCase {
    func testArriveInOrder() {
        var stops = [PlanStop(kind: .collection), PlanStop(kind: .delivery), PlanStop(kind: .delivery)]
        XCTAssertNil(stops.arrivalBlocker(for: 0))
        XCTAssertEqual(stops.arrivalBlocker(for: 1), 0, "first stop not done yet")
        stops[0].arrivedAt = .now
        XCTAssertEqual(stops.currentStopIndex, 0)
        XCTAssertEqual(stops.arrivalBlocker(for: 1), 0, "still at the first stop")
        stops[0].departedAt = .now
        XCTAssertNil(stops.arrivalBlocker(for: 1))
        XCTAssertEqual(stops.arrivalBlocker(for: 2), 1)
        stops[1].outcomeRaw = PlanStop.Outcome.allCases.first?.rawValue   // cancelled/failed counts as finished
        XCTAssertNil(stops.arrivalBlocker(for: 2))
        XCTAssertNil(stops.currentStopIndex)
    }

    func testPhonesAndCompanies() throws {
        XCTAssertEqual(PhoneContact.callURL("03457 11 41 41")?.absoluteString, "tel:03457114141")
        XCTAssertEqual(PhoneContact.callURL("+44 (0)300 123")?.absoluteString, "tel:+440300123")
        XCTAssertNil(PhoneContact.callURL("n/a"))
        var c = CompanyProfile(name: "DHL Supply Chain")
        XCTAssertTrue(c.matches(" dhl supply chain "))
        XCTAssertFalse(c.matches(""))
        c.showOnToday = true
        var s = AppSettings()
        s.companies = [c, CompanyProfile(name: "Tesco")]
        XCTAssertEqual(CompanyTile.shown(s, jobCompany: "tesco").map(\.name), ["DHL Supply Chain", "Tesco"])
        // Partial saved data still loads.
        let old = try JSONDecoder().decode(CompanyProfile.self, from: Data(#"{"name":"Agency"}"#.utf8))
        XCTAssertEqual(old.name, "Agency")
        XCTAssertTrue(old.phones.isEmpty)
        XCTAssertFalse(EmergencyNumbers.uk.isEmpty)
    }
}

/// 3.19: trailer at the start and finish, loaded/empty per stop.
@MainActor
final class StartFinishTests: XCTestCase {
    func testStartAndFinishTasks() throws {
        let plan = WorkPlan(start: .now, end: .now.addingTimeInterval(3600))
        XCTAssertFalse(plan.hasStartTask)
        XCTAssertEqual(plan.endAction, .none)
        plan.startTrailerRef = "T42"
        plan.startLoad = "loaded"
        XCTAssertTrue(plan.hasStartTask)
        let text = plan.startTaskText(in: [])
        XCTAssertTrue(text.contains("T42"))
        XCTAssertTrue(text.contains(LoadState.title("loaded")))
        plan.endAction = .leaveVehicle
        XCTAssertEqual(plan.endActionRaw, "leaveVehicle")
        // Stops saved before 3.19 have no load state.
        let old = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"delivery","place":"Tesco","time":"","reference":"","pallets":"","notes":""}]"#
        let decoded = try JSONDecoder().decode([PlanStop].self, from: Data(old.utf8))
        XCTAssertNil(decoded.first?.loadAfter)
        XCTAssertEqual(LoadState.title(nil), "")
    }
}
