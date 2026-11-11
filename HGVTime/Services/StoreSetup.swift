import Foundation
import SwiftData

/// Creates the app's database and brings back data from the older location.
///
/// Since the widgets were added (App Group), SwiftData keeps its database in the shared App Group folder.
/// Earlier versions kept it in the app's own Application Support folder. On first launch after that change,
/// everything from the old database is copied across (skipping anything already there), and the old file is
/// renamed to `default.store.migrated` as a backup.
enum StoreSetup {
    static let schema = Schema([ActivityEntry.self, NightOut.self, PayItem.self, Vehicle.self,
                                WorkPlan.self, NoteItem.self, CardEvent.self, SpeedEvent.self, DayRecord.self, ResourceLog.self, Reminder.self, EventLog.self, TrackPoint.self, VehicleUse.self])

    /// One container for the whole app (also used when iOS relaunches the app in the background).
    @MainActor static let shared: ModelContainer = makeContainer()

    static func makeContainer() -> ModelContainer {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            // Last resort so the app still opens; data won't persist this session.
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        migrateLegacyStore(into: container)
        return container
    }

    /// The pre-App-Group database location.
    private static var legacyURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("default.store")
    }

    private static func migrateLegacyStore(into container: ModelContainer) {
        guard let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        // Don't copy a database onto itself (if there's no App Group, both locations are the same).
        if let current = container.configurations.first?.url, current.standardizedFileURL == legacyURL.standardizedFileURL { return }

        do {
            let legacy = try ModelContainer(for: schema, configurations: ModelConfiguration("legacy", schema: schema, url: legacyURL))
            let old = ModelContext(legacy)
            let new = ModelContext(container)

            let existingEntries = Set(((try? new.fetch(FetchDescriptor<ActivityEntry>())) ?? []).map(\.id))
            for e in (try? old.fetch(FetchDescriptor<ActivityEntry>())) ?? [] where !existingEntries.contains(e.id) {
                let copy = ActivityEntry(kind: e.kind, regime: e.regime, start: e.start, end: e.end,
                                         multiManned: e.multiManned, note: e.note, endsShift: e.endsShift)
                copy.id = e.id
                copy.plannedRestRaw = e.plannedRestRaw
                new.insert(copy)
            }

            let cal = Calendar.hgv
            let existingNights = ((try? new.fetch(FetchDescriptor<NightOut>())) ?? []).map(\.date)
            for n in (try? old.fetch(FetchDescriptor<NightOut>())) ?? []
            where !existingNights.contains(where: { cal.isDate($0, inSameDayAs: n.date) }) {
                new.insert(NightOut(date: n.date, note: n.note))
            }

            let existingItems = ((try? new.fetch(FetchDescriptor<PayItem>())) ?? []).map { "\($0.date.timeIntervalSince1970)|\($0.kindRaw)|\($0.title)|\($0.amount)" }
            for i in (try? old.fetch(FetchDescriptor<PayItem>())) ?? []
            where !existingItems.contains("\(i.date.timeIntervalSince1970)|\(i.kindRaw)|\(i.title)|\(i.amount)") {
                new.insert(PayItem(date: i.date, kind: i.kind, title: i.title, amount: i.amount, hours: i.hours))
            }

            try new.save()
        } catch {
            // Leave the old file in place so nothing is lost; try again next launch.
            return
        }

        // Keep the old database as a backup, out of the way.
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: legacyURL.path + suffix)
            let to = URL(fileURLWithPath: legacyURL.path + ".migrated" + suffix)
            try? FileManager.default.removeItem(at: to)
            try? FileManager.default.moveItem(at: from, to: to)
        }
    }
}
