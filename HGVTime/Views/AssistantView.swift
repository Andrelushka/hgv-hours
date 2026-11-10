import SwiftUI
import SwiftData

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

    private var claudeOn: Bool { store.settings.assistantUseClaude && KeychainKey.hasKey }

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
            Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { AssistantSettingsView() } }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(claudeOn ? "Claude AI is on" : "Offline answers", systemImage: claudeOn ? "sparkles" : "bolt.horizontal.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(claudeOn ? .purple : .accentColor)
            Text(claudeOn
                 ? "Ask anything about your hours, rest, pay or jobs. Your question and a summary of your records are sent to Anthropic to answer it."
                 : "Ask about driving left, breaks, rest, next start, 15h days, earnings, weekly rest or vehicle height. Answers come from your records on this iPhone. Turn on Claude AI (⚙︎ top right) for any other question.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background((claudeOn ? Color.purple : Color.accentColor).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func bubble(_ line: ChatLine) -> some View {
        HStack {
            if line.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(line.text)).font(.subheadline)
                if line.role == .assistant {
                    Text(line.byClaude ? "Claude" : "From your records").font(.caption2).foregroundStyle(.secondary)
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
            TextField("Ask a question…", text: $input, axis: .vertical)
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
        if let last = analysis.shifts.last, Calendar.hgv.isDateInToday(last.period.start) {
            dash.earnedShift = PayCalculator.calculate(shifts: [last], nightOuts: 0, settings: settings.pay).total
        }
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

    private func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking else { return }
        input = ""
        lines.append(ChatLine(role: .user, text: q))
        let f = facts()
        if claudeOn {
            thinking = true
            let history = apiHistory
            Task {
                do {
                    let reply = try await ClaudeAssistant.ask(q, facts: f, history: history)
                    apiHistory.append(["role": "user", "content": "My data right now:\n\(f.summary)\n\nQuestion: \(q)"])
                    apiHistory.append(["role": "assistant", "content": reply.rawContent])
                    lines.append(ChatLine(role: .assistant, text: reply.text, byClaude: true))
                } catch {
                    // Fall back to the offline answer if there is one.
                    if let offline = OfflineAssistant.answer(q, f) {
                        lines.append(ChatLine(role: .assistant, text: offline))
                    }
                    lines.append(ChatLine(role: .notice, text: error.localizedDescription))
                }
                thinking = false
            }
        } else if let offline = OfflineAssistant.answer(q, f) {
            lines.append(ChatLine(role: .assistant, text: offline))
        } else {
            lines.append(ChatLine(role: .notice, text: "I can answer questions about driving left, breaks, rest, next start, 15h and 10h days, earnings, weekly rest, infringements and vehicle height. For anything else, turn on Claude AI with ⚙︎ (top right)."))
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
