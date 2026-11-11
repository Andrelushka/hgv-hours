import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.modelContext) private var context
    @State private var confirmErase = false
    @State private var exporting = false
    /// True when pushed inside another navigation stack (from the Today gear button).
    var embedded = false

    var body: some View {
        if embedded {
            form
        } else {
            NavigationStack { form }
        }
    }

    private var form: some View {
        let s = store.settings
        return Group {
            Form {
                Section("Recording") {
                    NavigationLink { ShiftSettingsView() } label: {
                        SettingsRow(title: "Shift", symbol: "play.circle.fill", color: .green,
                                    value: "Start with \(s.shiftStartKind.shortTitle.lowercased())")
                    }
                    NavigationLink { InCabSettingsView() } label: {
                        SettingsRow(title: "In-cab automatic", symbol: "box.truck.fill", color: .blue,
                                    value: s.autoDetectEnabled ? "On" : "Off")
                    }
                }

                Section("Rules") {
                    NavigationLink { CountryRulesView() } label: {
                        SettingsRow(title: "Country & rules", symbol: "globe.europe.africa.fill", color: .teal,
                                    value: "\(s.region.flag) \(s.region.isEuropean ? s.region.title : s.region.title.components(separatedBy: " (").first ?? "")")
                    }
                    NavigationLink { DriversHoursSettingsView() } label: {
                        SettingsRow(title: "Drivers' hours", symbol: "steeringwheel", color: .indigo,
                                    value: s.primaryRegime.shortTitle)
                    }
                    NavigationLink { WorkingTimeSettingsView() } label: {
                        SettingsRow(title: "Working time", symbol: "briefcase.fill", color: .orange,
                                    value: s.applyWorkingTime ? "\(s.wtdReferenceWeeks)-week average" : "Off")
                    }
                }

                Section {
                    NavigationLink { TodayCustomiseView() } label: {
                        SettingsRow(title: "Customise Today", symbol: "slider.horizontal.below.square.and.square.filled", color: .indigo, value: "")
                    }
                } footer: {
                    Text("Pay settings are in the Earnings tab (⚙︎). Vehicles, fuel and lookups are in the Jobs tab (⚙︎).")
                }

                Section("Alerts") {
                    NavigationLink { AlertSettingsView() } label: {
                        SettingsRow(title: "Notifications & Lock Screen", symbol: "bell.badge.fill", color: .red,
                                    value: s.notificationsEnabled ? "\(s.warningLeadMinutes) min before" : "Off")
                    }
                    NavigationLink { WakeLeaveSettingsView() } label: {
                        SettingsRow(title: "Wake-up & leave home", symbol: "alarm.waves.left.and.right.fill", color: .orange,
                                    value: s.wakeAlarmEnabled || s.leaveReminderEnabled ? "On" : "Off")
                    }
                    NavigationLink { RemindersView() } label: {
                        SettingsRow(title: "Reminders", symbol: "alarm.fill", color: .orange, value: "")
                    }
                    NavigationLink { VoiceSettingsView() } label: {
                        SettingsRow(title: "Spoken alerts", symbol: "speaker.wave.2.fill", color: .purple,
                                    value: s.voiceEnabled ? "On" : "Off")
                    }
                }

                Section("Driver & security") {
                    NavigationLink { LockSettingsView() } label: {
                        SettingsRow(title: "App lock", symbol: "faceid", color: .green, value: s.lockEnabled ? "On" : "Off")
                    }
                    NavigationLink { BackupView() } label: {
                        SettingsRow(title: "Backup & restore", symbol: "externaldrive.fill", color: .blue, value: "")
                    }
                    NavigationLink { ProfileView() } label: {
                        SettingsRow(title: "Driver profile", symbol: "person.crop.circle.fill", color: .gray,
                                    value: s.driverName.isEmpty ? "Not set" : s.driverName)
                    }
                }

                Section("Data") {
                    Button { exporting = true } label: {
                        SettingsRow(title: "Export timesheet", symbol: "square.and.arrow.up.fill", color: .blue, value: "PDF / CSV")
                    }
                    .foregroundStyle(.primary)
                    Button("Erase all activity data", role: .destructive) { confirmErase = true }
                }

                Section {
                    NavigationLink { ReportProblemView(kind: .bug) } label: {
                        SettingsRow(title: "Report a problem", symbol: "ant.fill", color: .red, value: "")
                    }
                    NavigationLink { AboutView() } label: {
                        SettingsRow(title: "About HGV Hours", symbol: "info.circle.fill", color: .blue,
                                    value: "Version \(AppInfo.version)")
                    }
                } header: {
                    Text("Help & about")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $exporting) { ExportView() }
            .confirmationDialog("Erase all recorded activities and night-outs? This can't be undone.",
                                isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) {
                    try? context.delete(model: ActivityEntry.self)
                    try? context.delete(model: NightOut.self)
                    try? context.save()
                    ActivityController.refreshSideEffects(context: context, settings: store.settings)
                }
            }
        }
    }
}

