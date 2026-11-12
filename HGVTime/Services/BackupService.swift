import Foundation
import SwiftData

/// Saves everything to one file and restores it (e.g. when moving to a new iPhone).
@MainActor
enum BackupService {
    struct Backup: Codable {
        var format = 1
        var createdAt = Date()
        var appVersion = AppInfo.version
        var settings: AppSettings
        var entries: [Entry] = []
        var nights: [Night] = []
        var payItems: [Pay] = []
        var vehicles: [Veh] = []
        var plans: [Plan] = []
        var notes: [Note] = []
        var cards: [Card] = []
        var speeds: [Speed] = []
        var days: [Day] = []
        var resources: [Res] = []
        var reminders: [Rem] = []
        var events: [Event] = []
        var track: [Track] = []
        var uses: [Use]? = []
    }

    struct Use: Codable {
        var vehicleID, trailerID: String; var start: Date; var end: Date?
        var startKm, endKm, gpsKm: Double; var endEdited: Bool
        var load: String?
    }

    struct Entry: Codable { var id: UUID; var kind, regime: String; var start: Date; var end: Date?; var multi: Bool; var note: String; var endsShift: Bool; var plannedRest: String; var subtype: String? }
    struct Night: Codable { var date: Date; var note: String }
    struct Pay: Codable { var date: Date; var kind, title: String; var amount, hours: Double }
    struct Veh: Codable {
        var id: UUID; var kind, registration, fleetNumber, make, model: String
        var height, width, length, weight: Double; var axles: Int; var fuel, body, notes: String; var createdAt: Date; var odometerKm: Double
        var rules: String?; var speedLimit: Double?; var limiter: Double?
    }
    struct Plan: Codable {
        var id: UUID; var start, end: Date; var company, vehicleID, trailerID, startLocation, load, pallets, reference, notes: String
        var stops, lines: Data; var createdAt: Date
        var startPostcode: String?; var startLatitude, startLongitude: Double?; var completed: Bool?
        var startName, startHouseNumber, startHouseName, startFlat: String?
        var cancelled: Bool?; var cancelledAt: Date?; var cancelReason: String?
        var endMode, endName, endLocation, endPostcode: String?; var endLatitude, endLongitude: Double?
        var wakeOverride, leaveOverride: Date?; var alarmsOff: Bool?
    }
    struct Note: Codable { var id: UUID; var title, body, kind: String; var table: Data; var isTemplate, pinned: Bool; var createdAt, updatedAt: Date; var style: Data? }
    struct Card: Codable { var time: Date; var inserted: Bool }
    struct Speed: Codable { var start, end: Date; var maxKmh, limitKmh, latitude, longitude: Double }
    struct Day: Codable { var day: Date; var vehicleID: String; var startKm, endKm, gpsKm: Double; var notes: String }
    struct Res: Codable { var date: Date; var kind: String; var quantity, cost, odometerKm: Double; var location, vehicleID, notes: String }
    struct Rem: Codable {
        var id: UUID; var title, message, trigger: String; var time: Date; var repeatRule: String; var offset: Int
        var enabled, speak: Bool; var createdAt: Date
    }
    struct Event: Codable { var time: Date; var kind, title, detail: String; var lat, lon, speed, duration: Double; var key: String; var activity: String? }
    struct Track: Codable { var time: Date; var lat, lon, speed: Double }

