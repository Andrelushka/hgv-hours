import AppIntents
import SwiftUI
import WidgetKit

/// Something a widget block can show.
enum WidgetMetric: String, AppEnum {
    case driveLeft, workLeft, driveToday, breakDue, restBy, earnedToday, earnedWeek, weekDriving, weekWorking, card, height, status

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Information"
    static var caseDisplayRepresentations: [WidgetMetric: DisplayRepresentation] = [
        .driveLeft: "Driving till break (4h30)",
        .workLeft: "Working till break (6h)",
        .driveToday: "Driving left today",
        .breakDue: "Break due in",
        .restBy: "Start rest by",
        .earnedToday: "Earned today",
        .earnedWeek: "Earned this week",
        .weekDriving: "Driving this week",
        .weekWorking: "Working this week",
        .card: "Driver card",
        .height: "Vehicle height",
        .status: "Current activity"
    ]
}

struct MetricValue {
    var title: String
    var value: String
    var symbol: String
    var color: Color
    /// 0…1 for a gauge, nil for none.
    var fraction: Double?
}

extension WidgetMetric {
    func value(_ d: Dashboard, at date: Date) -> MetricValue {
        switch self {
        case .driveLeft:
            let v = d.driveLeft(at: date)
            return MetricValue(title: "Drive till break", value: d.onShift ? WFormat.hm(v) : "—", symbol: "steeringwheel",
                               color: v < 1800 && d.onShift ? .orange : .blue, fraction: d.onShift ? v / (4.5 * 3600) : nil)
        case .workLeft:
            let v = d.workLeft(at: date)
            return MetricValue(title: "Work till break", value: d.onShift ? WFormat.hm(v) : "—", symbol: "briefcase.fill",
                               color: v < 1800 && d.onShift ? .orange : .orange, fraction: d.onShift ? v / (6 * 3600) : nil)
        case .driveToday:
            let v = d.driveLeftToday(at: date)
            return MetricValue(title: "Drive today", value: d.onShift ? WFormat.hm(v) : "—", symbol: "road.lanes",
                               color: .indigo, fraction: d.onShift ? v / max(1, d.dailyDrivingLimit) : nil)
        case .breakDue:
            let v = d.breakDueIn(at: date)
            return MetricValue(title: "Break in", value: d.onShift ? WFormat.hm(v) : "—", symbol: "cup.and.saucer.fill",
                               color: .green, fraction: d.onShift ? v / (4.5 * 3600) : nil)
        case .restBy:
            return MetricValue(title: "Rest by", value: d.restBy.map(WFormat.time) ?? "—", symbol: "moon.zzz.fill", color: .teal, fraction: nil)
        case .earnedToday:
            return MetricValue(title: "Today", value: WFormat.money(d.earnedShift, d.currency), symbol: "sterlingsign.circle.fill", color: .green, fraction: nil)
        case .earnedWeek:
            return MetricValue(title: "This week", value: WFormat.money(d.earnedWeek, d.currency), symbol: "sterlingsign.circle", color: .green, fraction: nil)
        case .weekDriving:
            return MetricValue(title: "Week driving", value: WFormat.hm(d.weeklyDriving), symbol: "calendar", color: .blue,
                               fraction: d.weeklyDriving / (56 * 3600))
        case .weekWorking:
            return MetricValue(title: "Week working", value: WFormat.hm(d.weeklyWorking), symbol: "briefcase", color: .orange,
                               fraction: d.weeklyWorking / (60 * 3600))
        case .card:
            return MetricValue(title: "Card", value: d.cardInserted ? "In" : "Out", symbol: "creditcard.fill",
                               color: d.cardInserted ? .green : .red, fraction: nil)
        case .height:
            let inches = Int((d.vehicleHeight / 0.0254).rounded())
            return MetricValue(title: "Height", value: d.vehicleHeight > 0 ? "\(inches / 12)′\(inches % 12)″" : "—",
                               symbol: "arrow.up.and.down", color: .red, fraction: nil)
        case .status:
            return MetricValue(title: "Now", value: d.statusTitle, symbol: d.kind.symbol, color: d.kind.color, fraction: nil)
        }
    }
}

extension Dashboard {
    /// Example data for the widget gallery.
    static var widgetSample: Dashboard {
        var d = Dashboard()
        d.hasData = true
        d.onShift = true
        d.kind = .drive
        d.driveLeft = 3 * 3600 + 20 * 60
        d.workLeft = 4 * 3600
        d.breakDueIn = d.driveLeft
        d.driveLeftToday = 6 * 3600 + 40 * 60
        d.dailyDrivingLimit = 10 * 3600
        d.restBy = .now.addingTimeInterval(8 * 3600)
        d.earnedShift = 96.5
        d.earnedWeek = 412
        d.weeklyDriving = 21 * 3600
        d.weeklyWorking = 30 * 3600
        d.cardInserted = true
        d.vehicleHeight = 4.95
        return d
    }
}

// MARK: Configuration

struct CountdownConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Countdown"
    static var description = IntentDescription("Show one number, big.")
    @Parameter(title: "Show", default: .driveLeft) var metric: WidgetMetric
}

struct DashboardConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Dashboard"
    static var description = IntentDescription("Choose what each block shows.")
    @Parameter(title: "Block 1", default: .driveLeft) var m1: WidgetMetric
    @Parameter(title: "Block 2", default: .workLeft) var m2: WidgetMetric
    @Parameter(title: "Block 3", default: .restBy) var m3: WidgetMetric
    @Parameter(title: "Block 4", default: .earnedToday) var m4: WidgetMetric
    @Parameter(title: "Block 5 (large)", default: .weekDriving) var m5: WidgetMetric
    @Parameter(title: "Block 6 (large)", default: .card) var m6: WidgetMetric
}

