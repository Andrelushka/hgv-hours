import PhotosUI
import SwiftData
import SwiftUI
#if canImport(HGVAI)
import HGVAI
#endif

struct ChatLine: Identifiable, Equatable {
    enum Role { case user, assistant, notice }
    let id = UUID()
    var role: Role
    var text: String
    var byClaude = false
}

/// Ask about your hours, rest, pay and plans.
struct AssistantView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \WorkPlan.plannedStart) private var plans: [WorkPlan]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \NightOut.date) private var nightOuts: [NightOut]
    @Query(sort: \PayItem.date) private var payItems: [PayItem]

    @State private var lines: [ChatLine] = []
    @State private var apiHistory: [[String: Any]] = []
    @State private var input = ""
    @State private var thinking = false
    @State private var showingSettings = false
    @State private var voice = VoiceInput()
    /// Hands-free: answers are spoken and it listens again.
    @State private var talkMode = false
    @State private var photoItem: PhotosPickerItem?
    @State private var readingPhoto = false
    /// A change the assistant wants to make that needs your OK.
    @State private var confirmText: String?
    @State private var confirmReply: CheckedContinuation<Bool, Never>?
    #if canImport(HGVAI)
    @State private var localChat: LocalChat?
    #endif

    private var claudeOn: Bool { store.settings.assistantUseClaude && KeychainKey.hasKey }
    private var localOn: Bool {
        #if canImport(HGVAI)
        store.settings.assistantUseLocal
        #else
        false
        #endif
    }
    private var agentOn: Bool { localOn || claudeOn }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        intro
                        ForEach(lines) { line in bubble(line).id(line.id) }
                        if thinking {
                            HStack(spacing: 8) { ProgressView(); Text("Thinking…").font(.caption).foregroundStyle(.secondary) }
                                .id("thinking")
                        }
                    }
                    .padding()
                }
                .onChange(of: lines) { _, _ in
                    withAnimation { proxy.scrollTo(lines.last?.id, anchor: .bottom) }
                }
            }
            suggestions
            inputBar
        }
        .navigationTitle("Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: Binding(get: { talkMode }, set: { on in
                    talkMode = on
                    if on { voice.cancel(); VoiceService.shared.say("Talk mode on. Ask me anything, or say a command like start driving.", force: true); listen() }
                    else { voice.cancel() }
                })) {
                    Image(systemName: talkMode ? "person.wave.2.fill" : "person.wave.2")
                }
                .toggleStyle(.button)
                .accessibilityLabel("Talk mode")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .onDisappear { voice.cancel(); talkMode = false }
        .alert("Assistant wants to make a change", isPresented: Binding(get: { confirmText != nil }, set: { if !$0 { answerConfirm(false) } })) {
            Button("Yes, do it") { answerConfirm(true) }
            Button("No", role: .cancel) { answerConfirm(false) }
        } message: {
            Text(confirmText ?? "")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            readPhoto(item)
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { AssistantSettingsView() } }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(localOn ? "On-device AI agent" : (claudeOn ? "Claude AI agent" : "Offline answers"),
                  systemImage: localOn ? "cpu" : (claudeOn ? "sparkles" : "bolt.horizontal.circle"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(agentOn ? .purple : .accentColor)
            Text(localOn
                 ? "Ask anything, or tell it what to do: plan or cancel a job, add stops, write notes, set reminders, log fuel, change vehicle or trailer. 📷 reads delivery notes and booking sheets. Runs on this iPhone — nothing leaves the phone."
                 : claudeOn
                 ? "Ask anything, or tell it what to do: plan or cancel a job, add stops, write notes, set reminders, log fuel, change vehicle or trailer. 📷 reads delivery notes and booking sheets. Your question and the data it needs are sent to Anthropic."
                 : "Ask about driving left, breaks, rest, next start, 15h days, earnings, weekly rest or vehicle height. Answers come from your records on this iPhone. Turn on Claude AI (⚙︎ top right) for any other question.")
            Text("🎙 Tap the mic to speak, or turn on talk mode (👤 top right) for hands-free: answers are read out and it listens again. Say commands like \"start driving\", \"take a break\", \"loading\", \"insert card\" or \"end shift\".")
                .font(.caption).foregroundStyle(.secondary)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background((agentOn ? Color.purple : Color.accentColor).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func bubble(_ line: ChatLine) -> some View {
        HStack {
            if line.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(line.text)).font(.subheadline)
                if line.role == .assistant {
                    Text(line.byClaude ? (localOn ? "On-device AI" : "Claude") : "From your records").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .foregroundStyle(line.role == .user ? .white : .primary)
            .background(line.role == .user ? AnyShapeStyle(Color.accentColor) :
                            line.role == .notice ? AnyShapeStyle(Color.orange.opacity(0.15)) : AnyShapeStyle(Color(.secondarySystemBackground)),
                        in: RoundedRectangle(cornerRadius: 14))
            if line.role != .user { Spacer(minLength: 40) }
        }
    }

    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(OfflineAssistant.suggestions, id: \.self) { s in
                    Button(s) { send(s) }.buttonStyle(.bordered).font(.caption)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 6)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                if voice.isListening { voice.finish() } else { listen() }
            } label: {
                Image(systemName: voice.isListening ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.title2)
                    .foregroundStyle(voice.isListening ? .red : .accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: voice.isListening)
            }
            .accessibilityLabel(voice.isListening ? "Stop listening" : "Speak")
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: readingPhoto ? "hourglass.circle.fill" : "camera.circle.fill").font(.title2)
            }
            .disabled(readingPhoto || thinking)
            .accessibilityLabel("Read a photo")
            TextField(voice.isListening ? "Listening…" : "Ask or say a command…", text: voice.isListening ? .constant(voice.transcript) : $input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit { send(input) }
            Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thinking)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: Answering

    private func facts() -> AssistantFacts {
        let now = Date.now
        let settings = store.settings
        let cutoff = now.addingTimeInterval(-Double(settings.wtdReferenceWeeks + 2) * 7 * 86_400)
        let snaps = entries.filter { $0.start >= cutoff }.map(\.snapshot)
        let status = RulesEngine.status(snaps, now: now, config: settings.ruleConfig)
        let world = WorldRulesCache.refresh(snaps, now: now, settings: settings)
        let open = entries.last { $0.end == nil }
        var dash = Dashboard.make(status: status, settings: settings, openEntry: open)
        let analysis = RulesEngine.analyze(snaps, now: now, config: settings.ruleConfig)
        let weekStart = Calendar.hgv.startOfFixedWeek(for: now)
        let weekShifts = analysis.shifts.filter { $0.period.start >= weekStart }
        let week = PayCalculator.calculate(shifts: weekShifts, nightOuts: nightOuts.filter { $0.date >= weekStart }.count,
                                           settings: settings.pay, items: payItems.filter { $0.date >= weekStart }.map(\.snapshot))
        let today = analysis.shifts.workedOn(now)
        if !today.isEmpty { dash.earnedShift = PayCalculator.calculate(shifts: today, nightOuts: 0, settings: settings.pay).total }
        dash.cardInserted = settings.cardInserted
        let ids = [settings.currentVehicleID, settings.currentTrailerID]
        let height = vehicles.filter { ids.contains($0.id.uuidString) }.map(\.height).max() ?? 0
        let recent = (0..<7).reversed().compactMap { offset -> (Date, TimeInterval, TimeInterval)? in
            guard let day = Calendar.hgv.date(byAdding: .day, value: -offset, to: Calendar.hgv.startOfDay(for: now)) else { return nil }
            let t = DayTotals.compute(entries.filter { ($0.end ?? now) > day && $0.start < day.addingTimeInterval(86_400) }, day: day)
            return (day, t.driving, t.working)
        }
        return AssistantFacts(now: now, region: settings.region, dash: dash, status: status, world: world, weekPay: week.total,
                              currency: settings.pay.currencySymbol, nextPlan: plans.first { $0.plannedEnd > now },
                              vehicleHeight: height, recentDays: recent.map { (day: $0.0, drive: $0.1, work: $0.2) })
    }

    private func listen() {
        Task {
            await voice.start { heard in send(heard) }
            if let e = voice.error { lines.append(ChatLine(role: .notice, text: e)) }
        }
    }

    /// Adds an answer, speaks it in talk mode, then listens again.
    private func reply(_ line: ChatLine) {
        lines.append(line)
        guard talkMode, line.role != .user else { return }
        let plain = line.text.replacingOccurrences(of: "**", with: "")
        voice.cancel()
        VoiceService.shared.say(plain, force: true)
        // Listen again once the answer has been read out (start() waits for the voice to finish).
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            if talkMode && !voice.isListening && !thinking { listen() }
        }
    }

    private func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking else { return }
        input = ""
        lines.append(ChatLine(role: .user, text: q))
        if let command = VoiceCommand.parse(q) {
            ActivityController.perform(command, context: context, store: store)
            reply(ChatLine(role: .assistant, text: command.confirmation))
            return
        }
        let f = facts()
        if agentOn {
            thinking = true
            Task {
                do {
                    let answer = try await runAgent(q, facts: f)
                    self.reply(ChatLine(role: .assistant, text: answer, byClaude: true))
                } catch {
                    if let offline = OfflineAssistant.answer(q, f) { self.reply(ChatLine(role: .assistant, text: offline)) }
                    lines.append(ChatLine(role: .notice, text: error.localizedDescription))
                }
                thinking = false
            }
        } else if let offline = OfflineAssistant.answer(q, f) {
            reply(ChatLine(role: .assistant, text: offline))
        } else {
            reply(ChatLine(role: .notice, text: "I can answer questions about driving left, breaks, rest, next start, 15h and 10h days, earnings, weekly rest, infringements and vehicle height. For anything else, turn on Claude AI with ⚙︎ (top right). You can also say commands like start driving, take a break, loading, or end shift."))
        }
    }
}

