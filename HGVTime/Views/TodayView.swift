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
    @State private var helpSeen = true
    @State private var nightRefresh = 0
    /// What the "Wrong time?" bar under the help message adjusts.
    @State private var adjustEntryID: UUID?
    @State private var adjustCard: CardEvent?
    /// Rebuilds the help message for a corrected start time.
    @State private var helpBuilder: ((Date) -> HelpMessage)?
    @State private var pickingTime = false
    @State private var pickedTime = Date()
    @State private var editingLayout = false
    @State private var toast: Toast?
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
            helpSeen = false
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
                let snaps = snapshots(now: timeline.date)
                let status = RulesEngine.status(snaps, now: timeline.date, config: store.settings.ruleConfig)
                let dash = Dashboard.make(status: status, settings: store.settings, openEntry: openEntry)
                let data = HoursTileData(status: status, dash: dash, settings: store.settings, openEntry: openEntry, onShift: onShift)
                let hidden = store.settings.tileHidden(.today)
                let tiles = store.settings.tileOrder(.today).filter { !hidden.contains($0) && (editingLayout || applies($0, data: data, now: timeline.date)) }
                ScrollView {
                    VStack(spacing: 12) {
                        TileGrid(page: .today, tiles: tiles, editing: editingLayout) { tile in
                            if applies(tile, data: data, now: timeline.date) {
                                moduleView(tile, status: status, dash: dash, data: data, now: timeline.date)
                            } else {
                                TilePlaceholder(tile: tile)
                            }
                        }
                        if editingLayout { HiddenTilesTray(page: .today) }
                        if !status.hasData && !editingLayout { emptyState }
                        HStack(spacing: 16) {
                            Button { withAnimation(.snappy) { editingLayout.toggle() } } label: {
                                Label(editingLayout ? "Done" : "Edit layout", systemImage: editingLayout ? "checkmark.circle.fill" : "square.grid.2x2")
                            }
                            NavigationLink { TileCustomiseView(page: .today) } label: {
                                Label("Customise", systemImage: "switch.2")
                            }
                        }
                        .font(.caption)
                        .padding(.top, 4)
                    }
                    .padding()
                }
            }
            .overlay(alignment: .top) {
                if let toast {
                    ToastView(toast: toast)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: toast.id) {
                            try? await Task.sleep(for: .seconds(2.5))
                            withAnimation(.snappy) { if self.toast?.id == toast.id { self.toast = nil } }
                        }
                        .onTapGesture { withAnimation { self.toast = nil } }
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
                    let started = s.currentShift?.period.start
                    ActivityController.endShift(.daily, context: context, settings: store.settings)
                    ActivityController.resetAfterShift(context: context, store: store, shiftStart: started)
                    show(TodayHelp.afterEndShift(.daily, status: s), rebuild: { TodayHelp.afterEndShift(.daily, status: s, now: $0) })
                }
                Button("Weekly rest (24h or 45h)") {
                    let s = currentStatus()
                    let started = s.currentShift?.period.start
                    ActivityController.endShift(.weekly, context: context, settings: store.settings)
                    ActivityController.resetAfterShift(context: context, store: store, shiftStart: started)
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

    /// Whether a Today tile has something to show now.
    private func applies(_ tile: Tile, data: HoursTileData, now: Date) -> Bool {
        switch tile {
        case .warnings: return data.status.warnings.contains { $0.severity == .violation }
        case .job: return onShift || !plans.filter({ Calendar.hgv.isDate($0.plannedStart, inSameDayAs: now) && !$0.completed }).isEmpty
        case .vehicle: return true
        case .mileage: return onShift || VehicleLog.hasMileage(on: now, context: context)
        case .date, .card, .expiry, .status, .buttons, .inCab, .earnings, .nightOut: return true
        default: return data.applies(tile)
        }
    }

    @ViewBuilder
    private func moduleView(_ tile: Tile, status: ComplianceStatus, dash: Dashboard, data: HoursTileData, now: Date) -> some View {
        switch tile {
        case .date: DateTile(now: now)
        case .card: CardTile(inserted: cardIn, since: cardSince) { toggleCard() }
        case .expiry: ExpiryBanner()
        case .status: currentCard(status, dash)
        case .buttons:
            VStack(spacing: 10) {
                controls(status)
                subtypeChips(status)
            }
        case .inCab: inCabCard
        case .warnings:
            let urgent = status.warnings.filter { $0.severity == .violation }
            VStack(spacing: 10) {
                ForEach(urgent) { IssueRow(issue: $0) }
                Text("See the Hours tab for all your limits.").font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        case .earnings: PayCounterCard(now: now, currentShiftStart: onShift ? status.currentShift?.period.start : nil)
        case .nightOut: NightOutTile(now: now)
        case .job: todaysPlan(now: now)
        case .vehicle: CurrentVehicleCard()
        case .mileage: DayMileageCard(now: now)
        default: HoursTileView(tile: tile, data: data)
        }
    }

    /// Loading, unloading, waiting… chips for the current other work / POA.
    @ViewBuilder
    private func subtypeChips(_ status: ComplianceStatus) -> some View {
        if onShift, let open = openEntry, open.kind == .otherWork || open.kind == .availability {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ActivitySubtype.options(for: open.kind)) { sub in
                        let on = open.subtype == sub
                        Button {
                            ActivityController.setSubtype(on ? nil : sub, context: context, settings: store.settings)
                        } label: {
                            Label(sub.title, systemImage: sub.symbol)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .foregroundStyle(on ? .white : open.kind.color)
                                .background(on ? AnyShapeStyle(open.kind.color) : AnyShapeStyle(open.kind.color.opacity(0.12)), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func currentCard(_ status: ComplianceStatus, _ dash: Dashboard) -> some View {
        let restType = openEntry?.restType
        let symbol = openEntry?.subtype?.symbol ?? restType?.symbol ?? (status.hasData ? status.currentKind.symbol : "moon.zzz.fill")
        let color = restType?.color ?? (status.hasData ? status.currentKind.color : .gray)
        let title: String = {
            guard status.hasData, let open = openEntry else { return "Off duty" }
            return open.displayTitle
        }()
        let helpText = help.map { $0.lines.joined(separator: "\n\n") }
            ?? TodayHelp.next(status: status, openEntry: openEntry)
            ?? "Tap Start shift when you begin work, then the activity buttons as you change activity."
        return HStack(alignment: .top, spacing: 14) {
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
                if status.hasData, openEntry?.endsShift == true {
                    // Resting between shifts: count down to the next planned job; no counter when nothing is planned.
                    if let job = nextPlannedJob(after: status.now) {
                        Text(timerInterval: status.now...max(status.now, job.plannedStart), countsDown: true)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                        Text("until your next job at \(Fmt.time(job.plannedStart))\(job.company.isEmpty ? "" : " · \(job.company)")")
                            .font(.caption).foregroundStyle(.secondary)
                        WakeLeaveStrip()
                        let restAtStart = job.plannedStart.timeIntervalSince(status.currentSince)
                        if openEntry?.restType != .weekly && restAtStart < Limits.reducedDailyRest {
                            Text("⚠︎ Only \(Fmt.hm(restAtStart)) rest by then — 9h minimum").font(.caption.weight(.semibold)).foregroundStyle(.red)
                        }
                    } else {
                        Text("Resting since \(Fmt.dayTime(status.currentSince))").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let next = TodayHelp.next(status: status, openEntry: openEntry) {
                        Text(next)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if status.hasData {
                    Text(status.currentSince, style: .timer)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                    HStack(spacing: 4) {
                        Text("since").font(.caption).foregroundStyle(.secondary)
                        if let open = openEntry {
                            // Tap the time to correct it straight away.
                            NowDatePicker("Start time", selection: Binding(
                                get: { open.start },
                                set: { ActivityController.adjustStart(of: open, to: $0, context: context, settings: store.settings) }),
                                       in: (Date.now.addingTimeInterval(-24 * 3600))...Date.now,
                                       displayedComponents: [.hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .scaleEffect(0.85, anchor: .leading)
                                .frame(height: 28)
                        }
                        Text("· \(store.settings.currentRegime.shortTitle)\(store.settings.multiManned ? " · 2-man" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                InfoDot(title: help?.title ?? title, text: helpText, highlighted: help != nil && !helpSeen) { helpSeen = true }
                if openEntry != nil {
                    Button { editing = openEntry } label: {
                        Image(systemName: "pencil.circle").font(.title3).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit the current activity")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
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
                    if let plan = plans.first(where: { Calendar.hgv.isDateInToday($0.plannedStart) && !$0.cancelled }) {
                        if !plan.trailerID.isEmpty { store.settings.currentTrailerID = plan.trailerID }
                        if !plan.vehicleID.isEmpty { VehicleLog.select(plan.vehicleID, context: context, store: store) }
                    }
                    VehicleLog.applyRules(store.settings.currentVehicleID, context: context, store: store)
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
                    Label("Over \(Int(detector.speedLimitKmh)) km/h — overspeed being recorded", systemImage: "gauge.with.dots.needle.100percent")
                        .font(.caption.weight(.bold)).foregroundStyle(.red)
                }
                if detector.harshBrakesToday > 0 {
                    Label("Harsh braking today: \(detector.harshBrakesToday)", systemImage: "exclamationmark.brakesignal")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
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
        if inserting { ReminderService.shared.fire(.cardInserted, context: context) }
        EventRecorder.log(inserting ? .cardIn : .cardOut, context: context, settings: store.settings)
        ActivityController.refreshSideEffects(context: context, settings: store.settings)
        withAnimation(.snappy) {
            toast = Toast(symbol: "creditcard.fill", color: inserting ? .green : .red,
                          title: inserting ? "Card inserted" : "Card withdrawn",
                          detail: "Recorded at \(Fmt.time(now))" + (inserting && !onShift ? " · tap Start shift when you begin work" : ""))
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
                Button("Now") { pickedTime = .now }
                    .buttonStyle(.bordered)
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
        let todays = plans.filter { !$0.completed && (cal.isDate($0.plannedStart, inSameDayAs: now) || ($0.plannedStart <= now && $0.plannedEnd >= now)) }
            .sorted { ($0.cancelled ? 1 : 0, $0.plannedStart) < ($1.cancelled ? 1 : 0, $1.plannedStart) }
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

    /// The next job that isn't done or cancelled, starting within the next 24 hours.
    private func nextPlannedJob(after now: Date) -> WorkPlan? {
        plans.first { !$0.completed && !$0.cancelled && $0.plannedStart > now && $0.plannedStart < now.addingTimeInterval(24 * 3600) }
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
        ReminderService.shared.fire(.arrived, context: context)
        EventRecorder.log(.arrived, detail: "Unplanned stop", context: context, settings: store.settings)
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
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink { CalculatorView() } label: {
                Label("Calculator", systemImage: "plus.forwardslash.minus")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink { AssistantView() } label: {
                Label("Assistant", systemImage: "sparkles")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink { MapScreen(day: .now) } label: {
                Label("Map", systemImage: "map.fill")
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
