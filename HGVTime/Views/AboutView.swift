import SwiftUI
import UIKit

enum AppInfo {
    static let repoURL = URL(string: "https://github.com/Andrelushka/hgv-hours")!
    static let issuesURL = URL(string: "https://github.com/Andrelushka/hgv-hours/issues")!
    static let roadmapURL = URL(string: "https://github.com/Andrelushka/hgv-hours/blob/main/ROADMAP.md")!
    /// Set this to a donation page (e.g. Buy Me a Coffee) to show a Donate button.
    static let donateURL: URL? = nil

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1" }
}

struct AboutView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "truck.box.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HGV Hours").font(.title2.weight(.bold))
                        Text("Version \(AppInfo.version) (\(AppInfo.build))").foregroundStyle(.secondary)
                        Text("Drivers' hours, working time and pay for UK HGV drivers").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Link(destination: AppInfo.repoURL) { Label("Star HGV Hours on GitHub", systemImage: "star.fill") }
                ShareLink(item: AppInfo.repoURL, message: Text("HGV Hours — drivers' hours, breaks and pay for UK lorry drivers")) {
                    Label("Tell another driver about it", systemImage: "square.and.arrow.up")
                }
                NavigationLink { ReportProblemView(kind: .idea) } label: { Label("Suggest a feature", systemImage: "lightbulb.fill") }
                if let donate = AppInfo.donateURL {
                    Link(destination: donate) { Label("Donate", systemImage: "heart.fill") }
                }
            } header: {
                Text("Support the development")
            } footer: {
                Text("HGV Hours is free and has no adverts. Starring it, sharing it and sending ideas all help.")
            }

            Section {
                NavigationLink { ReportProblemView(kind: .bug) } label: { Label("Report a problem", systemImage: "ant.fill") }
                Link(destination: AppInfo.roadmapURL) { Label("What's coming next (roadmap)", systemImage: "map") }
                Link(destination: AppInfo.issuesURL) { Label("Known issues", systemImage: "list.bullet.clipboard") }
            }

            Section {
                Text("All your records stay on this iPhone (and your Apple Watch). There's no account, no tracking and no adverts. Internet is only used to name a place when you tap Arrived (Apple Maps) and, if you turn it on with your own API key, to ask Claude AI a question (a summary of your hours and pay is sent with it).")
                    .font(.footnote)
                Link(destination: URL(string: "https://www.gov.uk/guidance/drivers-hours-goods-vehicles")!) {
                    Label("GOV.UK: drivers' hours (goods vehicles)", systemImage: "link")
                }
                Link(destination: URL(string: "https://www.gov.uk/guidance/drivers-hours-goods-vehicles/annex-2-working-time-rules")!) {
                    Label("GOV.UK: working time rules", systemImage: "link")
                }
                Button("Show disclaimer") { store.settings.hasAcceptedDisclaimer = false }
            } header: {
                Text("Privacy & rules")
            } footer: {
                Text("Planning aid only. Your tachograph and your employer's records are the legal record.")
            }
        }
        .navigationTitle("About")
    }
}

/// Report a problem or suggest a feature, with optional anonymous app details.
struct ReportProblemView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case bug, rules, pay, idea
        var id: String { rawValue }
        var title: String {
            switch self {
            case .bug: "Something isn't working"
            case .rules: "A rule or limit looks wrong"
            case .pay: "Pay looks wrong"
            case .idea: "Idea / feature request"
            }
        }
    }

    @Environment(SettingsStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State var kind: Kind
    @State private var details = ""
    @State private var includeInfo = true

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.title).tag($0) }
                }
                TextField(kind == .idea ? "Describe your idea" : "What happened? What did you expect?", text: $details, axis: .vertical)
                    .lineLimit(5...12)
            }
            Section {
                Toggle("Include app details", isOn: $includeInfo)
                if includeInfo {
                    Text(diagnostics).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            } footer: {
                Text("App details are the version, iPhone model and your rule and pay settings — no name, vehicle, location or records.")
            }
            Section {
                Button {
                    openURL(issueURL)
                } label: {
                    Label("Send on GitHub", systemImage: "paperplane.fill")
                }
                .disabled(details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ShareLink(item: reportText, subject: Text("HGV Hours: \(kind.title)")) {
                    Label("Send by email, WhatsApp…", systemImage: "square.and.arrow.up")
                }
                .disabled(details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("GitHub reports are public, so don't include personal details. Use email or WhatsApp to send it privately.")
            }
        }
        .navigationTitle(kind == .idea ? "Suggest a feature" : "Report a problem")
        .keyboardDoneButton()
    }

    private var diagnostics: String {
        let s = store.settings
        return """
        App \(AppInfo.version) (\(AppInfo.build))
        iOS \(UIDevice.current.systemVersion) · \(deviceModel)
        Rules: \(s.primaryRegime.shortTitle) · working time \(s.applyWorkingTime ? "on" : "off") · ref \(s.wtdReferenceWeeks) wk
        Pay: \(s.pay.basis.title) · holiday \(s.pay.holiday.title)
        In-cab: \(s.autoDetectEnabled ? "on" : "off") · voice \(s.voiceEnabled ? "on" : "off")
        """
    }

    private var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    private var reportText: String {
        "\(kind.title)\n\n\(details)" + (includeInfo ? "\n\n---\n\(diagnostics)" : "")
    }

    private var issueURL: URL {
        var c = URLComponents(url: AppInfo.issuesURL.appendingPathComponent("new"), resolvingAgainstBaseURL: false)!
        let title = "\(kind.title): \(details.split(separator: "\n").first.map(String.init)?.prefix(60) ?? "")"
        c.queryItems = [URLQueryItem(name: "title", value: title),
                        URLQueryItem(name: "body", value: reportText),
                        URLQueryItem(name: "labels", value: kind == .idea ? "enhancement" : "bug")]
        return c.url ?? AppInfo.issuesURL
    }
}
