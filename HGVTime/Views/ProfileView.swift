import SwiftUI

/// Something on your licence or card that expires.
struct ExpiryItem: Identifiable {
    var id: String { title }
    var title: String
    var date: Date
    var symbol: String
    var daysLeft: Int { Calendar.hgv.dateComponents([.day], from: Calendar.hgv.startOfDay(for: .now), to: Calendar.hgv.startOfDay(for: date)).day ?? 0 }
}

extension AppSettings {
    var expiries: [ExpiryItem] {
        var list: [ExpiryItem] = []
        func add(_ t: String, _ v: Double, _ s: String) { if v > 0 { list.append(ExpiryItem(title: t, date: Date(timeIntervalSince1970: v), symbol: s)) } }
        add("Driving licence", licenceExpiry, "person.text.rectangle")
        add("Tacho driver card", cardExpiry, "creditcard")
        add("Driver CPC (DQC)", cpcExpiry, "graduationcap")
        add("Medical (D4)", medicalDue, "cross.case")
        return list.sorted { $0.date < $1.date }
    }

    /// Expiries inside the warning window.
    var expiriesDueSoon: [ExpiryItem] { expiries.filter { $0.daysLeft <= expiryWarningDays } }
}

/// Register / edit the driver profile.
struct ProfileView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Shown as first-time registration.
    var registering = false

    var body: some View {
        @Bindable var store = store
        Form {
            if registering {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create your driver profile").font(.title2.weight(.bold))
                        Text("It stays on this iPhone — no account or password is sent anywhere. It's used on timesheets and to remind you before your licence, card, CPC or medical expire.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Driver") {
                TextField("Full name", text: $store.settings.driverName).textContentType(.name).submitLabel(.done)
                TextField("Employer / agency", text: $store.settings.employer).submitLabel(.done)
                TextField("Phone (optional)", text: $store.settings.phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                TextField("Licence categories, e.g. C, C+E", text: $store.settings.licenceCategories).textInputAutocapitalization(.characters)
                TextField("Driver card number (optional)", text: $store.settings.driverCardNumber).textInputAutocapitalization(.characters)
            }
            Section {
                expiryRow("Driving licence", value: $store.settings.licenceExpiry)
                expiryRow("Tacho driver card", value: $store.settings.cardExpiry)
                expiryRow("Driver CPC (DQC)", value: $store.settings.cpcExpiry)
                expiryRow("Medical (D4) due", value: $store.settings.medicalDue)
                Stepper(value: $store.settings.expiryWarningDays, in: 7...180, step: 7) {
                    LabeledContent("Remind me", value: "\(store.settings.expiryWarningDays) days before")
                }
            } header: {
                Text("Expiry dates")
            } footer: {
                Text("Tacho cards last 5 years. Driver CPC needs 35 hours of training every 5 years. A D4 medical is needed at 45, then every 5 years to 65, then every year.")
            }
            if registering {
                Section {
                    Button {
                        store.settings.profileCreated = true
                        dismiss()
                    } label: {
                        Text("Create profile").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.settings.driverName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Skip for now") {
                        store.settings.profileCreated = true
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(registering ? "Welcome" : "Driver profile")
        .keyboardDoneButton()
        .interactiveDismissDisabled(registering)
    }

    private func expiryRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { value.wrappedValue > 0 },
                set: { value.wrappedValue = $0 ? (Calendar.hgv.date(byAdding: .year, value: 1, to: .now) ?? .now).timeIntervalSince1970 : 0 }))
            if value.wrappedValue > 0 {
                DatePicker("", selection: Binding(
                    get: { Date(timeIntervalSince1970: value.wrappedValue) },
                    set: { value.wrappedValue = $0.timeIntervalSince1970 }), displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }
}

/// Warning on Today when something expires soon.
struct ExpiryBanner: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        let due = store.settings.expiriesDueSoon
        if !due.isEmpty {
            NavigationLink { ProfileView() } label: {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(due) { item in
                        Label(item.daysLeft < 0 ? "\(item.title) expired \(-item.daysLeft) days ago"
                              : "\(item.title) expires in \(item.daysLeft) day\(item.daysLeft == 1 ? "" : "s") (\(Fmt.day(item.date)))",
                              systemImage: item.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.daysLeft < 14 ? .red : .orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}
