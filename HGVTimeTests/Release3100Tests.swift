import CoreLocation
import XCTest
@testable import HGVTime

/// 3.10.0: 15-min working-time break, lorry routing parse, polyline, cameras.
@MainActor
final class Release3100Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    func testFifteenMinuteBreakResetsSixHourWorkingClock() {
        let e = [EntrySnapshot(kind: .otherWork, regime: .assimilated, start: at(0), end: at(60)),
                 EntrySnapshot(kind: .drive, regime: .assimilated, start: at(60), end: at(240)),
                 EntrySnapshot(kind: .rest, regime: .assimilated, start: at(240), end: at(255)),   // 15 min
                 EntrySnapshot(kind: .drive, regime: .assimilated, start: at(255), end: nil)]
        let s = RulesEngine.status(e, now: at(256), config: RuleConfig(primaryRegime: .assimilated, applyWorkingTime: true))
        XCTAssertEqual(s.wtdWorkBeforeBreak, .hours(6) - 60, accuracy: 2)          // reset by the 15 min break
        XCTAssertEqual(s.stats.continuousDriving, .minutes(181), accuracy: 2)       // driving needs 30 more min
        XCTAssertEqual(s.breakNeeded, Limits.splitBreakSecond)
    }

    func testDailyBreakTotalStillChecked() {
        // 6h work, 15, 4h work: no 6h run, but only 15 min of breaks on a 10h day.
        let e = [EntrySnapshot(kind: .otherWork, regime: .assimilated, start: at(0), end: at(360)),
                 EntrySnapshot(kind: .rest, regime: .assimilated, start: at(360), end: at(375)),
                 EntrySnapshot(kind: .otherWork, regime: .assimilated, start: at(375), end: at(615)),
                 EntrySnapshot(kind: .rest, regime: .assimilated, start: at(615), end: at(615 + 11 * 60))]
        let a = RulesEngine.analyze(e, now: at(615 + 11 * 60), config: RuleConfig(primaryRegime: .assimilated, applyWorkingTime: true))
        let titles = a.shifts.first?.issues.map(\.title) ?? []
        XCTAssertTrue(titles.contains("Under 45 min breaks on a 9h+ day"))
        XCTAssertFalse(titles.contains("Worked over 6h without a break"))
    }

    func testPolylineDecode() {
        // Classic example from the polyline spec (precision 1e5).
        let c = TruckRouter.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 1e5)
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(c[0].latitude, 38.5, accuracy: 1e-6)
        XCTAssertEqual(c[0].longitude, -120.2, accuracy: 1e-6)
        XCTAssertEqual(c[2].longitude, -126.453, accuracy: 1e-6)
    }

    func testParseOSRMRouteWithLanesAndVoice() throws {
        let json = """
        {"routes":[{"distance":1200,"duration":120,"geometry":"_p~iF~ps|U_ulLnnqC","legs":[{"steps":[
          {"name":"Weedon Road","ref":"A4500","distance":800,"duration":80,
           "maneuver":{"type":"depart","modifier":"","location":[-120.2,38.5],"instruction":"Drive west."},
           "intersections":[{"location":[-120.2,38.5]}],
           "voiceInstructions":[{"announcement":"In 500 metres, keep left to stay on M1.","distanceAlongGeometry":500}]},
          {"name":"","ref":"M1","distance":400,"duration":40,
           "maneuver":{"type":"fork","modifier":"slight left","location":[-120.95,40.7],"instruction":"Keep left to stay on M1."},
           "intersections":[{"lanes":[{"indications":["slight left"],"valid":true,"active":true},{"indications":["straight"],"valid":false,"active":false}]}]}
        ]}]}]}
        """
        let r = try TruckRouter.parseOSRM(Data(json.utf8), isTruck: true)
        XCTAssertEqual(r.steps.count, 2)
        XCTAssertEqual(r.steps[1].symbol, "arrow.up.left")
        XCTAssertEqual(r.steps[1].lanes.map(\.valid), [true, false])
        XCTAssertEqual(r.steps[1].roadLabel, "M1")
        XCTAssertEqual(r.steps[0].voice.first?.before, 500)
        XCTAssertTrue(r.isTruckRoute)
    }

    func testCamerasParse() {
        let json = #"{"elements":[{"type":"node","id":1,"lat":52.1,"lon":-1.1,"tags":{"highway":"speed_camera","maxspeed":"50 mph"}},{"type":"node","id":2,"lat":52.2,"lon":-1.2,"tags":{"highway":"traffic_signals"}}]}"#
        let p = RoadHazards.parse(Data(json.utf8))
        XCTAssertEqual(p.map(\.kind), [.camera, .trafficLight])
        XCTAssertEqual(p.first?.maxspeed, "50 mph")
    }

    func testManeuverSymbols() {
        XCTAssertEqual(NavStep.symbol(type: "roundabout", modifier: "right"), "arrow.triangle.turn.up.right.circle.fill")
        XCTAssertEqual(NavStep.symbol(type: "turn", modifier: "sharp left"), "arrow.turn.left.down")
        XCTAssertEqual(NavStep.symbol(type: "arrive", modifier: ""), "flag.checkered")
    }
}
