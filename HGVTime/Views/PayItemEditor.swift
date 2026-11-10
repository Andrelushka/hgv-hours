import SwiftUI
import SwiftData

/// Add a holiday day or a one-off bonus / extra payment.
struct PayItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store

    @State private var kind: PayItemKind
    @State private var date: Date
    @State private var title = ""
    @State private var amount: Double = 0
    @State private var hours: Double

    init(defaultDate: Date = .now, kind: PayItemKind = .bonus, hours: Double = 8) {
        _kind = State(initialValue: kind)
        _date = State(initialValue: defaultDate)
        _hours = State(initialValue: hours)
    }

    var body: some View {
        let p = store.settings.pay
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(PayItemKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField(kind == .bonus ? "Name, e.g. Christmas bonus" : "Note (optional)", text: $title)
                        .submitLabel(.done)
                }
                if kind == .bonus {
                    Section {
                        LabeledContent("Amount") {
                            HStack(spacing: 2) {
                                Text(p.currencySymbol).foregroundStyle(.secondary)
                                TextField("0.00", value: $amount, format: .number.precision(.fractionLength(2)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 110)
                            }
                        }
                    } footer: {
                        Text("Use a minus amount for a deduction.")
                    }
                } else {
                    Section {
                        Text(p.holiday == .included
                             ? "Your holiday pay is already included in your rate, so this day is recorded but not paid again."
                             : "Paid at your average day's pay over the last 52 weeks (worked out automatically).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(kind == .bonus ? "Add bonus" : "Add holiday")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(PayItem(date: Calendar.hgv.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date,
                                               kind: kind, title: title, amount: amount, hours: hours))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(kind == .bonus && amount == 0)
                }
            }
        }
    }
}
