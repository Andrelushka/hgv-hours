import SwiftUI

@main
struct HGVTimeWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
    }
}

enum WFmt {
    static func hm(_ t: TimeInterval) -> String {
        let m = Int((max(0, t) / 60).rounded(.down))
        return String(format: "%dh%02d", m / 60, m % 60)
    }

    static func time(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            StatusPage()
            ControlsPage()
            InCabPage()
        }
        .tabViewStyle(.verticalPage)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
    }
}

// MARK: Status

struct StatusPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let d = store.dashboard {
                ScrollView {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: symbol(d))
                                .foregroundStyle(color(d))
                            Text(d.statusTitle).font(.headline).lineLimit(1)
                            Spacer()
                            Text(d.since, style: .timer)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if d.onShift {
                            HStack(spacing: 6) {
                                WatchRing(title: "Drive", value: d.driveLeft(at: context.date), full: 4.5 * 3600, color: .blue)
                                WatchRing(title: "Work", value: d.workLeft(at: context.date), full: 6 * 3600, color: .orange)
                            }
                            if let restBy = d.restBy {
                                row("Rest by", WFmt.time(restBy),
                                    tint: restBy < context.date ? .red : (restBy.timeIntervalSince(context.date) < 3600 ? .orange : .primary))
                            }
                            row("Break due in", WFmt.hm(d.breakDueIn(at: context.date)))
                            row("Driven today", "\(WFmt.hm(d.dailyDriving))/\(WFmt.hm(d.dailyDrivingLimit))")
                        } else if d.hasData {
                            let target: TimeInterval = d.restTypeRaw == "weekly" ? 45 * 3600 : 11 * 3600
                            let rest = d.restLength + context.date.timeIntervalSince(d.generatedAt)
                            Gauge(value: min(rest / target, 1)) {
                                Text("Rest")
                            } currentValueLabel: {
                                Text(WFmt.hm(rest)).monospacedDigit()
                            }
                            .gaugeStyle(.accessoryLinearCapacity)
                            .tint(d.restTypeRaw == "weekly" ? .indigo : .teal)
                            row("Full rest at", WFmt.time(d.since.addingTimeInterval(target)))
                        } else {
                            Text("Start your shift from the buttons page or your iPhone.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        row("Driver card", d.cardInserted ? "Inserted" : "Not inserted", tint: d.cardInserted ? .green : .red)
                        row("Week driving", WFmt.hm(d.weeklyDriving))
                        row("Week working", WFmt.hm(d.weeklyWorking))
                        if !store.isReachable {
                            Label("iPhone not connected", systemImage: "iphone.slash")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.radiowaves.left.and.right").font(.title2)
                    Text("Open HGV Hours on your iPhone to connect.")
                        .font(.footnote).multilineTextAlignment(.center)
                }
            }
        }
        .navigationTitle("HGV Hours")
    }

    private func row(_ title: String, _ value: String, tint: Color = .primary) -> some View {
        HStack {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
        }
    }

    private func symbol(_ d: Dashboard) -> String {
        switch d.restTypeRaw {
        case "weekly": return "house.fill"
        case "daily": return "moon.zzz.fill"
        case "break": return "cup.and.saucer.fill"
        default: return d.kind.symbol
        }
    }

    private func color(_ d: Dashboard) -> Color {
        switch d.restTypeRaw {
        case "weekly": return .indigo
        case "daily": return .teal
        default: return d.kind.color
        }
    }
}

struct WatchRing: View {
    var title: String
    var value: TimeInterval
    var full: TimeInterval
    var color: Color

    var body: some View {
        let fraction = min(max(value / full, 0), 1)
        let tint: Color = value <= 0 ? .red : (fraction < 0.12 ? .orange : color)
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(tint.opacity(0.2), lineWidth: 6)
                Circle().trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(WFmt.hm(value))
                    .font(.system(.footnote, design: .rounded).weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .padding(4)
            }
            .frame(height: 62)
            Text(title + " left").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Buttons

struct ControlsPage: View {
    @Environment(WatchStore.self) private var store
    @State private var confirmEnd = false

    var body: some View {
        let d = store.dashboard
        let onShift = d?.onShift ?? false
        ScrollView {
            VStack(spacing: 6) {
                if onShift {
                    Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                        GridRow {
                            button("Drive", "steeringwheel", .blue, .drive, selected: d?.kind == .drive)
                            button("Work", "hammer.fill", .orange, .otherWork, selected: d?.kind == .otherWork)
                        }
                        GridRow {
                            button("POA", "hourglass", .purple, .availability, selected: d?.kind == .availability)
                            button("Break", "cup.and.saucer.fill", .green, .breakTime, selected: d?.kind == .rest)
                        }
                    }
                    Button(role: .destructive) { confirmEnd = true } label: {
                        Label("End shift", systemImage: "stop.circle.fill")
                    }
                    .tint(.red)
                } else {
                    Button { store.send(.startShift) } label: {
                        Label("Start shift", systemImage: "play.circle.fill")
                            .font(.headline)
                    }
                    .tint(.green)
                    Button { store.send(.drive) } label: {
                        Label("Start driving", systemImage: "steeringwheel")
                    }
                }
                if let error = store.lastError {
                    Text(error).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
        .confirmationDialog("End shift and start…", isPresented: $confirmEnd) {
            Button("Daily rest") { store.send(.endShiftDaily) }
            Button("Weekly rest") { store.send(.endShiftWeekly) }
        }
    }

    private func button(_ title: String, _ symbol: String, _ color: Color, _ command: WatchCommand, selected: Bool) -> some View {
        Button { store.send(command) } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(selected ? .white : color)
            .background(selected ? color : color.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: In cab

struct InCabPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let on = store.dashboard?.autoDetect ?? false
        VStack(spacing: 10) {
            Image(systemName: on ? "box.truck.fill" : "figure.walk")
                .font(.largeTitle)
                .foregroundStyle(on ? .blue : .secondary)
            Toggle(isOn: Binding(get: { on }, set: { store.send($0 ? .autoOn : .autoOff) })) {
                Text(on ? "In cab" : "Walking").font(.headline)
            }
            Text(on ? "Moving = Driving\nStopped = Other work" : "Manual — tap the buttons")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
    }
}
