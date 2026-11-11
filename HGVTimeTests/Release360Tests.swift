import XCTest
@testable import HGVTime

/// 3.6.0: calculator, unit converters, wake-up and leave-home times.
@MainActor
final class Release360Tests: XCTestCase {
    private func type(_ keys: String) -> CalcEngine {
        var e = CalcEngine()
        for k in keys.split(separator: " ").map(String.init) {
            switch k {
            case "+": e.op(.add)
            case "-": e.op(.sub)
            case "*": e.op(.mul)
            case "/": e.op(.div)
            case "=": e.equals()
            case "%": e.percent()
            case "±": e.toggleSign()
            case "<": e.backspace()
            default: k.forEach { e.digit(String($0)) }
            }
        }
        return e
    }

    func testCalculatorPrecedenceAndDecimals() {
        XCTAssertEqual(type("2 + 3 * 4 =").result, 14)
        XCTAssertEqual(type("10 - 4 / 2 =").result, 8)
        XCTAssertEqual(type("0.1 + 0.2 =").result!, 0.3, accuracy: 1e-12)
        XCTAssertEqual(CalcEngine.display(type("0.1 + 0.2 =").result), "0.3")
        XCTAssertEqual(type("1..5 + 1 =").result, 2.5)        // second "." ignored
        XCTAssertEqual(type("7 + * 2 =").result, 14)          // last operator wins
        XCTAssertEqual(type("5 = + 1 =").result, 6)           // carry on from a result
        XCTAssertEqual(type("1 / 0 =").result.map(\.isFinite), false)
        XCTAssertEqual(CalcEngine.display(type("1 / 0 =").result), "Error")
    }

    func testCalculatorPercentSignAndBackspace() {
        XCTAssertEqual(type("200 + 10 % =").result, 220)      // 10% of 200
        XCTAssertEqual(type("50 * 10 % =").result, 5)
        XCTAssertEqual(type("5 ± + 2 =").result, -3)
        XCTAssertEqual(type("123 < =").result, 12)
        XCTAssertEqual(type("12 + <").expression, "12")
        XCTAssertEqual(type("3 +").preview, 3)
    }

    func testUnitConversions() {
        XCTAssertEqual(100 * UnitConversion.milesPerKm, 62.137, accuracy: 0.001)
        XCTAssertEqual(1 / UnitConversion.milesPerKm, 1.609_344, accuracy: 0.000_01)
        XCTAssertEqual(16.5 * UnitConversion.metresPerFoot, 5.0292, accuracy: 0.0001)
        XCTAssertEqual(UnitConversion.parse("16'6", feetInches: true)!, 16.5, accuracy: 1e-9)
        XCTAssertEqual(UnitConversion.parse("16 6", feetInches: true)!, 16.5, accuracy: 1e-9)
        XCTAssertEqual(UnitConversion.parse("1,234.5"), 1234.5)
        XCTAssertNil(UnitConversion.parse("abc"))
        XCTAssertEqual(UnitConversion.feetInches(4.88 / UnitConversion.metresPerFoot), "16 ft 0 in")
        XCTAssertEqual(UnitConversion.feetInches(16.5), "16 ft 6 in")
    }

    func testWakeAndLeaveTimes() {
        var s = AppSettings()
        s.leaveBufferMinutes = 10
        s.wakeGetReadyMinutes = 60
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let auto = WakeLeavePlan.times(start: start, travel: 40 * 60, settings: s, wakeOverride: nil, leaveOverride: nil)
        XCTAssertEqual(auto.leave, start.addingTimeInterval(-50 * 60))
        XCTAssertEqual(auto.wake, start.addingTimeInterval(-110 * 60))

        // Leave set by hand: wake-up follows it.
        let leave = start.addingTimeInterval(-90 * 60)
        let manualLeave = WakeLeavePlan.times(start: start, travel: 40 * 60, settings: s, wakeOverride: nil, leaveOverride: leave)
        XCTAssertEqual(manualLeave.leave, leave)
        XCTAssertEqual(manualLeave.wake, leave.addingTimeInterval(-60 * 60))

        // Wake-up set by hand wins.
        let wake = start.addingTimeInterval(-4 * 3600)
        XCTAssertEqual(WakeLeavePlan.times(start: start, travel: 0, settings: s, wakeOverride: wake, leaveOverride: nil).wake, wake)
    }

    func testNextJobSkipsCancelledDoneAndFar() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func job(_ h: Double, cancelled: Bool = false, done: Bool = false) -> WorkPlan {
            let p = WorkPlan(start: now.addingTimeInterval(h * 3600), end: now.addingTimeInterval(h * 3600 + 36_000))
            p.cancelled = cancelled
            p.completed = done
            return p
        }
        let past = job(-1), cancelled = job(2, cancelled: true), done = job(3, done: true), next = job(8), later = job(20), far = job(40)
        XCTAssertTrue(WakeLeaveService.nextJob([far, later, next, done, cancelled, past], now: now) === next)
        XCTAssertNil(WakeLeaveService.nextJob([far, past], now: now))
    }
}
