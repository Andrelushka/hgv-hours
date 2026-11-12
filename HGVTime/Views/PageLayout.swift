import SwiftUI

/// Pages built from blocks that you can reorder and hide with Edit layout, like the Today tiles.
enum LayoutPage: String, CaseIterable, Identifiable {
    case driverLogTabs, driverDay, jobsTabs, earnings, debrief
    var id: String { rawValue }

    var title: String {
        switch self {
        case .driverLogTabs: String(localized: "Driver log sections")
        case .driverDay: String(localized: "Driver log day")
        case .jobsTabs: String(localized: "Jobs sections")
        case .earnings: String(localized: "Earnings")
        case .debrief: String(localized: "Day debrief")
        }
    }

    /// Block id, title and symbol, in the default order.
    var blocks: [(id: String, title: String, symbol: String)] {
        switch self {
        case .driverLogTabs:
            [("days", String(localized: "Days"), "calendar"),
             ("events", String(localized: "Events"), "exclamationmark.triangle"),
             ("changes", String(localized: "Changes"), "pencil.and.list.clipboard")]
        case .driverDay:
            [("dayBar", String(localized: "Day chart and totals"), "chart.bar.xaxis"),
             ("activities", String(localized: "Activities"), "list.bullet"),
             ("events", String(localized: "Events"), "exclamationmark.triangle"),
             ("links", String(localized: "Map, debrief and delete"), "map")]
        case .jobsTabs:
            [("planner", String(localized: "Planner"), "calendar"),
             ("vehicles", String(localized: "Vehicles"), "box.truck"),
             ("fuel", String(localized: "Fuel"), "fuelpump"),
             ("notes", String(localized: "Notes"), "note.text")]
        case .earnings:
            [("total", String(localized: "Earned and estimate"), "sterlingsign.circle"),
             ("chart", String(localized: "Chart"), "chart.bar.fill"),
             ("breakdown", String(localized: "Breakdown"), "list.bullet.rectangle"),
             ("links", String(localized: "Week details, summary and pay settings"), "link")]
        case .debrief:
            [("job", String(localized: "Job"), "shippingbox"),
             ("vehicleCheck", String(localized: "Vehicle check"), "checklist.checked"),
             ("stops", String(localized: "Stops"), "mappin.and.ellipse"),
             ("activities", String(localized: "Activities"), "clock"),
             ("mileage", String(localized: "Mileage & resources"), "road.lanes"),
             ("events", String(localized: "Events"), "exclamationmark.triangle"),
             ("pay", String(localized: "Pay"), "sterlingsign.circle")]
        }
    }

    /// Section switchers must keep at least one block.
    var needsOne: Bool { self == .driverLogTabs || self == .jobsTabs }
}

extension AppSettings {
    /// Blocks in your order (new blocks added at the end).
    func blockOrder(_ page: LayoutPage) -> [String] {
        let all = page.blocks.map(\.id)
        var out = (pageOrders[page.rawValue] ?? []).filter { all.contains($0) }
        for id in all where !out.contains(id) { out.append(id) }
        return out
    }

    func blockHidden(_ page: LayoutPage) -> Set<String> { Set(pageHidden[page.rawValue] ?? []) }

    /// Visible blocks in order.
    func blocks(_ page: LayoutPage) -> [String] {
        let hidden = blockHidden(page)
        let out = blockOrder(page).filter { !hidden.contains($0) }
        return out.isEmpty && page.needsOne ? [blockOrder(page)[0]] : out
    }

    mutating func setBlock(_ id: String, visible: Bool, on page: LayoutPage) {
        var hidden = blockHidden(page)
        if visible { hidden.remove(id) } else { hidden.insert(id) }
        if page.needsOne, hidden.count >= page.blocks.count { return }
        pageHidden[page.rawValue] = blockOrder(page).filter { hidden.contains($0) }
    }

    mutating func moveBlocks(_ page: LayoutPage, from: IndexSet, to: Int) {
        var order = blockOrder(page)
        order.move(fromOffsets: from, toOffset: to)
        pageOrders[page.rawValue] = order
    }

    mutating func resetBlocks(_ page: LayoutPage) {
        pageOrders[page.rawValue] = nil
        pageHidden[page.rawValue] = nil
    }
}

/// Edit layout for a block page: drag to reorder, switch blocks on and off.
struct PageLayoutEditor: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var pages: [LayoutPage]

    var body: some View {
        List {
            ForEach(pages) { page in
                Section {
                    let hidden = store.settings.blockHidden(page)
                    ForEach(store.settings.blockOrder(page), id: \.self) { id in
                        let block = page.blocks.first { $0.id == id }
                        Toggle(isOn: Binding(get: { !hidden.contains(id) },
                                             set: { store.settings.setBlock(id, visible: $0, on: page) })) {
                            Label(block?.title ?? id, systemImage: block?.symbol ?? "square")
                        }
                    }
                    .onMove { store.settings.moveBlocks(page, from: $0, to: $1) }
                    Button("Reset to default") { withAnimation { store.settings.resetBlocks(page) } }
                        .font(.caption)
                } header: {
                    Text(page.title)
                } footer: {
                    if page.needsOne { Text("The first one shown opens when you come to the page. At least one stays on.") }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Edit layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

/// Toolbar button that opens the layout editor for one or more block pages.
struct EditLayoutButton: View {
    var pages: [LayoutPage]
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { Image(systemName: "square.grid.2x2") }
            .accessibilityLabel("Edit layout")
            .sheet(isPresented: $showing) { NavigationStack { PageLayoutEditor(pages: pages) } }
    }
}
