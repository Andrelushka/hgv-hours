import Foundation
import SwiftData

/// One line of the walk-round (pre-use) check.
struct CheckItem: Identifiable, Hashable {
    enum Applies { case vehicle, trailer, both }
    enum Answer { case tick, yesNo }
    var id: String
    var section: String
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

    /// Heavy-vehicle daily walk-round, like a typical UK operator pre-use check sheet.
    static let all: [CheckItem] = {
        let general = String(localized: "General items")
        let extra = String(localized: "Ancillary / specialist equipment")
        return [
            .init(id: "safetyFeatures", section: general, title: String(localized: "I understand how this vehicle's safety features work (e.g. park brake warning)"), applies: .both, answer: .yesNo),
            .init(id: "controls", section: general, title: String(localized: "Driving controls — condition, wear and operation"), applies: .vehicle),
            .init(id: "brakeOffWarning", section: general, title: String(localized: "Brake-off / door-open warning fitted and working"), applies: .vehicle),
            .init(id: "brakes", section: general, title: String(localized: "Brakes, reverse alarm and warning lights work correctly"), applies: .vehicle),
            .init(id: "belts", section: general, title: String(localized: "Seat belts undamaged and working (belts must be worn)"), applies: .vehicle),
            .init(id: "signs", section: general, title: String(localized: "Signs and documents displayed (plating, FORS, cameras, blind spot, height, no smoking)"), applies: .both),
            .init(id: "loose", section: general, title: String(localized: "Loose items stowed securely in the cab"), applies: .vehicle),
            .init(id: "tacho", section: general, title: String(localized: "Tachograph works, spare print rolls available"), applies: .vehicle),
            .init(id: "licenceDisc", section: general, title: String(localized: "Operator licence disc displayed and in date"), applies: .vehicle),
            .init(id: "exhaust", section: general, title: String(localized: "Exhaust — condition and excessive smoke"), applies: .vehicle),
            .init(id: "suspension", section: general, title: String(localized: "Suspension works, set to normal ride height"), applies: .both),
            .init(id: "heightIndicator", section: general, title: String(localized: "Height indicator set to the correct height"), applies: .both),
            .init(id: "bumpCards", section: general, title: String(localized: "Accident / bump cards in the cab"), applies: .vehicle, answer: .yesNo),
            .init(id: "camera", section: general, title: String(localized: "Forward-facing camera powers up and is secure"), applies: .vehicle),
            .init(id: "mirrors", section: general, title: String(localized: "Mirrors secure, undamaged and aligned"), applies: .vehicle),
            .init(id: "abs", section: general, title: String(localized: "ABS warning sequence correct"), applies: .both),
            .init(id: "air", section: general, title: String(localized: "Air pressure correct, working, no leaks"), applies: .both),
            .init(id: "lines", section: general, title: String(localized: "Air, electrical and ABS lines secure and undamaged"), applies: .both),
            .init(id: "coupling", section: general, title: String(localized: "Coupling secure, locking devices engaged — tug test done"), applies: .both, answer: .yesNo),
            .init(id: "proximity", section: general, title: String(localized: "Side / front proximity sensors working"), applies: .vehicle),
            .init(id: "rearProximity", section: general, title: String(localized: "Rear proximity sensors working"), applies: .trailer),
            .init(id: "tanks", section: general, title: String(localized: "Fuel and AdBlue tanks secure, caps on, no leaks"), applies: .vehicle),
            .init(id: "legs", section: general, title: String(localized: "Landing legs undamaged, handle stowed"), applies: .trailer),
            .init(id: "lights", section: general, title: String(localized: "Lights, indicators and brake lights working, clean"), applies: .both),
            .init(id: "reflectors", section: general, title: String(localized: "Reflectors and markings clean and visible"), applies: .both),
            .init(id: "plates", section: general, title: String(localized: "Number plates secure and legible"), applies: .both),
            .init(id: "trailerMOT", section: general, title: String(localized: "Trailer MOT disc / plating certificate in date"), applies: .trailer),
            .init(id: "tyres", section: general, title: String(localized: "Tyres — inflation, tread, cuts and bulges"), applies: .both),
            .init(id: "wheels", section: general, title: String(localized: "Wheels and nuts secure, nut indicators in place"), applies: .both),
            .init(id: "spray", section: general, title: String(localized: "Spray suppression — wings and flaps fitted"), applies: .both),
            .init(id: "body", section: general, title: String(localized: "Bodywork, steps, curtains, doors, locks, side guards secure"), applies: .both),
            .init(id: "load", section: general, title: String(localized: "Load secured"), applies: .both),
            .init(id: "windscreenArea", section: general, title: String(localized: "Windscreen area free from obstructions (sat-nav, phone…)"), applies: .vehicle, answer: .yesNo),
            .init(id: "windscreen", section: general, title: String(localized: "Windscreen undamaged, wipers and washers working"), applies: .vehicle),
            .init(id: "fluids", section: general, title: String(localized: "Fluid levels — oil, coolant, fuel, screenwash, AdBlue"), applies: .vehicle),
            .init(id: "equipOperates", section: extra, title: String(localized: "Tail lift, crane or moving floor operates correctly"), applies: .both),
            .init(id: "equipWarnings", section: extra, title: String(localized: "Equipment warning lights and devices work, signs in place"), applies: .both),
            .init(id: "equipSafety", section: extra, title: String(localized: "Safety devices, locks and stands in place and working"), applies: .both),
            .init(id: "equipLeaks", section: extra, title: String(localized: "Free from leaks — air, fluid, gas"), applies: .both),
            .init(id: "equipPower", section: extra, title: String(localized: "Power supplies, leads and sockets in good condition"), applies: .both),
        ]
    }()
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
