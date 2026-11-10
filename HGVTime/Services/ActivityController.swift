import Foundation
import SwiftData
import WidgetKit

/// Records activity changes and keeps notifications, the Live Activity and the Watch in step.
@MainActor
enum ActivityController {

    /// Ends the current activity and starts `kind` now.
    static func switchTo(_ kind: DutyKind, endShift: Bool = false, restType: RestType = .daily,
                         context: ModelContext, settings: AppSettings, at time: Date = .now) {
        let now = time
        let open = openEntries(context: context)
        let planned = endShift ? restType.rawValue : ""
        if let current = open.last, current.kind == kind, current.endsShift == endShift, open.count == 1 {
            // Same activity: only update the planned rest type if it changed.
            if endShift && current.plannedRestRaw != planned {
                current.plannedRestRaw = planned
                try? context.save()
                refreshSideEffects(context: context, settings: settings)
            }
            return
        }
        for entry in open {
            entry.end = max(entry.start, now)
        }
        let entry = ActivityEntry(kind: kind,
                                  regime: settings.currentRegime,
                                  start: now,
                                  multiManned: settings.multiManned,
                                  endsShift: kind == .rest && endShift)
        entry.plannedRestRaw = kind == .rest && endShift ? planned : ""
        context.insert(entry)
        try? context.save()
        refreshSideEffects(context: context, settings: settings)
        VoiceService.shared.activityChanged(to: entry.displayTitle + (entry.endsShift ? " started. Shift ended." : ""))
        if !entry.endsShift {
            EventRecorder.log(.activity, title: entry.displayTitle, at: now, activity: entry.kindRaw, context: context, settings: settings)
        }
    }

    /// Starts a shift with the activity chosen in Settings (usually other work for the walk-round check).
    static func startShift(context: ModelContext, settings: AppSettings) {
        EventRecorder.log(.shiftStart, detail: "Started with \(settings.shiftStartKind.title.lowercased())", context: context, settings: settings)
        switchTo(settings.shiftStartKind, context: context, settings: settings)
        ReminderService.shared.fire(.shiftStart, context: context)
    }

    /// Ends the shift and starts daily or weekly rest.
    static func endShift(_ restType: RestType, context: ModelContext, settings: AppSettings) {
        switchTo(.rest, endShift: true, restType: restType == .breakTime ? .daily : restType,
                 context: context, settings: settings)
        EventRecorder.log(.shiftEnd, detail: restType == .weekly ? "Weekly rest" : "Daily rest", context: context, settings: settings)
        ReminderService.shared.fire(.shiftEnd, context: context)
    }

    /// After a shift ends: clear the vehicle/trailer in use and mark the day's job done,
    /// so tomorrow starts clean. Earnings, the route and the debrief are kept.
    static func resetAfterShift(context: ModelContext, store: SettingsStore, shiftStart: Date?) {
        store.settings.currentVehicleID = ""
        store.settings.currentTrailerID = ""
        let from = (shiftStart ?? Calendar.hgv.startOfDay(for: .now)).addingTimeInterval(-6 * 3600)
        let plans = (try? context.fetch(FetchDescriptor<WorkPlan>())) ?? []
        for p in plans where p.plannedStart >= from && p.plannedStart <= .now && !p.completed {
            p.completed = true
        }
        try? context.save()
    }

    /// True when the driver is on a shift (the last activity isn't a daily/weekly rest).
    static func isOnShift(context: ModelContext) -> Bool {
        guard let last = openEntries(context: context).last else { return false }
        return !last.endsShift
    }

