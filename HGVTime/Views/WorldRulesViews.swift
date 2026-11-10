import SwiftUI

/// Hours tab content for USA, Canada, Australia and New Zealand rules.
struct WorldHoursSection: View {
    var world: WorldStatus
    var dash: Dashboard
    var onShift: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("\(world.region.flag) \(world.region.title)").font(.subheadline.weight(.semibold))
                Spacer()
            }
            if onShift {
                HStack(spacing: 10) {
                    RingTile(title: "Driving left", value: Fmt.hm(world.driveLeft), caption: world.driveReason,
                             fraction: world.driveLeft / .hours(8), color: .blue, symbol: "steeringwheel")
                    RingTile(title: "Working left", value: Fmt.hm(world.workLeft), caption: world.workReason,
                             fraction: world.workLeft / .hours(8), color: .orange, symbol: "briefcase.fill")
                }
                if let by = world.breakBy, world.breakLength > 0 {
                    HStack {
                        Image(systemName: "cup.and.saucer.fill").foregroundStyle(.green)
                        Text("Take \(Fmt.hm(world.breakLength)) by \(Fmt.time(by))").font(.headline.monospacedDigit())
                        Spacer()
                        Text("\(world.breakReason) rule").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            ForEach(world.violations) { IssueRow(issue: $0) }
            SectionHeader(title: "Limits")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(world.limits) { l in
                    LimitCard(title: l.title, value: "\(Fmt.hm(l.used)) / \(Fmt.hm(l.limit))",
                              caption: "\(Fmt.hm(l.remaining)) left · \(l.note)", progress: l.used / l.limit,
                              symbol: l.drivingOnly ? "steeringwheel" : "clock.fill")
                }
            }
            if let next = world.nextStart {
                InfoCard(title: "Next shift can start", value: Fmt.dayTime(next),
                         caption: "After \(Fmt.hm(world.dailyRest)) off duty", symbol: "play.circle")
            }
            Text("Planning aid only. Check the official rules for your exact situation (exemptions, sleeper berths, split rest, regional variations).")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Choose the country whose rules you drive under; see what other countries use.
struct CountryRulesView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store

    var body: some View {
        let region = store.settings.region
        Form {
            Section {
                Picker("I drive under", selection: Binding(get: { store.settings.ruleRegionRaw }, set: {
                    store.settings.ruleRegionRaw = $0
                    if let r = RuleRegion(rawValue: $0), !r.isEuropean { store.settings.applyWorkingTime = false }
                    ActivityController.refreshSideEffects(context: context, settings: store.settings)
                })) {
                    ForEach(RuleRegion.allCases) { Text("\($0.flag) \($0.title)").tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Rules")
            } footer: {
                Text(region.lawName)
            }
            if region == .usa {
                Section {
                    Picker("Cycle", selection: Binding(get: { store.settings.usCycle70 }, set: { store.settings.usCycle70 = $0 })) {
                        Text("70 hours / 8 days").tag(true)
                        Text("60 hours / 7 days").tag(false)
                    }
                }
            }
            if !region.isEuropean {
                Section {
                    Text("Outside UK/EU/AETR rules, the Hours tab, alerts, widgets and Watch use these limits. European-only features (tachograph minute rule, 10h/15h days, UK working time, split rests) don't apply. Pay, planner, mileage and records work as normal.")
                        .font(.footnote)
                }
            }
            Section {
                NavigationLink { RulesMatrixView() } label: { Label("Rules matrix and countries", systemImage: "tablecells") }
            }
        }
        .navigationTitle("Country & rules")
    }
}

/// Key limits for every rule set, and which countries use which.
struct RulesMatrixView: View {
    @State private var search = ""

    var body: some View {
        List {
            Section("Key limits") {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        GridRow {
                            Text("Rules").font(.caption.weight(.bold))
                            ForEach(CountryRules.columns, id: \.self) { Text($0).font(.caption.weight(.bold)) }
                        }
                        Divider()
                        ForEach([RuleRegion.uk, .usa, .canada, .australia, .newZealand], id: \.self) { r in
                            GridRow {
                                Text("\(r.flag) \(r.isEuropean ? "UK / EU / AETR" : r.title)").font(.caption.weight(.semibold))
                                ForEach(CountryRules.row(r), id: \.self) { Text($0).font(.caption).frame(maxWidth: 160, alignment: .leading) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                ForEach(CountryRules.list.filter { search.isEmpty || $0.country.localizedCaseInsensitiveContains(search) }, id: \.country) { item in
                    LabeledContent(item.country) {
                        if let r = item.region {
                            Text("\(r.flag) \(r.isEuropean ? (r == .uk ? "UK rules" : r == .eu ? "EU 561/2006" : "AETR") : r.title)")
                        } else {
                            Text("Not covered yet").foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Countries")
            } footer: {
                Text("International journeys: EU rules apply within the EU/EEA and Switzerland; AETR applies on journeys through AETR countries. Countries marked 'not covered yet' have their own national rules — check locally.")
            }
        }
        .searchable(text: $search, prompt: "Find a country")
        .navigationTitle("Rules matrix")
    }
}