struct ConfigEntry<C: WidgetConfigurationIntent>: TimelineEntry {
    var date: Date
    var dashboard: Dashboard?
    var config: C
}

struct ConfigProvider<C: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ConfigEntry<C> {
        ConfigEntry(date: .now, dashboard: .widgetSample, config: C())
    }

    func snapshot(for configuration: C, in context: Context) async -> ConfigEntry<C> {
        ConfigEntry(date: .now, dashboard: SharedStore.load() ?? placeholder(in: context).dashboard, config: configuration)
    }

    func timeline(for configuration: C, in context: Context) async -> Timeline<ConfigEntry<C>> {
        let d = SharedStore.load()
        let now = Date.now
        let entries = (0..<36).map { ConfigEntry(date: now.addingTimeInterval(Double($0) * 300), dashboard: d, config: configuration) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(3 * 3600)))
    }
}

// MARK: Views

struct BlockView: View {
    var v: MetricValue
    var big = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(v.title, systemImage: v.symbol).font(.caption2.weight(.semibold)).foregroundStyle(v.color).lineLimit(1)
            Text(v.value)
                .font(big ? .system(.title, design: .rounded).weight(.bold).monospacedDigit() : .headline.monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
            if let f = v.fraction {
                ProgressView(value: min(max(f, 0), 1)).tint(v.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ConfigEntry<CountdownConfig>

    var body: some View {
        if let d = entry.dashboard {
            let v = entry.config.metric.value(d, at: entry.date)
            switch family {
            case .accessoryCircular:
                Gauge(value: min(max(v.fraction ?? 1, 0), 1)) { Image(systemName: v.symbol) } currentValueLabel: {
                    Text(v.value).font(.system(size: 11, weight: .bold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            case .accessoryInline:
                Label("\(v.title) \(v.value)", systemImage: v.symbol)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label(v.title, systemImage: v.symbol).font(.caption).widgetAccentable()
                    Text(v.value).font(.title2.weight(.bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                    if let f = v.fraction { ProgressView(value: min(max(f, 0), 1)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium, .systemLarge, .systemExtraLarge:
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(v.title, systemImage: v.symbol).font(.headline).foregroundStyle(v.color)
                        Text(v.value)
                            .font(.system(size: family == .systemMedium ? 44 : 64, weight: .bold, design: .rounded).monospacedDigit())
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Spacer(minLength: 0)
                        Label(d.statusTitle, systemImage: d.kind.symbol).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let f = v.fraction {
                        Gauge(value: min(max(f, 0), 1)) { EmptyView() }
                            .gaugeStyle(.accessoryCircularCapacity)
                            .tint(v.color)
                            .scaleEffect(family == .systemMedium ? 1.4 : 2)
                            .frame(width: family == .systemMedium ? 90 : 140)
                    }
                }
            default:
                VStack(alignment: .leading) {
                    BlockView(v: v, big: true)
                    Spacer(minLength: 0)
                    Text(d.statusTitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Open HGV Hours").font(.caption)
        }
    }
}

struct DashboardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ConfigEntry<DashboardConfig>

    var body: some View {
        if let d = entry.dashboard {
            let c = entry.config
            let big = family == .systemLarge || family == .systemExtraLarge
            let metrics: [WidgetMetric] = switch family {
            case .systemSmall, .accessoryRectangular: [c.m1, c.m2]
            case .systemLarge, .systemExtraLarge: [c.m1, c.m2, c.m3, c.m4, c.m5, c.m6]
            default: [c.m1, c.m2, c.m3, c.m4]
            }
            switch family {
            case .accessoryInline:
                let v = c.m1.value(d, at: entry.date)
                Label("\(v.title) \(v.value)", systemImage: v.symbol)
            case .accessoryCircular:
                let v = c.m1.value(d, at: entry.date)
                Gauge(value: min(max(v.fraction ?? 1, 0), 1)) { Image(systemName: v.symbol) } currentValueLabel: {
                    Text(v.value).font(.system(size: 11, weight: .bold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, m in
                        let v = m.value(d, at: entry.date)
                        VStack(alignment: .leading, spacing: 1) {
                            Label(v.title, systemImage: v.symbol).font(.caption2).lineLimit(1).widgetAccentable()
                            Text(v.value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                            if let f = v.fraction { ProgressView(value: min(max(f, 0), 1)) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            default:
            VStack(alignment: .leading, spacing: 8) {
                if big {
                    HStack {
                        Label(d.statusTitle, systemImage: d.kind.symbol).font(.headline).foregroundStyle(d.kind.color)
                        Spacer()
                        if d.hasData { Text(d.since, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: family == .systemExtraLarge ? 3 : (family == .systemSmall ? 1 : 2)),
                          spacing: big ? 14 : 8) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, m in
                        BlockView(v: m.value(d, at: entry.date), big: big)
                    }
                }
                Spacer(minLength: 0)
            }
            }
        } else {
            Text("Open HGV Hours").font(.caption)
        }
    }
}

struct HGVCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HGVCountdownWidget", intent: CountdownConfig.self, provider: ConfigProvider<CountdownConfig>()) { entry in
            CountdownWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("HGV Countdown")
        .description("One number of your choice: driving left, rest by, earnings…")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct HGVDashboardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HGVDashboardWidget", intent: DashboardConfig.self, provider: ConfigProvider<DashboardConfig>()) { entry in
            DashboardWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("HGV Dashboard")
        .description("Pick what each block shows. Long-press the widget → Edit Widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
