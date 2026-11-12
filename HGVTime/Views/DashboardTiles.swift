import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Every block that can appear on the Today and Hours pages.
enum Tile: String, CaseIterable, Identifiable {
    // Today
    case date, card, expiry, status, buttons, inCab, warnings, earnings, nightOut, job, vehicle, mileage, checks
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
        case .date, .card, .expiry, .status, .buttons, .inCab, .warnings, .earnings, .job, .vehicle, .mileage, .checks,
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
        case .date, .expiry, .status, .buttons, .inCab, .warnings, .earnings, .job, .vehicle, .mileage, .checks, .navMap, .navTurn,
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
            [.date, .status, .navTurn, .navMap, .navRoad, .navSpeedLimit, .navArrival, .navVoice, .buttons, .driveLeft, .workLeft, .checks, .card, .nightOut, .inCab, .warnings, .expiry, .earnings,
             .job, .vehicle, .mileage, .restBy, .shiftLeft, .breakDue, .drivenToday, .workedToday, .nextBreak,
             .tenHourDays, .fifteenHourDays, .shiftLength]
        case .hours:
            Tile.allCases.filter { ![.today].contains($0.group) }
        }
    }

    /// Shown until the driver changes the layout.
    var defaultVisible: Set<Tile> {
        switch self {
        case .today: [.date, .card, .expiry, .status, .buttons, .navTurn, .navMap, .navArrival, .driveLeft, .workLeft, .checks, .inCab, .warnings, .earnings, .nightOut, .job, .vehicle, .mileage]
        case .hours: Set(allowed)
        }
    }

    /// Hours is shown in groups; Today is one free-order list.
    var grouped: Bool { self == .hours }
}

extension AppSettings {
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
                    if row.count == 1 && !row[0].isWide {
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
            if t.isWide {
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
                    Image(systemName: "line.3.horizontal").font(.caption.weight(.bold)).padding(6)
                        .background(.thinMaterial, in: Circle()).padding(4)
                }
                .contentShape(Rectangle())
                .draggable(tile.rawValue) {
                    Label(tile.title, systemImage: tile.symbol).padding(8).background(.regularMaterial, in: Capsule())
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let dragged = Tile(rawValue: raw) else { return false }
                    withAnimation(.snappy) { store.settings.moveTile(dragged, before: tile, on: page) }
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
        let groups = TileGroup.allCases.filter { g in page.allowed.contains { $0.group == g && hidden.contains($0) } }
        VStack(alignment: .leading, spacing: 10) {
            Text("Add tiles").font(.headline)
            if groups.isEmpty { Text("Everything is showing.").font(.caption).foregroundStyle(.secondary) }
            ForEach(groups) { g in
                Text(g.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                FlowRow {
                    ForEach(page.allowed.filter { $0.group == g && hidden.contains($0) }) { t in
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

/// Group heading with a switch menu for the group's tiles.
struct TileGroupHeader: View {
    @Environment(SettingsStore.self) private var store
    var group: TileGroup
    var page: TilePage

    var body: some View {
        HStack {
            Text(group.title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(page.allowed.filter { $0.group == group }) { t in
                    Toggle(isOn: Binding(get: { !store.settings.tileHidden(page).contains(t) },
                                         set: { store.settings.setTile(t, visible: $0, on: page) })) {
                        Label(t.title, systemImage: t.symbol)
                    }
                }
            } label: {
                Image(systemName: "switch.2").font(.subheadline).padding(4)
            }
            .accessibilityLabel("Choose \(group.title) tiles")
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
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
            let groups: [TileGroup?] = page.grouped ? TileGroup.allCases.filter { g in order.contains { $0.group == g } } : [nil]
            ForEach(groups, id: \.self) { group in
                Section {
                    let items = order.filter { group == nil || $0.group == group }
                    ForEach(items) { t in
                        Toggle(isOn: Binding(get: { !hidden.contains(t) }, set: { store.settings.setTile(t, visible: $0, on: page) })) {
                            Label(t.title, systemImage: t.symbol)
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
                    Text(group?.title ?? "Tiles")
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
                }
            } footer: {
                Text("Tip: on the \(page == .today ? "Today" : "Hours") page, tap Edit to drag tiles around and hide or add them right there.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(page == .today ? "Customise Today" : "Customise Hours")
    }
}
