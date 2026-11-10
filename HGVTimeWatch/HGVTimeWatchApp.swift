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

    static func dayTime(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? time(d) : d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

extension Dashboard {
    var accent: Color {
        switch restTypeRaw {
        case "weekly": .indigo
        case "daily": .teal
        default: hasData ? kind.color : .gray
        }
    }

    var symbolName: String {
        switch restTypeRaw {
        case "weekly": "house.fill"
        case "daily": "moon.zzz.fill"
        case "break": "cup.and.saucer.fill"
        default: hasData ? kind.symbol : "moon.zzz.fill"
        }
    }
}

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let accent = store.dashboard?.accent ?? .gray
        TabView {
            NowPage()
                .containerBackground(accent.gradient.opacity(0.45), for: .tabView)
            ButtonsPage()
                .containerBackground(Color.blue.gradient.opacity(0.25), for: .tabView)
            NextPage()
                .containerBackground(Color.green.gradient.opacity(0.25), for: .tabView)
            CardPage()
                .containerBackground(((store.dashboard?.cardInserted ?? false) ? Color.green : Color.red).gradient.opacity(0.3), for: .tabView)
        }
        .tabViewStyle(.verticalPage)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
    }
}

// MARK: Now

struct NowPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let d = store.dashboard {
                GeometryReader { geo in
                    let ring = min(geo.size.width / 2 - 6, geo.size.height * 0.48)
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: d.symbolName).font(.headline)
                            Text(d.statusTitle).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength: 0)
                            if d.hasData {
                                Text(d.since, style: .timer).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                    .fixedSize().padding(.trailing, 6)
                            }
                        }
                        if d.onShift {
                            HStack(spacing: 8) {
                                BigRing(title: "Drive", value: d.driveLeft(at: context.date), full: 4.5 * 3600, color: .blue, size: ring)
                                BigRing(title: "Work", value: d.workLeft(at: context.date), full: 6 * 3600, color: .orange, size: ring)
                            }
                            .frame(maxHeight: .infinity)
                            if let restBy = d.dailyRestRegularBy ?? d.restBy {
                                Label("Rest by \(WFmt.time(restBy))", systemImage: "moon.zzz.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(restBy.timeIntervalSince(context.date) < 3600 ? .orange : .primary)
                            }
                        } else if d.hasData {
                            let target: TimeInterval = d.restTypeRaw == "weekly" ? 45 * 3600 : 11 * 3600
                            let rest = d.restLength + context.date.timeIntervalSince(d.generatedAt)
                            ZStack {
                                Circle().stroke(d.accent.opacity(0.25), lineWidth: 10)
                                Circle().trim(from: 0, to: min(rest / target, 1))
                                    .stroke(d.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 0) {
                                    Text(WFmt.hm(rest)).font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                                    Text("of \(WFmt.hm(target))").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: ring * 1.3, height: ring * 1.3)
                            .frame(maxHeight: .infinity)
                            if let next = d.nextStart {
                                Label("Can start \(WFmt.dayTime(next))", systemImage: "play.circle").font(.caption.weight(.semibold))
                            }
                        } else {
                            Spacer()
                            Text("Swipe down to start your shift.").font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                        }
                        if !store.isReachable {
                            Label("iPhone not connected", systemImage: "iphone.slash").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.radiowaves.left.and.right").font(.title2)
                    Text("Open HGV Hours on your iPhone to connect.").font(.footnote).multilineTextAlignment(.center)
                }
            }
        }
        .navigationTitle("HGV Hours")
    }
}

struct BigRing: View {
    var title: String
    var value: TimeInterval
    var full: TimeInterval
    var color: Color
    var size: CGFloat

    var body: some View {
        let fraction = min(max(value / full, 0), 1)
        let tint: Color = value <= 0 ? .red : (fraction < 0.12 ? .orange : color)
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: max(6, size * 0.1))
            Circle().trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: max(6, size * 0.1), lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(WFmt.hm(value))
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text(title).font(.system(size: max(10, size * 0.13))).foregroundStyle(.secondary)
            }
            .padding(size * 0.12)
        }
        .frame(width: size, height: size)
    }
}

// MARK: Buttons

struct ButtonsPage: View {
    @Environment(WatchStore.self) private var store
    @State private var confirmEnd = false

