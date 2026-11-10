import SwiftUI

/// A card showing used vs limit with a progress bar that turns orange/red near the limit.
struct LimitCard: View {
    var title: String
    var value: String
    var caption: String
    var progress: Double
    var symbol: String
    var cautionAt: Double = 0.85

    private var tint: Color {
        if progress >= 1 { return .red }
        if progress >= cautionAt { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        Text(title)
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
        .frame(maxWidth: .infinity)
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
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
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
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