    private static func all<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    /// Writes a backup file and returns its location.
    static func export(context: ModelContext, settings: AppSettings) throws -> URL {
        var b = Backup(settings: settings)
        b.entries = all(ActivityEntry.self, context).map {
            Entry(id: $0.id, kind: $0.kindRaw, regime: $0.regimeRaw, start: $0.start, end: $0.end, multi: $0.multiManned,
                  note: $0.note, endsShift: $0.endsShift, plannedRest: $0.plannedRestRaw, subtype: $0.subtypeRaw)
        }
        b.nights = all(NightOut.self, context).map { Night(date: $0.date, note: $0.note) }
        b.payItems = all(PayItem.self, context).map { Pay(date: $0.date, kind: $0.kindRaw, title: $0.title, amount: $0.amount, hours: $0.hours) }
        b.vehicles = all(Vehicle.self, context).map {
            Veh(id: $0.id, kind: $0.kindRaw, registration: $0.registration, fleetNumber: $0.fleetNumber, make: $0.make, model: $0.model,
                height: $0.height, width: $0.width, length: $0.length, weight: $0.weight, axles: $0.axles, fuel: $0.fuelRaw,
                body: $0.body, notes: $0.notes, createdAt: $0.createdAt, odometerKm: $0.odometerKm,
                rules: $0.rulesRaw, speedLimit: $0.speedLimitKmh, limiter: $0.limiterKmh)
        }
        b.plans = all(WorkPlan.self, context).map {
            Plan(id: $0.id, start: $0.plannedStart, end: $0.plannedEnd, company: $0.company, vehicleID: $0.vehicleID, trailerID: $0.trailerID,
                 startLocation: $0.startLocation, load: $0.load, pallets: $0.pallets, reference: $0.reference, notes: $0.notes,
                 stops: $0.stopsData, lines: $0.linesData, createdAt: $0.createdAt,
                 startPostcode: $0.startPostcode, startLatitude: $0.startLatitude, startLongitude: $0.startLongitude, completed: $0.completed,
                 startName: $0.startName, startHouseNumber: $0.startHouseNumber, startHouseName: $0.startHouseName, startFlat: $0.startFlat,
                 cancelled: $0.cancelled, cancelledAt: $0.cancelledAt, cancelReason: $0.cancelReason,
                 endMode: $0.endModeRaw, endName: $0.endName, endLocation: $0.endLocation, endPostcode: $0.endPostcode,
                 endLatitude: $0.endLatitude, endLongitude: $0.endLongitude,
                 wakeOverride: $0.wakeOverride, leaveOverride: $0.leaveOverride, alarmsOff: $0.alarmsOff)
        }
        b.notes = all(NoteItem.self, context).map {
            Note(id: $0.id, title: $0.title, body: $0.body, kind: $0.kindRaw, table: $0.tableData, isTemplate: $0.isTemplate,
                 pinned: $0.pinned, createdAt: $0.createdAt, updatedAt: $0.updatedAt, style: $0.styleData)
        }
        b.cards = all(CardEvent.self, context).map { Card(time: $0.time, inserted: $0.inserted) }
        b.speeds = all(SpeedEvent.self, context).map {
            Speed(start: $0.start, end: $0.end, maxKmh: $0.maxKmh, limitKmh: $0.limitKmh, latitude: $0.latitude, longitude: $0.longitude)
        }
        b.days = all(DayRecord.self, context).map {
            Day(day: $0.day, vehicleID: $0.vehicleID, startKm: $0.startOdometerKm, endKm: $0.endOdometerKm, gpsKm: $0.gpsKm, notes: $0.notes)
        }
        b.resources = all(ResourceLog.self, context).map {
            Res(date: $0.date, kind: $0.kindRaw, quantity: $0.quantity, cost: $0.cost, odometerKm: $0.odometerKm,
                location: $0.location, vehicleID: $0.vehicleID, notes: $0.notes)
        }
        b.reminders = all(Reminder.self, context).map {
            Rem(id: $0.id, title: $0.title, message: $0.message, trigger: $0.triggerRaw, time: $0.time, repeatRule: $0.repeatRaw,
                offset: $0.offsetMinutes, enabled: $0.enabled, speak: $0.speak, createdAt: $0.createdAt)
        }
        b.events = all(EventLog.self, context).map {
            Event(time: $0.time, kind: $0.kindRaw, title: $0.title, detail: $0.detail, lat: $0.latitude, lon: $0.longitude,
                  speed: $0.speedKmh, duration: $0.duration, key: $0.key, activity: $0.activityRaw)
        }
        b.uses = all(VehicleUse.self, context).map {
            Use(vehicleID: $0.vehicleID, trailerID: $0.trailerID, start: $0.start, end: $0.end,
                startKm: $0.startOdometerKm, endKm: $0.endOdometerKm, gpsKm: $0.gpsKm, endEdited: $0.endEdited, load: $0.loadStateRaw)
        }
        b.track = all(TrackPoint.self, context).map { Track(time: $0.time, lat: $0.latitude, lon: $0.longitude, speed: $0.speedKmh) }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(b)
        let name = "HGV-Hours-backup-\(Fmt.isoDate(.now)).hgvbackup"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// What a backup file contains, for the confirmation message.
    static func read(_ url: URL) throws -> Backup {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Backup.self, from: Data(contentsOf: url))
    }