/// A settings row with a coloured icon and the current value.
struct SettingsRow: View {
    var title: String
    var symbol: String
    var color: Color
    var value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct ShiftSettingsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("Start shift with", selection: $store.settings.shiftStartKind) {
                    ForEach([DutyKind.otherWork, .drive, .availability]) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            } footer: {
                Text("“Start shift” records this first — usually other work for your walk-round check. “End shift” asks whether you're starting a daily rest (between shifts, 9h or 11h) or a weekly rest (24h or 45h).")
            }
            Section {
                Picker("Rules for new activities", selection: $store.settings.currentRegime) {
                    ForEach(Regime.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Double-manned", isOn: $store.settings.multiManned)
            } footer: {
                Text("With two drivers, each needs 9h of daily rest within 30h. Time in the passenger seat while the vehicle moves is recorded as POA.")
            }
        }
        .navigationTitle("Shift")
    }
}

struct InCabSettingsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var detector = AutoDriveDetector.shared

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("In cab — record driving automatically", isOn: $store.settings.autoDetectEnabled)
            } footer: {
                Text("Works like the tachograph: when the vehicle moves, Driving is recorded; when it stops, the activity below is recorded from the moment it stopped. Turn it off when you leave the cab (walking mode), so a car or bus ride isn't counted as driving. Uses GPS, so it uses more battery — keep the phone on charge in the cab.")
            }
            Section("When the vehicle stops") {
                Picker("Record", selection: $store.settings.autoStoppedKind) {
                    ForEach([DutyKind.otherWork, .availability, .rest]) { Text($0 == .rest ? "Break" : $0.title).tag($0) }
                }
                Picker("After stopped for", selection: $store.settings.autoStopDelaySeconds) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                }
            }
            Section {
                Stepper(value: $store.settings.autoMovingSpeedKmh, in: 5...30, step: 1) {
                    LabeledContent("Moving above", value: "\(Int(store.settings.autoMovingSpeedKmh)) km/h")
                }
            } footer: {
                Text("Speed needed for 8 seconds before driving starts. Raise it if walking or GPS drift is recorded as driving.")
            }
            Section {
                Toggle("Record overspeed", isOn: $store.settings.recordOverspeed)
                if store.settings.recordOverspeed {
                    Toggle("Automatic (vehicle & country)", isOn: $store.settings.autoSpeedLimit)
                    if store.settings.autoSpeedLimit {
                        LabeledContent("Now", value: SpeedLimits.describe(AutoDriveDetector.shared.speedLimitKmh))
                    } else {
                    Stepper(value: $store.settings.overspeedLimitKmh, in: 30...130, step: 1) {
                        LabeledContent("Overspeed above", value: "\(Int(store.settings.overspeedLimitKmh)) km/h (\(Int((store.settings.overspeedLimitKmh / 1.609).rounded())) mph)")
                    }
                    }
                }
            } header: {
                Text("Speed")
            } footer: {
                Text("Like the tachograph: more than 60 seconds in a row above this speed is an overspeed infringement. Shorter ones are recorded but not counted as infringements. Each event is saved with its time, top speed and location. Automatic uses the vehicle you're driving and your country: lorries over 3.5 t 90 km/h (56 mph) in the UK/EU, 100 km/h in Australia, 105 km/h in North America; vans use the road limit. A speed set on a vehicle always wins.")
            }
            Section {
                Toggle("Record harsh braking", isOn: $store.settings.recordHarshBraking)
                if store.settings.recordHarshBraking {
                    Stepper(value: $store.settings.harshBrakeMS2, in: 2.5...6, step: 0.1) {
                        LabeledContent("Sensitivity", value: String(format: "%.1f m/s² (%.2f g)", store.settings.harshBrakeMS2, store.settings.harshBrakeMS2 / 9.81))
                    }
                }
                Toggle("Road speed limits while navigating", isOn: $store.settings.onlineSpeedLimits)
            } header: {
                Text("Driving style")
            } footer: {
                Text("Harsh braking: a speed drop faster than this from 25 km/h or more, measured by GPS in in-cab mode. Lower = more sensitive; fleet systems typically use 0.3–0.4 g. Each event is saved with its time and place in the event log. Road speed limits come from OpenStreetMap: while navigating, your approximate position is sent to the OpenStreetMap Overpass service about once every 300 m.")
            }
            Section {
                Toggle("Save my route", isOn: $store.settings.recordRoute)
                Toggle("Save where events happen", isOn: $store.settings.recordEventLocations)
            } header: {
                Text("Map & event log")
            } footer: {
                Text("Your route and event locations are kept only on this iPhone, to show on the Map and in the Event log.")
            }
            Section {
                Text("Each minute is recorded as whichever activity filled most of it, as on a digital tachograph. A short movement during a break — e.g. moving up in a queue — doesn't interrupt the break.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Tachograph minute rule")
            }
            Section("Status") {
                LabeledContent("Location access", value: permissionText)
                if detector.needsAlwaysPermission {
                    Button("Allow “Always” (works with the phone locked)") { detector.requestAlways() }
                }
                if let kmh = detector.speedKmh {
                    LabeledContent("Current speed", value: "\(Int(kmh.rounded())) km/h")
                }
            }
        }
        .navigationTitle("In-cab automatic")
    }

    private var permissionText: String {
        switch detector.authorization {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While using the app"
        case .denied, .restricted: "Off — turn on in iPhone Settings"
        default: "Not asked yet"
        }
    }
}