    static func openEntries(context: ModelContext) -> [ActivityEntry] {
        let descriptor = FetchDescriptor<ActivityEntry>(sortBy: [SortDescriptor(\.start)])
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.end == nil }
    }

    /// Deletes one activity.
    static func delete(_ entry: ActivityEntry, context: ModelContext, settings: AppSettings) {
        EventRecorder.log(.correction, title: "Deleted \(entry.displayTitle)",
                          detail: "\(Fmt.dayTime(entry.start))–\(entry.end.map(Fmt.time) ?? "now")", context: context, settings: settings)
        context.delete(entry)
        try? context.save()
        refreshSideEffects(context: context, settings: settings)
    }

    /// Marks the current activity as loading, unloading, waiting… (or clears it with nil).
    static func setSubtype(_ subtype: ActivitySubtype?, context: ModelContext, settings: AppSettings) {
        guard let open = openEntries(context: context).last, !open.endsShift else { return }
        if let subtype, subtype.kind != open.kind {
            // e.g. tapping "Loading" while driving: switch to other work first.
            switchTo(subtype.kind, context: context, settings: settings)
        }
        guard let current = openEntries(context: context).last else { return }
        current.subtypeRaw = subtype?.rawValue ?? ""
        try? context.save()
        if let subtype {
            EventRecorder.log(.activity, title: subtype.title, activity: "\(subtype.kind.rawValue):\(subtype.rawValue)", context: context, settings: settings)
            VoiceService.shared.activityChanged(to: subtype.title)
        }
    }

    // MARK: Start time correction

    /// Moves the start of `entry` (e.g. "I pressed Drive 3 minutes late"). The activity before it
    /// is lengthened or shortened to match, so there's no gap or overlap. Returns the time actually set.
    @discardableResult
    static func adjustStart(of entry: ActivityEntry, to newStart: Date, context: ModelContext, settings: AppSettings) -> Date {
        let all = (try? context.fetch(FetchDescriptor<ActivityEntry>(sortBy: [SortDescriptor(\.start)]))) ?? []
        let previous = all.last { $0 !== entry && $0.start < entry.start && abs(($0.end ?? .distantFuture).timeIntervalSince(entry.start)) < 2 }
        var target = min(newStart, entry.end ?? .now, .now)
        if let previous { target = max(target, previous.start.addingTimeInterval(60)) }
        if let previous { previous.end = target }
        if abs(target.timeIntervalSince(entry.start)) >= 30 {
            EventRecorder.log(.correction, title: "\(entry.displayTitle) start changed", detail: "\(Fmt.time(entry.start)) → \(Fmt.time(target))",
                              context: context, settings: settings)
        }
        entry.start = target
        try? context.save()
        refreshSideEffects(context: context, settings: settings)
        return target
    }

    /// Removes a driving entry that the tacho minute rule says never happened, and lets the
    /// activity before it (e.g. a break) carry on as if it was never interrupted.
    static func discardShortDrive(_ entry: ActivityEntry, context: ModelContext, settings: AppSettings) {
        let all = (try? context.fetch(FetchDescriptor<ActivityEntry>(sortBy: [SortDescriptor(\.start)]))) ?? []
        let previous = all.last { $0 !== entry && $0.start < entry.start && abs(($0.end ?? .distantFuture).timeIntervalSince(entry.start)) < 2 }
        context.delete(entry)
        previous?.end = nil
        try? context.save()
        refreshSideEffects(context: context, settings: settings)
    }

    // MARK: Day record

    /// Today's (or a given day's) record, created if missing.
    static func dayRecord(for date: Date, context: ModelContext) -> DayRecord {
        let start = Calendar.hgv.startOfDay(for: date)
        let end = start.addingTimeInterval(86_400)
        let d = FetchDescriptor<DayRecord>(predicate: #Predicate { $0.day >= start && $0.day < end })
        if let existing = (try? context.fetch(d))?.first { return existing }
        let r = DayRecord(day: start)
        context.insert(r)
        return r
    }

    /// Adds GPS-measured distance (in-cab mode) to today's record.
    static func addGPSDistance(_ km: Double, at date: Date, context: ModelContext, vehicleID: String) {
        guard km > 0 else { return }
        let r = dayRecord(for: date, context: context)
        r.gpsKm += km
        if r.vehicleID.isEmpty { r.vehicleID = vehicleID }
        try? context.save()
    }

    /// Card inserted / withdrawn (Today button, watch, voice).
    static func setCard(inserted: Bool, context: ModelContext, store: SettingsStore) {
        store.settings.cardInserted = inserted
        store.settings.cardChangedAt = Date.now.timeIntervalSince1970
        store.save()
        context.insert(CardEvent(time: .now, inserted: inserted))
        try? context.save()
        EventRecorder.log(inserted ? .cardIn : .cardOut, context: context, settings: store.settings)
        if inserted { ReminderService.shared.fire(.cardInserted, context: context) }
        refreshSideEffects(context: context, settings: store.settings)
    }

    /// Runs a spoken command.
    static func perform(_ command: VoiceCommand, context: ModelContext, store: SettingsStore) {
        let settings = store.settings
        switch command {
        case .activity(let k): switchTo(k, context: context, settings: settings)
        case .subtype(let s): setSubtype(s, context: context, settings: settings)
        case .startShift: startShift(context: context, settings: settings)
        case .endShift(let r):
            let started = RulesEngine.status(recentSnapshots(context: context, settings: settings), now: .now, config: settings.ruleConfig).currentShift?.period.start
            endShift(r, context: context, settings: settings)
            resetAfterShift(context: context, store: store, shiftStart: started)
        case .cardIn: setCard(inserted: true, context: context, store: store)
        case .cardOut: setCard(inserted: false, context: context, store: store)
        case .arrived:
            EventRecorder.log(.arrived, detail: "By voice", context: context, settings: settings)
            ReminderService.shared.fire(.arrived, context: context)
        }
    }

    // MARK: Nights out

    static func nightOuts(on day: Date, context: ModelContext) -> [NightOut] {
        let cal = Calendar.hgv
        let start = cal.startOfDay(for: day)
        let end = start.addingTimeInterval(86_400)
        let d = FetchDescriptor<NightOut>(predicate: #Predicate { $0.date >= start && $0.date < end })
        return (try? context.fetch(d)) ?? []
    }

    /// Removes duplicate night-outs on the same day (left by an earlier bug).
    static func removeDuplicateNightOuts(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<NightOut>(sortBy: [SortDescriptor(\.date)]))) ?? []
        var seen = Set<Date>()
        for n in all {
            let day = Calendar.hgv.startOfDay(for: n.date)
            if seen.contains(day) { context.delete(n) } else { seen.insert(day) }
        }
        try? context.save()
    }

    // MARK: Driver card

    /// Latest card event: inserted or not, and since when.
    static func cardState(context: ModelContext) -> (inserted: Bool, since: Date?) {
        var descriptor = FetchDescriptor<CardEvent>(sortBy: [SortDescriptor(\.time, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let last = (try? context.fetch(descriptor))?.first else { return (false, nil) }
        return (last.inserted, last.time)
    }

    static func setCard(inserted: Bool, at time: Date = .now, context: ModelContext, settings: AppSettings) {
        context.insert(CardEvent(time: time, inserted: inserted))
        try? context.save()
        refreshSideEffects(context: context, settings: settings)
    }

    /// Removes everything between two times (e.g. a whole shift). Activities crossing the edges are trimmed.
    static func deleteRange(from start: Date, to end: Date, context: ModelContext, settings: AppSettings) {
        EventRecorder.log(.correction, title: "Deleted shift", detail: "\(Fmt.dayTime(start))–\(end == .distantFuture ? "now" : Fmt.dayTime(end))",
                          context: context, settings: settings)
        let all = (try? context.fetch(FetchDescriptor<ActivityEntry>(sortBy: [SortDescriptor(\.start)]))) ?? []
        for entry in all {
            let eEnd = entry.end ?? .distantFuture
            guard eEnd > start, entry.start < end else { continue }
            if entry.start >= start && eEnd <= end {
                context.delete(entry)
            } else if entry.start < start && eEnd > end {
                let tail = ActivityEntry(kind: entry.kind, regime: entry.regime, start: end, end: entry.end,
                                         multiManned: entry.multiManned, note: entry.note, endsShift: entry.endsShift)
                tail.plannedRestRaw = entry.plannedRestRaw
                context.insert(tail)
                entry.end = start
            } else if entry.start < start {
                entry.end = start
            } else {
                entry.start = end
            }
        }
        try? context.save()
        refreshSideEffects(context: context, settings: settings)
    }

    /// Removes everything recorded on a calendar day. Activities that cross midnight are trimmed, not deleted.
    static func deleteDay(_ day: Date, context: ModelContext, settings: AppSettings) {
        EventRecorder.log(.correction, title: "Deleted day", detail: Fmt.day(day), context: context, settings: settings)
        let cal = Calendar.hgv
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let descriptor = FetchDescriptor<ActivityEntry>(sortBy: [SortDescriptor(\.start)])
        let all = (try? context.fetch(descriptor)) ?? []
        for entry in all {
            let end = entry.end ?? .now
            guard end > dayStart, entry.start < dayEnd else { continue }
            let startsInside = entry.start >= dayStart
            let endsInside = end <= dayEnd && entry.end != nil
            switch (startsInside, endsInside) {
            case (true, true):
                context.delete(entry)
            case (false, true):
                entry.end = dayStart
            case (true, false):
                if entry.end == nil {
                    context.delete(entry)
                } else {
                    entry.start = dayEnd
                }
            case (false, false):
                // Spans the whole day: split around it.
                let after = ActivityEntry(kind: entry.kind, regime: entry.regime, start: dayEnd, end: entry.end,
                                          multiManned: entry.multiManned, note: entry.note, endsShift: entry.endsShift)
                after.plannedRestRaw = entry.plannedRestRaw
                context.insert(after)
                entry.end = dayStart
            }
        }
        for night in (try? context.fetch(FetchDescriptor<NightOut>())) ?? [] where cal.isDate(night.date, inSameDayAs: dayStart) {
            context.delete(night)
        }
        try? context.save()
        refreshSideEffects(context: context, settings: settings)
    }

    /// Entries needed for live status: the working-time reference period plus two weeks.
    static func recentSnapshots(context: ModelContext, settings: AppSettings, now: Date = .now) -> [EntrySnapshot] {
        let cutoff = now.addingTimeInterval(-Double(settings.wtdReferenceWeeks + 2) * 7 * 86_400)
        let descriptor = FetchDescriptor<ActivityEntry>(
            predicate: #Predicate<ActivityEntry> { $0.start >= cutoff },
            sortBy: [SortDescriptor(\.start)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map(\.snapshot)
    }

    static func refreshSideEffects(context: ModelContext, settings: AppSettings) {
        let now = Date()
        let snaps = recentSnapshots(context: context, settings: settings, now: now)
        let status = RulesEngine.status(snaps, now: now, config: settings.ruleConfig)
        WorldRulesCache.status = settings.region.isEuropean ? nil
            : WorldRules.status(snaps, now: now, region: settings.region, usCycle70: settings.usCycle70)
        let last = openEntries(context: context).last
        let shiftEnded = last?.endsShift ?? true
        ScreenAwake.apply(settings, onShift: !shiftEnded)
        if let world = WorldRulesCache.status {
            NotificationService.shared.rescheduleWorld(world, settings: settings, shiftEnded: shiftEnded)
        } else {
            NotificationService.shared.reschedule(status: status, settings: settings, shiftEnded: shiftEnded)
        }
        ReminderService.shared.schedule(context: context, status: status, settings: settings, shiftEnded: shiftEnded)
        if let world = WorldRulesCache.status {
            var w = status
            w.warnings = world.violations
            EventRecorder.logInfringements(w, context: context, settings: settings)
        } else {
            EventRecorder.logInfringements(status, context: context, settings: settings)
        }
        VoiceService.shared.update(settings: settings)
        let state = LiveActivityService.contentState(status: status, settings: settings, shiftEnded: shiftEnded)
        let name = settings.driverName
        Task { await LiveActivityService.shared.sync(state: state, driverName: name) }
        var dashboard = Dashboard.make(status: status, settings: settings, openEntry: last)
        addPayAndVehicle(to: &dashboard, context: context, settings: settings, now: now)
        dashboard.cardInserted = settings.cardInserted
        PhoneWatchBridge.shared.send(dashboard)
        SharedStore.save(dashboard)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Earnings this shift and this week, and the vehicle height, for the Watch and widgets.
    private static func addPayAndVehicle(to d: inout Dashboard, context: ModelContext, settings: AppSettings, now: Date) {
        let cal = Calendar.hgv
        let weekStart = cal.startOfFixedWeek(for: now)
        let from = weekStart.addingTimeInterval(-2 * 86_400)
        let descriptor = FetchDescriptor<ActivityEntry>(sortBy: [SortDescriptor(\.start)])
        let entries = ((try? context.fetch(descriptor)) ?? []).filter { ($0.end ?? now) > from }.map(\.snapshot)
        let analysis = RulesEngine.analyze(entries, now: now, config: settings.ruleConfig)
        let weekShifts = analysis.shifts.filter { $0.period.start >= weekStart }
        let nights = ((try? context.fetch(FetchDescriptor<NightOut>())) ?? []).filter { $0.date >= weekStart }.count
        let items = ((try? context.fetch(FetchDescriptor<PayItem>())) ?? []).filter { $0.date >= weekStart }.map(\.snapshot)
        d.earnedWeek = PayCalculator.calculate(shifts: weekShifts, nightOuts: nights, settings: settings.pay, items: items).total
        if let last = analysis.shifts.last, d.onShift || cal.isDate(last.period.start, inSameDayAs: now) {
            d.earnedShift = PayCalculator.calculate(shifts: [last], nightOuts: 0, settings: settings.pay).total
        }
        d.currency = settings.pay.currencySymbol
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        d.vehicleHeight = vehicles.filter { $0.id.uuidString == settings.currentVehicleID || $0.id.uuidString == settings.currentTrailerID }
            .map(\.height).max() ?? 0
    }
}
