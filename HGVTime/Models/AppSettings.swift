import Foundation
import Observation

/// How the driver is paid. Every field is optional to use — leave what doesn't apply at zero.
struct PaySettings: Codable, Equatable {
    var baseRate: Double = 15.00
    var payDriving = true
    var payOtherWork = true
    var payAvailability = true
    /// Percentage of the base rate paid for POA (100 = same as work).
    var availabilityPercent: Double = 100
    var payBreaks = false
    /// Overtime after this many paid hours in a shift (0 = off).
    var dailyOvertimeAfterHours: Double = 0
    /// Overtime after this many paid hours in a week (0 = off).
    var weeklyOvertimeAfterHours: Double = 0
    var overtimeMultiplier: Double = 1.5
    var saturdayMultiplier: Double = 1.0
    var sundayMultiplier: Double = 1.0
    /// Extra £ per hour worked inside the night window.
    var nightPremiumPerHour: Double = 0
    var nightPremiumStartHour: Int = 22
    var nightPremiumEndHour: Int = 6
    /// £ per night out.
    var nightOutAllowance: Double = 0
    /// Guaranteed paid hours per shift (0 = off).
    var minimumPaidHoursPerShift: Double = 0
    /// Guaranteed paid hours per week (0 = off).
    var minimumPaidHoursPerWeek: Double = 0
    /// Guaranteed paid hours per calendar month (0 = off).
    var minimumPaidHoursPerMonth: Double = 0

    // Salary
    var salaryAmount: Double = 0
    /// "year", "month", "week" or "day".
    var salaryPeriod: String = SalaryPeriod.year.rawValue
    /// Contracted hours per week: overtime starts after these (salary only).
    var contractedHoursPerWeek: Double = 45
    var contractedDaysPerWeek: Double = 5
    var currencySymbol = "£"
    /// Custom overtime rate in £/hour. 0 = use the multiplier instead.
    var overtimeFixedRate: Double = 0

    // How you're paid
    /// "hourly" or "daily".
    var payBasis: String = PayBasis.hourly.rawValue
    /// £ per shift when paid a day rate.
    var dayRate: Double = 0
    /// Hours the day rate covers; paid hours beyond this are overtime.
    var dayRateHours: Double = 10

    // Typed-in rates (0 = use the multiplier). £/hour when hourly, £/day when on a day rate.
    var saturdayFixedRate: Double = 0
    var sundayFixedRate: Double = 0
    var bankHolidayMultiplier: Double = 1.0
    var bankHolidayFixedRate: Double = 0

    // Holiday pay
    /// "none", "included" (rolled up into the rate) or "onTop" (added as a % of earnings).
    var holidayMode: String = HolidayMode.none.rawValue
    var holidayPercent: Double = 12.07
    /// Paid hours for a holiday day you take off.
    var holidayDayHours: Double = 8
    /// £/hour for holiday days (0 = basic hourly rate). On a day rate, £/day (0 = the day rate).
    var holidayFixedRate: Double = 0

    /// Regular bonuses and allowances.
    var extras: [PayExtra] = []

    var basis: PayBasis { PayBasis(rawValue: payBasis) ?? .hourly }
    var salaryPer: SalaryPeriod { SalaryPeriod(rawValue: salaryPeriod) ?? .year }

    /// Salary converted to one week.
    var weeklySalary: Double {
        switch salaryPer {
        case .year: salaryAmount / 52
        case .month: salaryAmount * 12 / 52
        case .week: salaryAmount
        case .day: salaryAmount * contractedDaysPerWeek
        }
    }

    /// Hourly value of the salary, used for overtime.
    var salaryHourly: Double { contractedHoursPerWeek > 0 ? weeklySalary / contractedHoursPerWeek : 0 }
    var holiday: HolidayMode {
        holidayMode == "onTop" ? .separate : (HolidayMode(rawValue: holidayMode) ?? .none)
    }
}

enum PayBasis: String, CaseIterable, Identifiable {
    case hourly, daily, salary
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hourly: "Hourly"
        case .daily: "Day rate"
        case .salary: "Salary"
        }
    }
    var unit: String { self == .daily ? "/day" : "/h" }
}

enum SalaryPeriod: String, CaseIterable, Identifiable {
    case year, month, week, day
    var id: String { rawValue }
    var title: String {
        switch self {
        case .year: "per year"
        case .month: "per month"
        case .week: "per week"
        case .day: "per day"
        }
    }
}

enum HolidayMode: String, CaseIterable, Identifiable {
    case none, included, separate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Don't track"
        case .included: "Included in my rate"
        case .separate: "Paid separately"
        }
    }
    /// UK statutory accrual for irregular hours / rolled-up holiday pay: 5.6 weeks ÷ 46.4 weeks.
    static let ukRate = 12.07
}

/// A regular bonus or allowance, e.g. "Tipper bonus £20 per shift".
struct PayExtra: Codable, Equatable, Identifiable {
    enum Per: String, Codable, CaseIterable, Identifiable {
        case shift, week, nightOut
        var id: String { rawValue }
        var title: String {
            switch self {
            case .shift: "per shift"
            case .week: "per week"
            case .nightOut: "per night out"
            }
        }
    }
    var id = UUID()
    var name: String = ""
    var amount: Double = 0
    var per: Per = .shift
}

