import Foundation
import SwiftData
import SwiftUI

/// Which drivers' hours rules a piece of activity falls under.
enum Regime: String, Codable, CaseIterable, Identifiable {
    /// Assimilated rules (retained EU 561/2006) and AETR — tachograph work.
    case assimilated
    /// GB domestic rules (Transport Act 1968) — e.g. vehicles exempt from assimilated rules.
    case gbDomestic
    /// Out of scope: vehicle exempt from drivers' hours rules (e.g. under 3.5 t, or an exempt use).
    /// Driving counts as working time only.
    case exempt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assimilated: "Assimilated / AETR (tacho)"
        case .gbDomestic: "GB domestic"
        case .exempt: "Exempt (no drivers' hours rules)"
        }
    }

    var shortTitle: String {
        switch self {
        case .assimilated: "EU/AETR"
        case .gbDomestic: "GB"
        case .exempt: "Exempt"
        }
    }
}

/// One recorded period of driving, other work, availability or rest.
/// An entry with `end == nil` is the activity currently in progress.
@Model
final class ActivityEntry {
    var id: UUID = UUID()
    var kindRaw: String = DutyKind.rest.rawValue
    var regimeRaw: String = Regime.assimilated.rawValue
    var start: Date = Date()
    var end: Date?
    var multiManned: Bool = false
    var note: String = ""
    /// True for the rest entry created by "End shift" (daily/weekly rest rather than a break).
    var endsShift: Bool = false
    /// For end-of-shift rest: "daily" or "weekly" as chosen by the driver ("" = not set).
    var plannedRestRaw: String = ""
    /// Loading, unloading, waiting… ("" = none).
    var subtypeRaw: String = ""

    init(kind: DutyKind, regime: Regime, start: Date, end: Date? = nil, multiManned: Bool = false, note: String = "", endsShift: Bool = false) {
        self.endsShift = endsShift
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.regimeRaw = regime.rawValue
        self.start = start
        self.end = end
        self.multiManned = multiManned
        self.note = note
    }

    var kind: DutyKind {
        get { DutyKind(rawValue: kindRaw) ?? .rest }
        set { kindRaw = newValue.rawValue }
    }

    var regime: Regime {
        get { Regime(rawValue: regimeRaw) ?? .assimilated }
        set { regimeRaw = newValue.rawValue }
    }

    /// What kind of rest this entry is, for display.
    var restType: RestType? {
        guard kind == .rest else { return nil }
        if !endsShift { return .breakTime }
        return plannedRestRaw == RestType.weekly.rawValue ? .weekly : .daily
    }

    var subtype: ActivitySubtype? { ActivitySubtype(rawValue: subtypeRaw) }

    /// Label shown in lists: "Break", "Daily rest", "Weekly rest", "Loading" or the activity name.
    var displayTitle: String { restType?.title ?? subtype?.title ?? kind.title }

    var snapshot: EntrySnapshot {
        EntrySnapshot(kind: kind, regime: regime, start: start, end: end, multiManned: multiManned)
    }
}

/// A night spent away from home (for night-out allowance).
@Model
final class NightOut {
    var date: Date = Date()
    var note: String = ""

    init(date: Date, note: String = "") {
        self.date = date
        self.note = note
    }
}

/// Break inside a shift, daily rest or weekly rest.
enum RestType: String, Codable, CaseIterable, Identifiable {
    case breakTime = "break"
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakTime: "Break"
        case .daily: "Daily rest"
        case .weekly: "Weekly rest"
        }
    }

    var symbol: String {
        switch self {
        case .breakTime: "cup.and.saucer.fill"
        case .daily: "moon.zzz.fill"
        case .weekly: "house.fill"
        }
    }

    var color: Color {
        switch self {
        case .breakTime: .green
        case .daily: .teal
        case .weekly: .indigo
        }
    }
}

/// A one-off pay item on a date: a bonus, an extra payment, or a paid holiday day.
@Model
final class PayItem {
    var date: Date = Date()
    /// "bonus", "holiday" or "bankHolidayOff".
    var kindRaw: String = "bonus"
    var title: String = ""
    /// £ for bonuses. Ignored for holidays (paid from hours × holiday rate).
    var amount: Double = 0
    /// Paid hours for a holiday day.
    var hours: Double = 0

    init(date: Date, kind: PayItemKind, title: String = "", amount: Double = 0, hours: Double = 0) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.title = title
        self.amount = amount
        self.hours = hours
    }

    var kind: PayItemKind {
        get { PayItemKind(rawValue: kindRaw) ?? .bonus }
        set { kindRaw = newValue.rawValue }
    }

    var snapshot: PayItemSnapshot { PayItemSnapshot(date: date, kind: kind, title: title, amount: amount, hours: hours) }
}

enum PayItemKind: String, Codable, CaseIterable, Identifiable {
    case bonus, holiday
    var id: String { rawValue }
    var title: String { self == .bonus ? "Bonus / extra" : "Holiday day" }
    var symbol: String { self == .bonus ? "gift.fill" : "sun.horizon.fill" }
}

struct PayItemSnapshot {
    var date: Date
    var kind: PayItemKind
    var title: String
    var amount: Double
    var hours: Double
}
