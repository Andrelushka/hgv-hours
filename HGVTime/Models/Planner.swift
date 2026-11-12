import Foundation
import SwiftUI
import SwiftData

// MARK: Vehicles and trailers

enum FuelType: String, Codable, CaseIterable, Identifiable {
    case diesel, dieselAdBlue, hvo, lng, cng, electric, hybrid, petrol
    var id: String { rawValue }
    var title: String {
        switch self {
        case .diesel: String(localized: "Diesel")
        case .dieselAdBlue: String(localized: "Diesel + AdBlue")
        case .hvo: String(localized: "HVO")
        case .lng: String(localized: "Gas (LNG)")
        case .cng: String(localized: "Gas (CNG)")
        case .electric: String(localized: "Electric")
        case .hybrid: String(localized: "Hybrid")
        case .petrol: String(localized: "Petrol")
        }
    }
}

enum VehicleKind: String, Codable, CaseIterable, Identifiable {
    case tractor, rigid, van, trailer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tractor: String(localized: "Tractor unit (artic)")
        case .rigid: String(localized: "Rigid")
        case .van: String(localized: "Van")
        case .trailer: String(localized: "Trailer")
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
    /// Rules when driving this vehicle: "" = your usual rules, or a Regime raw value
    /// ("assimilated" tacho, "gbDomestic", "exempt" = no drivers' hours rules).
    var rulesRaw: String = ""
    /// Overspeed threshold for this vehicle in km/h (0 = automatic from vehicle type and country).
    var speedLimitKmh: Double = 0
    /// Speed limiter setting (0 = usual for the type: 90 km/h / 56 mph for lorries over 3.5 t). Used for arrival times.
    var limiterKmh: Double = 0

    var rules: Regime? {
        get { Regime(rawValue: rulesRaw) }
        set { rulesRaw = newValue?.rawValue ?? "" }
    }

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
        if height > 0 { parts.append("\(Fmt.length(height)) high") }
        if length > 0 { parts.append("\(Fmt.length(length)) long") }
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

    /// "Trailer T1234" / "AB12 CDE" for a pick-up or drop-off stop ("" for other stops).
    func equipmentName(in vehicles: [Vehicle]) -> String {
        guard isEquipmentStop else { return "" }
        if let id = equipmentID, let v = vehicles.first(where: { $0.id.uuidString == id }) { return v.displayName }
        return equipmentRef ?? ""
    }

    /// "Drop T1 · Pick up T2" for trailer changes at an ordinary stop ("" if none).
    func trailerChangeText(in vehicles: [Vehicle]) -> String {
        func name(_ id: String?) -> String? {
            guard let id, !id.isEmpty else { return nil }
            if id == "current" { return String(localized: "current trailer") }
            return vehicles.first { $0.id.uuidString == id }?.displayName
        }
        var parts: [String] = []
        if let d = name(dropTrailerID) { parts.append(String(localized: "Drop \(d)")) }
        if let p = name(pickTrailerID) ?? ((pickTrailerRef ?? "").isEmpty ? nil : pickTrailerRef) {
            parts.append(String(localized: "Pick up \(p)"))
        }
        return parts.joined(separator: " · ")
    }

    /// Picking up or dropping off a trailer or vehicle.
    var isEquipmentStop: Bool { [.trailerPickup, .trailerDrop, .vehiclePickup, .vehicleDrop].contains(kind) }
    var isTrailerStop: Bool { kind == .trailerPickup || kind == .trailerDrop }

    /// Address line(s) for navigation and geocoding.
    var fullAddress: String {
        AddressParts.join(flat: flat, houseName: houseName, houseNumber: houseNumber, street: address ?? place, postcode: postcode)
    }

    /// Booking time as text (new date field, or the old free-text time).
    var bookingText: String {
        if let b = bookingTime { return Fmt.time(b) }
        return time
    }

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case collection, delivery, depot, fuel, parking, trailer, trailerPickup, trailerDrop, vehiclePickup, vehicleDrop, service, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .collection: String(localized: "Collection")
            case .delivery: String(localized: "Delivery")
            case .depot: String(localized: "Depot")
            case .fuel: String(localized: "Fuel")
            case .parking: String(localized: "Parking / rest")
            case .trailer: String(localized: "Trailer swap")
            case .trailerPickup: String(localized: "Pick up trailer")
            case .trailerDrop: String(localized: "Drop off trailer")
            case .vehiclePickup: String(localized: "Pick up vehicle")
            case .vehicleDrop: String(localized: "Drop off vehicle")
            case .service: String(localized: "Vehicle service")
            case .other: String(localized: "Custom stop")
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
            case .trailerPickup: "link.circle.fill"
            case .trailerDrop: "personalhotspot.circle"
            case .vehiclePickup: "key.fill"
            case .vehicleDrop: "key"
            case .service: "wrench.and.screwdriver.fill"
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
            case .trailer, .trailerPickup, .trailerDrop: .brown
            case .vehiclePickup, .vehicleDrop: .blue
            case .service: .red
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
    /// Address details: house/building number, house or building name, flat/unit.
    var houseNumber: String?
    var houseName: String?
    var flat: String?
    // Recorded on the day with the Arrived / Departed buttons.
    var arrivedAt: Date?
    var departedAt: Date?
    var latitude: Double?
    var longitude: Double?
    /// For trailer / vehicle pick-up and drop-off stops: the trailer or vehicle (Vehicle.id) from your list…
    var equipmentID: String?
    /// …or its number / registration typed in.
    var equipmentRef: String?
    /// Any stop: drop a trailer here and/or pick one up (e.g. deliver, drop the loaded trailer, take an empty one).
    /// Drop: "current" = whatever trailer you have, or a trailer id. Pick: a trailer id.
    var dropTrailerID: String?
    var pickTrailerID: String?
    var pickTrailerRef: String?
    /// What happened at this stop when it didn't go to plan (nil = normal).
    var outcomeRaw: String?
    var outcomeReason: String?
    var outcomeAt: Date?

