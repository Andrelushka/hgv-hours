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
        case .hourly: String(localized: "Hourly")
        case .daily: String(localized: "Day rate")
        case .salary: String(localized: "Salary")
        }
    }
    var unit: String { self == .daily ? "/day" : "/h" }
}

enum SalaryPeriod: String, CaseIterable, Identifiable {
    case year, month, week, day
    var id: String { rawValue }
    var title: String {
        switch self {
        case .year: String(localized: "per year")
        case .month: String(localized: "per month")
        case .week: String(localized: "per week")
        case .day: String(localized: "per day")
        }
    }
}

enum HolidayMode: String, CaseIterable, Identifiable {
    case none, included, separate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: String(localized: "Don't track")
        case .included: String(localized: "Included in my rate")
        case .separate: String(localized: "Paid separately")
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
            case .shift: String(localized: "per shift")
            case .week: String(localized: "per week")
            case .nightOut: String(localized: "per night out")
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

    // Today screen
    /// Order of the Today tiles (Tile raw values; empty = default layout).
    var todayOrder: [String] = []
    /// Today tiles switched off.
    var todayHidden: [String] = []
    /// Order and hidden tiles of the Hours page.
    var hoursOrder: [String] = []
    var hoursHidden: [String] = []
    /// How Today's date tile shows the date ("long", "week", "medium", "short", "us", "iso").
    var dateStyle = "long"
    /// "always", "shift" (only while on shift) or "never".
    var keepScreenOn = "shift"

    // Country rules
    var ruleRegionRaw = RuleRegion.uk.rawValue
    /// USA: 70 hours / 8 days (true) or 60 hours / 7 days (false).
    var usCycle70 = true

    // AI assistant
    /// Use Claude for free-form questions (needs your own Anthropic API key in the Keychain).
    var assistantUseClaude = false
    /// Use the on-device model (free, private, offline after download).
    var assistantUseLocal = false
    /// Hugging Face id of the on-device model.
    var assistantLocalModel = "mlx-community/Qwen3.5-2B-4bit"

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
    /// Also show the other distance unit in brackets (e.g. "62 mi (100 km)").
    var distanceBoth = false
    /// Heights: "m", "ft", "m+ft" (metres first) or "ft+m" (feet first).
    var heightUnit = "m+ft"

    // Driver card
    var cardInserted = false
    /// When the card was last inserted or withdrawn (seconds since 1970, 0 = never).
    var cardChangedAt: Double = 0

    // Vehicle in use (Vehicle.id as text, "" = none)
    var currentVehicleID = ""
    var currentTrailerID = ""
    /// Running loaded or empty: "loaded", "empty" or "" (not recorded).
    var currentLoadState = ""
    /// Your start- and end-of-shift checks.
    var shiftChecks: [ShiftCheckTemplate] = []

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
    /// Overspeed threshold from the vehicle type and country (otherwise the number above).
    var autoSpeedLimit = true
    var recordOverspeed = true
    /// Record sudden stops (in-cab mode).
    var recordHarshBraking = true
    /// Deceleration that counts as harsh braking, m/s² (3.4 ≈ 0.35 g, a common fleet-telematics threshold).
    var harshBrakeMS2: Double = 3.4
    /// Look up the road's speed limit from OpenStreetMap while navigating.
    var onlineSpeedLimits = true
    /// Spoken turn-by-turn directions.
    var navVoiceOn = true
    /// Directions voice: "all" prompts or "turns" only.
    var navVoiceLevel = "all"
    /// Routing: "valhalla" (lorry route from OpenStreetMap) or "apple" (Apple Maps, not lorry-checked).
    var navRouting = "valhalla"
    var navPreferMotorways = true
    var navAvoidTolls = false
    // Navigation screen layout
    /// Speedometer size: "s", "m" or "l".
    var navSpeedoSize = "l"
    /// Speedometer on the "left" or "right".
    var navSpeedoSide = "left"
    var navShowLanes = true
    /// Big see-through arrow on the right of the screen.
    var navSideArrow = true
    var navSideArrowOpacity: Double = 0.35
    var navShowRoad = true
    /// "standard" or "hybrid" (satellite with roads).
    var navMapStyle = "standard"
    /// How the map follows you: "follow3D", "headingUp", "northUp" or "overview".
    var navViewMode = "follow3D"
    /// Camera tilt in the 3D view, degrees (0 = looking straight down, 75 = low behind the lorry).
    var navPitch: Double = 62
    /// Camera distance: 0.5 = close, 1 = normal, 2 = far.
    var navZoom: Double = 1
    /// Directions banner: "m" or "l".
    var navBannerSize = "m"
    // Alerts on the map
    var navCameraAlerts = true
    var navShowTrafficLights = true
    var navShowReports = true
    var navShowCameras = true
    var navShowParking = true
    // Map filters (remembered)
    var mapShowRoute = true
    var mapShowPlanned = true
    var mapShowStops = true
    var mapProblemsOnly = false
    /// Event types hidden on the day map (EventKind raw values).
    var mapHiddenEvents: [String] = []

    // Wake-up alarm and "time to leave" (worked out from the next planned job)
    var wakeAlarmEnabled = false
    /// Name shown on the alarm.
    var wakeAlarmTitle = "Wake up"
    /// Time to get up and ready before leaving home.
    var wakeGetReadyMinutes = 60
    /// A second alarm this many minutes after the first (0 = off).
    var wakeBackupMinutes = 0
    /// Snooze button on alarms: minutes (0 = no snooze button).
    var wakeSnoozeMinutes = 9
    /// Leave-home as a real alarm (rings on silent) instead of a notification.
    var leaveAsAlarm = false
    /// No limit/reminder notifications or spoken alerts while on daily or weekly rest (alarms still ring).
    var quietDuringRest = false
    var leaveReminderEnabled = false
    /// Arrive at the job this many minutes before the start time.
    var leaveBufferMinutes = 10
    /// An extra heads-up this many minutes before leaving (0 = off).
    var leaveHeadsUpMinutes = 15
    /// Journey time from home to work, used when there's no traffic estimate.
    var commuteMinutes = 30
    /// Ask Apple Maps for the drive time from home to the job's start, with traffic.
    var commuteUseTraffic = true
    var homeAddress = ""
    var homePostcode = ""
    var homeLatitude: Double?
    var homeLongitude: Double?
    /// One-off alarm set by hand (seconds since 1970, 0 = none).
    var manualAlarmAt: Double = 0

    var pay = PaySettings()

    var region: RuleRegion { RuleRegion(rawValue: ruleRegionRaw) ?? .uk }

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

    var settings: AppSettings {
        didSet { if settings.heightUnit != oldValue.heightUnit || settings.distanceBoth != oldValue.distanceBoth { Fmt.applyUnits(settings) } }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
        Fmt.applyUnits(settings)
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
