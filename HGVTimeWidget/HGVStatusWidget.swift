import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    var date: Date
    var dashboard: Dashboard?
}

/// Reads the dashboard the app shared and projects the countdowns forward.
struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        var d = Dashboard()
        d.hasData = true
        d.onShift = true
        d.kind = .drive
        d.driveLeft = 3 * 3600 + 20 * 60
        d.workLeft = 4 * 3600
        d.breakDueIn = d.driveLeft
        d.restBy = .now.addingTimeInterval(8 * 3600)
        d.earnedShift = 96.5
        d.earnedWeek = 412
        return StatusEntry(date: .now, dashboard: d)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(SharedStore.load().map { StatusEntry(date: .now, dashboard: $0) } ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let d = SharedStore.load()
        let now = Date.now
        // One entry every 5 minutes for 3 hours; the app refreshes the timeline whenever anything changes.
        let entries = (0..<36).map { StatusEntry(date: now.addingTimeInterval(Double($0) * 300), dashboard: d) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3 * 3600))))
    }
}

enum WFormat {
    static func hm(_ t: TimeInterval) -> String {
        let m = Int((max(0, t) / 60).rounded(.down))
        return String(format: "%dh%02d", m / 60, m % 60)
    }
    static func money(_ v: Double, _ symbol: String) -> String { String(format: "%@%.2f", symbol, v) }
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
}

private extension Dashboard {
    var tint: Color {
        switch restTypeRaw {
        case "weekly": .indigo
        case "daily": .teal
        default: hasData ? kind.color : .gray
        }
    }
    var symbol: String {
        switch restTypeRaw {
        case "weekly": "house.fill"
        case "daily": "moon.zzz.fill"
        case "break": "cup.and.saucer.fill"
        default: hasData ? kind.symbol : "moon.zzz.fill"
        }
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatusEntry

    var body: some View {
        if let d = entry.dashboard {
            switch family {
            case .accessoryInline: inline(d)
            case .accessoryCircular: circular(d)
            case .accessoryRectangular: rectangular(d)
            case .systemMedium: medium(d)
            case .systemLarge: large(d, wide: false)
            case .systemExtraLarge: large(d, wide: true)
            default: small(d)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "truck.box.fill").font(.title2)
                Text("Open HGV Hours").font(.caption)
            }
        }
    }

    // MARK: Lock Screen

    private func inline(_ d: Dashboard) -> some View {
        if d.onShift {
            Label("Drive \(WFormat.hm(d.driveLeft(at: entry.date))) · Work \(WFormat.hm(d.workLeft(at: entry.date)))", systemImage: "steeringwheel")
        } else {
            Label(d.statusTitle, systemImage: d.symbol)
        }
    }