extension AssistantView {
    /// Runs the question through the on-device model or Claude, letting it use the app's tools.
    fileprivate func runAgent(_ q: String, facts f: AssistantFacts) async throws -> String {
        let summary = f.summary
        #if canImport(HGVAI)
        if localOn {
            let model = LocalModel.shared
            if model.loadedID != store.settings.assistantLocalModel || localChat == nil {
                lines.append(ChatLine(role: .notice, text: "Loading the on-device model…"))
                try await model.load(store.settings.assistantLocalModel) { _ in }
                let tools = AgentTools.all.map { d in
                    AgentTool(name: d.name, description: d.description,
                              parameters: d.params.map { (name: $0.name, type: $0.type, description: $0.description, required: $0.required) })
                }
                let ctx = context, st = store
                localChat = try model.makeChat(
                    instructions: AgentTools.instructions + "\nToday is \(Date.now.formatted(date: .complete, time: .shortened)).",
                    tools: tools) { name, args in
                        await AgentTools.run(name, args, context: ctx, store: st, status: { summary }, confirm: { await self.askConfirm($0) })
                    }
            }
            guard let chat = localChat else { throw LocalModel.Failure.notLoaded }
            return try await chat.send(q)
        }
        #endif
        var history = apiHistory
        let answer = try await ClaudeAssistant.agent(q, history: &history) { name, args in
            await AgentTools.run(name, args, context: context, store: store, status: { summary }, confirm: { await askConfirm($0) })
        }
        apiHistory = history
        return answer
    }

