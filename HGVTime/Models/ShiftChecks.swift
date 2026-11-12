import Foundation
import SwiftData

/// A check you do at the start or end of a shift (agency form, licence check, card download…), set up by you.
struct ShiftCheckTemplate: Codable, Identifiable, Equatable, Hashable {
    enum Phase: String, Codable, CaseIterable, Identifiable {
        case start, end
        var id: String { rawValue }
        var title: String { self == .start ? "Start of shift" : "End of shift" }
    }

    enum Schedule: String, Codable, CaseIterable, Identifiable {
        case everyShift, days, weekly, fortnightly, monthly
        var id: String { rawValue }
        var title: String {
            switch self {
            case .everyShift: "Every shift"
            case .days: "On chosen days"
            case .weekly: "Once a week"
            case .fortnightly: "Every 2 weeks"
            case .monthly: "Once a month"
            }
        }
    }

    var id = UUID()
    var title: String
    var note: String = ""
    /// Web address to open (an online agency form, a licence-check site…).
    var link: String = ""
    var phase: Phase = .start
    var schedule: Schedule = .everyShift
    /// For `.days`: Calendar weekdays (1 = Sunday … 7 = Saturday).
    var weekdays: [Int] = []
    /// Only for jobs with this company / agency client ("" = any job).
    var company: String = ""
    var enabled = true

    var scheduleText: String {
        guard schedule == .days else { return schedule.title }
        let names = Calendar.current.shortWeekdaySymbols
        let order = [2, 3, 4, 5, 6, 7, 1]
        let picked = order.filter(weekdays.contains).map { names[$0 - 1] }
        return picked.isEmpty ? "No days chosen" : picked.joined(separator: ", ")
    }

    static let presets: [ShiftCheckTemplate] = [
        .init(title: "Walk-round / defect check", note: "Record defects before driving.", phase: .start),
        .init(title: "Agency sign-in form", note: "Fill in the agency's start-of-shift form.", phase: .start),
        .init(title: "Driving licence check", note: "Share a DVLA check code if the agency asks.", link: "https://www.gov.uk/view-driving-licence", phase: .start, schedule: .monthly),
        .init(title: "Fuel card, keys and paperwork collected", phase: .start),
        .init(title: "Download driver card", note: "At least every 28 days by law; many firms want it weekly.", phase: .end, schedule: .weekly),
        .init(title: "Download vehicle unit (tacho)", phase: .end, schedule: .monthly),
        .init(title: "Sign timesheet / register", phase: .end),
        .init(title: "Hand in delivery notes and keys", phase: .end),
        .init(title: "End-of-shift defect report", phase: .end),
    ]
}

/// One check done (or skipped) for a shift.
@Model
final class CheckRecord {
    var id: UUID = UUID()
    var templateID: String = ""
    var title: String = ""
    var phaseRaw: String = "start"
    var doneAt: Date = Date()
    var skipped: Bool = false

    init(template: ShiftCheckTemplate, at: Date = .now, skipped: Bool = false) {
        templateID = template.id.uuidString
        title = template.title
        phaseRaw = template.phase.rawValue
        doneAt = at
        self.skipped = skipped
    }
}

enum ShiftChecks {
    /// Checks still to do in this phase for a shift that started at `shiftStart`.
    static func due(_ templates: [ShiftCheckTemplate], phase: ShiftCheckTemplate.Phase, shiftStart: Date,
                    company: String, records: [CheckRecord], calendar cal: Calendar = .hgv) -> [ShiftCheckTemplate] {
        templates.filter { t in
            guard t.enabled, t.phase == phase else { return false }
            if !t.company.isEmpty && t.company.caseInsensitiveCompare(company) != .orderedSame { return false }
            let since: Date
            switch t.schedule {
            case .everyShift:
                since = shiftStart
            case .days:
                guard t.weekdays.contains(cal.component(.weekday, from: shiftStart)) else { return false }
                since = shiftStart
            case .weekly:
                since = cal.startOfFixedWeek(for: shiftStart)
            case .fortnightly:
                since = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: shiftStart)) ?? shiftStart
            case .monthly:
                since = cal.dateInterval(of: .month, for: shiftStart)?.start ?? shiftStart
            }
            // Checks done just before pressing Start shift still count.
            let from = t.schedule == .everyShift || t.schedule == .days ? since.addingTimeInterval(-3 * 3600) : since
            return !records.contains { $0.templateID == t.id.uuidString && $0.doneAt >= from }
        }
    }
}
