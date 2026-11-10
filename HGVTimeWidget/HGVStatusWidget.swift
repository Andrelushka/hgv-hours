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

    private func rectangular(_ d: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(d.statusTitle, systemImage: d.symbol).font(.headline).widgetAccentable()
            if d.onShift {
                Text("Drive \(WFormat.hm(d.driveLeft(at: entry.date))) · Work \(WFormat.hm(d.workLeft(at: entry.date)))")
                    .font(.caption.monospacedDigit())
                if let restBy = d.restBy { Text("Rest by \(WFormat.time(restBy))").font(.caption2) }
            } else if d.hasData {
                Text("Since \(WFormat.time(d.since))").font(.caption)
            }
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
