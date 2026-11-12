import Foundation
import SwiftData
import SwiftUI

/// Where you are on the walk round: lines are shown in the order you meet them walking round the vehicle.
enum CheckArea: String, CaseIterable, Identifiable {
    case cab, front, fluids, nearside, coupling, rear, offside, equipment
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cab: String(localized: "In the cab")
        case .front: String(localized: "Front")
        case .fluids: String(localized: "Engine & fluids")
        case .nearside: String(localized: "Nearside (passenger side)")
        case .coupling: String(localized: "Coupling & lines")
        case .rear: String(localized: "Rear")
        case .offside: String(localized: "Offside (driver's side)")
        case .equipment: String(localized: "Equipment & load")
        }
    }

    var symbol: String {
        switch self {
        case .cab: "steeringwheel"
        case .front: "headlight.high.beam.fill"
        case .fluids: "drop.fill"
        case .nearside: "arrow.turn.down.left"
        case .coupling: "link"
        case .rear: "light.beacon.max.fill"
        case .offside: "arrow.turn.down.right"
        case .equipment: "shippingbox.fill"
        }
    }

    var color: Color {
        switch self {
        case .cab: .indigo
        case .front: .blue
        case .fluids: .teal
        case .nearside: .green
        case .coupling: .orange
        case .rear: .red
        case .offside: .mint
        case .equipment: .brown
        }
    }
}

/// One line of the walk-round (pre-use) check.
struct CheckItem: Identifiable, Hashable {
    enum Applies { case vehicle, trailer, both }
    enum Answer { case tick, yesNo }
    var id: String
    var area: CheckArea
    /// Where it's checked on a trailer, if different.
    var trailerArea: CheckArea? = nil
    var title: String
    var applies: Applies
    var answer: Answer = .tick

    func applies(toTrailer trailer: Bool) -> Bool {
        switch applies {
        case .both: true
        case .vehicle: !trailer
        case .trailer: trailer
        }
    }

    func area(trailer: Bool) -> CheckArea { trailer ? (trailerArea ?? area) : area }

    /// The lines for a vehicle or a trailer column, in walk-round order.
    static func walkRound(trailer: Bool) -> [(area: CheckArea, items: [CheckItem])] {
        let lines = all.filter { $0.applies(toTrailer: trailer) }
        // Round a trailer you start at the coupling (front of the trailer), then down the side to the rear.
        let order: [CheckArea] = trailer ? [.coupling, .cab, .front, .fluids, .nearside, .rear, .offside, .equipment] : CheckArea.allCases
        return order.compactMap { a in
            let items = lines.filter { $0.area(trailer: trailer) == a }
            return items.isEmpty ? nil : (a, items)
        }
    }