struct AppSettings: Codable, Equatable {
    var driverName = ""
    var employer = ""
    var vehicleReg = ""

    // Driver profile (kept only on this iPhone)
    var profileCreated = false
    var phone = ""
    /// e.g. "C, C+E"
    var licenceCategories = "C+E"
    var driverCardNumber = ""
    /// Expiry dates as seconds since 1970 (0 = not set).
    var licenceExpiry: Double = 0
    var cardExpiry: Double = 0
    var cpcExpiry: Double = 0
    var medicalDue: Double = 0
    /// Days before an expiry to start reminding.
    var expiryWarningDays = 60

    // App lock
    var lockEnabled = false
    /// Lock again after this many minutes in the background (0 = every time).
    var lockAfterMinutes = 0

    // Rules
    var primaryRegime: Regime = .assimilated
    var applyWorkingTime = true
    /// RT(WT)R night-work limit (10h unless a collective/workforce agreement says otherwise).
    var nightWorkLimitHours: Double = 10
    var wtdReferenceWeeks = 17
    /// International goods derogation: two consecutive reduced weekly rests outside the UK.
    var allowConsecutiveReducedWeekly = false

    // Current state toggles (used for new entries)
    var currentRegime: Regime = .assimilated
    var multiManned = false

    // Alerts
    var notificationsEnabled = true
    var warningLeadMinutes = 15
    var liveActivityEnabled = true

    var hasAcceptedDisclaimer = false

    // Spoken alerts
    var voiceEnabled = false
    /// 0.3 (slow) … 0.6 (fast)
    var voiceRate: Double = 0.5
    /// AVSpeechSynthesisVoice identifier ("" = default English voice).
    var voiceIdentifier = ""
    var speakActivityChanges = true
    var speakWarnings = true
    var speakOverspeed = true
    var speakReminders = true
    /// Minutes before a limit that the warning is spoken.
    var voiceWarningMinutes = 15
    var seededDefaultReminders = false

    // Event log
    /// Save where each event happened.
    var recordEventLocations = true
    /// Save the route while in-cab mode runs.
    var recordRoute = true

    // Units
    /// Show distances in miles (UK) instead of km.
    var useMiles = true
    /// Show heights/lengths in feet and inches as well as metres.
    var showFeet = true

    // Driver card
    var cardInserted = false
    /// When the card was last inserted or withdrawn (seconds since 1970, 0 = never).
    var cardChangedAt: Double = 0

    // Vehicle in use (Vehicle.id as text, "" = none)
    var currentVehicleID = ""
    var currentTrailerID = ""

    // Shift
    /// Activity recorded when you tap "Start shift" (usually other work for the walk-round check).
    var shiftStartKind: DutyKind = .otherWork

    // Automatic drive detection ("in cab" mode)
    /// On = moving is recorded as driving and stopping switches to `autoStoppedKind`, like a tachograph.
    var autoDetectEnabled = false
    /// Speed above which the vehicle counts as moving.
    var autoMovingSpeedKmh: Double = 10
    /// How long the vehicle must be stopped before driving ends.
    var autoStopDelaySeconds: Int = 60
    /// What is recorded when the vehicle stops.
    var autoStoppedKind: DutyKind = .otherWork
    /// Record speed above this as overspeed (tachographs are usually set at 90 km/h for HGVs).
    var overspeedLimitKmh: Double = 90
    var recordOverspeed = true

    var pay = PaySettings()

    var ruleConfig: RuleConfig {
        RuleConfig(
            primaryRegime: primaryRegime,
            applyWorkingTime: applyWorkingTime,
            nightWorkLimit: nightWorkLimitHours * 3600,
            allowConsecutiveReducedWeekly: allowConsecutiveReducedWeekly,
            wtdReferenceWeeks: wtdReferenceWeeks
        )
    }
}

/// Persists `AppSettings` to UserDefaults. Unknown/missing keys fall back to defaults,
/// so adding settings in future versions never wipes a user's existing configuration.
@Observable
final class SettingsStore {
    private static let key = "hgv.settings.v1"

    var settings: AppSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
    }

    @ObservationIgnored private let defaults: UserDefaults

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private static func load(from defaults: UserDefaults) -> AppSettings {
        guard let stored = defaults.data(forKey: key),
              let storedObject = try? JSONSerialization.jsonObject(with: stored) as? [String: Any],
              let defaultData = try? JSONEncoder().encode(AppSettings()),
              let defaultObject = try? JSONSerialization.jsonObject(with: defaultData) as? [String: Any]
        else { return AppSettings() }
        let merged = deepMerge(defaultObject, storedObject)
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: mergedData)
        else { return AppSettings() }
        return settings
    }

    private static func deepMerge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            if let baseDict = base[key] as? [String: Any], let overlayDict = value as? [String: Any] {
                result[key] = deepMerge(baseDict, overlayDict)
            } else if base[key] != nil {
                result[key] = value
            }
        }
        return result
    }
}
