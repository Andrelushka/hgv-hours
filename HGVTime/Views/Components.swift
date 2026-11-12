import SwiftUI

/// A card showing used vs limit with a progress bar that turns orange/red near the limit.
struct LimitCard: View {
    var title: String
    var value: String
    var caption: String
    var progress: Double
    var symbol: String
    var cautionAt: Double = 0.85
    /// ⓘ text; defaults to the UK/EU rule for this title.
    var info: String? = nil

    private var tint: Color {
        if progress >= 1 { return .red }
        if progress >= cautionAt { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let info = info ?? RuleInfo.text(for: title) { InfoDot(title: title, text: info).padding(-6) }
            }
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(progress >= 1 ? .red : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ProgressView(value: min(max(progress, 0), 1))
                .tint(tint)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// A card with a single fact (time or count) and no bar.
struct InfoCard: View {
    var title: String
    var value: String
    var caption: String
    var symbol: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let info = RuleInfo.text(for: title) { InfoDot(title: title, text: info).padding(-6) }
            }
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct IssueRow: View {
    var issue: ComplianceIssue
    var showDate = false

    private var color: Color {
        switch issue.severity {
        case .violation: .red
        case .caution: .orange
        case .info: .blue
        }
    }

    private var symbol: String {
        switch issue.severity {
        case .violation: "exclamationmark.octagon.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title).font(.subheadline.weight(.semibold))
                Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                Text(showDate ? "\(issue.family.rawValue) · \(issue.date.map(Fmt.day) ?? "")" : issue.family.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader: View {
    var title: String
    var body: some View {
        Text(LocalizedStringKey(title))
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

struct DisclaimerView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "truck.box.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Before you start")
                        .font(.largeTitle.bold())
                    Text("HGV Hours helps you plan your driving, breaks, rest and working time against UK rules: assimilated (retained EU) rules, AETR, the Road Transport (Working Time) Regulations, and GB domestic rules.")
                    Text("It is a planning aid, **not** a legal record. Your tachograph and your employer's records are what count. Always follow your tachograph, your operator's instructions and DVSA guidance.")
                    Text("Exemptions, derogations, ferry/train rest rules and workforce agreements aren't fully modelled. If in doubt, check GOV.UK: “Drivers' hours and tachographs: goods vehicles”.")
                    SafetyNotice()
                    Text("All data stays on this iPhone.")
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    store.settings.hasAcceptedDisclaimer = true
                } label: {
                    Text("I understand").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
        }
    }
}

/// A big countdown with a ring, used for "Driving left" and "Working left".
struct RingTile: View {
    var title: String
    var value: String
    var caption: String
    var fraction: Double
    var color: Color
    var symbol: String

    private var tint: Color {
        if fraction <= 0 { return .red }
        if fraction < 0.12 { return .orange }
        return color
    }

    var body: some View {
        VStack(spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    if let info = RuleInfo.text(for: title) { InfoDot(title: title, text: info).padding(-6) }
                }
            ZStack {
                Circle().stroke(tint.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(fraction <= 0 ? .red : .primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
            }
            .frame(width: 118, height: 118)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 28, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// A small label/value pair.
struct MiniStat: View {
    var title: String
    var value: String
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(LocalizedStringKey(title)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Colour for an entry, separating break, daily rest and weekly rest.
extension ActivityEntry {
    var displayColor: Color { restType?.color ?? kind.color }
    var displaySymbol: String { restType?.symbol ?? kind.symbol }
}

/// A 24-hour bar like a tachograph chart: one coloured block per activity.
struct DayTimelineBar: View {
    var entries: [ActivityEntry]
    var day: Date
    var now: Date = .now
    var height: CGFloat = 22

    var body: some View {
        let dayStart = Calendar.hgv.startOfDay(for: day)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill))
                    ForEach(entries) { entry in
                        let s = max(entry.start, dayStart)
                        let e = min(entry.end ?? now, dayEnd)
                        if e > s {
                            let x = s.timeIntervalSince(dayStart) / 86_400 * geo.size.width
                            let w = max(1, e.timeIntervalSince(s) / 86_400 * geo.size.width)
                            Rectangle()
                                .fill(entry.displayColor)
                                .frame(width: w, height: entry.kind == .rest ? height * 0.45 : height)
                                .offset(x: x, y: entry.kind == .rest ? height * 0.275 : 0)
                        }
                    }
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                    Text(String(format: "%02d", h)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                    if h < 24 { Spacer() }
                }
            }
        }
        .accessibilityLabel("Day chart")
    }
}

/// Colour key for the chart.
struct ActivityLegend: View {
    var body: some View {
        let items: [(String, Color)] = [
            ("Drive", DutyKind.drive.color), ("Work", DutyKind.otherWork.color), ("POA", DutyKind.availability.color),
            ("Break", RestType.breakTime.color), ("Daily rest", RestType.daily.color), ("Weekly rest", RestType.weekly.color)
        ]
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], alignment: .leading, spacing: 4) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(item.1).frame(width: 10, height: 10)
                    Text(item.0).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension View {
    /// Adds a "Done" button above the keyboard and lets a scroll dismiss it.
    /// Number pads have no Return key, so without this the keyboard never goes away.
    func keyboardDoneButton() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
            }
    }
}

/// "2 of 3 left" with dots.
struct CountCard: View {
    var title: String
    var left: Int
    var of: Int
    var caption: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(LocalizedStringKey(title)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let info = RuleInfo.text(for: title) { InfoDot(title: title, text: info).padding(-6) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(left)").font(.title.weight(.bold).monospacedDigit()).foregroundStyle(left == 0 ? .red : .primary)
                Text("of \(of) left").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(0..<of, id: \.self) { i in
                    Circle().fill(i < left ? color : Color(.tertiarySystemFill)).frame(width: 10, height: 10)
                }
            }
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// A help message shown after tapping a button: what it means and what's next.
struct HelpMessage: Identifiable, Equatable {
    let id = UUID()
    var symbol: String
    var color: Color
    var title: String
    var lines: [String]
}

struct HelpBanner: View {
    var message: HelpMessage
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: message.symbol).font(.title3).foregroundStyle(message.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(message.title).font(.subheadline.weight(.bold))
                ForEach(message.lines, id: \.self) { line in
                    Text(line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close help")
        }
        .padding(12)
        .background(message.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(message.color.opacity(0.3)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Big green/red driver card button: tap to record inserting or withdrawing the card.
struct CardButton: View {
    var inserted: Bool
    var since: Date?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(inserted ? Color.green : Color.red).frame(width: 26, height: 26)
                    Image(systemName: inserted ? "checkmark" : "xmark").font(.caption.weight(.heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(inserted ? "Driver card inserted" : "Driver card not inserted")
                        .font(.subheadline.weight(.bold))
                    Text(inserted ? (since.map { "Since \(Fmt.dayTime($0))" } ?? "") : "Tap when you insert your card")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(inserted ? "Withdraw" : "Insert")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background((inserted ? Color.red : Color.green).opacity(0.18), in: Capsule())
                    .foregroundStyle(inserted ? .red : .green)
            }
            .padding(12)
            .background((inserted ? Color.green : Color.red).opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke((inserted ? Color.green : Color.red).opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: inserted)
        .accessibilityLabel(inserted ? "Driver card inserted. Tap to record withdrawing it." : "Driver card not inserted. Tap to record inserting it.")
    }
}

/// An ⓘ that shows an explanation in a small pop-over.
struct InfoDot: View {
    var title: String
    var text: String
    var highlighted = false
    var onOpen: (() -> Void)? = nil
    @State private var showing = false

    var body: some View {
        Button { showing = true; onOpen?() } label: {
            Image(systemName: highlighted ? "info.circle.fill" : "info.circle")
                .font(.subheadline)
                .foregroundStyle(highlighted ? Color.accentColor : .secondary)
                .symbolEffect(.pulse, isActive: highlighted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(title)")
        .popover(isPresented: $showing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(title)).font(.headline)
                    Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
            .frame(minWidth: 260, maxWidth: 340, maxHeight: 360)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Plain-English explanations for the limits shown on cards.
/// The ⓘ explanation for each tile, matched to its exact title so the text always describes what the tile shows.
enum RuleInfo {
    static let fourThirty = String(localized: "After 4h30 of driving you must take a 45-minute break. You can split it: at least 15 minutes, then at least 30 minutes later (in that order). A break of 15–29 minutes on its own doesn't reset the 4h30, but it counts as the first part. Breaks also count towards your working-time breaks.")
    static let sixHours = String(localized: "Working Time rules: no more than 6 hours of work in a row. Any break of 15 minutes or more resets the 6 hours. Over the day, breaks must add up to 30 minutes if you work 6–9 hours, or 45 minutes over 9 hours, in pieces of at least 15 minutes. Driving and other work count; POA and breaks don't.")
    static let dailyRest = String(localized: "Daily rest must be completed within 24 hours of the start of your shift: 11 hours normally, 9 hours reduced (up to 3 times between weekly rests), or split 3 hours + 9 hours.")

    static func text(for title: String) -> String? {
        switch title {
        case "Driving left":
            return String(localized: "Driving you can do before your next break: what's left of the 4h30, or less if your daily (9h/10h) or weekly (56h, 90h in two weeks) driving runs out first. It doesn't drop to zero during a break — stopping a break early is allowed, it just doesn't reset the 4h30. After 45 minutes (or 15 then 30) you get a fresh 4h30. Driving left for the whole day is on the Hours page.")
        case "Working left":
            return String(localized: "Working time you can do before a working-time break: what's left of the 6 hours, or less if the 60-hour week or the night-work limit is nearer. Driving and other work count; POA and breaks don't. Any break of 15 minutes or more resets the 6 hours.")
        case "Before break":
            return fourThirty
        case "Before 6h break":
            return sixHours
        case "Break due in":
            return String(localized: "Time until your next break is due if you carry on as you are: the sooner of the 4h30 driving limit and the 6-hour working-time limit.")
        case "Daily driving":
            return String(localized: "Normally 9 hours of driving between daily rests. Twice a week you may drive 10 hours.")
        case "Driven today":
            return String(localized: "Driving recorded today against your daily limit: 9 hours, or 10 hours on up to two days in a fixed week.")
        case "This week", "Week driving":
            return String(localized: "No more than 56 hours of driving in a fixed week (Monday 00:00 to Sunday 24:00).")
        case "Fortnight":
            return String(localized: "No more than 90 hours of driving in any two consecutive fixed weeks.")
        case "Week working":
            return String(localized: "No more than 60 hours of working time in any week. Driving and other work count; POA and breaks don't.")
        case "Night shift work":
            return String(localized: "If your shift includes any time between 00:00 and 04:00, you may work no more than 10 hours in that shift, unless a collective or workforce agreement allows more.")
        case "Worked today":
            return String(localized: "Driving plus other work recorded today. POA and breaks are not working time.")
        case "Shift working time":
            return String(localized: "Driving plus other work in this shift (POA and breaks don't count). It's what the working-time break rules and the night-work limit use.")
        case "Shift time left":
            return String(localized: "Time until you must start your daily rest. A shift can last up to 13 hours if you then rest 11 hours, or 15 hours with a reduced 9-hour rest (up to 3 times between weekly rests) — all within 24 hours of the shift start.")
        case "Start daily rest by":
            return String(localized: "The latest time to start your daily rest so it fits within 24 hours of your shift start: 11 hours normally, or 9 hours reduced (up to 3 times between weekly rests).")
        case "Daily rest":
            return dailyRest
        case "Resting for":
            return String(localized: "How long you've been resting. 9 hours is a reduced daily rest and 11 hours a regular one; 24 hours is a reduced weekly rest and 45 hours a regular weekly rest.")
        case "Next shift can start":
            return String(localized: "The earliest time your next shift can start: after at least 9 hours' rest (reduced, if you have any left) or 11 hours (regular), or after your weekly rest if one is due.")
        case "Reduced rests":
            return String(localized: "A 9-hour reduced daily rest lets your day stretch to 15 hours. You can use up to 3 between weekly rests.")
        case "Weekly rest", "Weekly rest by":
            return String(localized: "A weekly rest of 45 hours (or reduced, 24 hours) must start no later than 6 × 24 hours after the end of the previous one. In any two weeks at least one must be a regular 45-hour rest. A reduced weekly rest must be made up in one block before the end of the third week after it.")
        case "Compensation owed":
            return String(localized: "Hours missing from a reduced weekly rest must be added, in one block, to a rest of 9 hours or more before the end of the third week after it.")
        case "GB driving":
            return String(localized: "GB domestic rules: no more than 10 hours of driving in a working day.")
        case "GB duty":
            return String(localized: "GB domestic rules: no more than 11 hours on duty in a working day (driving and other work).")
        default:
            break
        }
        let t = title.lowercased()
        if t.contains("average") {
            return String(localized: "Your working time must average no more than 48 hours a week over the reference period (17 weeks unless an agreement says 26).")
        }
        if t.contains("10h driving") { return String(localized: "You may extend daily driving to 10 hours twice in a fixed week.") }
        if t.contains("15h day") { return String(localized: "A 9-hour reduced daily rest lets your day stretch to 15 hours. You can use up to 3 between weekly rests.") }
        if t.contains("earned") { return String(localized: "An estimate before tax and deductions, from your pay settings (Earnings tab ⚙︎). Check your payslip.") }
        return nil
    }
}

/// A short message that slides in and disappears by itself.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    var symbol: String
    var color: Color
    var title: String
    var detail: String = ""
}

struct ToastView: View {
    var toast: Toast
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(toast.color.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title).font(.subheadline.weight(.bold))
                if !toast.detail.isEmpty { Text(toast.detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(toast.color.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Square driver card tile: one tap records inserting or withdrawing the card.
struct CardTile: View {
    var inserted: Bool
    var since: Date?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Driver card", systemImage: "creditcard.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(inserted ? Color.green : Color.red).frame(width: 30, height: 30)
                        Image(systemName: inserted ? "checkmark" : "xmark").font(.subheadline.weight(.heavy)).foregroundStyle(.white)
                    }
                    Text(inserted ? "Inserted" : "Not inserted").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(inserted ? (since.map { "Since \(Fmt.time($0)) · tap to withdraw" } ?? "Tap to withdraw") : "Tap when you insert it")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background((inserted ? Color.green : Color.red).opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke((inserted ? Color.green : Color.red).opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: inserted)
        .accessibilityLabel(inserted ? "Driver card inserted. Tap to record withdrawing it." : "Driver card not inserted. Tap to record inserting it.")
    }
}

extension Binding where Value == Double {
    /// Shows an empty box instead of "0" so there's nothing to delete before typing.
    var emptyIfZero: Binding<Double?> {
        Binding<Double?>(get: { wrappedValue == 0 ? nil : wrappedValue }, set: { wrappedValue = $0 ?? 0 })
    }
}


/// Phone-use warning (UK law: Road Vehicles (Construction and Use) Regulations 1986, reg. 110; Highway Code rule 149).
struct SafetyNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "iphone.slash").font(.title2).foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Use only when parked").font(.headline)
                Text("It's illegal to hold or use a phone while driving — including when stopped in traffic or queuing (Highway Code rule 149). Set up navigation, change settings and enter records only when you're safely parked with the engine off or the handbrake on. A sat-nav may be used hands-free, fixed in a holder that doesn't block your view.")
                    .font(.subheadline)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Shown on Today while the vehicle is moving (in-cab mode): don't touch the phone.
struct DrivingSafetyBanner: View {
    @State private var detector = AutoDriveDetector.shared

    var body: some View {
        if detector.isMoving {
            HStack(spacing: 8) {
                Image(systemName: "iphone.slash")
                Text("Driving — don't use the phone. Driving is being recorded for you.")
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.red.gradient)
            .accessibilityElement(children: .combine)
        }
    }
}


/// Today: vehicle height (vehicle or trailer, whichever is taller) with a one-tap "checked" record, like the driver card.
struct HeightCheckTile: View {
    var height: Double
    var checkedAt: Date?
    var action: () -> Void

    var body: some View {
        let checked = checkedAt != nil
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(checked ? Color.green : Color.orange).frame(width: 34, height: 34)
                    Image(systemName: checked ? "checkmark" : "arrow.up.and.down").font(.subheadline.weight(.heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Vehicle height").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if height > 0 {
                            Text(Fmt.length(height)).font(.headline.monospacedDigit())
                        }
                    }
                    if let checkedAt {
                        Text("Checked at \(Fmt.time(checkedAt)) · tap to undo").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(height > 0 ? "Not checked — tap when you've checked the height plate" : "Set the height on your vehicle or trailer, then tap when checked")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background((checked ? Color.green : Color.orange).opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke((checked ? Color.green : Color.orange).opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: checked)
        .accessibilityLabel(checked ? "Vehicle height checked. Tap to undo." : "Vehicle height not checked. Tap to record checking it.")
    }
}
