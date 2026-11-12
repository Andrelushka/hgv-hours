import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Every block that can appear on the Today and Hours pages.
enum Tile: String, CaseIterable, Identifiable {
    // Today
    case date, card, expiry, status, buttons, inCab, warnings, earnings, nightOut, job, vehicle, mileage, checks, heightCheck, vehicleCheck, company, emergency
    // Navigation (shown while navigating)
    case navMap, navTurn, navRoad, navSpeedLimit, navArrival, navVoice
    // Right now
    case driveLeft, workLeft, restBy, shiftLeft, breakDue, drivenToday, workedToday, restNow
    // Breaks and deadlines
    case nextBreak, comingUp
    // Extensions
    case tenHourDays, fifteenHourDays, shiftLength, restRules
    // Drivers' hours (tacho)
    case beforeBreak, dailyDriving, weekDriving, fortnight
    // Rest
    case dailyRest, reducedRests, weeklyRest, compensation
    // Working time
    case wtdBreak, shiftWorking, weekWorking, average
    // GB domestic
    case gbDriving, gbDuty
    // Alerts
    case allWarnings, infringements

    var id: String { rawValue }

    var group: TileGroup {
        switch self {
        case .date, .card, .expiry, .status, .buttons, .inCab, .warnings, .earnings, .job, .vehicle, .mileage, .checks, .heightCheck, .vehicleCheck, .company, .emergency,
             .navMap, .navTurn, .navRoad, .navSpeedLimit, .navArrival, .navVoice: .today
        case .driveLeft, .workLeft, .restBy, .shiftLeft, .breakDue, .drivenToday, .workedToday, .restNow: .now
        case .nextBreak, .comingUp: .breaks
        case .tenHourDays, .fifteenHourDays, .shiftLength, .restRules: .extensions
        case .beforeBreak, .dailyDriving, .weekDriving, .fortnight: .tacho
        case .dailyRest, .reducedRests, .weeklyRest, .compensation: .rest
        case .wtdBreak, .shiftWorking, .weekWorking, .average: .wtd
        case .gbDriving, .gbDuty: .gb
        case .allWarnings, .infringements, .nightOut: .alerts
        }
    }

    /// Full width (otherwise half width, two to a row).
    var isWide: Bool {
        switch self {
        case .date, .expiry, .status, .buttons, .inCab, .warnings, .earnings, .job, .vehicle, .mileage, .checks, .heightCheck, .vehicleCheck, .company, .navMap, .navTurn,
             .restNow, .nextBreak, .comingUp, .shiftLength, .restRules, .allWarnings, .infringements:
            true
        default: false
        }
    }

    var title: String {
        switch self {
        case .date: String(localized: "Today's date")
        case .card: String(localized: "Driver card")
        case .expiry: String(localized: "Expiry warnings")
        case .status: String(localized: "Current activity")
        case .buttons: String(localized: "Activity buttons")
        case .inCab: String(localized: "In-cab automatic")
        case .warnings: String(localized: "Urgent warnings")
        case .earnings: String(localized: "Earnings")
        case .nightOut: String(localized: "Night out")
        case .job: String(localized: "Today's job")
        case .checks: String(localized: "Shift checks")
        case .heightCheck: String(localized: "Vehicle height checked")
        case .vehicleCheck: String(localized: "Vehicle check")
        case .company: String(localized: "Company")
        case .emergency: String(localized: "Emergency")
        case .navMap: String(localized: "Navigation map")
        case .navTurn: String(localized: "Next turn")
        case .navRoad: String(localized: "Road you're on")
        case .navSpeedLimit: String(localized: "Speed limit")
        case .navArrival: String(localized: "Arrival time")
        case .navVoice: String(localized: "Navigation voice")
        case .vehicle: String(localized: "Vehicle & height")
        case .mileage: String(localized: "Mileage & fuel")
        case .driveLeft: String(localized: "Driving left")
        case .workLeft: String(localized: "Working left")
        case .restBy: String(localized: "Start daily rest by")
        case .shiftLeft: String(localized: "Shift time left")
        case .breakDue: String(localized: "Break due in")
        case .drivenToday: String(localized: "Driven today")
        case .workedToday: String(localized: "Worked today")
        case .restNow: String(localized: "Current rest")
        case .nextBreak: String(localized: "Next break")
        case .comingUp: String(localized: "Coming up")
        case .tenHourDays: String(localized: "10h driving days")
        case .fifteenHourDays: String(localized: "15h days")
        case .shiftLength: String(localized: "Shift length")
        case .restRules: String(localized: "Rest rules")
        case .beforeBreak: String(localized: "Before break")
        case .dailyDriving: String(localized: "Daily driving")
        case .weekDriving: String(localized: "This week")
        case .fortnight: String(localized: "Fortnight")
        case .dailyRest: String(localized: "Daily rest")
        case .reducedRests: String(localized: "Reduced rests")
        case .weeklyRest: String(localized: "Weekly rest")
        case .compensation: String(localized: "Compensation owed")
        case .wtdBreak: String(localized: "Before 6h break")
        case .shiftWorking: String(localized: "Shift working time")
        case .weekWorking: String(localized: "Week working")
        case .average: String(localized: "Weekly average")
        case .gbDriving: String(localized: "GB driving")
        case .gbDuty: String(localized: "GB duty")
        case .allWarnings: String(localized: "All warnings")
        case .infringements: String(localized: "Infringements")
        }
    }

