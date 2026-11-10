import Foundation

/// The headline numbers shown at the top of Today and on the Apple Watch.
/// Values are as of `generatedAt`; use the `…(at:)` helpers to count down live.
struct Dashboard: Codable, Equatable {
    var generatedAt: Date = .now
    var hasData = false
    var onShift = false
    var kind: DutyKind = .rest
    /// "break", "daily" or "weekly" when resting.
    var restTypeRaw: String = ""
    var since: Date = .now

    /// Driving available before any limit.
    var driveLeft: TimeInterval = 0
    var driveLeftReason: String = ""
    /// Driving before the next 45-minute break is due.
    var breakDueIn: TimeInterval = 0
    /// Working time available before a working-time limit (6h break, 60h week, night limit, GB duty).
    var workLeft: TimeInterval = 0
    var workLeftReason: String = ""
    /// Latest time to start daily rest.
    var restBy: Date?

    var dailyDriving: TimeInterval = 0
    var dailyDrivingLimit: TimeInterval = 9 * 3600
    var weeklyDriving: TimeInterval = 0
    var weeklyWorking: TimeInterval = 0
    var shiftWorking: TimeInterval = 0
    var restLength: TimeInterval = 0

    var autoDetect = false
    /// Driver card in the tachograph.
    var cardInserted = false

    // Pay (for widgets)
    var earnedShift: Double = 0
    var earnedWeek: Double = 0
    var currency: String = "£"
    /// Highest of vehicle/trailer height in metres (0 = not set).
    var vehicleHeight: Double = 0

    var statusTitle: String {
        if !hasData || (!onShift && kind == .rest) {
            switch restTypeRaw {
            case "weekly": return "Weekly rest"
            case "daily": return "Daily rest"
            default: return "Off duty"
            }
        }
        if kind == .rest { return "Break" }
        return kind.title
    }

    private var isDriving: Bool { onShift && kind == .drive }
    private var isWorking: Bool { onShift && (kind == .drive || kind == .otherWork) }

    func driveLeft(at now: Date) -> TimeInterval {
        isDriving ? max(0, driveLeft - now.timeIntervalSince(generatedAt)) : driveLeft
    }

    func breakDueIn(at now: Date) -> TimeInterval {
        isDriving ? max(0, breakDueIn - now.timeIntervalSince(generatedAt)) : breakDueIn
    }

    func workLeft(at now: Date) -> TimeInterval {
        isWorking ? max(0, workLeft - now.timeIntervalSince(generatedAt)) : workLeft
    }
}

/// Messages the Watch sends to the iPhone.
enum WatchCommand: String, Codable {
    case drive, otherWork, availability, breakTime
    case startShift, endShiftDaily, endShiftWeekly
    case autoOn, autoOff
    case refresh
}

/// Shares the dashboard between the app and its widgets through the App Group.
enum SharedStore {
    static let appGroup = "group.com.andreikotlyarenko.hgvhours"
    private static let key = "hgv.dashboard"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func save(_ dashboard: Dashboard) {
        guard let data = try? JSONEncoder().encode(dashboard) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load() -> Dashboard? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Dashboard.self, from: data)
    }
}
