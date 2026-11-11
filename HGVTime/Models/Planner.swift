import Foundation
import SwiftUI
import SwiftData

// MARK: Vehicles and trailers

enum FuelType: String, Codable, CaseIterable, Identifiable {
    case diesel, dieselAdBlue, hvo, lng, cng, electric, hybrid, petrol
    var id: String { rawValue }
    var title: String {
        switch self {
        case .diesel: "Diesel"
        case .dieselAdBlue: "Diesel + AdBlue"
        case .hvo: "HVO"
        case .lng: "Gas (LNG)"
        case .cng: "Gas (CNG)"
        case .electric: "Electric"
        case .hybrid: "Hybrid"
        case .petrol: "Petrol"
        }
    }
}

enum VehicleKind: String, Codable, CaseIterable, Identifiable {
    case tractor, rigid, van, trailer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tractor: "Tractor unit (artic)"
        case .rigid: "Rigid"
        case .van: "Van"
        case .trailer: "Trailer"
        }
    }
    var symbol: String {
        switch self {
        case .tractor: "truck.box.fill"
        case .rigid: "box.truck.fill"
        case .van: "car.side.fill"
        case .trailer: "shippingbox.fill"
        }
    }
}

/// A saved lorry, van or trailer with its specifications.
@Model
final class Vehicle {
    var id: UUID = UUID()
    var kindRaw: String = VehicleKind.tractor.rawValue
    var registration: String = ""
    var fleetNumber: String = ""
    var make: String = ""
    var model: String = ""
    /// Metres. 0 = not set.
    var height: Double = 0
    var width: Double = 0
    var length: Double = 0
    /// Gross weight in tonnes.
    var weight: Double = 0
    var axles: Int = 0
    var fuelRaw: String = FuelType.dieselAdBlue.rawValue
    /// Trailer body, e.g. curtainsider, fridge, box, flatbed, tipper, tanker.
    var body: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    /// Latest odometer reading in km (0 = not set).
    var odometerKm: Double = 0

    init(kind: VehicleKind = .tractor) {
        self.kindRaw = kind.rawValue
    }

    var kind: VehicleKind {
        get { VehicleKind(rawValue: kindRaw) ?? .tractor }
        set { kindRaw = newValue.rawValue }
    }

    var fuel: FuelType {
        get { FuelType(rawValue: fuelRaw) ?? .diesel }
        set { fuelRaw = newValue.rawValue }
    }

    var displayName: String {
        let reg = registration.isEmpty ? (fleetNumber.isEmpty ? "Unnamed" : fleetNumber) : registration
        let model = [make, self.model].filter { !$0.isEmpty }.joined(separator: " ")
        return model.isEmpty ? reg : "\(reg) · \(model)"
    }