    var symbol: String {
        switch self {
        case .date: "calendar"
        case .card: "creditcard.fill"
        case .expiry: "calendar.badge.exclamationmark"
        case .status: "timer"
        case .buttons: "square.grid.2x2.fill"
        case .inCab: "box.truck.fill"
        case .warnings: "exclamationmark.triangle.fill"
        case .earnings: "sterlingsign.circle.fill"
        case .nightOut: "bed.double.fill"
        case .job: "shippingbox.fill"
        case .checks: "checklist"
        case .heightCheck: "arrow.up.and.down.square.fill"
        case .vehicleCheck: "checklist.checked"
        case .company: "building.2.fill"
        case .emergency: "sos"
        case .navMap: "map.fill"
        case .navTurn: "arrow.turn.up.right"
        case .navRoad: "road.lanes"
        case .navSpeedLimit: "circle.circle"
        case .navArrival: "flag.checkered"
        case .navVoice: "speaker.wave.2.fill"
        case .vehicle: "arrow.up.and.down"
        case .mileage: "road.lanes"
        case .driveLeft: "steeringwheel"
        case .workLeft: "briefcase.fill"
        case .restBy: "moon.zzz.fill"
        case .shiftLeft: "hourglass"
        case .breakDue: "cup.and.saucer.fill"
        case .drivenToday: "sun.max.fill"
        case .workedToday: "clock.fill"
        case .restNow: "bed.double.fill"
        case .nextBreak: "cup.and.saucer"
        case .comingUp: "list.bullet.clipboard"
        case .tenHourDays: "10.circle"
        case .fifteenHourDays: "15.circle"
        case .shiftLength: "arrow.left.and.right"
        case .restRules: "moon.haze"
        case .beforeBreak: "cup.and.saucer.fill"
        case .dailyDriving: "sun.max.fill"
        case .weekDriving: "calendar"
        case .fortnight: "calendar.badge.clock"
        case .dailyRest: "moon.fill"
        case .reducedRests: "moon.haze.fill"
        case .weeklyRest: "house.fill"
        case .compensation: "arrow.uturn.backward.circle"
        case .wtdBreak: "figure.walk"
        case .shiftWorking: "clock.fill"
        case .weekWorking: "briefcase.fill"
        case .average: "chart.bar.fill"
        case .gbDriving: "steeringwheel"
        case .gbDuty: "clock.fill"
        case .allWarnings: "exclamationmark.bubble"
        case .infringements: "exclamationmark.octagon"
        }
    }
}

enum TileGroup: String, CaseIterable, Identifiable {
    case today, now, breaks, extensions, tacho, rest, wtd, gb, alerts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .now: String(localized: "Right now")
        case .breaks: String(localized: "Breaks & deadlines")
        case .extensions: String(localized: "Extensions & shift length")
        case .tacho: String(localized: "Drivers' hours (tacho)")
        case .rest: String(localized: "Rest")
        case .wtd: String(localized: "Working time")
        case .gb: String(localized: "GB domestic")
        case .alerts: String(localized: "Warnings & night out")
        }
    }
}