struct DriversHoursSettingsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("Main rules", selection: $store.settings.primaryRegime) {
                    ForEach(Regime.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: store.settings.primaryRegime) { _, newValue in
                    store.settings.currentRegime = newValue
                }
            } footer: {
                Text("Assimilated rules (formerly EU rules) cover most HGVs over 3.5t in the UK and on UK–EU journeys. AETR applies to other international journeys and is almost identical. GB domestic rules cover most exempt vehicles.")
            }
            Section {
                Toggle("Two reduced weekly rests in a row", isOn: $store.settings.allowConsecutiveReducedWeekly)
            } header: {
                Text("International")
            } footer: {
                Text("Allows two consecutive reduced weekly rests outside the UK and your country of residence, with at least two regular weekly rests every four weeks.")
            }
        }
        .navigationTitle("Drivers' hours")
    }
}

struct WorkingTimeSettingsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var customWeeks = false

    var body: some View {
        @Bindable var store = store
        let weeks = store.settings.wtdReferenceWeeks
        Form {
            Section {
                Toggle("Apply working time rules", isOn: $store.settings.applyWorkingTime)
            } footer: {
                Text("Road Transport (Working Time) Regulations 2005: max 60h in a week, 48h average, no more than 6h work without a break, and a 10h limit in any shift that includes 00:00–04:00. Breaks and POA don't count as working time.")
            }
            if store.settings.applyWorkingTime {
                Section {
                    Picker("Reference period", selection: Binding(
                        get: { customWeeks || ![17, 26].contains(weeks) ? 0 : weeks },
                        set: { value in
                            if value == 0 { customWeeks = true } else { customWeeks = false; store.settings.wtdReferenceWeeks = value }
                        })) {
                        Text("17 weeks (standard)").tag(17)
                        Text("26 weeks (by agreement)").tag(26)
                        Text("Custom").tag(0)
                    }
                    if customWeeks || ![17, 26].contains(weeks) {
                        Stepper(value: $store.settings.wtdReferenceWeeks, in: 1...52) {
                            LabeledContent("Weeks", value: "\(weeks)")
                        }
                    }
                } header: {
                    Text("48-hour average")
                } footer: {
                    Text("The law sets 17 weeks. A collective or workforce agreement can extend it to 26 weeks. If your employer uses a different period, choose Custom (1–52 weeks). The app uses a rolling average; your employer may use fixed periods.")
                }
                Section {
                    Stepper(value: $store.settings.nightWorkLimitHours, in: 8...15, step: 0.5) {
                        LabeledContent("Night-work limit", value: Fmt.hm(store.settings.nightWorkLimitHours * 3600))
                    }
                } footer: {
                    Text("Only raise this if a collective or workforce agreement allows it.")
                }
            }
        }
        .navigationTitle("Working time")
    }
}

