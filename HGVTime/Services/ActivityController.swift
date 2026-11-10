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
    }

    /// Starts a shift with the activity chosen in Settings (usually other work for the walk-round check).
    static func startShift(context: ModelContext, settings: AppSettings) {
        switchTo(settings.shiftStartKind, context: context, settings: settings)
    }

    /// Ends the shift and starts daily or weekly rest.
    static func endShift(_ restType: RestType, context: ModelContext, settings: AppSettings) {
        switchTo(.rest, endShift: true, restType: restType == .breakTime ? .daily : restType,
                 context: context, settings: settings)
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
        context.delete(entry)
        try? context.save()
        refreshSideEffects(context: context, settings: settings)
    }

    /// Removes everything between two times (e.g. a whole shift). Activities crossing the edges are trimmed.
    static func deleteRange(from start: Date, to end: Date, context: ModelContext, settings: AppSettings) {
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
        let status = RulesEngine.status(recentSnapshots(context: context, settings: settings, now: now), now: now, config: settings.ruleConfig)
        let last = openEntries(context: context).last
        let shiftEnded = last?.endsShift ?? true
        NotificationService.shared.reschedule(status: status, settings: settings, shiftEnded: shiftEnded)
        let state = LiveActivityService.contentState(status: status, settings: settings, shiftEnded: shiftEnded)
        let name = settings.driverName
        Task { await LiveActivityService.shared.sync(state: state, driverName: name) }
        var dashboard = Dashboard.make(status: status, settings: settings, openEntry: last)
        addPayAndVehicle(to: &dashboard, context: context, settings: settings, now: now)
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