    /// Replaces everything on this phone with the backup. The app lock setting on this phone is kept.
    static func restore(_ b: Backup, context: ModelContext, store: SettingsStore) throws {
        try context.delete(model: ActivityEntry.self)
        try context.delete(model: NightOut.self)
        try context.delete(model: PayItem.self)
        try context.delete(model: Vehicle.self)
        try context.delete(model: WorkPlan.self)
        try context.delete(model: NoteItem.self)
        try context.delete(model: CardEvent.self)
        try context.delete(model: SpeedEvent.self)
        try context.delete(model: DayRecord.self)
        try context.delete(model: ResourceLog.self)
        try context.delete(model: Reminder.self)
        try context.delete(model: EventLog.self)
        try context.delete(model: TrackPoint.self)
        try context.delete(model: VehicleUse.self)

        for e in b.entries {
            let x = ActivityEntry(kind: DutyKind(rawValue: e.kind) ?? .rest, regime: Regime(rawValue: e.regime) ?? .assimilated,
                                  start: e.start, end: e.end, multiManned: e.multi, note: e.note, endsShift: e.endsShift)
            x.id = e.id
            x.plannedRestRaw = e.plannedRest
            x.subtypeRaw = e.subtype ?? ""
            context.insert(x)
        }
        b.nights.forEach { context.insert(NightOut(date: $0.date, note: $0.note)) }
        b.payItems.forEach { context.insert(PayItem(date: $0.date, kind: PayItemKind(rawValue: $0.kind) ?? .bonus, title: $0.title, amount: $0.amount, hours: $0.hours)) }
        for v in b.vehicles {
            let x = Vehicle(kind: VehicleKind(rawValue: v.kind) ?? .tractor)
            x.id = v.id; x.registration = v.registration; x.fleetNumber = v.fleetNumber; x.make = v.make; x.model = v.model
            x.height = v.height; x.width = v.width; x.length = v.length; x.weight = v.weight; x.axles = v.axles
            x.fuelRaw = v.fuel; x.body = v.body; x.notes = v.notes; x.createdAt = v.createdAt; x.odometerKm = v.odometerKm
            x.rulesRaw = v.rules ?? ""; x.speedLimitKmh = v.speedLimit ?? 0; x.limiterKmh = v.limiter ?? 0
            context.insert(x)
        }
        for p in b.plans {
            let x = WorkPlan(start: p.start, end: p.end)
            x.id = p.id; x.company = p.company; x.vehicleID = p.vehicleID; x.trailerID = p.trailerID; x.startLocation = p.startLocation
            x.load = p.load; x.pallets = p.pallets; x.reference = p.reference; x.notes = p.notes
            x.stopsData = p.stops; x.linesData = p.lines; x.createdAt = p.createdAt
            x.startPostcode = p.startPostcode ?? ""; x.startLatitude = p.startLatitude; x.startLongitude = p.startLongitude
            x.completed = p.completed ?? false
            x.startName = p.startName ?? ""; x.startHouseNumber = p.startHouseNumber ?? ""
            x.startHouseName = p.startHouseName ?? ""; x.startFlat = p.startFlat ?? ""
            x.cancelled = p.cancelled ?? false; x.cancelledAt = p.cancelledAt; x.cancelReason = p.cancelReason ?? ""
            x.endModeRaw = p.endMode ?? "same"; x.endName = p.endName ?? ""; x.endLocation = p.endLocation ?? ""
            x.endPostcode = p.endPostcode ?? ""; x.endLatitude = p.endLatitude; x.endLongitude = p.endLongitude
            x.wakeOverride = p.wakeOverride; x.leaveOverride = p.leaveOverride; x.alarmsOff = p.alarmsOff ?? false
            context.insert(x)
        }
        for n in b.notes {
            let x = NoteItem(title: n.title, kind: n.kind, isTemplate: n.isTemplate)
            x.id = n.id; x.body = n.body; x.tableData = n.table; x.pinned = n.pinned; x.createdAt = n.createdAt; x.updatedAt = n.updatedAt
            x.styleData = n.style ?? Data()
            context.insert(x)
        }
        b.cards.forEach { context.insert(CardEvent(time: $0.time, inserted: $0.inserted)) }
        b.speeds.forEach { context.insert(SpeedEvent(start: $0.start, end: $0.end, maxKmh: $0.maxKmh, limitKmh: $0.limitKmh, latitude: $0.latitude, longitude: $0.longitude)) }
        for d in b.days {
            let x = DayRecord(day: d.day)
            x.vehicleID = d.vehicleID; x.startOdometerKm = d.startKm; x.endOdometerKm = d.endKm; x.gpsKm = d.gpsKm; x.notes = d.notes
            context.insert(x)
        }
        for r in b.resources {
            let x = ResourceLog(date: r.date, kind: ResourceKind(rawValue: r.kind) ?? .other)
            x.quantity = r.quantity; x.cost = r.cost; x.odometerKm = r.odometerKm; x.location = r.location; x.vehicleID = r.vehicleID; x.notes = r.notes
            context.insert(x)
        }
        for r in b.reminders {
            let x = Reminder(title: r.title, message: r.message, trigger: ReminderTrigger(rawValue: r.trigger) ?? .time, offsetMinutes: r.offset)
            x.id = r.id; x.time = r.time; x.repeatRaw = r.repeatRule; x.enabled = r.enabled; x.speak = r.speak; x.createdAt = r.createdAt
            context.insert(x)
        }
        for e in b.events {
            let x = EventLog(time: e.time, kind: EventKind(rawValue: e.kind) ?? .note, title: e.title, detail: e.detail)
            x.latitude = e.lat; x.longitude = e.lon; x.speedKmh = e.speed; x.duration = e.duration; x.key = e.key
            x.activityRaw = e.activity ?? ""
            context.insert(x)
        }
        for u in b.uses ?? [] {
            let x = VehicleUse(vehicleID: u.vehicleID, trailerID: u.trailerID, start: u.start, startOdometerKm: u.startKm)
            x.end = u.end; x.endOdometerKm = u.endKm; x.gpsKm = u.gpsKm; x.endEdited = u.endEdited; x.loadStateRaw = u.load ?? ""
            context.insert(x)
        }
        b.track.forEach { context.insert(TrackPoint(time: $0.time, latitude: $0.lat, longitude: $0.lon, speedKmh: $0.speed)) }
        try context.save()

        var settings = b.settings
        settings.lockEnabled = store.settings.lockEnabled
        settings.lockAfterMinutes = store.settings.lockAfterMinutes
        settings.hasAcceptedDisclaimer = true
        store.settings = settings
        store.save()
        ActivityController.refreshSideEffects(context: context, settings: settings)
    }
}
