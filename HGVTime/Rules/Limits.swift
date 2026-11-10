import Foundation

extension TimeInterval {
    static func hours(_ h: Double) -> TimeInterval { h * 3600 }
    static func minutes(_ m: Double) -> TimeInterval { m * 60 }
}

/// Legal limits used by the engine.
///
/// Sources:
/// - Assimilated Regulation (EC) 561/2006 as it has effect in the UK, and AETR
///   (GOV.UK "Drivers' hours and tachographs: goods vehicles", section 1).
/// - Road Transport (Working Time) Regulations 2005 (SI 2005/639), as amended.
/// - GB domestic rules, Transport Act 1968 (GOV.UK section 2).
enum Limits {
    // Assimilated / AETR — driving & breaks
    static let continuousDriving: TimeInterval = .hours(4.5)
    static let fullBreak: TimeInterval = .minutes(45)
    static let splitBreakFirst: TimeInterval = .minutes(15)
    static let splitBreakSecond: TimeInterval = .minutes(30)
    static let dailyDriving: TimeInterval = .hours(9)
    static let extendedDailyDriving: TimeInterval = .hours(10)
    static let maxExtensionsPerWeek = 2
    static let weeklyDriving: TimeInterval = .hours(56)
    static let fortnightlyDriving: TimeInterval = .hours(90)

    // Assimilated / AETR — rest
    static let regularDailyRest: TimeInterval = .hours(11)
    static let reducedDailyRest: TimeInterval = .hours(9)
    static let splitRestFirstPart: TimeInterval = .hours(3)
    static let maxReducedDailyRests = 3
    static let dailyRestWindow: TimeInterval = .hours(24)
    static let multiMannedRestWindow: TimeInterval = .hours(30)
    static let regularWeeklyRest: TimeInterval = .hours(45)
    static let reducedWeeklyRest: TimeInterval = .hours(24)
    /// Weekly rest must START no later than six 24-hour periods after the previous one ended.
    static let weeklyRestInterval: TimeInterval = .hours(144)

    // Road Transport (Working Time) Regulations 2005
    static let wtdMaxWorkWithoutBreak: TimeInterval = .hours(6)
    static let wtdBreakPiece: TimeInterval = .minutes(15)
    static let wtdBreakShortDay: TimeInterval = .minutes(30)
    static let wtdBreakLongDay: TimeInterval = .minutes(45)
    static let wtdLongDayThreshold: TimeInterval = .hours(9)
    static let wtdWeeklyMaximum: TimeInterval = .hours(60)
    static let wtdWeeklyAverage: TimeInterval = .hours(48)

    // GB domestic (goods vehicles)
    static let gbDailyDriving: TimeInterval = .hours(10)
    static let gbDailyDuty: TimeInterval = .hours(11)

    /// Small tolerance so that e.g. 4h30m00s of driving isn't flagged because of rounding.
    static let tolerance: TimeInterval = 59
}

struct RuleConfig: Equatable {
    var primaryRegime: Regime = .assimilated
    var applyWorkingTime = true
    var nightWorkLimit: TimeInterval = .hours(10)
    /// RT(WT)R night time for goods vehicles: 00:00–04:00.
    var nightStartHour = 0
    var nightEndHour = 4
    var allowConsecutiveReducedWeekly = false
    var wtdReferenceWeeks = 17
    var calendar: Calendar = .hgv
}

extension Calendar {
    /// Gregorian calendar with fixed weeks running Monday 00:00 to Sunday 24:00.
    static var hgv: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        cal.timeZone = .current
        return cal
    }

    func startOfFixedWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}
