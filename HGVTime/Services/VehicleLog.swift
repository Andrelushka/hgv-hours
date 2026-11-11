import Foundation
import SwiftData

/// Which vehicle is in use, when it changed, and the mileage of each vehicle in a shift.
@MainActor
enum VehicleLog {
    static func openUse(context: ModelContext) -> VehicleUse? {
        let d = FetchDescriptor<VehicleUse>(predicate: #Predicate { $0.end == nil }, sortBy: [SortDescriptor(\.start)])
        return (try? context.fetch(d))?.last
    }

    static func vehicle(_ id: String, context: ModelContext) -> Vehicle? {
        guard !id.isEmpty else { return nil }
        return ((try? context.fetch(FetchDescriptor<Vehicle>())) ?? []).first { $0.id.uuidString == id }
    }

    /// Vehicles used on a day (any use that overlaps it).
    static func uses(on day: Date, context: ModelContext) -> [VehicleUse] {
        let start = Calendar.hgv.startOfDay(for: day)
        let end = start.addingTimeInterval(86_400)
        let all = (try? context.fetch(FetchDescriptor<VehicleUse>(sortBy: [SortDescriptor(\.start)]))) ?? []
        return all.filter { $0.start < end && ($0.end ?? .now) > start }
    }

    /// Whether anything was recorded on a day (so the mileage card stays after the shift ends, until midnight).
    static func hasMileage(on day: Date, context: ModelContext) -> Bool {
        if !uses(on: day, context: context).isEmpty { return true }
        let start = Calendar.hgv.startOfDay(for: day)
        let end = start.addingTimeInterval(86_400)
        let records = (try? context.fetch(FetchDescriptor<DayRecord>(predicate: #Predicate { $0.day >= start && $0.day < end }))) ?? []
        return records.contains { $0.startOdometerKm > 0 || $0.endOdometerKm > 0 || $0.gpsKm > 0 }
    }

    /// Chooses the vehicle you're driving. On a shift this closes the previous vehicle's use (end mileage
    /// worked out from GPS, adjustable later) and starts a new one. The vehicle's own rules (tacho, GB domestic
    /// or exempt) become the rules for new activities.
    static func select(_ vehicleID: String, context: ModelContext, store: SettingsStore, at time: Date = .now) {
        let onShift = ActivityController.isOnShift(context: context)
        if onShift {
            if let open = openUse(context: context) {
                if open.vehicleID == vehicleID { applyRules(vehicleID, context: context, store: store); return }
                close(open, at: time, context: context)
            }
            if !vehicleID.isEmpty { open(vehicleID, trailerID: store.settings.currentTrailerID, at: time, context: context) }
        }
        let previous = store.settings.currentVehicleID
        store.settings.currentVehicleID = vehicleID
        applyRules(vehicleID, context: context, store: store)
        if onShift && previous != vehicleID && !vehicleID.isEmpty {
            let name = vehicle(vehicleID, context: context)?.displayName ?? "vehicle"
            EventRecorder.log(.note, title: "Vehicle changed", detail: name, context: context, settings: store.settings)
        }
        try? context.save()
    }

    /// Changes the trailer. On a shift the current use is split so each part of the day
    /// records which trailer was on (mileage carries over to the new part).
    static func selectTrailer(_ trailerID: String, context: ModelContext, store: SettingsStore, at time: Date = .now) {
        let previous = store.settings.currentTrailerID
        guard previous != trailerID else { return }
        store.settings.currentTrailerID = trailerID
        if ActivityController.isOnShift(context: context) {
            if let open = openUse(context: context) {
                let vehicleID = open.vehicleID
                close(open, at: time, context: context)
                let next = self.open(vehicleID, trailerID: trailerID, at: time, context: context)
                if open.endOdometerKm > 0 { next.startOdometerKm = open.endOdometerKm }
            }
            let name = vehicle(trailerID, context: context)?.displayName
            EventRecorder.log(.note, title: trailerID.isEmpty ? "Trailer dropped" : "Trailer changed",
                              detail: name ?? "", context: context, settings: store.settings)
        }
        try? context.save()
    }

    /// The selected vehicle's rules, or your usual rules.
    static func applyRules(_ vehicleID: String, context: ModelContext, store: SettingsStore) {
        let rules = vehicle(vehicleID, context: context)?.rules ?? store.settings.primaryRegime
        if store.settings.currentRegime != rules { store.settings.currentRegime = rules }
    }

    @discardableResult
    static func open(_ vehicleID: String, trailerID: String, at time: Date, context: ModelContext) -> VehicleUse {
        let v = vehicle(vehicleID, context: context)
        let use = VehicleUse(vehicleID: vehicleID, trailerID: trailerID, start: time, startOdometerKm: v?.odometerKm ?? 0)
        context.insert(use)
        try? context.save()
        return use
    }

    static func close(_ use: VehicleUse, at time: Date, context: ModelContext) {
        use.end = max(use.start, time)
        if !use.endEdited, use.effectiveEndKm > 0 { use.endOdometerKm = use.effectiveEndKm }
        if let v = vehicle(use.vehicleID, context: context), use.endOdometerKm > v.odometerKm { v.odometerKm = use.endOdometerKm }
        try? context.save()
    }

    /// Shift started: start recording the vehicle in use.
    static func shiftStarted(settings: AppSettings, context: ModelContext, at time: Date = .now) {
        guard openUse(context: context) == nil, !settings.currentVehicleID.isEmpty else { return }
        open(settings.currentVehicleID, trailerID: settings.currentTrailerID, at: time, context: context)
    }

    /// Shift ended: close the vehicle's use.
    static func shiftEnded(context: ModelContext, at time: Date = .now) {
        if let open = openUse(context: context) { close(open, at: time, context: context) }
    }

    static func addGPS(_ km: Double, context: ModelContext) {
        guard km > 0, let open = openUse(context: context) else { return }
        open.gpsKm += km
    }

    /// Typed odometer reading for a use.
    static func setReading(_ use: VehicleUse, start: Bool, km: Double, context: ModelContext) {
        if start { use.startOdometerKm = km } else { use.endOdometerKm = km; use.endEdited = km > 0 }
        if let v = vehicle(use.vehicleID, context: context), km > v.odometerKm { v.odometerKm = km }
        try? context.save()
    }

    /// Total distance on a day: vehicle uses when recorded, otherwise the day record.
    static func distance(on day: Date, context: ModelContext) -> Double {
        let u = uses(on: day, context: context)
        if !u.isEmpty { return u.reduce(0) { $0 + $1.distanceKm } }
        return ActivityController.dayRecord(for: day, context: context).distanceKm
    }
}

/// Overspeed thresholds by vehicle and country.
enum SpeedLimits {
    /// km/h above which in-cab mode records overspeed.
    static func limitKmh(vehicle: Vehicle?, region: RuleRegion, manual: Double, automatic: Bool) -> Double {
        if let v = vehicle, v.speedLimitKmh > 0 { return v.speedLimitKmh }
        guard automatic else { return manual }
        return defaultKmh(kind: vehicle?.kind ?? .tractor, weightT: vehicle?.weight ?? 0, region: region)
    }

    /// Typical maximum for the vehicle type: the speed limiter for lorries over 3.5 t, the road limit for vans.
    static func defaultKmh(kind: VehicleKind, weightT: Double, region: RuleRegion) -> Double {
        let isLight = kind == .van && (weightT == 0 || weightT <= 3.5)
        switch region {
        case .uk: return isLight ? 113 : 90          // 70 mph motorway for vans; 56 mph limiter for HGVs
        case .eu, .aetr: return isLight ? 130 : 90   // EU limiter 90 km/h over 3.5 t
        case .usa: return isLight ? 113 : 105        // 65–70 mph typical truck limits
        case .canada: return isLight ? 110 : 105     // 105 km/h limiter (Ontario/Quebec)
        case .australia: return isLight ? 110 : 100  // 100 km/h limiter over 12 t
        case .newZealand: return isLight ? 100 : 90  // 90 km/h heavy vehicles
        }
    }

    static func describe(_ kmh: Double) -> String {
        "\(Int(kmh.rounded())) km/h (\(Int((kmh / 1.609344).rounded())) mph)"
    }
}