    enum Outcome: String, CaseIterable, Identifiable {
        case cancelled, failed, rejected
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cancelled: String(localized: "Cancelled")
            case .failed: String(localized: "Failed")
            case .rejected: String(localized: "Rejected")
            }
        }
        var detail: String {
            switch self {
            case .cancelled: String(localized: "Customer or office cancelled the stop")
            case .failed: String(localized: "Couldn't deliver or collect (closed, no access, no booking…)")
            case .rejected: String(localized: "Goods refused or load rejected")
            }
        }
        var symbol: String {
            switch self {
            case .cancelled: "xmark.octagon.fill"
            case .failed: "exclamationmark.triangle.fill"
            case .rejected: "hand.raised.fill"
            }
        }
    }

    var outcome: Outcome? {
        get { outcomeRaw.flatMap(Outcome.init(rawValue:)) }
        set { outcomeRaw = newValue?.rawValue; outcomeAt = newValue == nil ? nil : .now; if newValue == nil { outcomeReason = nil } }
    }
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
    /// Business / depot name and address details for the start location.
    var startName: String = ""
    var startHouseNumber: String = ""
    var startHouseName: String = ""
    var startFlat: String = ""
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
    /// The job was cancelled (kept for the record, not driven).
    var cancelled: Bool = false
    var cancelledAt: Date?
    var cancelReason: String = ""
    /// Wake-up and leave-home times set by hand for this job (nil = worked out automatically).
    var wakeOverride: Date?
    var leaveOverride: Date?
    /// No wake-up alarm or leave reminder for this job.
    var alarmsOff: Bool = false
    /// Where the job finishes: "same" (back to the start), "different" (the end fields below) or "unknown" (tramping / trunking).
    var endModeRaw: String = "same"
    var endName: String = ""
    var endLocation: String = ""
    var endPostcode: String = ""
    var endLatitude: Double?
    var endLongitude: Double?

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

    enum EndMode: String, CaseIterable, Identifiable {
        case same, different, unknown
        var id: String { rawValue }
        var title: String {
            switch self {
            case .same: String(localized: "Same as start")
            case .different: String(localized: "Somewhere else")
            case .unknown: String(localized: "Not known yet")
            }
        }
    }

    var endMode: EndMode {
        get { EndMode(rawValue: endModeRaw) ?? .same }
        set { endModeRaw = newValue.rawValue }
    }

    /// "Back to start", the end place, or "Unknown".
    var endText: String {
        switch endMode {
        case .same: return "Back to start"
        case .unknown: return "Not known yet"
        case .different:
            let t = [endName, endLocation, endPostcode].filter { !$0.isEmpty }.joined(separator: ", ")
            return t.isEmpty ? "Somewhere else" : t
        }
    }
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
        case .diesel: String(localized: "Diesel")
        case .petrol: String(localized: "Petrol")
        case .adblue: String(localized: "AdBlue")
        case .gas: String(localized: "Gas (LNG/CNG)")
        case .electricity: String(localized: "Electricity")
        case .tachoRoll: String(localized: "Tacho roll")
        case .oil: String(localized: "Oil")
        case .other: String(localized: "Other")
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
        case .time: String(localized: "At a time")
        case .shiftStart: String(localized: "When I start a shift")
        case .shiftEnd: String(localized: "When I end a shift")
        case .arrived: String(localized: "When I tap Arrived")
        case .cardInserted: String(localized: "When I insert my card")
        case .beforeDrivingBreak: String(localized: "Before my driving break is due")
        case .beforeWorkingBreak: String(localized: "Before my working-time break is due")
        case .beforeDailyRest: String(localized: "Before I must start daily rest")
        case .beforeWeeklyRest: String(localized: "Before weekly rest is due")
        case .afterShiftStart: String(localized: "Some time after shift start")
        case .dailyRestComplete: String(localized: "When my daily rest is complete")
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
        case .once: String(localized: "Once")
        case .daily: String(localized: "Every day")
        case .weekdays: String(localized: "Mon–Fri")
        case .weekly: String(localized: "Every week")
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
    case shiftStart, shiftEnd, activity, cardIn, cardOut, arrived, departed, fuel, overspeed, infringement, note, correction, harshBraking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shiftStart: String(localized: "Shift started")
        case .shiftEnd: String(localized: "Shift ended")
        case .activity: String(localized: "Activity")
        case .cardIn: String(localized: "Card inserted")
        case .cardOut: String(localized: "Card withdrawn")
        case .arrived: String(localized: "Arrived")
        case .departed: String(localized: "Departed")
        case .fuel: String(localized: "Fuel / resources")
        case .overspeed: String(localized: "Overspeed")
        case .infringement: String(localized: "Infringement")
        case .note: String(localized: "Note")
        case .correction: String(localized: "Record changed")
        case .harshBraking: String(localized: "Harsh braking")
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
        case .harshBraking: "exclamationmark.brakesignal"
        }
    }

    var isProblem: Bool { self == .overspeed || self == .infringement || self == .harshBraking }
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
        case .loading: String(localized: "Loading")
        case .unloading: String(localized: "Unloading")
        case .vehicleCheck: String(localized: "Vehicle check")
        case .yardCheck: String(localized: "Yard check")
        case .fuelling: String(localized: "Fuelling")
        case .paperwork: String(localized: "Paperwork")
        case .cleaning: String(localized: "Cleaning")
        case .waitingLoad: String(localized: "Waiting to load")
        case .waitingUnload: String(localized: "Waiting to unload")
        case .waitingShift: String(localized: "Waiting for shift")
        case .waitingJob: String(localized: "Waiting for job")
        case .spare: String(localized: "Spare / standby")
        case .ferryTrain: String(localized: "Ferry / train")
        case .doubleManned: String(localized: "Double-manned")
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