/// The Today page and the Hours page each have their own layout.
enum TilePage: String {
    case today, hours

    var allowed: [Tile] {
        switch self {
        case .today:
            [.date, .heightCheck, .emergency, .company, .status, .navTurn, .navMap, .navRoad, .navSpeedLimit, .navArrival, .navVoice, .buttons, .driveLeft, .workLeft, .checks, .vehicleCheck, .card, .nightOut, .inCab, .warnings, .expiry, .earnings,
             .job, .vehicle, .mileage, .restBy, .shiftLeft, .breakDue, .drivenToday, .workedToday, .nextBreak,
             .tenHourDays, .fifteenHourDays, .shiftLength]
        case .hours:
            Tile.allCases.filter { ![.today].contains($0.group) }
        }
    }

    /// Shown until the driver changes the layout.
    var defaultVisible: Set<Tile> {
        switch self {
        case .today: [.date, .card, .heightCheck, .company, .emergency, .expiry, .status, .buttons, .navTurn, .navMap, .navArrival, .driveLeft, .workLeft, .checks, .vehicleCheck, .inCab, .warnings, .earnings, .nightOut, .job, .vehicle, .mileage]
        case .hours: Set(allowed)
        }
    }

}

extension Tile {
    /// Tiles that only make sense full width (buttons, the current activity…).
    var canResize: Bool { ![.buttons, .status, .navMap, .navTurn].contains(self) }
}

extension AppSettings {
    /// Hours is always in groups; Today only if you turn groups on.
    func isGrouped(_ page: TilePage) -> Bool { page == .hours || todayGrouped }

    /// The group a tile sits in (yours if you moved it).
    func group(of tile: Tile) -> TileGroup {
        tileGroups[tile.rawValue].flatMap(TileGroup.init(rawValue:)) ?? tile.group
    }

    mutating func setGroup(_ tile: Tile, _ group: TileGroup) {
        tileGroups[tile.rawValue] = group == tile.group ? nil : group.rawValue
    }

    /// Groups in your order.
    var orderedGroups: [TileGroup] {
        var out = groupOrder.compactMap(TileGroup.init(rawValue:))
        for g in TileGroup.allCases where !out.contains(g) { out.append(g) }
        return out
    }

    mutating func moveGroup(_ group: TileGroup, by delta: Int) {
        var order = orderedGroups
        guard let i = order.firstIndex(of: group) else { return }
        let j = max(0, min(order.count - 1, i + delta))
        order.remove(at: i)
        order.insert(group, at: j)
        groupOrder = order.map(\.rawValue)
    }

    func groupTitle(_ group: TileGroup) -> String {
        let custom = groupNames[group.rawValue]?.trimmingCharacters(in: .whitespaces) ?? ""
        return custom.isEmpty ? group.title : custom
    }

    func isGroupHidden(_ group: TileGroup) -> Bool { groupsHidden.contains(group.rawValue) }

    mutating func setGroupHidden(_ group: TileGroup, _ hidden: Bool) {
        groupsHidden.removeAll { $0 == group.rawValue }
        if hidden { groupsHidden.append(group.rawValue) }
    }

    /// Full width or half width, as you set it in Edit layout.
    func isWide(_ tile: Tile) -> Bool {
        guard tile.canResize, let size = tileSizes[tile.rawValue] else { return tile.isWide }
        return size == "wide"
    }

    mutating func setWide(_ tile: Tile, _ wide: Bool) {
        tileSizes[tile.rawValue] = wide == tile.isWide ? nil : (wide ? "wide" : "half")
    }

