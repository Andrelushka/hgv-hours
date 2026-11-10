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
    @State private var nightRefresh = 0
    /// What the "Wrong time?" bar under the help message adjusts.
    @State private var adjustEntryID: UUID?
    @State private var adjustCard: CardEvent?
    /// Rebuilds the help message for a corrected start time.
    @State private var helpBuilder: ((Date) -> HelpMessage)?
    @State private var pickingTime = false
    @State private var pickedTime = Date()
    @Query(sort: \CardEvent.time) private var cardEvents: [CardEvent]

    private var cardIn: Bool { store.settings.cardInserted }
    private var cardSince: Date? {
        store.settings.cardChangedAt > 0 ? Date(timeIntervalSince1970: store.settings.cardChangedAt) : nil
    }

    /// Status right now, used to explain a button press.
    private func currentStatus() -> ComplianceStatus {
        RulesEngine.status(snapshots(now: .now), now: .now, config: store.settings.ruleConfig)
    }

    /// Shows a help message. When `adjustable`, a "Wrong time?" bar lets you move the start of what just began.
    private func show(_ message: HelpMessage, adjustable: Bool = true, rebuild: ((Date) -> HelpMessage)? = nil) {
        withAnimation(.snappy) {
            help = message
            helpBuilder = rebuild
            adjustCard = nil
            adjustEntryID = adjustable ? ActivityController.openEntries(context: context).last?.id : nil
        }
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
                        CardButton(inserted: cardIn, since: cardSince) { toggleCard() }
                        currentCard(status, dash)
                        if let help {
                            HelpBanner(message: help) {
                                withAnimation(.snappy) { self.help = nil; adjustEntryID = nil; adjustCard = nil }
                            }
                            adjustBar
                        }
                        controls(status)
                        inCabCard
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
                        SectionHeader(title: "Earnings")
                        PayCounterCard(now: timeline.date, currentShiftStart: onShift ? status.currentShift?.period.start : nil)
                        nightOutButton(now: timeline.date)
                        SectionHeader(title: "Job & vehicle")
                        todaysPlan(now: timeline.date)
                        CurrentVehicleCard()
                        DayMileageCard(now: timeline.date)
                    }
                    .padding()
                }
            }
            .navigationTitle("Today")
            .toolbar { toolbarContent }
            .sheet(item: $editingPlan) { PlanEditor(plan: $0) }
            .sheet(isPresented: $pickingTime) { timePickerSheet }
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
                    show(TodayHelp.afterEndShift(.daily, status: s), rebuild: { TodayHelp.afterEndShift(.daily, status: s, now: $0) })
                }
                Button("Weekly rest (24h or 45h)") {
                    let s = currentStatus()
                    ActivityController.endShift(.weekly, context: context, settings: store.settings)
                    show(TodayHelp.afterEndShift(.weekly, status: s), rebuild: { TodayHelp.afterEndShift(.weekly, status: s, now: $0) })
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Daily rest is your rest between shifts. Weekly rest is the long rest at least every 6 days.")
            }
        }
    }

    private func nightOutButton(now: Date) -> some View {
        let tonight = Calendar.hgv.startOfDay(for: now)
        _ = nightRefresh // re-read after each tap
        let hasNightOut = !ActivityController.nightOuts(on: tonight, context: context).isEmpty
        return Button {
            toggleNightOut(on: tonight)
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
                    let settings = store.settings
                    let noCard = !cardIn
                    let build: (Date) -> HelpMessage = { start in
                        var message = TodayHelp.afterStartShift(status: s, settings: settings, now: start)
                        if noCard { message.lines.insert("Your driver card isn't marked as inserted — tap the red No card button when you put it in.", at: 0) }
                        return message
                    }
                    show(build(.now), rebuild: build)
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
            let settings = store.settings
            let build: (Date) -> HelpMessage = { start in TodayHelp.afterSwitch(to: kind, status: s, settings: settings, now: start) }
            show(build(.now), rebuild: build)
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
                    show(TodayHelp.inCab(on: value, settings: store.settings), adjustable: false)
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
                if detector.isOverspeeding {
                    Label("Over \(Int(store.settings.overspeedLimitKmh)) km/h — overspeed being recorded", systemImage: "gauge.with.dots.needle.100percent")
                        .font(.caption.weight(.bold)).foregroundStyle(.red)
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

    /// Adds or removes tonight's night out. Reads the database directly, so repeated taps can never
    /// add more than one night out for the same day.
    private func toggleNightOut(on day: Date) {
        let existing = ActivityController.nightOuts(on: day, context: context)
        if existing.isEmpty {
            context.insert(NightOut(date: day))
        } else {
            existing.forEach { context.delete($0) }
        }
        try? context.save()
        nightRefresh += 1
        ActivityController.refreshSideEffects(context: context, settings: store.settings)
    }

    // MARK: Driver card

    private func toggleCard() {
        let inserting = !cardIn
        let now = Date.now
        store.settings.cardInserted = inserting
        store.settings.cardChangedAt = now.timeIntervalSince1970
        let event = CardEvent(time: now, inserted: inserting)
        context.insert(event)
        try? context.save()
        ActivityController.refreshSideEffects(context: context, settings: store.settings)
        let lines = inserting
            ? ["Recorded at \(Fmt.time(.now)).", onShift ? "Remember to make a manual entry on the tacho for any work before you inserted it." : "Tap Start shift when you begin work."]
            : ["Recorded at \(Fmt.time(.now)).", "Make sure your activities are complete before you leave the vehicle. Keep your card safe."]
        withAnimation(.snappy) {
            helpBuilder = nil
            help = HelpMessage(symbol: "creditcard.fill", color: inserting ? .green : .red,
                               title: inserting ? "Driver card inserted" : "Driver card withdrawn", lines: lines)
            adjustEntryID = nil
            adjustCard = event
        }
    }

    // MARK: Wrong time?

    /// Start time of what the bar adjusts.
    private var adjustTime: Date? {
        if let adjustCard { return adjustCard.time }
        if let id = adjustEntryID { return entries.first { $0.id == id }?.start }
        return nil
    }

    @ViewBuilder
    private var adjustBar: some View {
        if let time = adjustTime {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wrong time?").font(.caption.weight(.semibold))
                    Text("Started \(Fmt.time(time))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                ForEach([-5, -1, 1], id: \.self) { minutes in
                    Button(minutes > 0 ? "+\(minutes)" : "\(minutes)") { shift(by: Double(minutes) * 60) }
                        .buttonStyle(.bordered)
                        .disabled(minutes > 0 && time.addingTimeInterval(60) > .now)
                }
                Button("Set…") {
                    pickedTime = time
                    pickingTime = true
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.caption.weight(.semibold))
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func shift(by seconds: TimeInterval) {
        guard let time = adjustTime else { return }
        setAdjusted(time.addingTimeInterval(seconds))
    }

    private func setAdjusted(_ newTime: Date) {
        if let card = adjustCard {
            let earlier = cardEvents.last { $0 !== card && $0.time < card.time }?.time ?? .distantPast
            card.time = min(max(newTime, earlier.addingTimeInterval(60)), .now)
            store.settings.cardChangedAt = card.time.timeIntervalSince1970
            try? context.save()
            ActivityController.refreshSideEffects(context: context, settings: store.settings)
        } else if let id = adjustEntryID, let entry = entries.first(where: { $0.id == id }) {
            ActivityController.adjustStart(of: entry, to: newTime, context: context, settings: store.settings)
        }
        if let time = adjustTime, var message = helpBuilder?(time) ?? help {
            message.lines.removeAll { $0.hasPrefix("Time changed to") }
            message.lines.insert("Time changed to \(Fmt.time(time)).", at: 0)
            help = message
        }
    }

    private var timePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker("Start time", selection: $pickedTime, in: Date.now.addingTimeInterval(-24 * 3600)...Date.now,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                Text("The activity before it is shortened or lengthened to match.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .navigationTitle("Correct the start time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pickingTime = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        setAdjusted(pickedTime)
                        pickingTime = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
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
                Button { startUnplannedJob() } label: {
                    Label("Arrived", systemImage: "mappin.and.ellipse")
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
                TodayJobCard(plan: plan) { editingPlan = plan }
            }
        }
    }

    /// "Arrived" with no plan: makes today's job (from now) and records an arrival here.
    private func startUnplannedJob() {
        let now = Date.now
        let plan = WorkPlan(start: now, end: now.addingTimeInterval(10 * 3600))
        plan.vehicleID = store.settings.currentVehicleID
        plan.trailerID = store.settings.currentTrailerID
        var stop = PlanStop(kind: .other)
        stop.arrivedAt = now
        stop.place = "Locating…"
        plan.stops = [stop]
        context.insert(plan)
        try? context.save()
        let id = stop.id
        Task {
            let location = await LocationOnce.shared.current()
            let name = location != nil ? await LocationOnce.shared.placeName(for: location!) : "Unplanned stop"
            var stops = plan.stops
            if let i = stops.firstIndex(where: { $0.id == id }) {
                stops[i].place = name
                stops[i].latitude = location?.coordinate.latitude
                stops[i].longitude = location?.coordinate.longitude
                plan.stops = stops
                try? context.save()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button { toggleCard() } label: {
                HStack(spacing: 5) {
                    Circle().fill(cardIn ? Color.green : Color.red).frame(width: 10, height: 10)
                    Text(cardIn ? "Card in" : "No card").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background((cardIn ? Color.green : Color.red).opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(cardIn ? "Driver card inserted" : "Driver card not inserted")
        }
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