    /// Heavy-vehicle daily walk-round, like a typical UK operator pre-use check sheet,
    /// in the order you meet things: cab, front, under the cab, nearside, coupling, rear, offside, equipment.
    static let all: [CheckItem] = [
        // In the cab
        .init(id: "safetyFeatures", area: .cab, trailerArea: .coupling, title: String(localized: "I understand how this vehicle's safety features work (e.g. park brake warning)"), applies: .both, answer: .yesNo),
        .init(id: "controls", area: .cab, title: String(localized: "Driving controls — condition, wear and operation"), applies: .vehicle),
        .init(id: "belts", area: .cab, title: String(localized: "Seat belts undamaged and working (belts must be worn)"), applies: .vehicle),
        .init(id: "brakes", area: .cab, title: String(localized: "Brakes, reverse alarm and warning lights work correctly"), applies: .vehicle),
        .init(id: "abs", area: .cab, trailerArea: .coupling, title: String(localized: "ABS warning sequence correct"), applies: .both),
        .init(id: "air", area: .cab, trailerArea: .coupling, title: String(localized: "Air pressure correct, working, no leaks"), applies: .both),
        .init(id: "brakeOffWarning", area: .cab, title: String(localized: "Brake-off / door-open warning fitted and working"), applies: .vehicle),
        .init(id: "mirrors", area: .cab, title: String(localized: "Mirrors secure, undamaged and aligned"), applies: .vehicle),
        .init(id: "windscreenArea", area: .cab, title: String(localized: "Windscreen area free from obstructions (sat-nav, phone…)"), applies: .vehicle, answer: .yesNo),
        .init(id: "tacho", area: .cab, title: String(localized: "Tachograph works, spare print rolls available"), applies: .vehicle),
        .init(id: "camera", area: .cab, title: String(localized: "Forward-facing camera powers up and is secure"), applies: .vehicle),
        .init(id: "heightIndicator", area: .cab, trailerArea: .rear, title: String(localized: "Height indicator set to the correct height"), applies: .both),
        .init(id: "loose", area: .cab, title: String(localized: "Loose items stowed securely in the cab"), applies: .vehicle),
        .init(id: "bumpCards", area: .cab, title: String(localized: "Accident / bump cards in the cab"), applies: .vehicle, answer: .yesNo),
        .init(id: "licenceDisc", area: .cab, title: String(localized: "Operator licence disc displayed and in date"), applies: .vehicle),
        .init(id: "signs", area: .cab, trailerArea: .rear, title: String(localized: "Signs and documents displayed (plating, FORS, cameras, blind spot, height, no smoking)"), applies: .both),
        // Front
        .init(id: "windscreen", area: .front, title: String(localized: "Windscreen undamaged, wipers and washers working"), applies: .vehicle),
        .init(id: "lights", area: .front, trailerArea: .rear, title: String(localized: "Lights, indicators and brake lights working, clean"), applies: .both),
        .init(id: "plates", area: .front, trailerArea: .rear, title: String(localized: "Number plates secure and legible"), applies: .both),
        .init(id: "reflectors", area: .front, trailerArea: .nearside, title: String(localized: "Reflectors and markings clean and visible"), applies: .both),
        .init(id: "proximity", area: .front, title: String(localized: "Side / front proximity sensors working"), applies: .vehicle),
        // Engine & fluids
        .init(id: "fluids", area: .fluids, title: String(localized: "Fluid levels — oil, coolant, fuel, screenwash, AdBlue"), applies: .vehicle),
        .init(id: "equipLeaks", area: .fluids, trailerArea: .equipment, title: String(localized: "Free from leaks — air, fluid, gas"), applies: .both),
        // Nearside
        .init(id: "tyres", area: .nearside, title: String(localized: "Tyres — inflation, tread, cuts and bulges"), applies: .both),
        .init(id: "wheels", area: .nearside, title: String(localized: "Wheels and nuts secure, nut indicators in place"), applies: .both),
        .init(id: "spray", area: .nearside, title: String(localized: "Spray suppression — wings and flaps fitted"), applies: .both),
        .init(id: "tanks", area: .nearside, title: String(localized: "Fuel and AdBlue tanks secure, caps on, no leaks"), applies: .vehicle),
        .init(id: "exhaust", area: .nearside, title: String(localized: "Exhaust — condition and excessive smoke"), applies: .vehicle),
        .init(id: "suspension", area: .nearside, title: String(localized: "Suspension works, set to normal ride height"), applies: .both),
        .init(id: "body", area: .nearside, title: String(localized: "Bodywork, steps, curtains, doors, locks, side guards secure"), applies: .both),
        // Coupling
        .init(id: "coupling", area: .coupling, title: String(localized: "Coupling secure, locking devices engaged — tug test done"), applies: .both, answer: .yesNo),
        .init(id: "lines", area: .coupling, title: String(localized: "Air, electrical and ABS lines secure and undamaged"), applies: .both),
        .init(id: "legs", area: .coupling, title: String(localized: "Landing legs undamaged, handle stowed"), applies: .trailer),
        .init(id: "trailerMOT", area: .coupling, title: String(localized: "Trailer MOT disc / plating certificate in date"), applies: .trailer),
        // Rear
        .init(id: "rearProximity", area: .rear, title: String(localized: "Rear proximity sensors working"), applies: .trailer),
        .init(id: "load", area: .rear, title: String(localized: "Load secured"), applies: .both),
        // Equipment
        .init(id: "equipOperates", area: .equipment, title: String(localized: "Tail lift, crane or moving floor operates correctly"), applies: .both),
        .init(id: "equipWarnings", area: .equipment, title: String(localized: "Equipment warning lights and devices work, signs in place"), applies: .both),
        .init(id: "equipSafety", area: .equipment, title: String(localized: "Safety devices, locks and stands in place and working"), applies: .both),
        .init(id: "equipPower", area: .equipment, title: String(localized: "Power supplies, leads and sockets in good condition"), applies: .both),
    ]
}

/// A completed (or in-progress) vehicle check: a column for the vehicle and each trailer.
@Model
final class VehicleCheck {
    var id: UUID = UUID()
    var date: Date = Date()
    var driverName: String = ""
    /// Column names: the vehicle registration, then trailer numbers.
    var columnsData: Data = Data()
    /// Which columns are trailers.
    var trailerColumnsData: Data = Data()
    /// Answers: "itemID|column" → "ok", "defect", "na", "yes", "no".
    var answersData: Data = Data()
    /// Defect notes: itemID|column → note.
    var defectsData: Data = Data()
    /// Height when leaving site, metres, per column.
    var heightsData: Data = Data()
    var defectBookRef: String = ""
    var notes: String = ""
    var signed: Bool = false
    var signedAt: Date?