    var body: some View {
        let d = store.dashboard
        let onShift = d?.onShift ?? false
        GeometryReader { geo in
            let tileHeight = max(52, (geo.size.height - 70) / 2)
            VStack(spacing: 6) {
                if onShift {
                    Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                        GridRow {
                            tile("Drive", "steeringwheel", .blue, .drive, selected: d?.kind == .drive, height: tileHeight)
                            tile("Work", "hammer.fill", .orange, .otherWork, selected: d?.kind == .otherWork, height: tileHeight)
                        }
                        GridRow {
                            tile("POA", "hourglass", .purple, .availability, selected: d?.kind == .availability, height: tileHeight)
                            tile("Break", "cup.and.saucer.fill", .green, .breakTime, selected: d?.kind == .rest, height: tileHeight)
                        }
                    }
                    Button(role: .destructive) { confirmEnd = true } label: {
                        Label("End shift", systemImage: "stop.circle.fill").font(.headline).frame(maxWidth: .infinity)
                    }
                    .tint(.red)
                } else {
                    Spacer()
                    Button { store.send(.startShift) } label: {
                        Label("Start shift", systemImage: "play.circle.fill").font(.title3.weight(.bold)).frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .tint(.green)
                    Button { store.send(.drive) } label: {
                        Label("Start driving", systemImage: "steeringwheel").frame(maxWidth: .infinity)
                    }
                    Spacer()
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

    private func tile(_ title: String, _ symbol: String, _ color: Color, _ command: WatchCommand, selected: Bool, height: CGFloat) -> some View {
        Button { store.send(command) } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(selected ? .white : color)
            .background(selected ? color : color.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? .white.opacity(0.6) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Next

struct NextPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let d = store.dashboard {
                        if d.onShift, let by = d.breakBy {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Next break").font(.caption2).foregroundStyle(.secondary)
                                HStack(alignment: .firstTextBaseline) {
                                    Text(WFmt.hm(d.breakLength)).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(.green)
                                    Text("by \(WFmt.time(by))").font(.headline.monospacedDigit())
                                        .foregroundStyle(by.timeIntervalSince(context.date) < 1800 ? .orange : .primary)
                                }
                                Text(d.breakReason + " rule").font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        }
                        if let r = d.dailyRestRegularBy { row("moon.zzz.fill", "11h rest by", WFmt.time(r)) }
                        if let r = d.restBy, r != d.dailyRestRegularBy { row("moon.haze.fill", "9h rest by", WFmt.time(r)) }
                        if let w = d.weeklyRestBy { row("house.fill", "Weekly rest by", WFmt.dayTime(w)) }
                        if let n = d.nextStart { row("play.circle", d.onShift ? "If you stop now" : "Can start", WFmt.dayTime(n)) }
                        row("sun.max.fill", "10h days left", "\(d.tenHourDaysLeft) of 2")
                        row("moon.haze", "15h days left", "\(d.reducedRestsLeft) of 3")
                        row("calendar", "Week driving", "\(WFmt.hm(d.weeklyDriving)) / 56h")
                        row("briefcase.fill", "Week working", "\(WFmt.hm(d.weeklyWorking)) / 60h")
                        if d.earnedShift > 0 || d.earnedWeek > 0 {
                            row("sterlingsign.circle", "Earned today", String(format: "%@%.2f", d.currency, d.earnedShift))
                        }
                    } else {
                        Text("No data yet.").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Coming up")
    }

    private func row(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(title).font(.caption)
            Spacer()
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
        }
    }
}

// MARK: Card & cab

struct CardPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let cardIn = store.dashboard?.cardInserted ?? false
        let cab = store.dashboard?.autoDetect ?? false
        VStack(spacing: 10) {
            Button { store.send(cardIn ? .cardOut : .cardIn) } label: {
                VStack(spacing: 4) {
                    Image(systemName: cardIn ? "checkmark.circle.fill" : "xmark.circle.fill").font(.title)
                    Text(cardIn ? "Card in" : "No card").font(.headline)
                    Text(cardIn ? "Tap to withdraw" : "Tap when inserted").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 90)
                .foregroundStyle(.white)
                .background((cardIn ? Color.green : Color.red).gradient, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            Toggle(isOn: Binding(get: { cab }, set: { store.send($0 ? .autoOn : .autoOff) })) {
                Label(cab ? "In cab" : "Walking", systemImage: cab ? "box.truck.fill" : "figure.walk")
            }
            Text(cab ? "Moving = Driving · Stopped = Other work" : "Manual — use the buttons")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .navigationTitle("Card & cab")
    }
}
