import SwiftUI
import SwiftData
import AVFoundation

/// Your own reminders: at a time, or tied to a button press or an upcoming limit.
struct RemindersView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \Reminder.createdAt, order: .reverse) private var reminders: [Reminder]
    @State private var editing: Reminder?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(reminders) { r in
                    HStack(spacing: 12) {
                        Image(systemName: r.trigger.symbol)
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background((r.enabled ? Color.orange : .gray).gradient, in: RoundedRectangle(cornerRadius: 8))
                        Button { editing = r } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title.isEmpty ? "Reminder" : r.title).font(.subheadline.weight(.semibold))
                                Text(r.summary + (r.speak ? " · spoken" : "")).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Toggle("", isOn: Binding(get: { r.enabled }, set: { r.enabled = $0; changed() })).labelsHidden()
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { context.delete(r); changed() }
                    }
                }
                Button { adding = true } label: { Label("Add reminder", systemImage: "plus.circle.fill") }
            } footer: {
                Text("Reminders can go off at a time, when you press a button (start or end shift, Arrived, card inserted), or a set time before a break or rest is due. Allow notifications for HGV Hours in iPhone Settings so they show when the app is closed.")
            }
        }
        .navigationTitle("Reminders")
        .sheet(item: $editing, onDismiss: changed) { ReminderEditor(reminder: $0) }
        .sheet(isPresented: $adding, onDismiss: changed) { ReminderEditor(reminder: nil) }
    }

    private func changed() {
        try? context.save()
        ActivityController.refreshSideEffects(context: context, settings: store.settings)
    }
}

struct ReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    private let reminder: Reminder?
    @State private var title: String
    @State private var message: String
    @State private var trigger: ReminderTrigger
    @State private var time: Date
    @State private var repeatRule: ReminderRepeat
    @State private var offset: Int
    @State private var speak: Bool

    init(reminder: Reminder?) {
        self.reminder = reminder
        _title = State(initialValue: reminder?.title ?? "")
        _message = State(initialValue: reminder?.message ?? "")
        _trigger = State(initialValue: reminder?.trigger ?? .time)
        _time = State(initialValue: reminder?.time ?? Calendar.hgv.date(bySettingHour: 6, minute: 0, second: 0, of: .now) ?? .now)
        _repeatRule = State(initialValue: reminder?.repeatRule ?? .weekdays)
        _offset = State(initialValue: reminder?.offsetMinutes ?? 15)
        _speak = State(initialValue: reminder?.speak ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title, e.g. Check tyres", text: $title)
                    TextField("Message (optional)", text: $message, axis: .vertical)
                }
                Section("When") {
                    Picker("Trigger", selection: $trigger) {
                        ForEach(ReminderTrigger.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    if trigger == .time {
                        DatePicker("Time", selection: $time, displayedComponents: repeatRule == .once ? [.date, .hourAndMinute] : [.hourAndMinute])
                        Picker("Repeat", selection: $repeatRule) {
                            ForEach(ReminderRepeat.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    if trigger.usesOffset {
                        Stepper(value: $offset, in: 1...240, step: offset < 15 ? 1 : 5) {
                            LabeledContent(trigger == .afterShiftStart ? "Minutes after" : "Minutes before", value: "\(offset) min")
                        }
                    }
                }
                Section {
                    Toggle("Speak it out loud", isOn: $speak)
                } footer: {
                    Text("Spoken when the app is open or in-cab mode is running. Turn on spoken alerts in Settings → Spoken alerts.")
                }
                if let reminder {
                    Section {
                        Button("Delete reminder", role: .destructive) {
                            context.delete(reminder)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(reminder == nil ? "New reminder" : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let r = reminder ?? Reminder(title: title, trigger: trigger)
                        if reminder == nil { context.insert(r) }
                        r.title = title.isEmpty ? trigger.title : title
                        r.message = message
                        r.trigger = trigger
                        r.time = time
                        r.repeatRule = repeatRule
                        r.offsetMinutes = offset
                        r.speak = speak
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Settings for spoken alerts.
struct VoiceSettingsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Spoken alerts", isOn: $store.settings.voiceEnabled)
            } footer: {
                Text("The phone reads alerts out loud, lowering music while it speaks. Works while the app is open, or in the background while in-cab mode is on.")
            }
            if store.settings.voiceEnabled {
                Section("Speak") {
                    Toggle("Activity changes (Driving, Break…)", isOn: $store.settings.speakActivityChanges)
                    Toggle("Warnings before limits", isOn: $store.settings.speakWarnings)
                    if store.settings.speakWarnings {
                        Stepper(value: $store.settings.voiceWarningMinutes, in: 5...60, step: 5) {
                            LabeledContent("Warn me", value: "\(store.settings.voiceWarningMinutes) min before")
                        }
                    }
                    Toggle("Overspeed", isOn: $store.settings.speakOverspeed)
                    Toggle("Reminders", isOn: $store.settings.speakReminders)
                }
                Section {
                    Picker("Voice", selection: $store.settings.voiceIdentifier) {
                        Text("Default (British English)").tag("")
                        ForEach(VoiceService.voices, id: \.identifier) { v in
                            Text("\(v.name) (\(v.language))").tag(v.identifier)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Speed")
                        Slider(value: $store.settings.voiceRate, in: 0.35...0.6) {
                            Text("Speed")
                        } minimumValueLabel: { Image(systemName: "tortoise") } maximumValueLabel: { Image(systemName: "hare") }
                    }
                    Button {
                        VoiceService.shared.update(settings: store.settings)
                        VoiceService.shared.say("Break due in 15 minutes, at 14:30.", force: true)
                    } label: {
                        Label("Test voice", systemImage: "speaker.wave.2.fill")
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    Text("Download better voices in iPhone Settings → Accessibility → Spoken Content → Voices.")
                }
            }
        }
        .navigationTitle("Spoken alerts")
        .onChange(of: store.settings) { _, value in VoiceService.shared.update(settings: value) }
    }
}