    init(date: Date = .now, driverName: String = "") {
        self.date = date
        self.driverName = driverName
    }

    private static func get<T: Decodable>(_ d: Data, _ fallback: T) -> T { (try? JSONDecoder().decode(T.self, from: d)) ?? fallback }
    private static func put<T: Encodable>(_ v: T) -> Data { (try? JSONEncoder().encode(v)) ?? Data() }

    var columns: [String] { get { Self.get(columnsData, []) } set { columnsData = Self.put(newValue) } }
    var trailerColumns: [Bool] { get { Self.get(trailerColumnsData, []) } set { trailerColumnsData = Self.put(newValue) } }
    var answers: [String: String] { get { Self.get(answersData, [:]) } set { answersData = Self.put(newValue) } }
    var defects: [String: String] { get { Self.get(defectsData, [:]) } set { defectsData = Self.put(newValue) } }
    var heights: [Double] { get { Self.get(heightsData, []) } set { heightsData = Self.put(newValue) } }

    static func key(_ item: String, _ column: Int) -> String { "\(item)|\(column)" }

    /// Lines with an ✗ (or a "No" on a yes/no line).
    var defectCount: Int { answers.values.filter { $0 == "defect" || $0 == "no" }.count }

    /// Applicable cells still blank.
    var openCount: Int {
        var n = 0
        for (c, trailer) in trailerColumns.enumerated() {
            for item in CheckItem.all where item.applies(toTrailer: trailer) && answers[Self.key(item.id, c)] == nil { n += 1 }
        }
        return n
    }
}

extension VehicleCheck {
    /// Today's check, or a new one with your current vehicle and trailer as columns.
    @MainActor
    static func today(in context: ModelContext, settings: AppSettings) -> VehicleCheck {
        let start = Calendar.hgv.startOfDay(for: .now)
        var fd = FetchDescriptor<VehicleCheck>(predicate: #Predicate { $0.date >= start }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = 1
        if let existing = try? context.fetch(fd).first { return existing }
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        let c = VehicleCheck(driverName: settings.driverName)
        let unit = vehicles.first { $0.id.uuidString == settings.currentVehicleID }
        c.columns = [unit.map(Self.columnName) ?? String(localized: "Vehicle")]
        c.trailerColumns = [false]
        c.heights = [unit?.height ?? 0]
        if let trailer = vehicles.first(where: { $0.id.uuidString == settings.currentTrailerID }) {
            c.addColumn(Self.columnName(trailer), trailer: true, height: trailer.height)
        }
        context.insert(c)
        try? context.save()
        return c
    }

    static func columnName(_ v: Vehicle) -> String {
        v.registration.isEmpty ? (v.fleetNumber.isEmpty ? v.displayName : v.fleetNumber) : v.registration
    }

    /// Adds a column (up to 7) unless one with that name is already there; returns its index.
    @discardableResult
    func addColumn(_ name: String, trailer: Bool, height: Double) -> Int? {
        if let i = columns.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return i }
        guard columns.count < 7 else { return nil }
        var h = heights
        while h.count < columns.count { h.append(0) }
        h.append(height)
        columns += [name]
        trailerColumns += [trailer]
        heights = h
        return columns.count - 1
    }

    /// Lines in one column still blank.
    func openCount(column c: Int) -> Int {
        guard c < columns.count else { return 0 }
        let trailer = c < trailerColumns.count && trailerColumns[c]
        return CheckItem.all.filter { $0.applies(toTrailer: trailer) && answers[Self.key($0.id, c)] == nil }.count
    }

    /// Share of lines answered (0…1).
    var progress: Double {
        var total = 0
        for trailer in trailerColumns { total += CheckItem.all.filter { $0.applies(toTrailer: trailer) }.count }
        return total == 0 ? 0 : Double(total - openCount) / Double(total)
    }

    /// Done for the shift checks: signed with every line answered.
    var isComplete: Bool { signed }
}

extension AppSettings {
    /// You chose "Not needed today" for the vehicle check.
    var vehicleCheckSkippedToday: Bool {
        vehicleCheckSkippedOn > 0 && Calendar.hgv.isDateInToday(Date(timeIntervalSince1970: vehicleCheckSkippedOn))
    }

    mutating func skipVehicleCheckToday(_ skip: Bool) {
        vehicleCheckSkippedOn = skip ? Calendar.hgv.startOfDay(for: .now).timeIntervalSince1970 : 0
    }
}
