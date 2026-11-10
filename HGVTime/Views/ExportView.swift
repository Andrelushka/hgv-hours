import SwiftUI
import SwiftData

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \NightOut.date) private var nightOuts: [NightOut]
    @Query(sort: \PayItem.date) private var payItems: [PayItem]

    @State private var from: Date
    @State private var to: Date
    @State private var format: ExportFormat = .pdfTimesheet
    @State private var includePay = true
    @State private var fileURL: URL?
    @State private var errorMessage: String?

    init(initialFrom: Date? = nil, initialTo: Date? = nil) {
        let cal = Calendar.hgv
        let weekStart = cal.startOfFixedWeek(for: .now)
        _from = State(initialValue: initialFrom ?? weekStart)
        _to = State(initialValue: initialTo ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Period") {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                    HStack {
                        quickRange("This week", weeksBack: 0)
                        quickRange("Last week", weeksBack: 1)
                        quickRange("Last 4 weeks", weeksBack: 3, span: 4)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
                Section("Format") {
                    Picker("Format", selection: $format) {
                        ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if format == .pdfTimesheet {
                        Toggle("Include pay estimate", isOn: $includePay)
                    }
                }
                Section {
                    Button("Create file", action: create)
                    if let fileURL {
                        ShareLink(item: fileURL) {
                            Label("Share \(fileURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Share by email, AirDrop, Files or WhatsApp. CSV opens in Excel, Numbers and Google Sheets.")
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .onChange(of: format) { fileURL = nil }
            .onChange(of: from) { fileURL = nil }
            .onChange(of: to) { fileURL = nil }
        }
    }

    private func quickRange(_ title: String, weeksBack: Int, span: Int = 1) -> some View {
        Button(title) {
            let cal = Calendar.hgv
            let thisWeek = cal.startOfFixedWeek(for: .now)
            let start = cal.date(byAdding: .day, value: -7 * weeksBack, to: thisWeek) ?? thisWeek
            from = start
            to = min(.now, cal.date(byAdding: .day, value: 7 * span - 1, to: start) ?? .now)
        }
    }

    private func create() {
        do {
            fileURL = try ExportService.export(format: format, from: from, to: to,
                                               entries: entries.map(\.snapshot),
                                               nightOuts: nightOuts.map(\.date),
                                               settings: store.settings, includePay: includePay,
                                               payItems: payItems.map(\.snapshot))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
