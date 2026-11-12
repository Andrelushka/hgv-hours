import SwiftData
import SwiftUI

/// Settings → Reset & erase: choose which records to erase and which settings to put back to default.
struct ResetView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var choice = ResetService.Choice()
    @State private var counts: [DataGroup: Int] = [:]
    @State private var confirming = false
    @State private var typed = ""
    @State private var done = false

    private let confirmWord = "ERASE"

    var body: some View {
        Form {
            Section {
                preset("Factory reset — erase everything", "trash.fill", .red,
                       data: Set(DataGroup.allCases), settings: Set(SettingsGroup.allCases))
                preset("Reset all settings, keep my records", "gearshape.arrow.triangle.2.circlepath", .orange,
                       data: [], settings: Set(SettingsGroup.allCases))
                preset("Erase all records, keep my settings", "externaldrive.badge.minus", .orange,
                       data: Set(DataGroup.allCases).subtracting([.assistant]), settings: [])
                if !choice.isEmpty {
                    Button("Clear selection") { choice = .init() }
                }
            } header: {
                Text("Quick choices")
            } footer: {
                Text("Or tick exactly what you want below.")
            }

            Section {
                ForEach(DataGroup.allCases) { g in
                    toggleRow(title: g.title, detail: g.detail, symbol: g.symbol, count: counts[g],
                              isOn: Binding(get: { choice.data.contains(g) },
                                            set: { on in if on { choice.data.insert(g) } else { choice.data.remove(g) } }))
                }
            } header: {
                HStack {
                    Text("Erase records")
                    Spacer()
                    allButton(choice.data.count == DataGroup.allCases.count) {
                        choice.data = $0 ? Set(DataGroup.allCases) : []
                    }
                }
            }

            Section {
                ForEach(SettingsGroup.allCases) { g in
                    toggleRow(title: g.title, detail: g.detail, symbol: g.symbol, count: nil,
                              isOn: Binding(get: { choice.settings.contains(g) },
                                            set: { on in if on { choice.settings.insert(g) } else { choice.settings.remove(g) } }))
                }
            } header: {
                HStack {
                    Text("Reset settings to default")
                    Spacer()
                    allButton(choice.settings.count == SettingsGroup.allCases.count) {
                        choice.settings = $0 ? Set(SettingsGroup.allCases) : []
                    }
                }
            }

            Section {
                NavigationLink { BackupView() } label: {
                    Label("Make a backup first", systemImage: "externaldrive.fill")
                }
                Button(role: .destructive) {
                    typed = ""
                    confirming = true
                } label: {
                    Label(choice.isEverything ? "Factory reset" : "Reset & erase selected", systemImage: "exclamationmark.triangle.fill")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .disabled(choice.isEmpty)
            } footer: {
                Text(summary)
            }
        }
        .navigationTitle("Reset & erase")
        .onAppear { counts = ResetService.counts(context: context) }
        .alert("This can't be undone", isPresented: $confirming) {
            TextField("Type \(confirmWord)", text: $typed)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Erase", role: .destructive) {
                guard typed.trimmingCharacters(in: .whitespaces).uppercased() == confirmWord else { return }
                ResetService.erase(choice, context: context, store: store)
                counts = ResetService.counts(context: context)
                choice = .init()
                done = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(summary)\n\nType \(confirmWord) to confirm.")
        }
        .alert("Done", isPresented: $done) {
            Button("OK") { dismiss() }
        } message: {
            Text("The selected data was erased and settings were reset.")
        }
        .sensoryFeedback(.warning, trigger: confirming)
    }

    private var summary: String {
        if choice.isEmpty { return "Nothing selected." }
        if choice.isEverything { return "Everything will be erased and all settings go back to default, as if the app were newly installed." }
        var parts: [String] = []
        if !choice.data.isEmpty {
            let total = choice.data.reduce(0) { $0 + (counts[$1] ?? 0) }
            parts.append("Erase \(choice.data.count) type\(choice.data.count == 1 ? "" : "s") of record (\(total) item\(total == 1 ? "" : "s")).")
        }
        if !choice.settings.isEmpty {
            parts.append("Reset \(choice.settings.count) group\(choice.settings.count == 1 ? "" : "s") of settings.")
        }
        let kept = DataGroup.allCases.count - choice.data.count
        if kept > 0 && !choice.data.isEmpty { parts.append("Everything else is kept.") }
        return parts.joined(separator: " ")
    }

    private func preset(_ title: String, _ symbol: String, _ color: Color, data: Set<DataGroup>, settings: Set<SettingsGroup>) -> some View {
        let selected = choice.data == data && choice.settings == settings
        return Button {
            withAnimation { choice = .init(data: data, settings: settings) }
        } label: {
            HStack {
                Label(title, systemImage: symbol).foregroundStyle(color)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(color).fontWeight(.bold) }
            }
        }
    }

    private func allButton(_ allOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        Button(allOn ? "None" : "All") { withAnimation { set(!allOn) } }
            .font(.caption.weight(.semibold))
            .textCase(nil)
    }

    private func toggleRow(title: String, detail: String, symbol: String, count: Int?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(isOn.wrappedValue ? .red : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(LocalizedStringKey(title))
                        if let count, count > 0 {
                            Text("\(count)").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                    }
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .tint(.red)
    }
}