    func tileOrder(_ page: TilePage) -> [Tile] {
        let raw = page == .today ? todayOrder : hoursOrder
        var order = raw.compactMap(Tile.init(rawValue:)).filter { page.allowed.contains($0) }
        // Layouts saved before 3.2 had no date or countdown tiles: put them in sensible places.
        if page == .today, !order.isEmpty, !raw.contains(Tile.date.rawValue) {
            order.insert(.date, at: 0)
            let at = (order.firstIndex(of: .buttons).map { $0 + 1 }) ?? order.count
            order.insert(contentsOf: [.driveLeft, .workLeft].filter { !order.contains($0) }, at: at)
            // Two half-width tiles side by side: driver card and night out.
            if let card = order.firstIndex(of: .card), let night = order.firstIndex(of: .nightOut) {
                order.remove(at: night)
                order.insert(.nightOut, at: min(order.firstIndex(of: .card).map { $0 + 1 } ?? card + 1, order.count))
            }
        }
        // Vehicle check (3.16) goes after the shift checks in layouts saved before it existed.
        if page == .today, !order.isEmpty, !raw.contains(Tile.vehicleCheck.rawValue),
           let i = order.firstIndex(of: .checks) ?? order.firstIndex(of: .workLeft) {
            order.insert(.vehicleCheck, at: i + 1)
        }
        // Height check (3.14) goes under the driver card / night out row in layouts saved before it existed.
        if page == .today, !order.isEmpty, !raw.contains(Tile.heightCheck.rawValue) {
            let after = [order.firstIndex(of: .nightOut), order.firstIndex(of: .card)].compactMap { $0 }.max()
            order.insert(.heightCheck, at: after.map { $0 + 1 } ?? 1)
        }
        // Navigation tiles (3.10) go just above the buttons in layouts saved before they existed (shown only while navigating).
        if page == .today, !order.isEmpty, !raw.contains(Tile.navTurn.rawValue), let b = order.firstIndex(of: .buttons) {
            order.insert(contentsOf: [.navTurn, .navMap, .navRoad, .navSpeedLimit, .navArrival, .navVoice].filter { !order.contains($0) }, at: b)
        }
        // Shift checks (3.9) go just under the buttons in layouts saved before they existed.
        if page == .today, !order.isEmpty, !raw.contains(Tile.checks.rawValue),
           let b = order.firstIndex(of: .workLeft) ?? order.firstIndex(of: .buttons) {
            order.insert(.checks, at: b + 1)
        }
        for t in page.allowed where !order.contains(t) { order.append(t) }
        return order
    }

    func tileHidden(_ page: TilePage) -> Set<Tile> {
        let raw = page == .today ? todayOrder : hoursOrder
        var hidden = Set((page == .today ? todayHidden : hoursHidden).compactMap(Tile.init(rawValue:)))
        for t in page.allowed where !raw.contains(t.rawValue) && !page.defaultVisible.contains(t) { hidden.insert(t) }
        return hidden
    }

    mutating func setTiles(_ page: TilePage, order: [Tile], hidden: Set<Tile>) {
        let o = order.map(\.rawValue)
        let h = page.allowed.filter { hidden.contains($0) }.map(\.rawValue)
        if page == .today { todayOrder = o; todayHidden = h } else { hoursOrder = o; hoursHidden = h }
    }

    mutating func setTile(_ tile: Tile, visible: Bool, on page: TilePage) {
        var hidden = tileHidden(page)
        if visible { hidden.remove(tile) } else { hidden.insert(tile) }
        setTiles(page, order: tileOrder(page), hidden: hidden)
    }

    mutating func moveTile(_ tile: Tile, before target: Tile, on page: TilePage) {
        var order = tileOrder(page)
        guard tile != target, let from = order.firstIndex(of: tile) else { return }
        order.remove(at: from)
        let to = order.firstIndex(of: target) ?? order.count
        order.insert(tile, at: to)
        setTiles(page, order: order, hidden: tileHidden(page))
    }

    /// Today's date in the chosen style.
    func formattedDate(_ date: Date) -> String {
        let cal = Calendar.hgv
        let week = "Week \(cal.component(.weekOfYear, from: date))"
        switch dateStyle {
        case "short": return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
        case "medium": return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        case "iso": return date.formatted(.iso8601.year().month().day())
        case "week": return "\(date.formatted(.dateTime.weekday(.wide).day().month(.wide))) · \(week)"
        case "us": return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year())
        default: return date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        }
    }

    static let dateStyles: [(id: String, title: String)] = [
        ("long", "Wednesday 11 November 2026"),
        ("week", "Wednesday 11 November · Week 46"),
        ("medium", "Wed 11 Nov 2026"),
        ("short", "11/11/2026"),
        ("us", "11/11/2026 (month first)"),
        ("iso", "2026-11-11")
    ]
}