    /// e.g. "4.95 m high · 16.5 m long · 44 t"
    var specsLine: String {
        var parts: [String] = []
        if height > 0 { parts.append(String(format: "%.2f m (%@) high", height, Fmt.feetInches(height))) }
        if length > 0 { parts.append(String(format: "%.1f m (%@) long", length, Fmt.feetInches(length))) }
        if weight > 0 { parts.append(String(format: "%g t", weight)) }
        if kind != .trailer { parts.append(fuel.title) }
        if !body.isEmpty { parts.append(body) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Work planner

/// A stop on a planned job.
struct PlanStop: Codable, Equatable, Identifiable {
    /// Short name for lists and the map: company, then place.
    var displayName: String {
        let c = company ?? ""
        if !c.isEmpty { return c }
        if !place.isEmpty { return place }
        return kindTitle
    }

    /// Type of stop, using the custom name for a custom stop.
    var kindTitle: String {
        if kind == .other, let c = customTitle, !c.isEmpty { return c }
        return kind.title
    }

    /// Address line(s) for navigation and geocoding.
    var fullAddress: String {
        [address ?? place, postcode ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Booking time as text (new date field, or the old free-text time).
    var bookingText: String {
        if let b = bookingTime { return Fmt.time(b) }
        return time
    }

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case collection, delivery, depot, fuel, parking, trailer, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .collection: "Collection"
            case .delivery: "Delivery"
            case .depot: "Depot"
            case .fuel: "Fuel"
            case .parking: "Parking / rest"
            case .trailer: "Trailer swap"
            case .other: "Custom stop"
            }
        }
        var symbol: String {
            switch self {
            case .collection: "arrow.up.bin.fill"
            case .delivery: "arrow.down.to.line.compact"
            case .depot: "building.2.fill"
            case .fuel: "fuelpump.fill"
            case .parking: "parkingsign.circle.fill"
            case .trailer: "arrow.triangle.swap"
            case .other: "mappin.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .collection: .orange
            case .delivery: .indigo
            case .depot: .gray
            case .fuel: .green
            case .parking: .teal
            case .trailer: .brown
            case .other: .purple
            }
        }
    }
    var id = UUID()
    var kind: Kind = .delivery
    var place: String = ""
    /// Booking time as text, e.g. "08:30" or "AM".
    var time: String = ""
    var reference: String = ""
    var pallets: String = ""
    var notes: String = ""
    // More detail (optional so older plans still load).
    var company: String?
    var address: String?
    var postcode: String?
    var bookingTime: Date?
    var orderReference: String?
    var weight: String?
    var contactName: String?
    var contactPhone: String?
    /// Name of a custom stop type, e.g. "Weighbridge", "Customs", "Wash".
    var customTitle: String?
    // Recorded on the day with the Arrived / Departed buttons.
    var arrivedAt: Date?
    var departedAt: Date?
    var latitude: Double?
    var longitude: Double?
}

/// A custom "label: value" line.
struct PlanLine: Codable, Equatable, Identifiable {
    var id = UUID()
    var label: String = ""
    var value: String = ""
}

/// A planned (booked) working day, with job details.
@Model
final class WorkPlan {
    var id: UUID = UUID()
    var plannedStart: Date = Date()
    var plannedEnd: Date = Date()
    var company: String = ""
    var vehicleID: String = ""
    var trailerID: String = ""
    var startLocation: String = ""
    var startPostcode: String = ""
    var startLatitude: Double?
    var startLongitude: Double?
    var load: String = ""
    var pallets: String = ""
    var reference: String = ""
    var notes: String = ""
    var stopsData: Data = Data()
    var linesData: Data = Data()
    var createdAt: Date = Date()
    /// Set when the shift ends: the job leaves the Today screen (still in the planner and debrief).
    var completed: Bool = false

    init(start: Date, end: Date) {
        self.plannedStart = start
        self.plannedEnd = end
    }

    var stops: [PlanStop] {
        get { (try? JSONDecoder().decode([PlanStop].self, from: stopsData)) ?? [] }
        set { stopsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var lines: [PlanLine] {
        get { (try? JSONDecoder().decode([PlanLine].self, from: linesData)) ?? [] }
        set { linesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var length: TimeInterval { plannedEnd.timeIntervalSince(plannedStart) }
}

// MARK: Notebook

/// A note, a table, or a template for either.
@Model
final class NoteItem {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    /// "text" or "table".
    var kindRaw: String = "text"
    var tableData: Data = Data()
    /// Header/frozen rows and columns, colours and widths (TableStyle).
    var styleData: Data = Data()
    var isTemplate: Bool = false
    var pinned: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(title: String = "", kind: String = "text", isTemplate: Bool = false) {
        self.title = title
        self.kindRaw = kind
        self.isTemplate = isTemplate
    }

    var isTable: Bool { kindRaw == "table" }

    /// Rows of cells; row 0 is the header.
    var table: [[String]] {
        get { (try? JSONDecoder().decode([[String]].self, from: tableData)) ?? [["", ""], ["", ""]] }
        set { tableData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var tableStyle: TableStyle {
        get { (try? JSONDecoder().decode(TableStyle.self, from: styleData)) ?? TableStyle() }
        set { styleData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    func copy(asTemplate: Bool) -> NoteItem {
        let n = NoteItem(title: title, kind: kindRaw, isTemplate: asTemplate)
        n.body = body
        n.tableData = tableData
        n.styleData = styleData
        return n
    }
}

// MARK: Driver card

/// A driver card insert or withdrawal, recorded from the Today screen.
@Model
final class CardEvent {
    var time: Date = Date()
    var inserted: Bool = true

    init(time: Date, inserted: Bool) {
        self.time = time
        self.inserted = inserted
    }
}

// MARK: Speed events

/// A period above the overspeed threshold, recorded in in-cab mode.
/// Like a tachograph, more than 60 seconds in a row counts as an overspeed infringement.
@Model
final class SpeedEvent {
    var start: Date = Date()
    var end: Date = Date()
    var maxKmh: Double = 0
    var limitKmh: Double = 90
    var latitude: Double = 0
    var longitude: Double = 0

    init(start: Date, end: Date, maxKmh: Double, limitKmh: Double, latitude: Double, longitude: Double) {
        self.start = start
        self.end = end
        self.maxKmh = maxKmh
        self.limitKmh = limitKmh
        self.latitude = latitude
        self.longitude = longitude
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var isInfringement: Bool { duration > 60 }
    var hasLocation: Bool { latitude != 0 || longitude != 0 }
}

// MARK: Day records and resources

/// Per-day vehicle and distance record (one per calendar day).
@Model
final class DayRecord {
    var day: Date = Date()
    var vehicleID: String = ""
    /// Odometer at start and end of the day, in km (0 = not entered).
    var startOdometerKm: Double = 0
    var endOdometerKm: Double = 0
    /// Distance measured by GPS in in-cab mode, km.
    var gpsKm: Double = 0
    var notes: String = ""

    init(day: Date) {
        self.day = Calendar.hgv.startOfDay(for: day)
    }

    /// Odometer distance if both readings are there, otherwise GPS distance.
    var distanceKm: Double {
        if startOdometerKm > 0 && endOdometerKm > startOdometerKm { return endOdometerKm - startOdometerKm }
        return gpsKm
    }
}

enum ResourceKind: String, Codable, CaseIterable, Identifiable {
    case diesel, petrol, adblue, gas, electricity, tachoRoll, oil, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .diesel: "Diesel"
        case .petrol: "Petrol"
        case .adblue: "AdBlue"
        case .gas: "Gas (LNG/CNG)"
        case .electricity: "Electricity"
        case .tachoRoll: "Tacho roll"
        case .oil: "Oil"
        case .other: "Other"
        }
    }
    var unit: String {
        switch self {
        case .diesel, .petrol, .adblue, .oil: "L"
        case .gas: "kg"
        case .electricity: "kWh"
        case .tachoRoll: "rolls"
        case .other: ""
        }
    }
    var symbol: String {
        switch self {
        case .diesel, .petrol: "fuelpump.fill"
        case .adblue: "drop.fill"
        case .gas: "flame.fill"
        case .electricity: "bolt.fill"
        case .tachoRoll: "scroll.fill"
        case .oil: "oilcan.fill"
        case .other: "shippingbox.fill"
        }
    }
}

/// Fuel, AdBlue, tacho rolls and other things used.
@Model
final class ResourceLog {
    var date: Date = Date()
    var kindRaw: String = ResourceKind.diesel.rawValue
    var quantity: Double = 0
    var cost: Double = 0
    var odometerKm: Double = 0
    var location: String = ""
    var vehicleID: String = ""
    var notes: String = ""

    init(date: Date = .now, kind: ResourceKind) {
        self.date = date
        self.kindRaw = kind.rawValue
    }

    var kind: ResourceKind {
        get { ResourceKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: Reminders

/// What sets a reminder off.
enum ReminderTrigger: String, Codable, CaseIterable, Identifiable {
    case time
    case shiftStart, shiftEnd, arrived, cardInserted
    case beforeDrivingBreak, beforeWorkingBreak, beforeDailyRest, beforeWeeklyRest
    case afterShiftStart, dailyRestComplete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: "At a time"
        case .shiftStart: "When I start a shift"
        case .shiftEnd: "When I end a shift"
        case .arrived: "When I tap Arrived"
        case .cardInserted: "When I insert my card"
        case .beforeDrivingBreak: "Before my driving break is due"
        case .beforeWorkingBreak: "Before my working-time break is due"
        case .beforeDailyRest: "Before I must start daily rest"
        case .beforeWeeklyRest: "Before weekly rest is due"
        case .afterShiftStart: "Some time after shift start"
        case .dailyRestComplete: "When my daily rest is complete"
        }
    }

    var symbol: String {
        switch self {
        case .time: "alarm.fill"
        case .shiftStart: "play.circle.fill"
        case .shiftEnd: "stop.circle.fill"
        case .arrived: "mappin.and.ellipse"
        case .cardInserted: "creditcard.fill"
        case .beforeDrivingBreak: "cup.and.saucer.fill"
        case .beforeWorkingBreak: "figure.walk"
        case .beforeDailyRest: "moon.zzz.fill"
        case .beforeWeeklyRest: "house.fill"
        case .afterShiftStart: "timer"
        case .dailyRestComplete: "sunrise.fill"
        }
    }

    /// Uses a "minutes before/after" value.
    var usesOffset: Bool {
        switch self {
        case .beforeDrivingBreak, .beforeWorkingBreak, .beforeDailyRest, .beforeWeeklyRest, .afterShiftStart: true
        default: false
        }
    }

    /// Happens because you pressed a button (fires straight away).
    var isAction: Bool {
        switch self {
        case .shiftStart, .shiftEnd, .arrived, .cardInserted: true
        default: false
        }
    }
}

enum ReminderRepeat: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekdays, weekly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .once: "Once"
        case .daily: "Every day"
        case .weekdays: "Mon–Fri"
        case .weekly: "Every week"
        }
    }
}

/// A reminder you set up yourself.
@Model
final class Reminder {
    var id: UUID = UUID()
    var title: String = ""
    var message: String = ""
    var triggerRaw: String = ReminderTrigger.time.rawValue
    var time: Date = Date()
    var repeatRaw: String = ReminderRepeat.daily.rawValue
    var offsetMinutes: Int = 15
    var enabled: Bool = true
    var speak: Bool = true
    var createdAt: Date = Date()

    init(title: String, message: String = "", trigger: ReminderTrigger, offsetMinutes: Int = 15) {
        self.title = title
        self.message = message
        self.triggerRaw = trigger.rawValue
        self.offsetMinutes = offsetMinutes
    }

    var trigger: ReminderTrigger {
        get { ReminderTrigger(rawValue: triggerRaw) ?? .time }
        set { triggerRaw = newValue.rawValue }
    }

    var repeatRule: ReminderRepeat {
        get { ReminderRepeat(rawValue: repeatRaw) ?? .once }
        set { repeatRaw = newValue.rawValue }
    }

    /// e.g. "15 min before my driving break is due" / "07:00 every day"
    var summary: String {
        switch trigger {
        case .time: return "\(Fmt.time(time)) · \(repeatRule == .once ? Fmt.day(time) : repeatRule.title)"
        case .afterShiftStart: return "\(offsetMinutes) min after shift start"
        default: return trigger.usesOffset ? "\(offsetMinutes) min \(trigger.title.lowercased())" : trigger.title
        }
    }

}

// MARK: Event log and route

enum EventKind: String, Codable, CaseIterable, Identifiable {
    case shiftStart, shiftEnd, activity, cardIn, cardOut, arrived, departed, fuel, overspeed, infringement, note, correction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shiftStart: "Shift started"
        case .shiftEnd: "Shift ended"
        case .activity: "Activity"
        case .cardIn: "Card inserted"
        case .cardOut: "Card withdrawn"
        case .arrived: "Arrived"
        case .departed: "Departed"
        case .fuel: "Fuel / resources"
        case .overspeed: "Overspeed"
        case .infringement: "Infringement"
        case .note: "Note"
        case .correction: "Record changed"
        }
    }

    var symbol: String {
        switch self {
        case .shiftStart: "play.circle.fill"
        case .shiftEnd: "stop.circle.fill"
        case .activity: "arrow.triangle.swap"
        case .cardIn, .cardOut: "creditcard.fill"
        case .arrived: "mappin.circle.fill"
        case .departed: "arrow.up.right.circle.fill"
        case .fuel: "fuelpump.fill"
        case .overspeed: "gauge.with.dots.needle.100percent"
        case .infringement: "exclamationmark.octagon.fill"
        case .note: "note.text"
        case .correction: "pencil.circle.fill"
        }
    }

    var isProblem: Bool { self == .overspeed || self == .infringement }
}

/// Something that happened, where and when.
@Model
final class EventLog {
    var time: Date = Date()
    var kindRaw: String = EventKind.note.rawValue
    var title: String = ""
    var detail: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    /// km/h at the time (0 = unknown).
    var speedKmh: Double = 0
    /// Seconds, for events that last (e.g. overspeed).
    var duration: Double = 0
    /// Prevents logging the same infringement twice.
    var key: String = ""
    /// For activity events: the DutyKind raw value, or "kind:subtype".
    var activityRaw: String = ""

    init(time: Date = .now, kind: EventKind, title: String = "", detail: String = "") {
        self.time = time
        self.kindRaw = kind.rawValue
        self.title = title.isEmpty ? kind.title : title
        self.detail = detail
    }

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var hasLocation: Bool { latitude != 0 || longitude != 0 }

    var activityKind: DutyKind? { DutyKind(rawValue: activityRaw.components(separatedBy: ":").first ?? "") }
    var activitySubtype: ActivitySubtype? {
        let parts = activityRaw.components(separatedBy: ":")
        return parts.count > 1 ? ActivitySubtype(rawValue: parts[1]) : nil
    }
}

/// A point on the route, saved while in-cab mode runs.
@Model
final class TrackPoint {
    var time: Date = Date()
    var latitude: Double = 0
    var longitude: Double = 0
    var speedKmh: Double = 0

    init(time: Date, latitude: Double, longitude: Double, speedKmh: Double) {
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
        self.speedKmh = speedKmh
    }
}

// MARK: Sub-activities

/// What kind of other work or POA it was, for the driver log and map.
enum ActivitySubtype: String, Codable, CaseIterable, Identifiable {
    case loading, unloading, vehicleCheck, yardCheck, fuelling, paperwork, cleaning
    case waitingLoad, waitingUnload, waitingShift, waitingJob, spare, ferryTrain, doubleManned

    var id: String { rawValue }

    var kind: DutyKind {
        switch self {
        case .waitingLoad, .waitingUnload, .waitingShift, .waitingJob, .spare, .ferryTrain, .doubleManned: .availability
        default: .otherWork
        }
    }

    var title: String {
        switch self {
        case .loading: "Loading"
        case .unloading: "Unloading"
        case .vehicleCheck: "Vehicle check"
        case .yardCheck: "Yard check"
        case .fuelling: "Fuelling"
        case .paperwork: "Paperwork"
        case .cleaning: "Cleaning"
        case .waitingLoad: "Waiting to load"
        case .waitingUnload: "Waiting to unload"
        case .waitingShift: "Waiting for shift"
        case .waitingJob: "Waiting for job"
        case .spare: "Spare / standby"
        case .ferryTrain: "Ferry / train"
        case .doubleManned: "Double-manned"
        }
    }

    var symbol: String {
        switch self {
        case .loading: "arrow.up.bin.fill"
        case .unloading: "arrow.down.to.line.compact"
        case .vehicleCheck: "checklist"
        case .yardCheck: "checklist.checked"
        case .fuelling: "fuelpump.fill"
        case .paperwork: "doc.text.fill"
        case .cleaning: "sparkles"
        case .waitingLoad, .waitingUnload: "hourglass"
        case .waitingShift: "clock.badge.questionmark"
        case .waitingJob: "tray.and.arrow.down"
        case .spare: "person.badge.clock"
        case .ferryTrain: "ferry.fill"
        case .doubleManned: "person.2.fill"
        }
    }

    static func options(for kind: DutyKind) -> [ActivitySubtype] { allCases.filter { $0.kind == kind } }
}
