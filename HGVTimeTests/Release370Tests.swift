import SwiftData
import XCTest
@testable import HGVTime

/// 3.7.0: reset and erase, by group.
@MainActor
final class Release370Tests: XCTestCase {
    private func changed() -> AppSettings {
        var s = AppSettings()
        s.driverName = "Sam"; s.homePostcode = "NN11 8XX"
        s.pay.baseRate = 17.5
        s.ruleRegionRaw = "us"
        s.voiceEnabled = true; s.wakeAlarmEnabled = true
        s.autoDetectEnabled = true
        s.useMiles = false
        s.assistantUseLocal = true
        s.lockEnabled = true
        s.hasAcceptedDisclaimer = true; s.profileCreated = true
        return s
    }

    func testSettingsGroupResetsOnlyItsOwnFields() {
        var s = changed()
        SettingsGroup.pay.reset(&s)
        XCTAssertEqual(s.pay, AppSettings().pay)
        XCTAssertEqual(s.driverName, "Sam")
        XCTAssertTrue(s.voiceEnabled)

        SettingsGroup.profile.reset(&s)
        XCTAssertEqual(s.driverName, "")
        XCTAssertEqual(s.homePostcode, "")
        XCTAssertEqual(s.ruleRegionRaw, "us")
    }

    func testEverythingElseKeepsGroupedFields() {
        var s = changed()
        SettingsGroup.other.reset(&s)
        XCTAssertFalse(s.hasAcceptedDisclaimer)       // reset
        XCTAssertFalse(s.profileCreated)
        XCTAssertEqual(s.driverName, "Sam")           // kept (profile group)
        XCTAssertEqual(s.pay.baseRate, 17.5)
        XCTAssertTrue(s.lockEnabled)
        XCTAssertTrue(s.autoDetectEnabled)
    }

    func testAllGroupsGiveDefaults() {
        var s = changed()
        for g in SettingsGroup.allCases { g.reset(&s) }
        XCTAssertEqual(s, AppSettings())
    }

    func testEraseChosenRecordsKeepsTheRest() throws {
        let container = try ModelContainer(for: StoreSetup.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let defaults = UserDefaults(suiteName: "reset-test-\(UUID())")!
        let store = SettingsStore(defaults: defaults)
        store.settings = changed()
        context.insert(ActivityEntry(kind: .drive, regime: .assimilated, start: .now.addingTimeInterval(-3600), end: .now))
        context.insert(WorkPlan(start: .now.addingTimeInterval(3600), end: .now.addingTimeInterval(7200)))
        context.insert(NoteItem())
        try context.save()

        ResetService.erase(.init(data: [.driverLog], settings: [.pay]), context: context, store: store)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActivityEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkPlan>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NoteItem>()), 1)
        XCTAssertEqual(store.settings.pay, AppSettings().pay)
        XCTAssertEqual(store.settings.driverName, "Sam")
    }
}