/// Lays tiles out as a grid: half-width tiles two to a row, wide tiles on their own row.
/// In edit mode tiles can be dragged onto each other to reorder, or hidden with the − button.
struct TileGrid<Content: View>: View {
    @Environment(SettingsStore.self) private var store
    var page: TilePage
    var tiles: [Tile]
    var editing: Bool
    @ViewBuilder var content: (Tile) -> Content

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows(), id: \.self) { row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(row, id: \.self) { tile in cell(tile) }
                    if row.count == 1 && !store.settings.isWide(row[0]) {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rows() -> [[Tile]] {
        var out: [[Tile]] = []
        var pending: Tile?
        for t in tiles {
            if store.settings.isWide(t) {
                if let p = pending { out.append([p]); pending = nil }
                out.append([t])
            } else if let p = pending {
                out.append([p, t])
                pending = nil
            } else {
                pending = t
            }
        }
        if let p = pending { out.append([p]) }
        return out
    }

    @ViewBuilder
    private func cell(_ tile: Tile) -> some View {
        if editing {
            content(tile)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                .overlay(alignment: .topLeading) {
                    Button {
                        withAnimation(.snappy) { store.settings.setTile(tile, visible: false, on: page) }
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.title2)
                            .symbolRenderingMode(.palette).foregroundStyle(.white, .red)
                    }
                    .offset(x: -8, y: -8)
                    .accessibilityLabel("Hide \(tile.title)")
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        if store.settings.isGrouped(page) {
                            Menu {
                                ForEach(store.settings.orderedGroups) { g in
                                    Button {
                                        withAnimation(.snappy) { store.settings.setGroup(tile, g) }
                                    } label: {
                                        if store.settings.group(of: tile) == g { Label(store.settings.groupTitle(g), systemImage: "checkmark") } else { Text(store.settings.groupTitle(g)) }
                                    }
                                }
                            } label: {
                                Image(systemName: "folder").font(.caption.weight(.bold)).padding(6)
                                    .background(Color.accentColor, in: Circle()).foregroundStyle(.white)
                            }
                            .accessibilityLabel("Move \(tile.title) to another group")
                        }
                        if tile.canResize {
                            // Wide ↔ half width.
                            Button {
                                withAnimation(.snappy) { store.settings.setWide(tile, !store.settings.isWide(tile)) }
                            } label: {
                                Image(systemName: store.settings.isWide(tile) ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.weight(.bold)).padding(6)
                                    .background(Color.accentColor, in: Circle()).foregroundStyle(.white)
                            }
                            .accessibilityLabel(store.settings.isWide(tile) ? "Make half width" : "Make full width")
                        }
                        Image(systemName: "line.3.horizontal").font(.caption.weight(.bold)).padding(6)
                            .background(.thinMaterial, in: Circle())
                    }
                    .padding(4)
                }
                .contentShape(Rectangle())
                .draggable(tile.rawValue) {
                    Label(tile.title, systemImage: tile.symbol).padding(8).background(.regularMaterial, in: Capsule())
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let dragged = Tile(rawValue: raw) else { return false }
                    withAnimation(.snappy) {
                        // Dropped onto a tile in another group: it joins that group.
                        if store.settings.isGrouped(page) { store.settings.setGroup(dragged, store.settings.group(of: tile)) }
                        store.settings.moveTile(dragged, before: tile, on: page)
                    }
                    return true
                }
        } else {
            content(tile).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// While editing: the hidden tiles, ready to add back.
struct HiddenTilesTray: View {
    @Environment(SettingsStore.self) private var store
    var page: TilePage

    var body: some View {
        let hidden = store.settings.tileHidden(page)
        let s = store.settings
        let groups = s.orderedGroups.filter { g in page.allowed.contains { s.group(of: $0) == g && hidden.contains($0) } }
        VStack(alignment: .leading, spacing: 10) {
            Text("Add tiles").font(.headline)
            if groups.isEmpty { Text("Everything is showing.").font(.caption).foregroundStyle(.secondary) }
            ForEach(groups) { g in
                Text(s.groupTitle(g)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                FlowRow {
                    ForEach(page.allowed.filter { s.group(of: $0) == g && hidden.contains($0) }) { t in
                        Button {
                            withAnimation(.snappy) { store.settings.setTile(t, visible: true, on: page) }
                        } label: {
                            Label(t.title, systemImage: "plus.circle.fill").font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Group heading with a switch menu for the group's tiles; while editing also rename, move and hide the group.
/// Drop a tile on the heading to move it into the group.
struct TileGroupHeader: View {
    @Environment(SettingsStore.self) private var store
    var group: TileGroup
    var page: TilePage
    var editing = false
    @State private var renaming = false
    @State private var name = ""

    var body: some View {
        let s = store.settings
        let hidden = s.isGroupHidden(group)
        HStack(spacing: 8) {
            Text(s.groupTitle(group).uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .strikethrough(hidden)
            if hidden { Text("Hidden").font(.caption2.weight(.semibold)).foregroundStyle(.orange) }
            Spacer()
            if editing {
                Button { withAnimation(.snappy) { store.settings.moveGroup(group, by: -1) } } label: { Image(systemName: "arrow.up") }
                    .accessibilityLabel("Move group up")
                Button { withAnimation(.snappy) { store.settings.moveGroup(group, by: 1) } } label: { Image(systemName: "arrow.down") }
                    .accessibilityLabel("Move group down")
            }
            Menu {
                if editing {
                    Button("Rename group", systemImage: "pencil") { name = s.groupTitle(group); renaming = true }
                    Button(hidden ? "Show group" : "Hide group", systemImage: hidden ? "eye" : "eye.slash") {
                        withAnimation(.snappy) { store.settings.setGroupHidden(group, !hidden) }
                    }
                    Divider()
                }
                ForEach(page.allowed.filter { s.group(of: $0) == group }) { t in
                    Toggle(isOn: Binding(get: { !store.settings.tileHidden(page).contains(t) },
                                         set: { store.settings.setTile(t, visible: $0, on: page) })) {
                        Label(t.title, systemImage: t.symbol)
                    }
                }
            } label: {
                Image(systemName: editing ? "ellipsis.circle" : "switch.2").font(.subheadline).padding(4)
            }
            .accessibilityLabel("Choose \(s.groupTitle(group)) tiles")
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, editing ? 6 : 0)
        .padding(.top, 6)
        .background(editing ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { items, _ in
            guard editing, let raw = items.first, let dragged = Tile(rawValue: raw) else { return false }
            withAnimation(.snappy) { store.settings.setGroup(dragged, group) }
            return true
        }
        .alert("Group name", isPresented: $renaming) {
            TextField(group.title, text: $name)
            Button("Save") { store.settings.groupNames[group.rawValue] = name.trimmingCharacters(in: .whitespaces) }
            Button("Default name") { store.settings.groupNames[group.rawValue] = nil }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Tiles laid out under group headings, in your group order. While editing, empty groups show so tiles can be dropped in.
struct GroupedTiles<Content: View>: View {
    @Environment(SettingsStore.self) private var store
    var page: TilePage
    var tiles: [Tile]
    var editing: Bool
    @ViewBuilder var content: (Tile) -> Content

    var body: some View {
        let s = store.settings
        ForEach(s.orderedGroups) { group in
            let inGroup = tiles.filter { s.group(of: $0) == group }
            let hidden = s.isGroupHidden(group)
            if editing || (!inGroup.isEmpty && !hidden) {
                TileGroupHeader(group: group, page: page, editing: editing)
                if inGroup.isEmpty {
                    Text("Drag a tile onto this heading to move it here.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                } else {
                    TileGrid(page: page, tiles: inGroup, editing: editing, content: content)
                        .opacity(hidden ? 0.4 : 1)
                }
            }
        }
    }
}

/// Simple wrapping row for chips.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

/// Switch tiles on and off by group, drag to reorder, pick the date style and screen-awake setting.
struct TileCustomiseView: View {
    @Environment(SettingsStore.self) private var store
    var page: TilePage

    var body: some View {
        let order = store.settings.tileOrder(page)
        let hidden = store.settings.tileHidden(page)
        List {
            let s = store.settings
            let groups: [TileGroup?] = s.isGrouped(page) ? s.orderedGroups.filter { g in order.contains { s.group(of: $0) == g } } : [nil]
            ForEach(groups, id: \.self) { group in
                Section {
                    let items = order.filter { group == nil || s.group(of: $0) == group }
                    ForEach(items) { t in
                        HStack {
                            Toggle(isOn: Binding(get: { !hidden.contains(t) }, set: { store.settings.setTile(t, visible: $0, on: page) })) {
                                Label(t.title, systemImage: t.symbol)
                            }
                            if let group {
                                Menu {
                                    ForEach(s.orderedGroups) { g in
                                        Button(s.groupTitle(g)) { store.settings.setGroup(t, g) }.disabled(g == group)
                                    }
                                } label: { Image(systemName: "folder") }
                                .accessibilityLabel("Move to group")
                            }
                            if t.canResize {
                                Picker("Size", selection: Binding(get: { store.settings.isWide(t) }, set: { store.settings.setWide(t, $0) })) {
                                    Text("Half").tag(false)
                                    Text("Full").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 110)
                                .labelsHidden()
                            }
                        }
                    }
                    .onMove { from, to in
                        var list = items
                        list.move(fromOffsets: from, toOffset: to)
                        // Write the group's new order back into the whole page order.
                        var full = order
                        let slots = full.indices.filter { items.contains(full[$0]) }
                        for (slot, tile) in zip(slots, list) { full[slot] = tile }
                        store.settings.setTiles(page, order: full, hidden: hidden)
                    }
                } header: {
                    Text(group.map { s.groupTitle($0) } ?? "Tiles")
                }
            }
            if page == .today || s.isGrouped(page) {
                Section {
                    if page == .today {
                        Toggle("Show Today in groups", isOn: Binding(get: { store.settings.todayGrouped }, set: { store.settings.todayGrouped = $0 }))
                    }
                    if s.isGrouped(page) {
                        NavigationLink { TileGroupsEditor() } label: { Label("Groups: order, names, hide", systemImage: "folder") }
                    }
                } header: {
                    Text("Groups")
                } footer: {
                    Text("Move a tile to another group with the folder button, or in Edit layout drag it onto a tile or heading in another group.")
                }
            }
            if page == .today {
                Section {
                    Picker("Date style", selection: Binding(get: { store.settings.dateStyle }, set: { store.settings.dateStyle = $0 })) {
                        ForEach(AppSettings.dateStyles, id: \.id) { Text($0.title).tag($0.id) }
                    }
                    Picker("Keep the screen on", selection: Binding(get: { store.settings.keepScreenOn }, set: { store.settings.keepScreenOn = $0 })) {
                        Text("While on a shift").tag("shift")
                        Text("Always (app open)").tag("always")
                        Text("Never").tag("never")
                    }
                } footer: {
                    Text("Keeping the screen on stops the iPhone dimming and locking while HGV Hours is open. Uses more battery — keep the phone on charge in the cab.")
                }
            }
            Section {
                Button("Reset to default layout") {
                    store.settings.setTiles(page, order: [], hidden: [])
                    if page == .today { store.settings.todayOrder = [] }
                    for t in page.allowed { store.settings.tileGroups[t.rawValue] = nil; store.settings.tileSizes[t.rawValue] = nil }
                }
                Button("Reset groups") {
                    store.settings.groupOrder = []; store.settings.groupsHidden = []; store.settings.groupNames = [:]
                    store.settings.tileGroups = [:]
                }
            } footer: {
                Text("Tip: on the \(page == .today ? "Today" : "Hours") page, tap Edit to drag tiles around and hide or add them right there.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(page == .today ? "Customise Today" : "Customise Hours")
    }
}


/// Reorder, rename and hide the tile groups (shared by Today and Hours).
struct TileGroupsEditor: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(store.settings.orderedGroups) { g in
                    HStack {
                        Toggle(isOn: Binding(get: { !store.settings.isGroupHidden(g) }, set: { store.settings.setGroupHidden(g, !$0) })) {
                            TextField(g.title, text: Binding(get: { store.settings.groupNames[g.rawValue] ?? "" },
                                                             set: { store.settings.groupNames[g.rawValue] = $0.isEmpty ? nil : $0 }))
                        }
                    }
                }
                .onMove { from, to in
                    var order = store.settings.orderedGroups
                    order.move(fromOffsets: from, toOffset: to)
                    store.settings.groupOrder = order.map(\.rawValue)
                }
            } footer: {
                Text("Drag to reorder. Type to rename (leave empty for the default name). Switch off to hide a whole group.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Groups")
    }
}
