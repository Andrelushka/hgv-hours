import SwiftUI
import SwiftData

/// One table with every day's figures: times, activities, distance, fuel, pay and infringements.
struct SummaryView: View {
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \DayRecord.day) private var records: [DayRecord]
    @Query(sort: \VehicleUse.start) private var uses: [VehicleUse]
    @Query(sort: \ResourceLog.date) private var resources: [ResourceLog]
    @Query(sort: \SpeedEvent.start) private var speedEvents: [SpeedEvent]
    @Query(sort: \NightOut.date) private var nightOuts: [NightOut]
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    @State private var period: EarningsPeriod = .week
    @State private var offset = 0
    @State private var groupBy: GroupBy = .day
    @State private var companyFilter = ""
    @State private var vehicleFilter = ""

    enum GroupBy: String, CaseIterable, Identifiable {
        case day, company, vehicle, trailer, location, weekday, month
        var id: String { rawValue }
        var title: String {
            switch self {
            case .day: "Day"
            case .company: "Company"
            case .vehicle: "Vehicle"
            case .trailer: "Trailer"
            case .location: "Start place"
            case .weekday: "Weekday"
            case .month: "Month"
            }
        }
    }

    static let groupColumns = ["Group", "Days", "Drive", "Work", "POA", "Breaks", "Working", "Distance", "Loaded", "Empty",
                               "Fuel", "Night out", "Pay", "Avg pay/day", "Infr."]

    /// One day's figures plus what it can be grouped by.
    struct DayFacts {
        var day: Date
        var row: [String]
        var company, vehicle, trailer, location: String
        var spread, drive, work, poa, breaks, working, km, loadedKm, emptyKm, fuel, adblue, pay: Double
        var night: Bool
        var infr, speed: Int
    }

    static let columns = ["Date", "Start", "Finish", "Spread", "Drive", "Work", "POA", "Breaks", "Working",
                          "Distance", "Fuel", "AdBlue", "Night out", "Pay", "Infr.", "Overspeed"]

    var body: some View {
        let cal = Calendar.hgv
        let settings = store.settings
        let component: Calendar.Component = period == .week ? .weekOfYear : (period == .month ? .month : .year)
        let anchor = cal.date(byAdding: component, value: offset, to: .now) ?? .now
        let (start, end) = Earnings.interval(period, containing: anchor)
        let facts = dayFacts(from: start, to: end, settings: settings)
        let filtered = facts.filter {
            (companyFilter.isEmpty || $0.company == companyFilter) && (vehicleFilter.isEmpty || $0.vehicle == vehicleFilter)
        }
        let columns = groupBy == .day ? Self.columns : Self.groupColumns
        let rows = groupBy == .day ? dayRows(filtered, settings: settings) : groupedRows(filtered, settings: settings)
        let companies = Array(Set(facts.map(\.company).filter { !$0.isEmpty })).sorted()
        let vehicleNames = Array(Set(facts.map(\.vehicle).filter { !$0.isEmpty })).sorted()
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker("Period", selection: $period) {
                    ForEach(EarningsPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: period) { _, _ in offset = 0 }
                HStack {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(title(start: start)).font(.headline)
                    Spacer()
                    Button { offset += 1 } label: { Image(systemName: "chevron.right") }.disabled(offset >= 0)
                }
                HStack {
                    Menu {
                        Picker("Group by", selection: $groupBy) {
                            ForEach(GroupBy.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label("By \(groupBy.title.lowercased())", systemImage: "square.stack.3d.up").font(.caption.weight(.semibold))
                    }
                    Spacer()
                    Menu {
                        Picker("Company", selection: $companyFilter) {
                            Text("All companies").tag("")
                            ForEach(companies, id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        Label(companyFilter.isEmpty ? "All companies" : companyFilter, systemImage: "building.2").font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    Menu {
                        Picker("Vehicle", selection: $vehicleFilter) {
                            Text("All vehicles").tag("")
                            ForEach(vehicleNames, id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        Label(vehicleFilter.isEmpty ? "All vehicles" : vehicleFilter, systemImage: "truck.box").font(.caption.weight(.semibold)).lineLimit(1)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        ForEach(columns, id: \.self) { Text($0).font(.caption.weight(.bold)).foregroundStyle(.secondary) }
                    }
                    Divider()
                    ForEach(rows.indices, id: \.self) { i in
                        GridRow {
                            ForEach(rows[i].indices, id: \.self) { c in
                                Text(rows[i][c])
                                    .font(.caption.monospacedDigit())
                                    .fontWeight(i == rows.count - 1 ? .bold : .regular)
                                    .foregroundStyle(columns[c].hasPrefix("Infr") && rows[i][c] != "0" && rows[i][c] != "" ? .red : .primary)
                            }
                        }
                        if i == rows.count - 2 { Divider() }
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.topLeading)
        }
        .navigationTitle("Summary")
        .toolbar {
            ShareLink(item: csvFile(columns: columns, rows: rows, start: start)) { Image(systemName: "square.and.arrow.up") }
        }
    }

    private func title(start: Date) -> String {
        switch period {
        case .week: "w/c \(Fmt.day(start))"
        case .month: start.formatted(.dateTime.month(.wide).year())
        case .year: start.formatted(.dateTime.year())
        }
    }

    /// Every day in the period that has anything recorded.
    private func dayFacts(from start: Date, to end: Date, settings: AppSettings) -> [DayFacts] {
        let cal = Calendar.hgv
        let miles = settings.useMiles
        let analysis = RulesEngine.analyze(entries.map(\.snapshot), now: .now, config: settings.ruleConfig)
        let name: (String) -> String = { id in self.vehicles.first { $0.id.uuidString == id }?.displayName ?? "" }
        var out: [DayFacts] = []
        var day = start
        while day < end {
            let next = cal.date(byAdding: .day, value: 1, to: day) ?? end
            defer { day = next }
            let dayEntries = entries.filter { ($0.end ?? .now) > day && $0.start < next }
            let shifts = analysis.shifts.filter { $0.period.start >= day && $0.period.start < next }
            let record = records.first { cal.isDate($0.day, inSameDayAs: day) }
            let res = resources.filter { $0.date >= day && $0.date < next }
            let speeds = speedEvents.filter { $0.start >= day && $0.start < next }
            let night = nightOuts.contains { cal.isDate($0.date, inSameDayAs: day) }
            let dayUses = uses.filter { $0.start < next && ($0.end ?? .now) > day }
            guard !dayEntries.isEmpty || record != nil || !dayUses.isEmpty || !res.isEmpty || !speeds.isEmpty || night else { continue }
            let plan = plans.first { cal.isDate($0.plannedStart, inSameDayAs: day) && !$0.cancelled }
            let t = DayTotals.compute(dayEntries, day: day)
            let km: Double? = dayUses.isEmpty ? record?.distanceKm : dayUses.reduce(0) { $0 + $1.distanceKm }
            let split = VehicleLog.loadSplit(dayUses)
            let first = shifts.first, last = shifts.last
            let spread = shifts.reduce(0.0) { $0 + $1.period.end.timeIntervalSince($1.period.start) }
            let fuel = res.filter { $0.kind == .diesel || $0.kind == .petrol }.reduce(0) { $0 + $1.quantity }
            let adblue = res.filter { $0.kind == .adblue }.reduce(0) { $0 + $1.quantity }
            let pay = PayCalculator.calculate(shifts: shifts, nightOuts: night ? 1 : 0, settings: settings.pay, salaryDays: 1).total
            let infr = shifts.flatMap(\.issues).filter { $0.severity == .violation }.count + speeds.filter(\.isInfringement).count
            let vehicleID = dayUses.first?.vehicleID ?? plan?.vehicleID ?? record?.vehicleID ?? ""
            let trailerID = dayUses.first(where: { !$0.trailerID.isEmpty })?.trailerID ?? plan?.trailerID ?? ""
            let location = plan.map { [$0.startName, $0.startLocation, $0.startPostcode].first { !$0.isEmpty } ?? "" } ?? ""
            let vehicleCount = Set(dayUses.map(\.vehicleID)).count
            let kmText: String = km.map { Fmt.distance($0, miles: miles) + (vehicleCount > 1 ? " (\(vehicleCount) veh.)" : "") } ?? ""
            let row: [String] = [
                day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                first.map { Fmt.time($0.period.start) } ?? "",
                last.map { $0.period.isOpen ? "now" : Fmt.time($0.period.end) } ?? "",
                shifts.isEmpty ? "" : Fmt.hmCompact(spread),
                Fmt.hmCompact(t.driving), Fmt.hmCompact(t.otherWork), Fmt.hmCompact(t.availability),
                Fmt.hmCompact(t.breaks), Fmt.hmCompact(t.working),
                kmText,
                fuel > 0 ? String(format: "%g L", fuel) : "",
                adblue > 0 ? String(format: "%g L", adblue) : "",
                night ? "Yes" : "",
                Fmt.money(pay, symbol: settings.pay.currencySymbol),
                "\(infr)",
                speeds.isEmpty ? "" : "\(speeds.count)"
            ]
            out.append(DayFacts(day: day, row: row, company: plan?.company ?? "", vehicle: name(vehicleID), trailer: name(trailerID),
                                location: location, spread: spread, drive: t.driving, work: t.otherWork, poa: t.availability,
                                breaks: t.breaks, working: t.working, km: km ?? 0, loadedKm: split.loaded, emptyKm: split.empty,
                                fuel: fuel, adblue: adblue, pay: pay, night: night, infr: infr, speed: speeds.count))
        }
        return out
    }

    /// One row per day, newest first, then a totals row.
    private func dayRows(_ facts: [DayFacts], settings: AppSettings) -> [[String]] {
        let miles = settings.useMiles
        var rows = facts.reversed().map(\.row)
        func sum(_ k: KeyPath<DayFacts, Double>) -> Double { facts.reduce(0) { $0 + $1[keyPath: k] } }
        let fuel = sum(\.fuel), adblue = sum(\.adblue), nights = facts.filter(\.night).count, speed = facts.reduce(0) { $0 + $1.speed }
        rows.append(["Total", "", "", Fmt.hmCompact(sum(\.spread)), Fmt.hmCompact(sum(\.drive)), Fmt.hmCompact(sum(\.work)),
                     Fmt.hmCompact(sum(\.poa)), Fmt.hmCompact(sum(\.breaks)), Fmt.hmCompact(sum(\.working)),
                     Fmt.distance(sum(\.km), miles: miles), fuel > 0 ? String(format: "%g L", fuel) : "",
                     adblue > 0 ? String(format: "%g L", adblue) : "", nights > 0 ? "\(nights)" : "",
                     Fmt.money(sum(\.pay), symbol: settings.pay.currencySymbol), "\(facts.reduce(0) { $0 + $1.infr })", speed > 0 ? "\(speed)" : ""])
        return rows
    }

    /// One row per company / vehicle / weekday…, biggest first, then a totals row.
    private func groupedRows(_ facts: [DayFacts], settings: AppSettings) -> [[String]] {
        let miles = settings.useMiles
        let sym = settings.pay.currencySymbol
        let key: (DayFacts) -> String = { f in
            switch groupBy {
            case .day: Fmt.day(f.day)
            case .company: f.company.isEmpty ? "No company" : f.company
            case .vehicle: f.vehicle.isEmpty ? "No vehicle" : f.vehicle
            case .trailer: f.trailer.isEmpty ? "No trailer" : f.trailer
            case .location: f.location.isEmpty ? "Not set" : f.location
            case .weekday: f.day.formatted(.dateTime.weekday(.wide))
            case .month: f.day.formatted(.dateTime.month(.wide).year())
            }
        }
        func line(_ name: String, _ g: [DayFacts]) -> [String] {
            func sum(_ k: KeyPath<DayFacts, Double>) -> Double { g.reduce(0) { $0 + $1[keyPath: k] } }
            let fuel = sum(\.fuel), pay = sum(\.pay), nights = g.filter(\.night).count
            return [name, "\(g.count)", Fmt.hmCompact(sum(\.drive)), Fmt.hmCompact(sum(\.work)), Fmt.hmCompact(sum(\.poa)),
                    Fmt.hmCompact(sum(\.breaks)), Fmt.hmCompact(sum(\.working)), Fmt.distance(sum(\.km), miles: miles),
                    sum(\.loadedKm) > 0 ? Fmt.distance(sum(\.loadedKm), miles: miles) : "",
                    sum(\.emptyKm) > 0 ? Fmt.distance(sum(\.emptyKm), miles: miles) : "",
                    fuel > 0 ? String(format: "%g L", fuel) : "", nights > 0 ? "\(nights)" : "",
                    Fmt.money(pay, symbol: sym), g.isEmpty ? "" : Fmt.money(pay / Double(g.count), symbol: sym),
                    "\(g.reduce(0) { $0 + $1.infr })"]
        }
        let groups = Dictionary(grouping: facts, by: key)
        var rows = groups.sorted { a, b in
            groupBy == .weekday || groupBy == .month
                ? (a.value.first?.day ?? .distantPast) < (b.value.first?.day ?? .distantPast)
                : a.value.reduce(0) { $0 + $1.working } > b.value.reduce(0) { $0 + $1.working }
        }.map { line($0.key, $0.value) }
        rows.append(line("Total", facts))
        return rows
    }

    private func csvFile(columns: [String], rows: [[String]], start: Date) -> URL {
        let lines = ([columns] + rows).map { $0.map { $0.contains(",") ? "\"\($0)\"" : $0 }.joined(separator: ",") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HGV-summary-\(Fmt.isoDate(start)).csv")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