    fileprivate func askConfirm(_ text: String) async -> Bool {
        await withCheckedContinuation { c in
            confirmReply = c
            confirmText = text
        }
    }

    fileprivate func answerConfirm(_ yes: Bool) {
        let c = confirmReply
        confirmReply = nil
        confirmText = nil
        c?.resume(returning: yes)
    }

    /// Reads the text in a photo on the phone and hands it to the assistant.
    fileprivate func readPhoto(_ item: PhotosPickerItem) {
        readingPhoto = true
        Task {
            defer { readingPhoto = false }
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                lines.append(ChatLine(role: .notice, text: "Couldn't open that photo."))
                return
            }
            let text = await AgentTools.readText(from: image)
            guard !text.isEmpty else {
                lines.append(ChatLine(role: .notice, text: "No text found in the photo."))
                return
            }
            let ask = input.trimmingCharacters(in: .whitespacesAndNewlines)
            input = ""
            if agentOn {
                send("Text read from my photo:\n\"\"\"\n\(text.prefix(4000))\n\"\"\"\n\n\(ask.isEmpty ? "What is this? If it's a job, booking or delivery note, offer to add it to my jobs." : ask)")
            } else {
                lines.append(ChatLine(role: .assistant, text: "Text in the photo:\n\n\(text)"))
                lines.append(ChatLine(role: .notice, text: "Turn on the AI agent (⚙︎) to turn photos into jobs, notes or reminders."))
            }
        }
    }
}