struct AlertSettingsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Notifications", isOn: $store.settings.notificationsEnabled)
                Stepper(value: $store.settings.warningLeadMinutes, in: 5...60, step: 5) {
                    LabeledContent("Warn me before limits", value: "\(store.settings.warningLeadMinutes) min")
                }
            } footer: {
                Text("To get alerts while driving, allow HGV Hours in iPhone Settings → Focus → Driving → Apps.")
            }
            Section {
                Toggle("Lock Screen countdown", isOn: $store.settings.liveActivityEnabled)
            } footer: {
                Text("Shows a Live Activity on the Lock Screen (and Dynamic Island on newer iPhones) counting down to your next break or limit.")
            }
        }
        .navigationTitle("Alerts")
    }
}

struct DriverSettingsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                TextField("Name", text: $store.settings.driverName)
                    .textContentType(.name)
                    .submitLabel(.done)
                TextField("Employer / agency", text: $store.settings.employer)
                    .submitLabel(.done)
                TextField("Usual vehicle reg", text: $store.settings.vehicleReg)
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.done)
            } footer: {
                Text("Printed on exported timesheets.")
            }
        }
        .navigationTitle("Driver details")
        .keyboardDoneButton()
    }
}

struct OvertimeSettingsView: View {
    @Environment(SettingsStore.self) private var store

    private func hourlyBase(_ p: PaySettings) -> Double {
        switch p.basis {
        case .daily: p.dayRateHours > 0 ? p.dayRate / p.dayRateHours : 0
        case .salary: p.salaryHourly
        case .hourly: p.baseRate
        }
    }

    static func summary(_ p: PaySettings) -> String {
        if p.basis == .daily {
            return p.overtimeFixedRate > 0 ? Fmt.money(p.overtimeFixedRate, symbol: p.currencySymbol) + "/h" : String(format: "×%g", p.overtimeMultiplier)
        }
        guard p.dailyOvertimeAfterHours > 0 || p.weeklyOvertimeAfterHours > 0 else { return "Off" }
        if p.overtimeFixedRate > 0 { return Fmt.money(p.overtimeFixedRate, symbol: p.currencySymbol) + "/h" }
        return String(format: "×%g", p.overtimeMultiplier)
    }

