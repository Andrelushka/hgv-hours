import CoreLocation
import SwiftUI

// MARK: - Emergency

/// Emergency numbers with call buttons, where you are (to read out), and your own contacts.
struct EmergencyView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var location: CLLocation?
    @State private var place = ""
    @State private var locating = false
    @State private var editingContacts = false

    var body: some View {
        List {
            Section {
                Label("Stop safely first. Use the phone only when parked or hands-free — in an emergency, put on your hazard lights and get everyone to a safe place.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.red)
            }
            Section {
                if let location {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.isEmpty ? String(localized: "Finding the address…") : place).font(.headline)
                        Text(String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).textSelection(.enabled)
                        if location.horizontalAccuracy > 0 {
                            Text("Accurate to about \(Int(location.horizontalAccuracy)) m").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ShareLink(item: "\(place)\nhttps://maps.apple.com/?ll=\(location.coordinate.latitude),\(location.coordinate.longitude)") {
                        Label("Send my location", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button { Task { await locate() } } label: {
                        Label(locating ? "Finding where you are…" : "Show where I am", systemImage: "location.fill")
                    }
                    .disabled(locating)
                }
            } header: {
                Text("Where you are")
            } footer: {
                Text("Read this to the operator. On a motorway, the marker posts on the hard shoulder and the driver location signs also tell them where you are.")
            }
            Section("United Kingdom") {
                ForEach(EmergencyNumbers.uk, id: \.self) { row($0) }
            }
            Section {
                ForEach(store.settings.emergencyContacts) { c in
                    callRow(title: c.label.isEmpty ? c.number : c.label, number: c.number, detail: nil, symbol: "person.crop.circle.fill", urgent: false)
                }
                Button { editingContacts = true } label: {
                    Label(store.settings.emergencyContacts.isEmpty ? "Add your own numbers" : "Edit your numbers", systemImage: "square.and.pencil")
                }
            } header: {
                Text("Your numbers")
            } footer: {
                Text("Breakdown company, transport office, out-of-hours manager, next of kin…")
            }
            Section {
                ForEach(store.settings.companies.filter { !$0.phones.isEmpty }) { company in
                    ForEach(company.phones) { p in
                        callRow(title: "\(company.name) · \(p.label.isEmpty ? String(localized: "Phone") : p.label)", number: p.number,
                                detail: nil, symbol: "building.2.fill", urgent: false)
                    }
                }
            } header: {
                if store.settings.companies.contains(where: { !$0.phones.isEmpty }) { Text("Companies") }
            }
            Section("Abroad") {
                ForEach(EmergencyNumbers.abroad, id: \.self) { row($0) }
            }
        }
        .navigationTitle("Emergency")
        .task { await locate() }
        .sheet(isPresented: $editingContacts) {
            NavigationStack {
                PhoneListEditor(title: String(localized: "Your numbers"), phones: Binding(
                    get: { store.settings.emergencyContacts }, set: { store.settings.emergencyContacts = $0 }))
            }
        }
    }

    private func row(_ e: EmergencyNumbers.Entry) -> some View {
        callRow(title: e.title, number: e.number, detail: e.detail, symbol: e.symbol, urgent: e.urgent)
    }

    private func callRow(title: String, number: String, detail: String?, symbol: String, urgent: Bool) -> some View {
        Button {
            if let url = PhoneContact.callURL(number) { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title3).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background((urgent ? Color.red : Color.blue).gradient, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 6)
                Label(number, systemImage: "phone.fill")
                    .font((urgent ? Font.headline : .subheadline.weight(.semibold)).monospacedDigit())
                    .foregroundStyle(urgent ? .red : .blue)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityLabel("Call \(title), \(number)")
    }

    private func locate() async {
        locating = true
        defer { locating = false }
        guard let loc = await LocationOnce.shared.current() else { return }
        location = loc
        place = await LocationOnce.shared.placeName(for: loc)
    }
}

/// Today: a red button that opens the emergency page.
struct EmergencyTile: View {
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "sos").font(.title3.weight(.bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Emergency").font(.headline)
                    Text("999 · 112 · bridge strike · where you are").font(.caption2).opacity(0.9).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) {
            NavigationStack {
                EmergencyView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { open = false } } }
            }
        }
    }
}

/// Add, edit, reorder and delete labelled phone numbers.
struct PhoneListEditor: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    @Binding var phones: [PhoneContact]

    var body: some View {
        Form {
            PhoneRowsSection(phones: $phones)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .confirmationAction) { Button("Done") { phones.removeAll { $0.number.isEmpty && $0.label.isEmpty }; dismiss() } }
        }
    }
}

/// Rows of label + number fields with an Add button.
struct PhoneRowsSection: View {
    @Binding var phones: [PhoneContact]

    var body: some View {
        Section {
            ForEach($phones) { $p in
                VStack(spacing: 6) {
                    TextField("Label, e.g. Transport office", text: $p.label)
                    TextField("Phone number", text: $p.number)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
            }
            .onDelete { phones.remove(atOffsets: $0) }
            .onMove { phones.move(fromOffsets: $0, toOffset: $1) }
            Button { phones.append(PhoneContact()) } label: { Label("Add a number", systemImage: "plus.circle.fill") }
        } header: {
            Text("Phone numbers")
        }
    }
}

// MARK: - Companies

/// Your companies / agency clients.
struct CompaniesView: View {
    @Environment(SettingsStore.self) private var store
    @State private var editing: CompanyProfile?
    @State private var isNew = false