/// Turn Claude on and manage the API key.
struct AssistantSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var store
    @State private var keyText = ""
    @State private var hasKey = KeychainKey.hasKey

    var body: some View {
        Form {
            OnDeviceAISection()
            Section {
                Toggle("Use Claude AI for questions", isOn: Binding(get: { store.settings.assistantUseClaude }, set: { store.settings.assistantUseClaude = $0 }))
                    .disabled(!hasKey)
            } footer: {
                Text("When on, each question is sent to Anthropic's Claude (\(ClaudeAssistant.model)) with a summary of your current hours, the last 7 days, this week's pay, your next plan and vehicle height. Your name, location, routes and notes are not sent. Without it, the assistant answers common questions offline from your records.")
            }
            Section {
                if hasKey {
                    Label("API key saved in the Keychain", systemImage: "key.fill").foregroundStyle(.green)
                    Button("Remove key", role: .destructive) {
                        KeychainKey.delete()
                        hasKey = false
                        store.settings.assistantUseClaude = false
                    }
                } else {
                    SecureField("Paste your Anthropic API key", text: $keyText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save key") {
                        KeychainKey.save(keyText.trimmingCharacters(in: .whitespacesAndNewlines))
                        keyText = ""
                        hasKey = KeychainKey.hasKey
                        if hasKey { store.settings.assistantUseClaude = true }
                    }
                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
                    Link("Get an API key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
            } header: {
                Text("Your Anthropic API key")
            } footer: {
                Text("Stored only in this iPhone's Keychain — never in backups or settings. Claude is paid per use on your Anthropic account (typically a penny or two per question); set a spending limit in the Anthropic Console.")
            }
        }
        .navigationTitle("Assistant settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Done") { dismiss() } }
    }
}

/// Download and switch on the on-device model.
struct OnDeviceAISection: View {
    @Environment(SettingsStore.self) private var store
    @State private var progress: Double?
    @State private var error: String?

    var body: some View {
        Section {
            #if canImport(HGVAI)
            Toggle("Use on-device AI agent", isOn: Binding(get: { store.settings.assistantUseLocal }, set: { on in
                store.settings.assistantUseLocal = on
                if on { store.settings.assistantUseClaude = false }
            }))
            Picker("Model", selection: Binding(get: { store.settings.assistantLocalModel }, set: { store.settings.assistantLocalModel = $0 })) {
                ForEach(LocalModelOption.all) { m in Text("\(m.title) · \(m.sizeMB) MB").tag(m.id) }
            }
            if let m = LocalModelOption.all.first(where: { $0.id == store.settings.assistantLocalModel }) {
                Text(m.detail).font(.caption).foregroundStyle(.secondary)
            }
            if let progress {
                ProgressView(value: progress) { Text(progress < 0.9 ? "Downloading…" : "Loading…") }
            } else {
                Button(LocalModel.shared.loadedID == store.settings.assistantLocalModel ? "Model ready ✓" : "Download / load model") {
                    error = nil
                    progress = 0
                    Task {
                        do {
                            try await LocalModel.shared.load(store.settings.assistantLocalModel) { p in
                                Task { @MainActor in progress = p }
                            }
                        } catch { self.error = error.localizedDescription }
                        progress = nil
                    }
                }
                let mb = LocalModel.downloadedMB()
                if mb > 0 {
                    Button("Delete downloaded models (\(mb) MB)", role: .destructive) { LocalModel.shared.deleteDownloads() }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            #else
            Label("On-device AI isn't included in this build yet.", systemImage: "cpu")
            #endif
        } header: {
            Text("On-device AI (free, private)")
        } footer: {
            Text("An open AI model (Qwen, by Alibaba, Apache-2.0 licence) runs on this iPhone with Apple's MLX. It can use the app's tools: plan, change or cancel jobs, add stops, notes, reminders and fuel, switch activity, vehicle or trailer, and read photos of delivery notes. The model downloads once over Wi-Fi from Hugging Face; after that nothing leaves the phone. Slower and less clever than Claude, and it uses battery while answering.")
        }
    }
}
