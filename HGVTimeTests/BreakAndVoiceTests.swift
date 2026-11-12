import CoreLocation
import XCTest
@testable import HGVTime

/// Driving left during breaks, split-break guidance, manoeuvre arrows.
@MainActor
final class BreakAndVoiceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }
    private var config: RuleConfig { RuleConfig(primaryRegime: .assimilated, applyWorkingTime: true) }

    func testDrivingLeftIsNotZeroDuringABreak() {
        // 3h driving, then on a break for 10 min.
        let e = [EntrySnapshot(kind: .drive, regime: .assimilated, start: at(0), end: at(180)),
                 EntrySnapshot(kind: .rest, regime: .assimilated, start: at(180), end: nil)]
        let s = RulesEngine.status(e, now: at(190), config: config)
        XCTAssertEqual(s.drivingLeftToday, .hours(7), accuracy: 1)        // 10h − 3h
        XCTAssertEqual(s.driveAvailableNow, .hours(1.5), accuracy: 1)     // 4h30 − 3h, break may be stopped early
        XCTAssertEqual(s.breakSplitPartAt, at(195))
        XCTAssertEqual(s.breakResetAt, at(225))
    }

    func testAfterFifteenOnlyThirtyIsNeeded() {
        let e = [EntrySnapshot(kind: .drive, regime: .assimilated, start: at(0), end: at(120)),
                 EntrySnapshot(kind: .rest, regime: .assimilated, start: at(120), end: at(135)),   // 15 min = part 1
                 EntrySnapshot(kind: .drive, regime: .assimilated, start: at(135), end: at(200)),
                 EntrySnapshot(kind: .rest, regime: .assimilated, start: at(200), end: at(215)),   // another 15 — doesn't reset
                 EntrySnapshot(kind: .drive, regime: .assimilated, start: at(215), end: at(240)),
                 EntrySnapshot(kind: .rest, regime: .assimilated, start: at(240), end: nil)]
        let s = RulesEngine.status(e, now: at(245), config: config)
        XCTAssertEqual(s.breakNeeded, Limits.splitBreakSecond)
        XCTAssertNil(s.breakSplitPartAt)
        XCTAssertEqual(s.breakResetAt, at(270))
        XCTAssertEqual(s.stats.continuousDriving, .minutes(210), accuracy: 1)   // 120 + 65 + 25: no reset yet
        let done = RulesEngine.status(e, now: at(271), config: config)
        XCTAssertEqual(done.stats.continuousDriving, 0, accuracy: 1)
    }

    func testWorkingLeftDiffersFromDrivingLeft() {
        let e = [EntrySnapshot(kind: .otherWork, regime: .assimilated, start: at(0), end: at(60)),
                 EntrySnapshot(kind: .drive, regime: .assimilated, start: at(60), end: nil)]
        let s = RulesEngine.status(e, now: at(120), config: config)
        XCTAssertEqual(s.drivingLeftToday, .hours(9), accuracy: 1)
        XCTAssertEqual(s.wtdWorkBeforeBreak, .hours(4), accuracy: 1)
        XCTAssertEqual(s.restStartByLatest, at(0).addingTimeInterval(.hours(15)))
    }

    func testManeuverArrowsIgnoreRoadNames() {
        XCTAssertEqual(NavigationModeView.maneuverSymbol("Turn right onto Leftwich Road"), "arrow.turn.up.right")
        XCTAssertEqual(NavigationModeView.maneuverSymbol("Turn left onto Wright Street"), "arrow.turn.up.left")
        XCTAssertEqual(NavigationModeView.maneuverSymbol("Keep left toward M1"), "arrow.up.left")
        XCTAssertEqual(NavigationModeView.maneuverSymbol("Take exit 16 on the right toward Northampton"), "arrow.up.right")
        XCTAssertEqual(NavigationModeView.maneuverSymbol("Arrive at Tesco"), "flag.checkered")
    }

    func testFlatDistanceIsAccurate() {
        let a = CLLocationCoordinate2D(latitude: 52.25, longitude: -1.16)
        let b = CLLocationCoordinate2D(latitude: 52.26, longitude: -1.15)
        let exact = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        XCTAssertEqual(NavigationEngine.metres(a, b), exact, accuracy: exact * 0.005)
    }
}
