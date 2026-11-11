import SwiftUI
import SwiftData

/// Drivers' hours, rest and working time: everything that counts down.
struct HoursView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \NightOut.date) private var nightOuts: [NightOut]
    @State private var showingAllInfringements = false

    private var openEntry: ActivityEntry? { entries.last { $0.end == nil } }
    private var onShift: Bool { openEntry.map { !$0.endsShift } ?? false }

    private func snapshots(now: Date) -> [EntrySnapshot] {
        let cutoff = now.addingTimeInterval(-Double(store.settings.wtdReferenceWeeks + 2) * 7 * 86_400)
        return entries.filter { $0.start >= cutoff }.map(\.snapshot)
    }

    @State private var editing = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 10)) { timeline in
                let snaps = snapshots(now: timeline.date)
                let status = RulesEngine.status(snaps, now: timeline.date, config: store.settings.ruleConfig)
                let world = WorldRulesCache.refresh(snaps, now: timeline.date, settings: store.settings)
                let dash = Dashboard.make(status: status, settings: store.settings, openEntry: openEntry)
                let data = HoursTileData(status: status, dash: dash, settings: store.settings, openEntry: openEntry, onShift: onShift)
                ScrollView {
                    VStack(spacing: 12) {
                        if let world {
                            WorldHoursSection(world: world, dash: dash, onShift: onShift)
                        } else {
                            if !status.hasData && !editing {
                                ContentUnavailableView("No hours yet", systemImage: "gauge.with.dots.needle.0percent",
                                                       description: Text("Start a shift on the Today tab and your driving, working time and rest limits appear here."))
                            }
                            let hidden = store.settings.tileHidden(.hours)
                            let order = store.settings.tileOrder(.hours).filter { !hidden.contains($0) }
                            ForEach(TileGroup.allCases) { group in
                                let tiles = order.filter { $0.group == group && (editing || data.applies($0)) }
                                if !tiles.isEmpty {
                                    TileGroupHeader(group: group, page: .hours)
                                    TileGrid(page: .hours, tiles: tiles, editing: editing) { tile in
                                        if data.applies(tile) { HoursTileView(tile: tile, data: data) } else { TilePlaceholder(tile: tile) }
                                    }
                                }
                            }
                            if editing { HiddenTilesTray(page: .hours) }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Hours")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing ? "Done" : "Edit") { withAnimation(.snappy) { editing.toggle() } }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { TileCustomiseView(page: .hours) } label: { Image(systemName: "switch.2") }
                        .accessibilityLabel("Choose tiles")
                }
            }
        }
    }
}
