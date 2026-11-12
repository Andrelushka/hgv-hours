import SwiftData
import SwiftUI

/// Settings → Wake-up & leave home.
struct WakeLeaveSettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]
    @State private var service = WakeLeaveService.shared
    @State private var editing: WorkPlan?
    @State private var testSent = false

    var body: some View {
        @Bindable var store = store
        Form {
            nextJobSection

            Section {
                Toggle("Wake-up alarm", isOn: Binding(get: { store.settings.wakeAlarmEnabled }, set: { on in
                    store.settings.wakeAlarmEnabled = on
                    if on { Task { await service.requestAlarmPermission(); refresh() } }
                }))
                if store.settings.wakeAlarmEnabled {
                    LabeledContent("Alarm name") {
                        TextField("Wake up", text: $store.settings.wakeAlarmTitle).multilineTextAlignment(.trailing)
                    }
                    Stepper(value: $store.settings.wakeGetReadyMinutes, in: 5...240, step: 5) {
                        LabeledContent("Time to get ready", value: Fmt.hm(Double(store.settings.wakeGetReadyMinutes * 60)))
                    }
                    Picker("Snooze", selection: $store.settings.wakeSnoozeMinutes) {
                        Text("No snooze button").tag(0)
                        ForEach([5, 9, 10, 15, 20, 30], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    Picker("Second alarm", selection: $store.settings.wakeBackupMinutes) {
                        Text("Off").tag(0)
                        ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\($0) min later").tag($0) }
                    }
                    if !service.alarmsAllowed {
                        Button("Allow alarms") { Task { await service.requestAlarmPermission(); refresh() } }
                    }
                    Button(testSent ? "Test alarm set for 1 minute from now" : "Test alarm (rings in 1 minute)") {
                        Task { await service.testAlarm(settings: store.settings); testSent = true }
                    }
                    .disabled(testSent)
                }
            } header: {
                Text("Wake-up alarm")
            } footer: {
                Text(service.alarmsAllowed
                     ? "A real alarm: it rings even on silent and shows full screen. Wake-up = leave time − get-ready time."
                     : "Allow alarms so it rings even on silent (iOS 26). Otherwise you get a notification with sound. Wake-up = leave time − get-ready time.")
            }

            Section {
                Toggle("Tell me when to leave home", isOn: $store.settings.leaveReminderEnabled)
                if store.settings.leaveReminderEnabled {
                    Toggle("Ring as an alarm", isOn: Binding(get: { store.settings.leaveAsAlarm }, set: { on in
                        store.settings.leaveAsAlarm = on
                        if on { Task { await service.requestAlarmPermission(); refresh() } }
                    }))
                    Stepper(value: $store.settings.leaveBufferMinutes, in: 0...90, step: 5) {
                        LabeledContent("Arrive early by", value: "\(store.settings.leaveBufferMinutes) min")
                    }
                    Picker("Heads-up before leaving", selection: $store.settings.leaveHeadsUpMinutes) {
                        Text("Off").tag(0)
                        ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                    }
                }
            } header: {
                Text("Leave home")
            } footer: {
                Text("Leave time = job start − journey time (with traffic) − arrive-early margin. As an alarm it rings even on silent, with the same snooze as your wake-up alarm.")
            }

            Section {
                AddressLookupFields(address: $store.settings.homeAddress, postcode: $store.settings.homePostcode,
                                    latitude: $store.settings.homeLatitude, longitude: $store.settings.homeLongitude,
                                    addressLabel: "Home address")
                Toggle("Use live traffic (Apple Maps)", isOn: $store.settings.commuteUseTraffic)
                Stepper(value: $store.settings.commuteMinutes, in: 0...300, step: 5) {
                    LabeledContent(store.settings.commuteUseTraffic ? "Journey if no traffic info" : "Journey time",
                                   value: Fmt.hm(Double(store.settings.commuteMinutes * 60)))
                }
            } header: {
                Text("Home to work")
            } footer: {
                Text(store.settings.homeLatitude == nil && store.settings.commuteUseTraffic
                     ? "Set your home address so the drive to each job's start place can be worked out with traffic."
                     : "The drive is worked out from home to the job's start place (or its first stop).")
            }

            Section {
                Toggle("One-off alarm", isOn: Binding(
                    get: { store.settings.manualAlarmAt > 0 },
                    set: { store.settings.manualAlarmAt = $0 ? Self.defaultManual().timeIntervalSince1970 : 0 }))
                if store.settings.manualAlarmAt > 0 {
                    DatePicker("Ring at", selection: Binding(
                        get: { Date(timeIntervalSince1970: store.settings.manualAlarmAt) },
                        set: { store.settings.manualAlarmAt = $0.timeIntervalSince1970 }), in: Date.now...)
                }
            } header: {
                Text("Alarm without a job")
            } footer: {
                Text("For days with no job in the planner yet.")
            }
        }
        .navigationTitle("Wake-up & leave home")
        .onAppear { service.checkPermission(); refresh() }
        .onChange(of: store.settings) { _, _ in refresh() }
        .sheet(item: $editing) { job in
            NavigationStack { WakeLeaveJobEditor(job: job) }
        }
    }

    @ViewBuilder private var nextJobSection: some View {
        Section("Next job") {
            if let job = WakeLeaveService.nextJob(plans) {
                if let p = service.plan, p.jobID == job.id {
                    WakeLeaveSummary(plan: p, settings: store.settings)
                } else if !store.settings.wakeAlarmEnabled && !store.settings.leaveReminderEnabled {
                    Text("\(job.company.isEmpty ? "Job" : job.company) at \(Fmt.dayTime(job.plannedStart)). Turn on the alarm or leave reminder below.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack { ProgressView(); Text("Working out the journey…").foregroundStyle(.secondary) }
                }
                Button("Change times for this job") { editing = job }
            } else {
                Text("No job planned in the next 36 hours. Add one in the Jobs tab and the alarm is set for it.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refresh() {
        WakeLeaveService.shared.refresh(context: context, settings: store.settings, force: true)
    }

    private static func defaultManual() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        return cal.date(bySettingHour: 5, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

/// Wake / leave / start lines for a job.
struct WakeLeaveSummary: View {
    var plan: WakeLeavePlan
    var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(plan.jobTitle) · starts \(Fmt.dayTime(plan.start))").font(.subheadline.weight(.semibold))
            if plan.alarmsOff {
                Label("Alarm and leave reminder off for this job", systemImage: "bell.slash").foregroundStyle(.secondary)
            } else {
                if settings.wakeAlarmEnabled {
                    row("alarm.fill", .orange, "Wake up", plan.wakeAt, manual: plan.wakeIsManual)
                }
                row("car.fill", .blue, "Leave home", plan.leaveAt, manual: plan.leaveIsManual)
                Text("\(Fmt.hm(plan.travel)) to \(plan.destination)\(plan.trafficBased ? " (traffic)" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ icon: String, _ color: Color, _ label: String, _ date: Date, manual: Bool) -> some View {
        HStack {
            Label(label, systemImage: icon).foregroundStyle(color)
            Spacer()
            Text(Fmt.time(date)).font(.body.monospacedDigit().weight(.semibold))
            if manual { Text("set by you").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

/// Change the wake-up and leave times for one job, or turn them off for it.
struct WakeLeaveJobEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Bindable var job: WorkPlan
    @State private var service = WakeLeaveService.shared

    var body: some View {
        let auto = service.plan.flatMap { $0.jobID == job.id ? $0 : nil }
        Form {
            Section {
                Toggle("Alarm and leave reminder", isOn: Binding(get: { !job.alarmsOff }, set: { job.alarmsOff = !$0 }))
            } footer: {
                Text("\(job.company.isEmpty ? "Job" : job.company) starts \(Fmt.dayTime(job.plannedStart)).")
            }
            if !job.alarmsOff {
                Section {
                    Toggle("Set leave time myself", isOn: Binding(
                        get: { job.leaveOverride != nil },
                        set: { job.leaveOverride = $0 ? (auto?.leaveAt ?? job.plannedStart.addingTimeInterval(-3600)) : nil }))
                    if let leave = job.leaveOverride {
                        DatePicker("Leave home at", selection: Binding(get: { leave }, set: { job.leaveOverride = $0 }),
                                   in: ...job.plannedStart, displayedComponents: [.date, .hourAndMinute])
                    } else if let auto {
                        LabeledContent("Leave home at", value: Fmt.time(auto.leaveAt))
                    }
                } footer: {
                    Text("Automatic: start − journey − \(store.settings.leaveBufferMinutes) min early.")
                }
                Section {
                    Toggle("Set wake-up time myself", isOn: Binding(
                        get: { job.wakeOverride != nil },
                        set: { job.wakeOverride = $0 ? (auto?.wakeAt ?? job.plannedStart.addingTimeInterval(-2 * 3600)) : nil }))
                    if let wake = job.wakeOverride {
                        DatePicker("Wake up at", selection: Binding(get: { wake }, set: { job.wakeOverride = $0 }),
                                   in: ...job.plannedStart, displayedComponents: [.date, .hourAndMinute])
                    } else if let auto {
                        LabeledContent("Wake up at", value: Fmt.time(auto.wakeAt))
                    }
                } footer: {
                    Text("Automatic: leave time − \(store.settings.wakeGetReadyMinutes) min to get ready.")
                }
            }
        }
        .navigationTitle("Wake-up & leave")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    try? context.save()
                    service.refresh(context: context, settings: store.settings, force: true)
                    dismiss()
                }
            }
        }
    }
}

/// Small strip on Today: next wake-up and leave times, tap to change.
struct WakeLeaveStrip: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]
    @State private var service = WakeLeaveService.shared
    @State private var editing: WorkPlan?

    var body: some View {
        if let p = service.plan, !p.alarmsOff, store.settings.wakeAlarmEnabled || store.settings.leaveReminderEnabled {
            Button {
                editing = plans.first { $0.id == p.jobID }
            } label: {
                HStack(spacing: 14) {
                    if store.settings.wakeAlarmEnabled {
                        Label(Fmt.time(p.wakeAt), systemImage: "alarm.fill").foregroundStyle(.orange)
                    }
                    if store.settings.leaveReminderEnabled {
                        Label("Leave \(Fmt.time(p.leaveAt))", systemImage: "car.fill").foregroundStyle(.blue)
                    }
                    Spacer()
                    Image(systemName: "pencil").foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wake-up \(Fmt.time(p.wakeAt)), leave home \(Fmt.time(p.leaveAt)). Change.")
            .sheet(item: $editing) { job in
                NavigationStack { WakeLeaveJobEditor(job: job) }
            }
        }
    }
}

/// Invisible: re-plans the alarm and leave reminder whenever a job is added, moved, cancelled or finished.
struct WakeLeavePlanWatcher: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]

    var body: some View {
        let key = plans.map {
            "\($0.id)\($0.plannedStart.timeIntervalSince1970)\($0.cancelled)\($0.completed)\($0.alarmsOff)\($0.wakeOverride?.timeIntervalSince1970 ?? 0)\($0.leaveOverride?.timeIntervalSince1970 ?? 0)\($0.startPostcode)\($0.startLatitude ?? 0)"
        }.joined()
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: key, initial: true) { _, _ in
                WakeLeaveService.shared.refresh(context: context, settings: store.settings)
            }
    }
}
