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

    @State private var period: EarningsPeriod = .week
    @State private var offset = 0

    static let columns = ["Date", "Start", "Finish", "Spread", "Drive", "Work", "POA", "Breaks", "Working",
                          "Distance", "Fuel", "AdBlue", "Night out", "Pay", "Infr.", "Overspeed"]

    var body: some View {
        let cal = Calendar.hgv
        let settings = store.settings
        let component: Calendar.Component = period == .week ? .weekOfYear : (period == .month ? .month : .year)
        let anchor = cal.date(byAdding: component, value: offset, to: .now) ?? .now
        let (start, end) = Earnings.interval(period, containing: anchor)
        let rows = makeRows(from: start, to: end, settings: settings)
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
            }
            .padding()
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        ForEach(Self.columns, id: \.self) { Text($0).font(.caption.weight(.bold)).foregroundStyle(.secondary) }
                    }
                    Divider()
                    ForEach(rows.indices, id: \.self) { i in
                        GridRow {
                            ForEach(rows[i].indices, id: \.self) { c in
                                Text(rows[i][c])
                                    .font(.caption.monospacedDigit())
                                    .fontWeight(i == rows.count - 1 ? .bold : .regular)
                                    .foregroundStyle(c == 14 && rows[i][c] != "0" && rows[i][c] != "" ? .red : .primary)
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
            ShareLink(item: csvFile(rows: rows, start: start)) { Image(systemName: "square.and.arrow.up") }
        }
    }

    private func title(start: Date) -> String {
        switch period {
        case .week: "w/c \(Fmt.day(start))"
        case .month: start.formatted(.dateTime.month(.wide).year())
        case .year: start.formatted(.dateTime.year())
        }
    }

    /// One row per day that has anything recorded, then a totals row.
    private func makeRows(from start: Date, to end: Date, settings: AppSettings) -> [[String]] {
        let cal = Calendar.hgv
        let miles = settings.useMiles
        let analysis = RulesEngine.analyze(entries.map(\.snapshot), now: .now, config: settings.ruleConfig)
        var rows: [[String]] = []
        var tot = (spread: 0.0, drive: 0.0, work: 0.0, poa: 0.0, breaks: 0.0, working: 0.0, km: 0.0, fuel: 0.0, adblue: 0.0, nights: 0, pay: 0.0, infr: 0, speed: 0)
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
            guard !dayEntries.isEmpty || record != nil || uses.contains(where: { Calendar.hgv.isDate($0.start, inSameDayAs: day) }) || !res.isEmpty || !speeds.isEmpty || night else { continue }
            let t = DayTotals.compute(dayEntries, day: day)
            let dayStartU = Calendar.hgv.startOfDay(for: day)
            let dayUses = uses.filter { $0.start < dayStartU.addingTimeInterval(86_400) && ($0.end ?? .now) > dayStartU }
            let km: Double? = dayUses.isEmpty ? record?.distanceKm : dayUses.reduce(0) { $0 + $1.distanceKm }
            let first = shifts.first, last = shifts.last
            let spread = shifts.reduce(0.0) { $0 + $1.period.end.timeIntervalSince($1.period.start) }
            let fuel = res.filter { $0.kind == .diesel || $0.kind == .petrol }.reduce(0) { $0 + $1.quantity }
            let adblue = res.filter { $0.kind == .adblue }.reduce(0) { $0 + $1.quantity }
            let pay = PayCalculator.calculate(shifts: shifts, nightOuts: night ? 1 : 0, settings: settings.pay, salaryDays: 1).total
            let infr = shifts.flatMap(\.issues).filter { $0.severity == .violation }.count + speeds.filter(\.isInfringement).count
            rows.append([
                day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                first.map { Fmt.time($0.period.start) } ?? "",
                last.map { $0.period.isOpen ? "now" : Fmt.time($0.period.end) } ?? "",
                shifts.isEmpty ? "" : Fmt.hmCompact(spread),
                Fmt.hmCompact(t.driving), Fmt.hmCompact(t.otherWork), Fmt.hmCompact(t.availability),
                Fmt.hmCompact(t.breaks), Fmt.hmCompact(t.working),
                km.map { Fmt.distance($0, miles: miles) + (dayUses.count > 1 ? " (\(dayUses.count) vehicles)" : "") } ?? "",
                fuel > 0 ? String(format: "%g L", fuel) : "",
                adblue > 0 ? String(format: "%g L", adblue) : "",
                night ? "Yes" : "",
                Fmt.money(pay, symbol: settings.pay.currencySymbol),
                "\(infr)",
                speeds.isEmpty ? "" : "\(speeds.count)"
            ])
            tot.spread += spread; tot.drive += t.driving; tot.work += t.otherWork; tot.poa += t.availability
            tot.breaks += t.breaks; tot.working += t.working; tot.km += km ?? 0
            tot.fuel += fuel; tot.adblue += adblue; tot.nights += night ? 1 : 0; tot.pay += pay; tot.infr += infr; tot.speed += speeds.count
        }
        rows.append(["Total", "", "", Fmt.hmCompact(tot.spread), Fmt.hmCompact(tot.drive), Fmt.hmCompact(tot.work),
                     Fmt.hmCompact(tot.poa), Fmt.hmCompact(tot.breaks), Fmt.hmCompact(tot.working),
                     Fmt.distance(tot.km, miles: miles), tot.fuel > 0 ? String(format: "%g L", tot.fuel) : "",
                     tot.adblue > 0 ? String(format: "%g L", tot.adblue) : "", tot.nights > 0 ? "\(tot.nights)" : "",
                     Fmt.money(tot.pay, symbol: settings.pay.currencySymbol), "\(tot.infr)", tot.speed > 0 ? "\(tot.speed)" : ""])
        return rows
    }

    private func csvFile(rows: [[String]], start: Date) -> URL {
        let lines = ([Self.columns] + rows).map { $0.map { $0.contains(",") ? "\"\($0)\"" : $0 }.joined(separator: ",") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HGV-summary-\(Fmt.isoDate(start)).csv")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
