import SwiftUI

/// Jobs tab: planner (calendar), vehicles & trailers, fuel & resources, and notes.
struct JobsTab: View {
    @Environment(SettingsStore.self) private var store
    @State private var section = ""
    @State private var showingSettings = false

    var body: some View {
        let tabs = store.settings.blocks(.jobsTabs)
        let current = tabs.contains(section) ? section : tabs[0]
        NavigationStack {
            VStack(spacing: 0) {
                if tabs.count > 1 {
                    Picker("Show", selection: Binding(get: { current }, set: { section = $0 })) {
                        ForEach(tabs, id: \.self) { id in
                            Text(LayoutPage.jobsTabs.blocks.first { $0.id == id }?.title ?? id).tag(id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
                switch current {
                case "vehicles": VehiclesView()
                case "fuel": ResourcesView()
                case "notes": NotebookView(embedded: true)
                default: CalendarHistoryView(planningOnly: true)
                }
            }
            .navigationTitle("Jobs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarLeading) { EditLayoutButton(pages: [.jobsTabs, .debrief]) }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    JobSettingsView().toolbar { Button("Done") { showingSettings = false } }
                }
            }
        }
    }
}

/// Settings for jobs and vehicles.
struct JobSettingsView: View {
    @Environment(SettingsStore.self) private var store
    var body: some View {
        Form {
            Section {
                NavigationLink { ShiftSettingsView() } label: { Label("Shift start & double-manning", systemImage: "play.circle") }
                NavigationLink { VehiclesView() } label: { Label("Vehicles & trailers", systemImage: "box.truck") }
                NavigationLink { LookupSettingsView() } label: { Label("Registration & postcode lookup", systemImage: "magnifyingglass") }
                NavigationLink { UnitsSettingsView() } label: { Label("Units (miles/km, feet/metres)", systemImage: "ruler") }
            }
        }
        .navigationTitle("Jobs settings")
    }
}

/// Earnings tab: earnings with its own pay settings.
struct EarningsTab: View {
    @State private var showingSettings = false
    var body: some View {
        NavigationStack {
            EarningsView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    }
                    ToolbarItem(placement: .topBarLeading) { EditLayoutButton(pages: [.earnings]) }
                }
                .sheet(isPresented: $showingSettings) {
                    NavigationStack {
                        Form {
                            NavigationLink { PaySettingsView() } label: { Label("Pay rates, holiday & bonuses", systemImage: "sterlingsign.circle") }
                            NavigationLink { OvertimeSettingsView() } label: { Label("Overtime", systemImage: "clock.badge.checkmark") }
                        }
                        .navigationTitle("Earnings settings")
                        .toolbar { Button("Done") { showingSettings = false } }
                    }
                }
        }
    }
}

/// Opens one day of the driver log from elsewhere (e.g. the planner).
struct DriverDayLink: View {
    var day: Date
    var body: some View {
        DriverDayView(day: day)
            .navigationTitle(Fmt.day(day))
    }
}

/// Optional DVLA key for looking up vehicles by registration. (Postcode/address search uses Apple Maps and needs no key.)
struct LookupSettingsView: View {
    @State private var keyText = ""
    @State private var hasKey = DVLAKey.hasKey

    var body: some View {
        Form {
            Section {
                if hasKey {
                    Label("DVLA key saved in the Keychain", systemImage: "key.fill").foregroundStyle(.green)
                    Button("Remove key", role: .destructive) { DVLAKey.delete(); hasKey = false }
                } else {
                    SecureField("Paste your DVLA Vehicle Enquiry API key", text: $keyText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save key") {
                        DVLAKey.save(keyText.trimmingCharacters(in: .whitespacesAndNewlines))
                        keyText = ""
                        hasKey = DVLAKey.hasKey
                    }
                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                    Link("Register for a free key on GOV.UK", destination: URL(string: "https://register-for-ves.driver-vehicle-licensing.api.gov.uk/")!)
                }
            } header: {
                Text("Registration lookup (UK)")
            } footer: {
                Text("With a key, typing or scanning a registration fills in make, colour, fuel, year and MOT/tax status from the DVLA. Only the registration is sent. Without a key, enter details by hand.")
            }
            Section {
                Text("Postcode and address search uses Apple Maps as you type — no key needed. Pick a result or type the address yourself.")
                    .font(.footnote)
            } header: {
                Text("Postcode & address search")
            }
        }
        .navigationTitle("Lookups")
    }
}
