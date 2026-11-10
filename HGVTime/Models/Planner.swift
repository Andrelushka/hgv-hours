import Foundation
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
        if height > 0 { parts.append(String(format: "%.2f m high", height)) }
        if length > 0 { parts.append(String(format: "%.1f m long", length)) }
        if weight > 0 { parts.append(String(format: "%g t", weight)) }
        if kind != .trailer { parts.append(fuel.title) }
        if !body.isEmpty { parts.append(body) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Work planner

/// A stop on a planned job.
struct PlanStop: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case collection, delivery, depot, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .collection: "Collection"
            case .delivery: "Delivery"
            case .depot: "Depot"
            case .other: "Stop"
            }
        }
        var symbol: String {
            switch self {
            case .collection: "arrow.up.bin.fill"
            case .delivery: "arrow.down.to.line.compact"
            case .depot: "building.2.fill"
            case .other: "mappin.circle.fill"
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
    var load: String = ""
    var pallets: String = ""
    var reference: String = ""
    var notes: String = ""
    var stopsData: Data = Data()
    var linesData: Data = Data()
    var createdAt: Date = Date()

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

    func copy(asTemplate: Bool) -> NoteItem {
        let n = NoteItem(title: title, kind: kindRaw, isTemplate: asTemplate)
        n.body = body
        n.tableData = tableData
        return n
    }
}