    private func circular(_ d: Dashboard) -> some View {
        let left = d.driveLeft(at: entry.date)
        return Gauge(value: d.onShift ? min(left / (4.5 * 3600), 1) : 0) {
            Image(systemName: "steeringwheel")
        } currentValueLabel: {
            Text(d.onShift ? WFormat.hm(left) : "—").font(.system(size: 11, weight: .bold).monospacedDigit())
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    /// Lock Screen: status, live timer, both countdowns with bars, and the next break / rest deadline.
    private func rectangular(_ d: Dashboard) -> some View {
        let drive = d.driveLeft(at: entry.date)
        let work = d.workLeft(at: entry.date)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: d.symbol)
                Text(d.statusTitle).font(.caption.weight(.bold)).lineLimit(1)
                Spacer(minLength: 2)
                if d.hasData { Text(d.since, style: .timer).font(.caption2.monospacedDigit()).multilineTextAlignment(.trailing).frame(maxWidth: 52) }
            }
            .widgetAccentable()
            if d.onShift {
                HStack(spacing: 6) {
                    miniBar("steeringwheel", WFormat.hm(drive), drive / (4.5 * 3600))
                    miniBar("briefcase.fill", WFormat.hm(work), work / (6 * 3600))
                }
                Text([d.breakBy.map { "Break \(WFormat.time($0))" }, d.restBy.map { "Rest by \(WFormat.time($0))" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
            } else if d.hasData {
                let target: TimeInterval = d.restTypeRaw == "weekly" ? 45 * 3600 : 11 * 3600
                Text("Resting \(WFormat.hm(d.restLength + entry.date.timeIntervalSince(d.generatedAt)))").font(.caption.monospacedDigit())
                Text("Full rest \(WFormat.time(d.since.addingTimeInterval(target)))\(d.nextStart.map { " · start \(WFormat.time($0))" } ?? "")")
                    .font(.caption2.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
            } else {
                Text("Tap to start your shift").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniBar(_ symbol: String, _ value: String, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 9))
                Text(value).font(.caption.weight(.bold).monospacedDigit())
            }
            ProgressView(value: min(max(fraction, 0), 1)).progressViewStyle(.linear).frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Home Screen

    private func small(_ d: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: d.symbol).foregroundStyle(d.tint)
                Text(d.statusTitle).font(.caption.weight(.bold)).lineLimit(1)
            }
            if d.hasData {
                Text(d.since, style: .timer).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            if d.onShift {
                Text("Driving left").font(.caption2).foregroundStyle(.secondary)
                Text(WFormat.hm(d.driveLeft(at: entry.date)))
                    .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(d.driveLeft(at: entry.date) < 1800 ? .orange : .primary)
                Text("Work \(WFormat.hm(d.workLeft(at: entry.date)))").font(.caption2.monospacedDigit())
            } else {
                Text(WFormat.money(d.earnedWeek, d.currency)).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(.green)
                Text("this week").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ d: Dashboard) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(d.statusTitle, systemImage: d.symbol).font(.headline).foregroundStyle(d.tint).lineLimit(1)
                if d.hasData {
                    Text(d.since, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                Text(WFormat.money(d.earnedShift, d.currency)).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(.green)
                Text("today · \(WFormat.money(d.earnedWeek, d.currency)) week").font(.caption2).foregroundStyle(.secondary)
                Label(d.cardInserted ? "Card in" : "No card", systemImage: "creditcard.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(d.cardInserted ? .green : .red)
                if d.vehicleHeight > 0 {
                    Text(String(format: "Height %.2f m", d.vehicleHeight)).font(.caption2.weight(.bold)).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if d.onShift {
                VStack(alignment: .leading, spacing: 6) {
                    row("Drive left", WFormat.hm(d.driveLeft(at: entry.date)), .blue)
                    row("Work left", WFormat.hm(d.workLeft(at: entry.date)), .orange)
                    row("Break in", WFormat.hm(d.breakDueIn(at: entry.date)), .green)
                    if let restBy = d.restBy { row("Rest by", WFormat.time(restBy), .teal) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if d.hasData {
                VStack(alignment: .leading, spacing: 6) {
                    let target: TimeInterval = d.restTypeRaw == "weekly" ? 45 * 3600 : 11 * 3600
                    row("Resting", WFormat.hm(d.restLength + entry.date.timeIntervalSince(d.generatedAt)), d.tint)
                    row("Full rest at", WFormat.time(d.since.addingTimeInterval(target)), d.tint)
                    row("Week driving", WFormat.hm(d.weeklyDriving), .blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Large / extra-large: everything at a glance.
    private func large(_ d: Dashboard, wide: Bool) -> some View {
        let drive = d.driveLeft(at: entry.date)
        let work = d.workLeft(at: entry.date)
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .leading), count: wide ? 4 : 3)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(d.statusTitle, systemImage: d.symbol).font(.headline).foregroundStyle(d.tint)
                if d.hasData { Text(d.since, style: .timer).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
                Spacer()
                Label(d.cardInserted ? "Card in" : "No card", systemImage: "creditcard.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(d.cardInserted ? .green : .red)
            }
            if d.onShift {
                HStack(spacing: 14) {
                    ring("Driving left", WFormat.hm(drive), drive / (4.5 * 3600), .blue)
                    ring("Working left", WFormat.hm(work), work / (6 * 3600), .orange)
                    if wide, let restBy = d.restBy {
                        ring("Rest by", WFormat.time(restBy), max(0, restBy.timeIntervalSince(entry.date)) / (13 * 3600), .teal)
                    }
                }
            } else if d.hasData {
                let target: TimeInterval = d.restTypeRaw == "weekly" ? 45 * 3600 : 11 * 3600
                let rested = d.restLength + entry.date.timeIntervalSince(d.generatedAt)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resting \(WFormat.hm(rested)) of \(WFormat.hm(target))").font(.title3.weight(.bold).monospacedDigit())
                    ProgressView(value: min(rested / target, 1)).tint(d.tint)
                    Text("Full rest at \(WFormat.time(d.since.addingTimeInterval(target)))").font(.caption).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: cols, alignment: .leading, spacing: 10) {
                if d.onShift {
                    row("Break in", WFormat.hm(d.breakDueIn(at: entry.date)), .green)
                    if let b = d.breakBy { row("Break by", "\(WFormat.time(b)) · \(Int(d.breakLength / 60))m", .green) }
                    if let restBy = d.restBy { row("Rest by", WFormat.time(restBy), .teal) }
                    row("Driven today", "\(WFormat.hm(d.dailyDriving))/\(WFormat.hm(d.dailyDrivingLimit))", .blue)
                    row("Shift work", WFormat.hm(d.shiftWorking), .orange)
                }
                if let next = d.nextStart { row("Next start", WFormat.time(next), .indigo) }
                if let w = d.weeklyRestBy { row("Weekly rest by", w.formatted(.dateTime.weekday(.abbreviated).hour().minute()), .indigo) }
                row("Week driving", "\(WFormat.hm(d.weeklyDriving))/56h", .blue)
                row("Week working", "\(WFormat.hm(d.weeklyWorking))/60h", .orange)
                row("10h days left", "\(d.tenHourDaysLeft) of 2", .blue)
                row("9h rests left", "\(d.reducedRestsLeft) of 3", .teal)
                row("Earned today", WFormat.money(d.earnedShift, d.currency), .green)
                row("This week", WFormat.money(d.earnedWeek, d.currency), .green)
                if d.vehicleHeight > 0 {
                    let inches = Int((d.vehicleHeight / 0.0254).rounded())
                    row("Height", "\(inches / 12)′\(inches % 12)″ · \(String(format: "%.2f m", d.vehicleHeight))", .red)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func ring(_ title: String, _ value: String, _ fraction: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 8)
                Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value).font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit()).minimumScaleFactor(0.6).padding(6)
            }
            .frame(width: 78, height: 78)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(color)
        }
    }
}

struct HGVStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HGVStatusWidget", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("HGV Hours")
        .description("Driving and working time left, rest deadline and earnings.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
