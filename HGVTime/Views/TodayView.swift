import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \NightOut.date) private var nightOuts: [NightOut]
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]
    @State private var editingPlan: WorkPlan?
    @State private var planningToday = false
    @State private var showingSettings = false

    @State private var editing: ActivityEntry?
    @State private var confirmEndShift = false
    @State private var detector = AutoDriveDetector.shared
    @State private var help: HelpMessage?

    /// Status right now, used to explain a button press.
    private func currentStatus() -> ComplianceStatus {
        RulesEngine.status(snapshots(now: .now), now: .now, config: store.settings.ruleConfig)
    }

    private func show(_ message: HelpMessage) {
        withAnimation(.snappy) { help = message }
    }

    private var openEntry: ActivityEntry? { entries.last { $0.end == nil } }
    private var onShift: Bool { openEntry.map { !$0.endsShift } ?? false }

    private func snapshots(now: Date) -> [EntrySnapshot] {
        let cutoff = now.addingTimeInterval(-Double(store.settings.wtdReferenceWeeks + 2) * 7 * 86_400)
        return entries.filter { $0.start >= cutoff }.map(\.snapshot)
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 10)) { timeline in
                let status = RulesEngine.status(snapshots(now: timeline.date), now: timeline.date, config: store.settings.ruleConfig)
                let dash = Dashboard.make(status: status, settings: store.settings, openEntry: openEntry)
                ScrollView {
                    VStack(spacing: 14) {
                        currentCard(status, dash)
                        if let help {
                            HelpBanner(message: help) { withAnimation(.snappy) { self.help = nil } }
                        }
                        PayCounterCard(now: timeline.date, currentShiftStart: onShift ? status.currentShift?.period.start : nil)
                        controls(status)
                        inCabCard
                        CurrentVehicleCard()
                        todaysPlan(now: timeline.date)
                        let urgent = status.warnings.filter { $0.severity == .violation }
                        if !urgent.isEmpty {
                            VStack(spacing: 10) {
                                ForEach(urgent) { IssueRow(issue: $0) }
                                Text("See the Hours tab for all your limits.").font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }
                        if !status.hasData { emptyState }
                        nightOutButton(now: timeline.date)
                    }
                    .padding()
                }
            }
            .navigationTitle("Today")
            .toolbar { toolbarContent }
            .sheet(item: $editingPlan) { PlanEditor(plan: $0) }
            .sheet(isPresented: $planningToday) {
                PlanEditor(plan: nil, day: .now, defaultVehicleID: store.settings.currentVehicleID,
                           defaultTrailerID: store.settings.currentTrailerID)
            }
            .sheet(item: $editing) { entry in
                EntryEditor(entry: entry)
            }
            .confirmationDialog("End shift and start…", isPresented: $confirmEndShift, titleVisibility: .visible) {
                Button("Daily rest (9h or 11h)") {
                    let s = currentStatus()
                    ActivityController.endShift(.daily, context: context, settings: store.settings)
                    show(TodayHelp.afterEndShift(.daily, status: s))
                }
                Button("Weekly rest (24h or 45h)") {
                    let s = currentStatus()
                    ActivityController.endShift(.weekly, context: context, settings: store.settings)
                    show(TodayHelp.afterEndShift(.weekly, status: s))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Daily rest is your rest between shifts. Weekly rest is the long rest at least every 6 days.")
            }
        }
    }

    private func nightOutButton(now: Date) -> some View {
        let tonight = Calendar.hgv.startOfDay(for: now)
        let hasNightOut = nightOuts.contains { Calendar.hgv.isDate($0.date, inSameDayAs: tonight) }
        return Button {
            toggleNightOut(on: tonight, existing: hasNightOut)
        } label: {
            Label(hasNightOut ? "Night out logged for tonight" : "Log a night out tonight",
                  systemImage: hasNightOut ? "checkmark.circle.fill" : "bed.double.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    // MARK: Current activity

    private func currentCard(_ status: ComplianceStatus, _ dash: Dashboard) -> some View {
        let restType = openEntry?.restType
        let symbol = restType?.symbol ?? (status.hasData ? status.currentKind.symbol : "moon.zzz.fill")
        let color = restType?.color ?? (status.hasData ? status.currentKind.color : .gray)
        let title: String = {
            guard status.hasData, let open = openEntry else { return "Off duty" }
            return open.displayTitle
        }()
        return Button {
            editing = openEntry
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline)
                        if onShift {
                            Text("ON SHIFT")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                    }
                    if status.hasData {
                        Text(status.currentSince, style: .timer)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                        Text("since \(Fmt.time(status.currentSince)) · \(store.settings.currentRegime.shortTitle)\(store.settings.multiManned ? " · double-manned" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let next = TodayHelp.next(status: status, openEntry: openEntry) {
                            Text(next)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("Tap Start shift when you begin work").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if openEntry != nil {
                    Image(systemName: "pencil.circle").font(.title2).foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit the current activity")
    }

    // MARK: Buttons

    @ViewBuilder
    private func controls(_ status: ComplianceStatus) -> some View {
        let current = status.hasData ? status.currentKind : nil
        if onShift {
            VStack(spacing: 10) {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        activityButton(.drive, label: "Drive", selected: current == .drive)
                        activityButton(.otherWork, label: "Other work", selected: current == .otherWork)
                    }
                    GridRow {
                        activityButton(.availability, label: "POA", selected: current == .availability)
                        activityButton(.rest, label: "Break", selected: current == .rest, symbol: RestType.breakTime.symbol)
                    }
                }
                Button {
                    confirmEndShift = true
                } label: {
                    Label("End shift", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        } else {
            VStack(spacing: 6) {
                Button {
                    let s = currentStatus()
                    if let plan = plans.first(where: { Calendar.hgv.isDateInToday($0.plannedStart) }) {
                        if !plan.vehicleID.isEmpty { store.settings.currentVehicleID = plan.vehicleID }
                        if !plan.trailerID.isEmpty { store.settings.currentTrailerID = plan.trailerID }
                    }
                    ActivityController.startShift(context: context, settings: store.settings)
                    show(TodayHelp.afterStartShift(status: s, settings: store.settings))
                } label: {
                    Label("Start shift", systemImage: "play.circle.fill")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Text("Starts with \(store.settings.shiftStartKind.title.lowercased()). Change this in Settings → Shift.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let open = openEntry, open.endsShift {
                    Picker("Rest type", selection: Binding(
                        get: { open.restType ?? .daily },
                        set: { ActivityController.endShift($0, context: context, settings: store.settings) })) {
                        Text("Daily rest").tag(RestType.daily)
                        Text("Weekly rest").tag(RestType.weekly)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
                }
            }
        }
    }

    private func activityButton(_ kind: DutyKind, label: String, selected: Bool, symbol: String? = nil) -> some View {
        Button {
            let s = currentStatus()
            ActivityController.switchTo(kind, context: context, settings: store.settings)
            show(TodayHelp.afterSwitch(to: kind, status: s, settings: store.settings))
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol ?? kind.symbol).font(.title2)
                Text(label).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(selected ? .white : kind.color)
            .background(selected ? AnyShapeStyle(kind.color.gradient) : AnyShapeStyle(kind.color.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: In cab (automatic)

    private var inCabCard: some View {
        let on = store.settings.autoDetectEnabled
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { store.settings.autoDetectEnabled },
                set: { value in
                    store.settings.autoDetectEnabled = value
                    show(TodayHelp.inCab(on: value, settings: store.settings))
                })) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(on ? "In cab — automatic" : "Walking — manual")
                            .font(.subheadline.weight(.semibold))
                        Text(on ? "Moving = Driving · Stopped = \(store.settings.autoStoppedKind == .rest ? "Break" : store.settings.autoStoppedKind.title)"
                                : "Turn on in the cab to record driving automatically, like the tacho.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: on ? "box.truck.fill" : "figure.walk")
                        .foregroundStyle(on ? .blue : .secondary)
                }
            }
            if on {
                Button {
                    if detector.state == .denied { detector.openSettings() }
                    else if detector.needsAlwaysPermission { detector.requestAlways() }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 9, height: 9)
                        Text(detector.statusText).monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(detector.state == .denied ? .red : .primary)
                }
                .buttonStyle(.plain)
                if detector.needsAlwaysPermission {
                    Button("Allow location “Always” so it works with the phone locked") { detector.requestAlways() }
                        .font(.caption)
                }
                if let event = detector.lastEvent {
                    Text(event).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(on ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusColor: Color {
        switch detector.state {
        case .moving: .blue
        case .stopped: .orange
        case .denied: .red
        case .off: .secondary
        default: .yellow
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap").font(.largeTitle).foregroundStyle(.secondary)
            Text("Tap **Start shift** when you begin work, then **Drive**, **Other work**, **POA** or **Break** as you change activity — or turn on **In cab** to record driving automatically.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 30)
    }

    // MARK: Actions

    private func toggleNightOut(on day: Date, existing: Bool) {
        if existing {
            for night in nightOuts where Calendar.hgv.isDate(night.date, inSameDayAs: day) {
                context.delete(night)
            }
        } else {
            context.insert(NightOut(date: day))
        }
        try? context.save()
    }

    /// Today's planned job, or a button to plan one.
    @ViewBuilder
    private func todaysPlan(now: Date) -> some View {
        let cal = Calendar.hgv
        let todays = plans.filter { cal.isDate($0.plannedStart, inSameDayAs: now) || ($0.plannedStart <= now && $0.plannedEnd >= now) }
        if todays.isEmpty {
            let next = plans.first { $0.plannedStart > now }
            HStack {
                Button { planningToday = true } label: {
                    Label("Plan today's job", systemImage: "calendar.badge.plus")
                }
                Spacer()
                if let next {
                    Button { editingPlan = next } label: {
                        Text("Next: \(Fmt.day(next.plannedStart)) \(Fmt.time(next.plannedStart))").font(.caption)
                    }
                }
            }
            .buttonStyle(.bordered)
            .tint(.indigo)
        } else {
            ForEach(todays) { plan in
                PlanCard(plan: plan, title: "Today's job")
                    .onTapGesture { editingPlan = plan }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink { SettingsView(embedded: true) } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Rules for new activity", selection: Binding(
                    get: { store.settings.currentRegime },
                    set: { store.settings.currentRegime = $0 })) {
                    ForEach(Regime.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Double-manned", isOn: Binding(
                    get: { store.settings.multiManned },
                    set: { store.settings.multiManned = $0 }))
            } label: {
                Label("Mode", systemImage: "slider.horizontal.3")
            }
        }
    }
}