    var body: some View {
        @Bindable var store = store
        let p = store.settings.pay
        Form {
            Section {
                Stepper(value: $store.settings.pay.dailyOvertimeAfterHours, in: 0...16, step: 0.5) {
                    LabeledContent("After hours in a shift", value: p.dailyOvertimeAfterHours == 0 ? "Off" : Fmt.hm(p.dailyOvertimeAfterHours * 3600))
                }
                Stepper(value: $store.settings.pay.weeklyOvertimeAfterHours, in: 0...80, step: 1) {
                    LabeledContent("After hours in a week", value: p.weeklyOvertimeAfterHours == 0 ? "Off" : Fmt.hm(p.weeklyOvertimeAfterHours * 3600))
                }
            } header: {
                Text("When overtime starts")
            } footer: {
                Text(p.basis == .daily
                     ? "On a day rate, overtime starts after the hours your day rate covers (Pay rates), or after the shift hours set here if that's set. Weekly overtime applies to hourly pay only."
                     : "Set to Off (0) to switch off. Paid hours past either threshold count as overtime.")
            }

            Section {
                RateEditor(multiplier: $store.settings.pay.overtimeMultiplier, fixed: $store.settings.pay.overtimeFixedRate,
                           base: hourlyBase(p), symbol: p.currencySymbol, unit: "/h", allowNormal: false)
            } header: {
                Text("Overtime rate")
            } footer: {
                Text(p.basis == .daily
                     ? "Pick a multiplier of your day rate ÷ the hours it covers, or type your exact £/hour."
                     : "Pick time and a quarter, time and a half or double time, type your own multiplier, or type your exact overtime rate.")
            }
        }
        .navigationTitle("Overtime")
        .keyboardDoneButton()
    }
}