    var body: some View {
        List {
            if store.settings.companies.isEmpty {
                ContentUnavailableView("No companies yet", systemImage: "building.2",
                                       description: Text("Add the companies and agency clients you drive for: their site address and phone numbers, ready to call or navigate to from Today."))
            }
            ForEach(store.settings.companies) { c in
                Button { isNew = false; editing = c } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name.isEmpty ? String(localized: "No name") : c.name).font(.headline).foregroundStyle(.primary)
                            if !c.fullAddress.isEmpty { Text(c.fullAddress).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            Text("\(c.phones.count) phone number(s)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if c.showOnToday { Image(systemName: "pin.fill").foregroundStyle(.orange).accessibilityLabel("On Today") }
                    }
                }
            }
            .onDelete { store.settings.companies.remove(atOffsets: $0) }
            .onMove { store.settings.companies.move(fromOffsets: $0, toOffset: $1) }
        }
        .navigationTitle("Companies")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isNew = true; editing = CompanyProfile() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add company")
            }
        }
        .sheet(item: $editing) { c in
            NavigationStack {
                CompanyEditor(company: c, isNew: isNew) { saved in
                    if let i = store.settings.companies.firstIndex(where: { $0.id == saved.id }) {
                        store.settings.companies[i] = saved
                    } else {
                        store.settings.companies.append(saved)
                    }
                } onDelete: {
                    store.settings.companies.removeAll { $0.id == c.id }
                }
            }
        }
    }
}

struct CompanyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var company: CompanyProfile
    var isNew: Bool
    var onSave: (CompanyProfile) -> Void
    var onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("Company name", text: $company.name)
                Toggle("Always show on Today", isOn: $company.showOnToday)
            } footer: {
                Text("It also shows on Today whenever today's job is for this company (same name as in the job).")
            }
            Section("Location") {
                AddressLookupFields(address: $company.address, postcode: $company.postcode,
                                    latitude: $company.latitude, longitude: $company.longitude,
                                    addressLabel: "Site address / depot")
            }
            PhoneRowsSection(phones: $company.phones)
            Section {
                TextField("Email", text: $company.email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Notes (gate code, where to park, contact name…)", text: $company.notes, axis: .vertical)
            }
            if !isNew {
                Section { Button("Delete company", role: .destructive) { onDelete(); dismiss() } }
            }
        }
        .navigationTitle(isNew ? "New company" : company.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    company.phones.removeAll { $0.number.trimmingCharacters(in: .whitespaces).isEmpty }
                    onSave(company)
                    dismiss()
                }
                .disabled(company.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

/// Today: your company (today's job company and any you pinned) with call and navigate buttons.
struct CompanyTile: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.openURL) private var openURL
    var jobCompany: String
    @State private var navigating: MapScreen.NavTarget?
    @State private var showingAll = false

    static func shown(_ settings: AppSettings, jobCompany: String) -> [CompanyProfile] {
        settings.companies.filter { $0.showOnToday || $0.matches(jobCompany) }
    }

    var body: some View {
        let companies = Self.shown(store.settings, jobCompany: jobCompany)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Company", systemImage: "building.2.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { showingAll = true } label: { Image(systemName: "list.bullet") }
                    .buttonStyle(.borderless).accessibilityLabel("All companies")
            }
            if companies.isEmpty {
                Text("Add your companies with their address and phone numbers, then pin one here or it appears with today's job.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Add a company") { showingAll = true }.buttonStyle(.bordered).font(.caption.weight(.semibold))
            }
            ForEach(companies) { c in
                VStack(alignment: .leading, spacing: 6) {
                    Text(c.name).font(.headline)
                    if !c.fullAddress.isEmpty { Text(c.fullAddress).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    if !c.notes.isEmpty { Text(c.notes).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                    FlowRow(spacing: 6) {
                        ForEach(c.phones) { p in
                            Button {
                                if let url = p.callURL { openURL(url) }
                            } label: {
                                Label(p.label.isEmpty ? p.number : p.label, systemImage: "phone.fill").font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent).tint(.green)
                            .accessibilityLabel("Call \(c.name) \(p.label) \(p.number)")
                        }
                        if c.latitude != nil || !c.fullAddress.isEmpty {
                            Button {
                                navigating = MapScreen.NavTarget(name: c.name,
                                                                 coordinate: c.latitude.flatMap { lat in c.longitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } },
                                                                 address: c.fullAddress)
                            } label: {
                                Label("Navigate", systemImage: "location.north.fill").font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                        }
                        if !c.email.isEmpty, let url = URL(string: "mailto:\(c.email)") {
                            Button { openURL(url) } label: { Label("Email", systemImage: "envelope.fill").font(.caption.weight(.semibold)) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                if c.id != companies.last?.id { Divider() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .fullScreenCover(item: $navigating) { NavigationModeView(target: $0) }
        .sheet(isPresented: $showingAll) {
            NavigationStack {
                CompaniesView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingAll = false } } }
            }
        }
    }
}