enum AddressParts {
    /// "Flat 2, Rose House, 14 High Street, Daventry, NN11 4XX" — leaves out the empty parts and
    /// doesn't repeat a number already at the start of the street line.
    static func join(flat: String?, houseName: String?, houseNumber: String?, street: String, postcode: String?) -> String {
        let f = (flat ?? "").trimmingCharacters(in: .whitespaces)
        let n = (houseNumber ?? "").trimmingCharacters(in: .whitespaces)
        var streetLine = street
        if !n.isEmpty && !street.hasPrefix(n) { streetLine = street.isEmpty ? n : "\(n) \(street)" }
        return [f.isEmpty ? "" : (f.lowercased().hasPrefix("flat") || f.lowercased().hasPrefix("unit") ? f : "Flat \(f)"),
                houseName ?? "", streetLine, postcode ?? ""]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// MARK: Vehicle use

/// One vehicle driven during a shift, with its own odometer readings and GPS distance.
/// A shift can have several (change of vehicle mid-shift).
@Model
final class VehicleUse {
    var id: UUID = UUID()
    var vehicleID: String = ""
    var trailerID: String = ""
    /// "loaded", "empty" or "" for the time this record covers.
    var loadStateRaw: String = ""
    var start: Date = Date()
    var end: Date?
    /// Odometer readings in km (0 = not entered).
    var startOdometerKm: Double = 0
    var endOdometerKm: Double = 0
    /// Distance measured by GPS while this vehicle was in use (in-cab mode), km.
    var gpsKm: Double = 0
    /// True once the driver typed the end reading (otherwise it's worked out from start + GPS).
    var endEdited: Bool = false

    init(vehicleID: String, trailerID: String = "", start: Date, startOdometerKm: Double = 0) {
        self.vehicleID = vehicleID
        self.trailerID = trailerID
        self.start = start
        self.startOdometerKm = startOdometerKm
    }

    /// End reading typed by the driver, or start + GPS distance.
    var effectiveEndKm: Double {
        if endEdited && endOdometerKm > 0 { return endOdometerKm }
        if startOdometerKm > 0 && gpsKm > 0 { return startOdometerKm + gpsKm }
        return endOdometerKm
    }

    /// Distance from the odometer readings when both are there, otherwise GPS.
    var distanceKm: Double {
        let e = effectiveEndKm
        if startOdometerKm > 0 && e > startOdometerKm { return e - startOdometerKm }
        return gpsKm
    }
}

extension Array where Element == PlanStop {
    /// A stop is finished once you've left it or marked it cancelled / failed / rejected.
    static func isFinished(_ s: PlanStop) -> Bool { s.departedAt != nil || s.outcome != nil }

    /// The earlier stop that must be finished before you can arrive at stop `index` (nil = you can arrive).
    /// Move, swap or edit the stops to change the order.
    func arrivalBlocker(for index: Int) -> Int? {
        guard index > 0, index <= count else { return nil }
        return self[..<index].firstIndex { !Self.isFinished($0) }
    }

    /// The stop you're at now (arrived, not left yet).
    var currentStopIndex: Int? { firstIndex { $0.arrivedAt != nil && !Self.isFinished($0) } }
}
