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
        d.driveLeftToday = 6 * 3600 + 40 * 60
        d.dailyDriving = 3 * 3600 + 20 * 60
        d.dailyDrivingLimit = 10 * 3600
        d.breakBy = .now.addingTimeInterval(3 * 3600 + 20 * 60)
        d.breakLength = 45 * 60
        d.shiftWorking = 4 * 3600
        d.weeklyDriving = 21 * 3600
        d.weeklyWorking = 30 * 3600
        d.cardInserted = true
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
            Label("Break in \(WFormat.hm(d.driveLeft(at: entry.date))) · Work \(WFormat.hm(d.workLeft(at: entry.date)))", systemImage: "steeringwheel")
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

    /// Lock Screen: what you're doing, then the two clocks with plain labels.
    private func rectangular(_ d: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: d.symbol)
                Text(d.statusTitle).font(.caption.weight(.bold)).lineLimit(1)
                Spacer(minLength: 2)
                if d.hasData { Text(d.since, style: .timer).font(.caption2.monospacedDigit()).multilineTextAlignment(.trailing).frame(maxWidth: 52) }
            }
            .widgetAccentable()
            if d.onShift {
                Text("Drive \(WFormat.hm(d.driveLeft(at: entry.date))) till break").font(.caption.weight(.semibold).monospacedDigit())
                Text("Work \(WFormat.hm(d.workLeft(at: entry.date))) · today \(WFormat.hm(d.driveLeftToday(at: entry.date)))")
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

    // MARK: Home Screen

    /// Small: activity, then the driving clock big, working clock underneath.
    private func small(_ d: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            header(d, compact: true)
            Spacer(minLength: 2)
            if d.onShift {
                Text("Driving till break").font(.caption2).foregroundStyle(.secondary)
                clock(d.driveLeft(at: entry.date), ends: d.driveEnds(d.driveLeft), font: .system(.title, design: .rounded))
                    .foregroundStyle(d.driveLeft(at: entry.date) < 1800 ? .orange : .blue)
                Text("Work till break \(WFormat.hm(d.workLeft(at: entry.date)))").font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.orange)
            } else {
                restSummary(d, compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Medium: the two clocks as rings, and three clearly labelled lines.
    private func medium(_ d: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(d, compact: false)
            if d.onShift {
                HStack(spacing: 10) {
                    ring("Driving\ntill break", d.driveLeft(at: entry.date), d.driveEnds(d.driveLeft), of: 4.5 * 3600, .blue, size: 66)
                    ring("Working\ntill break", d.workLeft(at: entry.date), d.workEnds(d.workLeft), of: 6 * 3600, .orange, size: 66)
                    VStack(alignment: .leading, spacing: 5) {
                        line("Driving left today", WFormat.hm(d.driveLeftToday(at: entry.date)), .blue)
                        if let b = d.breakBy { line("Next break", "\(WFormat.time(b)) · \(Int(d.breakLength / 60)) min", .green) }
                        if let r = d.restBy { line("Start rest by", WFormat.time(r), .teal) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                restSummary(d, compact: false)
            }
        }
    }

    /// Large: header, two rings, then "Today" and "This week" in labelled rows.
    private func large(_ d: Dashboard, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(d, compact: false)
            if d.onShift {
                HStack(spacing: 12) {
                    ring("Driving till break", d.driveLeft(at: entry.date), d.driveEnds(d.driveLeft), of: 4.5 * 3600, .blue, size: 92)
                    ring("Working till break", d.workLeft(at: entry.date), d.workEnds(d.workLeft), of: 6 * 3600, .orange, size: 92)
                    if wide {
                        ring("Driving left today", d.driveLeftToday(at: entry.date), d.driveEnds(d.driveLeftToday), of: d.dailyDrivingLimit, .indigo, size: 92)
                    }
                }
                section("Today") {
                    line("Driving left today", "\(WFormat.hm(d.driveLeftToday(at: entry.date))) (\(WFormat.hm(d.dailyDriving)) of \(WFormat.hm(d.dailyDrivingLimit)) driven)", .blue)
                    if let b = d.breakBy { line("Next break", "\(Int(d.breakLength / 60)) min by \(WFormat.time(b))", .green) }
                    if let r = d.restBy { line("Start daily rest by", WFormat.time(r), .teal) }
                    line("Worked this shift", WFormat.hm(d.shiftWorking), .orange)
                }
            } else {
                restSummary(d, compact: false)
            }
            section("This week") {
                line("Driving", "\(WFormat.hm(d.weeklyDriving)) of 56h", .blue)
                line("Working", "\(WFormat.hm(d.weeklyWorking)) of 60h", .orange)
                line("10h days · 9h rests left", "\(d.tenHourDaysLeft) of 2 · \(d.reducedRestsLeft) of 3", .indigo)
                line("Earned", "\(WFormat.money(d.earnedShift, d.currency)) today · \(WFormat.money(d.earnedWeek, d.currency)) week", .green)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Pieces

    private func header(_ d: Dashboard, compact: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: d.symbol).foregroundStyle(d.tint)
            Text(d.statusTitle).font(compact ? .caption.weight(.bold) : .headline).foregroundStyle(d.tint).lineLimit(1)
            if d.hasData && !compact {
                Text(d.since, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            if !compact {
                Image(systemName: "creditcard.fill").font(.caption).foregroundStyle(d.cardInserted ? .green : .red)
                    .accessibilityLabel(d.cardInserted ? "Card in" : "No card")
            }
        }
    }

    @ViewBuilder
    private func restSummary(_ d: Dashboard, compact: Bool) -> some View {
        if d.hasData {
            let target: TimeInterval = d.restTypeRaw == "weekly" ? 45 * 3600 : 11 * 3600
            let rested = d.restLength + entry.date.timeIntervalSince(d.generatedAt)
            VStack(alignment: .leading, spacing: 3) {
                Text("Rested \(WFormat.hm(rested)) of \(WFormat.hm(target))").font(compact ? .caption.weight(.bold) : .headline).monospacedDigit()
                ProgressView(value: min(max(rested / target, 0), 1)).tint(d.tint)
                Text("Full rest at \(WFormat.time(d.since.addingTimeInterval(target)))").font(.caption2).foregroundStyle(.secondary)
                if let next = d.nextStart { Text("Can start from \(WFormat.time(next))").font(.caption2).foregroundStyle(.secondary) }
                if !compact { Text("Week: \(WFormat.hm(d.weeklyDriving)) driven · \(WFormat.money(d.earnedWeek, d.currency))").font(.caption2).foregroundStyle(.secondary) }
            }
        } else {
            Text("Tap to start your shift").font(.caption)
        }
    }

    /// A live countdown when the clock is running, otherwise the value.
    @ViewBuilder
    private func clock(_ value: TimeInterval, ends: Date?, font: Font) -> some View {
        if let ends, ends > entry.date {
            Text(timerInterval: entry.date...ends, countsDown: true).font(font.weight(.bold).monospacedDigit())
        } else {
            Text(WFormat.hm(value)).font(font.weight(.bold).monospacedDigit())
        }
    }

    private func ring(_ title: String, _ value: TimeInterval, _ ends: Date?, of total: TimeInterval, _ color: Color, size: CGFloat) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: size * 0.1)
                Circle().trim(from: 0, to: min(max(value / max(1, total), 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(WFormat.hm(value)).font(.system(size: size * 0.22, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6).padding(4)
            }
            .frame(width: size, height: size)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func line(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Text(value).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
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
        .description("Driving and working time till your next break, driving left today, next break, rest deadline, week totals and earnings.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