struct PaySettingsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let p = store.settings.pay
        let symbol = p.currencySymbol
        let unit = p.basis.unit
        let base = p.basis == .daily ? p.dayRate : p.baseRate
        Form {
            Section {
                Picker("Paid by", selection: $store.settings.pay.payBasis) {
                    ForEach(PayBasis.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                if p.basis == .hourly {
                    moneyField("Hourly rate", value: $store.settings.pay.baseRate, symbol: symbol, unit: "/h")
                    Stepper(value: $store.settings.pay.minimumPaidHoursPerShift, in: 0...12, step: 0.5) {
                        LabeledContent("Guaranteed hours / shift", value: hoursText(p.minimumPaidHoursPerShift))
                    }
                    Stepper(value: $store.settings.pay.minimumPaidHoursPerWeek, in: 0...70, step: 1) {
                        LabeledContent("Guaranteed hours / week", value: hoursText(p.minimumPaidHoursPerWeek))
                    }
                    Stepper(value: $store.settings.pay.minimumPaidHoursPerMonth, in: 0...300, step: 5) {
                        LabeledContent("Guaranteed hours / month", value: hoursText(p.minimumPaidHoursPerMonth))
                    }
                } else if p.basis == .salary {
                    moneyField("Salary", value: $store.settings.pay.salaryAmount, symbol: symbol, unit: "")
                    Picker("Per", selection: $store.settings.pay.salaryPeriod) {
                        ForEach(SalaryPeriod.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Stepper(value: $store.settings.pay.contractedHoursPerWeek, in: 10...70, step: 0.5) {
                        LabeledContent("Contracted hours / week", value: Fmt.hm(p.contractedHoursPerWeek * 3600))
                    }
                    Stepper(value: $store.settings.pay.contractedDaysPerWeek, in: 1...7, step: 1) {
                        LabeledContent("Days / week", value: "\(Int(p.contractedDaysPerWeek))")
                    }
                    LabeledContent("Works out at", value: "\(Fmt.money(p.weeklySalary, symbol: symbol))/week · \(Fmt.money(p.salaryHourly, symbol: symbol))/h")
                        .foregroundStyle(.secondary)
                } else {
                    moneyField("Day rate", value: $store.settings.pay.dayRate, symbol: symbol, unit: "/day")
                    Stepper(value: $store.settings.pay.dayRateHours, in: 4...16, step: 0.5) {
                        LabeledContent("Day rate covers", value: Fmt.hm(p.dayRateHours * 3600))
                    }
                }
            } header: {
                Text("How you're paid")
            } footer: {
                switch p.basis {
                case .hourly:
                    Text("Guaranteed hours are topped up at your hourly rate when you work less (per shift, per week or per calendar month). Not sure? Check your contract or a payslip.")
                case .daily:
                    Text("Each shift is paid the day rate. Paid hours past what the day rate covers are paid as overtime (Settings → Overtime).")
                case .salary:
                    Text("Your salary is paid whatever hours you work. Hours past your contracted hours per week are paid as overtime at the hourly value of your salary (Settings → Overtime).")
                }
            }

            Section {
                RateRow(title: "Saturday", multiplier: $store.settings.pay.saturdayMultiplier,
                        fixed: $store.settings.pay.saturdayFixedRate, base: base, symbol: symbol, unit: unit)
                RateRow(title: "Sunday", multiplier: $store.settings.pay.sundayMultiplier,
                        fixed: $store.settings.pay.sundayFixedRate, base: base, symbol: symbol, unit: unit)
                RateRow(title: "Bank holiday", multiplier: $store.settings.pay.bankHolidayMultiplier,
                        fixed: $store.settings.pay.bankHolidayFixedRate, base: base, symbol: symbol, unit: unit)
                NavigationLink {
                    OvertimeSettingsView()
                } label: {
                    LabeledContent("Overtime", value: OvertimeSettingsView.summary(p))
                }
            } header: {
                Text("Rates")
            } footer: {
                Text("Tap a rate to switch between a multiplier (×1.5 = time and a half) and typing your exact rate. The highest rate that applies is used; they don't stack. Bank holidays are England & Wales dates.")
            }

            Section {
                Picker("Holiday pay", selection: Binding(
                    get: { p.holiday.rawValue },
                    set: { store.settings.pay.holidayMode = $0 })) {
                    ForEach(HolidayMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Holiday")
            } footer: {
                switch p.holiday {
                case .included:
                    Text("Your rate already includes holiday pay (rolled-up, common for agency drivers). The UK rate is 12.07% — Weeks & pay shows how much of your pay is holiday pay. Nothing extra is added.")
                case .separate:
                    Text("You're paid when you take holiday. Mark holiday days in the Calendar; each is paid at your average day's pay over the last 52 weeks, worked out automatically. Weeks & pay shows the holiday you've earned (12.07% of hours worked).")
                case .none:
                    Text("Holiday pay isn't shown.")
                }
            }

            Section {
                ForEach($store.settings.pay.extras) { $extra in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Name, e.g. Tipper bonus", text: $extra.name)
                            .submitLabel(.done)
                        HStack {
                            Text(symbol).foregroundStyle(.secondary)
                            TextField("0.00", value: $extra.amount.emptyIfZero, format: .number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 90)
                            Spacer()
                            Picker("", selection: $extra.per) {
                                ForEach(PayExtra.Per.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                        }
                    }
                }
                .onDelete { store.settings.pay.extras.remove(atOffsets: $0) }
                Button {
                    store.settings.pay.extras.append(PayExtra())
                } label: {
                    Label("Add bonus or allowance", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Regular bonuses & extras")
            } footer: {
                Text("Paid automatically per shift, per week or per night out. Swipe left to delete. For one-off bonuses use Weeks & pay → Add holiday, bonus or extra.")
            }

            Section("What's paid") {
                Toggle("Driving", isOn: $store.settings.pay.payDriving)
                Toggle("Other work", isOn: $store.settings.pay.payOtherWork)
                Toggle("POA / waiting time", isOn: $store.settings.pay.payAvailability)
                if p.payAvailability {
                    Stepper(value: $store.settings.pay.availabilityPercent, in: 0...100, step: 5) {
                        LabeledContent("POA paid at", value: "\(Int(p.availabilityPercent))%")
                    }
                }
                Toggle("Breaks", isOn: $store.settings.pay.payBreaks)
            }

            Section {
                moneyField("Night premium", value: $store.settings.pay.nightPremiumPerHour, symbol: symbol, unit: "/h")
                if p.nightPremiumPerHour > 0 {
                    Picker("Night starts", selection: $store.settings.pay.nightPremiumStartHour) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    Picker("Night ends", selection: $store.settings.pay.nightPremiumEndHour) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                }
                moneyField("Night-out allowance", value: $store.settings.pay.nightOutAllowance, symbol: symbol, unit: "/night")
            } header: {
                Text("Nights")
            } footer: {
                Text("The night premium is added on top of the hourly rate. Log nights out from the Today screen.")
            }

            Section {
                TextField("Currency symbol", text: $store.settings.pay.currencySymbol)
                    .submitLabel(.done)
            }
        }
        .navigationTitle("Pay rates")
        .keyboardDoneButton()
    }

    private func moneyField(_ title: String, value: Binding<Double>, symbol: String, unit: String, placeholder: String = "0.00") -> some View {
        LabeledContent(title) {
            HStack(spacing: 2) {
                Text(symbol).foregroundStyle(.secondary)
                TextField(placeholder, value: value.emptyIfZero, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                Text(unit).foregroundStyle(.secondary).font(.caption)
            }
        }
    }

    private func hoursText(_ hours: Double) -> String { hours == 0 ? "Off" : Fmt.hm(hours * 3600) }
}

/// A rate: normal, a preset multiplier, a custom multiplier, or a custom typed amount.
struct RateRow: View {
    var title: String
    @Binding var multiplier: Double
    @Binding var fixed: Double
    var base: Double
    var symbol: String
    var unit: String
    var allowNormal = true
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            RateEditor(multiplier: $multiplier, fixed: $fixed, base: base, symbol: symbol, unit: unit, allowNormal: allowNormal)
        } label: {
            LabeledContent(title, value: RateEditor.summary(multiplier: multiplier, fixed: fixed, base: base, symbol: symbol, unit: unit))
        }
    }
}

/// Choose: Normal, ×1.25, ×1.5, ×2, Custom × or Custom £.
struct RateEditor: View {
    @Binding var multiplier: Double
    @Binding var fixed: Double
    var base: Double
    var symbol: String
    var unit: String
    var allowNormal = true
    @State private var mode: Mode = .normal

    enum Mode: String, CaseIterable, Identifiable {
        case normal, x125, x15, x2, customMultiplier, customRate
        var id: String { rawValue }
        var title: String {
            switch self {
            case .normal: "Normal rate"
            case .x125: "Time and a quarter (×1.25)"
            case .x15: "Time and a half (×1.5)"
            case .x2: "Double time (×2)"
            case .customMultiplier: "Custom multiplier"
            case .customRate: "Custom rate (type amount)"
            }
        }
        var preset: Double? {
            switch self {
            case .normal: 1
            case .x125: 1.25
            case .x15: 1.5
            case .x2: 2
            default: nil
            }
        }
    }

    static func summary(multiplier: Double, fixed: Double, base: Double, symbol: String, unit: String) -> String {
        if fixed > 0 { return Fmt.money(fixed, symbol: symbol) + unit }
        if multiplier == 1 { return "Normal" }
        return String(format: "×%g = ", multiplier) + Fmt.money(base * multiplier, symbol: symbol) + unit
    }

    var body: some View {
        Picker("Rate", selection: Binding(get: { mode }, set: { apply($0) })) {
            ForEach(Mode.allCases.filter { allowNormal || $0 != .normal }) { Text($0.title).tag($0) }
        }
        .onAppear { mode = Self.mode(multiplier: multiplier, fixed: fixed) }
        if mode == .customMultiplier {
            LabeledContent("Multiplier") {
                HStack(spacing: 2) {
                    Text("×").foregroundStyle(.secondary)
                    TextField("1.5", value: $multiplier.emptyIfZero, format: .number.precision(.fractionLength(0...3)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                }
            }
        }
        if mode == .customRate {
            LabeledContent("Amount") {
                HStack(spacing: 2) {
                    Text(symbol).foregroundStyle(.secondary)
                    TextField("0.00", value: $fixed.emptyIfZero, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                    Text(unit).foregroundStyle(.secondary).font(.caption)
                }
            }
        }
        if mode != .customRate {
            LabeledContent("Works out at", value: Fmt.money(base * multiplier, symbol: symbol) + unit)
                .foregroundStyle(.secondary)
        }
    }

    static func mode(multiplier: Double, fixed: Double) -> Mode {
        if fixed > 0 { return .customRate }
        return Mode.allCases.first { $0.preset == multiplier } ?? .customMultiplier
    }

    private func apply(_ new: Mode) {
        mode = new
        if let preset = new.preset {
            multiplier = preset
            fixed = 0
        } else if new == .customRate {
            fixed = max(base * multiplier, 0.01)
        } else {
            fixed = 0
        }
    }
}
