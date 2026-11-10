import SwiftUI
import SwiftData

/// Drivers' hours, rest and working time: everything that counts down.
struct HoursView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \ActivityEntry.start) private var entries: [ActivityEntry]
    @Query(sort: \NightOut.date) private var nightOuts: [NightOut]
    @State private var showingAllInfringements = false

    private var openEntry: ActivityEntry? { entries.last { $0.end == nil } }
    private var onShift: Bool { openEntry.map { !$0.endsShift } ?? false }

    private func snapshots(now: Date) -> [EntrySnapshot] {
        let cutoff = now.addingTimeInterval(-Double(store.settings.wtdReferenceWeeks + 2) * 7 * 86_400)
        return entries.filter { $0.start >= cutoff }.map(\.snapshot)
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 10)) { timeline in
                let snaps = snapshots(now: timeline.date)
                let status = RulesEngine.status(snaps, now: timeline.date, config: store.settings.ruleConfig)
                let world = WorldRulesCache.refresh(snaps, now: timeline.date, settings: store.settings)
                let dash = Dashboard.make(status: status, settings: store.settings, openEntry: openEntry)
                ScrollView {
                    VStack(spacing: 14) {
                        if let world {
                            WorldHoursSection(world: world, dash: dash, onShift: onShift)
                        } else {
                        if status.hasData { SectionHeader(title: "Right now") }
                        if onShift {
                            dashboardTiles(dash, status)
                        } else if status.hasData {
                            restCard(status)
                        }
                        if onShift, let plan = Deadlines.breakPlan(status, applyWorkingTime: store.settings.applyWorkingTime) {
                            SectionHeader(title: "Next break")
                            BreakPlanCard(plan: plan, now: status.now)
                        }
                        if status.hasData {
                            SectionHeader(title: "Coming up")
                            DeadlineList(deadlines: Deadlines.all(status, applyWorkingTime: store.settings.applyWorkingTime), now: status.now)
                            SectionHeader(title: "Extensions & rest rules")
                            extensionCards(status)
                            RestRulesCard(status: status, allowConsecutiveReduced: store.settings.allowConsecutiveReducedWeekly)
                        }
                        if !status.warnings.isEmpty {
                            VStack(spacing: 10) {
                                ForEach(status.warnings) { IssueRow(issue: $0) }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                        if status.hasData {
                            SectionHeader(title: "All limits")
                            limitsGrid(status)
                        } else {
                            ContentUnavailableView("No hours yet", systemImage: "gauge.with.dots.needle.0percent",
                                                   description: Text("Start a shift on the Today tab and your driving, working time and rest limits appear here."))
                        }
                        }
                        if world == nil && !status.recentInfringements.isEmpty {
                            Button {
                                showingAllInfringements = true
                            } label: {
                                Label("\(status.recentInfringements.count) infringement\(status.recentInfringements.count == 1 ? "" : "s") in the last 28 days",
                                      systemImage: "exclamationmark.octagon")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .sheet(isPresented: $showingAllInfringements) {
                                NavigationStack {
                                    List(status.recentInfringements) { IssueRow(issue: $0, showDate: true) }
                                        .navigationTitle("Last 28 days")
                                        .toolbar { Button("Done") { showingAllInfringements = false } }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Hours")
        }
    }

    // MARK: Headline countdowns

    private func dashboardTiles(_ d: Dashboard, _ s: ComplianceStatus) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                RingTile(title: "Driving left", value: Fmt.hm(d.driveLeft), caption: d.driveLeftReason,
                         fraction: d.driveLeft / Limits.continuousDriving, color: .blue, symbol: "steeringwheel")
                RingTile(title: "Working left", value: Fmt.hm(d.workLeft), caption: d.workLeftReason.isEmpty ? "" : "Then: \(d.workLeftReason)",
                         fraction: d.workLeft / Limits.wtdMaxWorkWithoutBreak, color: .orange, symbol: "briefcase.fill")
            }
            if let restBy = d.restBy {
                let left = restBy.timeIntervalSince(s.now)
                HStack {
                    Image(systemName: "moon.zzz.fill").font(.title2).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start daily rest by").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(Fmt.time(restBy)).font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(left < 0 ? .red : (left < 3600 ? .orange : .primary))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Shift time left").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(left < 0 ? "Overdue" : Fmt.hm(left)).font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(left < 0 ? .red : .primary)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            HStack(spacing: 10) {
                MiniStat(title: "Break due in", value: Fmt.hm(d.breakDueIn), tint: d.breakDueIn < 1800 ? .orange : .primary)
                MiniStat(title: "Driven today", value: "\(Fmt.hm(d.dailyDriving))/\(Fmt.hm(d.dailyDrivingLimit))")
                MiniStat(title: "Worked today", value: Fmt.hm(d.shiftWorking))
            }
        }
    }

    /// 10h driving days, 15h days (9h reduced rests) and how long the shift has run.
    private func extensionCards(_ s: ComplianceStatus) -> some View {
        let tenHourLeft = max(0, Limits.maxExtensionsPerWeek - s.extensionsUsed)
        let reducedLeft = max(0, Limits.maxReducedDailyRests - s.reducedRestsUsed)
        let shiftStart = s.currentShift?.period.start
        let spread = shiftStart.map { s.now.timeIntervalSince($0) } ?? 0
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                CountCard(title: "10h driving days", left: tenHourLeft, of: Limits.maxExtensionsPerWeek,
                          caption: "left this week (normally 9h)", color: .blue)
                CountCard(title: "15h days", left: reducedLeft, of: Limits.maxReducedDailyRests,
                          caption: "9h reduced rests left before weekly rest", color: .teal)
            }
            if let shiftStart {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Shift length", systemImage: "arrow.left.and.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Fmt.hm(spread)) since \(Fmt.time(shiftStart))").font(.subheadline.weight(.bold).monospacedDigit())
                    }
                    GeometryReader { geo in
                        let w = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill))
                            Capsule().fill(spread > 15 * 3600 ? Color.red : (spread > 13 * 3600 ? Color.orange : Color.teal))
                                .frame(width: min(w, w * spread / (15 * 3600)))
                            Rectangle().fill(.primary.opacity(0.6)).frame(width: 2).offset(x: w * 13 / 15 - 1)
                        }
                    }
                    .frame(height: 10)
                    HStack {
                        Text("13h normal: \(Fmt.time(shiftStart.addingTimeInterval(13 * 3600)))")
                        Spacer()
                        Text(reducedLeft > 0 ? "15h max: \(Fmt.time(shiftStart.addingTimeInterval(15 * 3600)))" : "No 15h days left")
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func restCard(_ s: ComplianceStatus) -> some View {
        let type = openEntry?.restType ?? .daily
        let rest = s.currentRestLength
        let target: TimeInterval = type == .weekly ? Limits.regularWeeklyRest : Limits.regularDailyRest
        let minimum: TimeInterval = type == .weekly ? Limits.reducedWeeklyRest : Limits.reducedDailyRest
        let since = s.currentSince
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(type == .weekly ? "Weekly rest" : "Daily rest", systemImage: type.symbol)
                    .font(.headline).foregroundStyle(type.color)
                Spacer()
                Text("\(Fmt.hm(rest)) of \(Fmt.hm(target))").font(.headline.monospacedDigit())
            }
            ProgressView(value: min(rest / target, 1)).tint(type.color)
            HStack {
                VStack(alignment: .leading) {
                    Text(type == .weekly ? "Reduced (24h)" : "Reduced (9h)").font(.caption).foregroundStyle(.secondary)
                    Text(rest >= minimum ? "Done" : Fmt.dayTime(since.addingTimeInterval(minimum)))
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(type == .weekly ? "Regular (45h)" : "Regular (11h)").font(.caption).foregroundStyle(.secondary)
                    Text(rest >= target ? "Done" : Fmt.dayTime(since.addingTimeInterval(target)))
                        .font(.subheadline.weight(.semibold))
                }
            }
            if let due = s.weeklyRestDueBy, type == .daily {
                Text("Next weekly rest due by \(Fmt.dayTime(due))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(type.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Limits

    @ViewBuilder
    private func limitsGrid(_ s: ComplianceStatus) -> some View {
        let settings = store.settings
        let st = s.stats
        let usesEU = settings.primaryRegime == .assimilated || st.euDriving > 0 || s.weeklyDriving > 0
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

        if usesEU {
            SectionHeader(title: "Drivers' hours (tacho)")
            LazyVGrid(columns: columns, spacing: 10) {
                LimitCard(title: "Before break", value: Fmt.hm(s.continuousDrivingRemaining),
                          caption: s.breakNeeded == Limits.splitBreakSecond ? "15 min taken — 30 min completes the break" : "\(Fmt.hm(st.continuousDriving)) of 4h30 driven",
                          progress: st.continuousDriving / Limits.continuousDriving, symbol: "cup.and.saucer.fill")
                LimitCard(title: "Daily driving", value: "\(Fmt.hm(st.euDriving)) / \(Fmt.hm(s.dailyDrivingLimit))",
                          caption: "10h extensions used this week: \(s.extensionsUsed) of 2",
                          progress: st.euDriving / s.dailyDrivingLimit, symbol: "sun.max.fill")
                LimitCard(title: "This week", value: "\(Fmt.hm(s.weeklyDriving)) / 56h",
                          caption: "Week from \(Fmt.day(s.weekStart))",
                          progress: s.weeklyDriving / Limits.weeklyDriving, symbol: "calendar")
                LimitCard(title: "Fortnight", value: "\(Fmt.hm(s.weeklyDriving + s.previousWeekDriving)) / 90h",
                          caption: "Last week \(Fmt.hm(s.previousWeekDriving))",
                          progress: (s.weeklyDriving + s.previousWeekDriving) / Limits.fortnightlyDriving, symbol: "calendar.badge.clock")
            }

            SectionHeader(title: "Rest")
            LazyVGrid(columns: columns, spacing: 10) {
                if s.isOnDailyRest {
                    InfoCard(title: "Resting for", value: Fmt.hm(s.currentRestLength),
                             caption: restProgressCaption(s), symbol: "bed.double.fill", tint: .green)
                } else if let latest = s.restStartByLatest {
                    InfoCard(title: "Start daily rest by", value: Fmt.time(latest),
                             caption: restDeadlineCaption(s),
                             symbol: "moon.fill",
                             tint: s.now > latest ? .red : (latest.timeIntervalSince(s.now) < .hours(1) ? .orange : .primary))
                } else {
                    InfoCard(title: "Daily rest", value: "—", caption: "Starts counting when your shift starts", symbol: "moon.fill")
                }
                InfoCard(title: "Reduced rests", value: "\(s.reducedRestsUsed) of 3",
                         caption: "9h rests since your last weekly rest", symbol: "moon.haze.fill",
                         tint: s.reducedRestsUsed >= 3 ? .orange : .primary)
                if let due = s.weeklyRestDueBy {
                    InfoCard(title: "Weekly rest by", value: Fmt.dayTime(due),
                             caption: s.nextWeeklyMustBeRegular ? "Must be a regular 45h rest" : "24h reduced or 45h regular",
                             symbol: "house.fill", tint: s.now > due ? .red : .primary)
                } else {
                    InfoCard(title: "Weekly rest", value: s.currentRestLength >= Limits.reducedWeeklyRest ? "In progress" : "—",
                             caption: s.currentRestLength >= Limits.reducedWeeklyRest ? restProgressCaption(s) : "Shows once a 24h+ rest is logged",
                             symbol: "house.fill")
                }
                if s.compensationOwed > 0, let due = s.compensationDueBy {
                    InfoCard(title: "Compensation owed", value: Fmt.hm(s.compensationOwed),
                             caption: "Attach to a 9h+ rest before \(Fmt.day(due))", symbol: "arrow.uturn.backward.circle", tint: .orange)
                }
            }
        }

        if settings.applyWorkingTime {
            SectionHeader(title: "Working time")
            LazyVGrid(columns: columns, spacing: 10) {
                LimitCard(title: "Before 6h break", value: Fmt.hm(s.wtdWorkBeforeBreak),
                          caption: s.wtdBreakNeededToday > 0 ? "Need \(Fmt.hm(s.wtdBreakNeededToday)) more breaks today" : "Breaks taken: \(Fmt.hm(st.wtdBreakTotal))",
                          progress: st.wtdWorkSinceBreak / Limits.wtdMaxWorkWithoutBreak, symbol: "figure.walk")
                if let night = s.nightWorkRemaining {
                    LimitCard(title: "Night shift work", value: "\(Fmt.hm(st.workingTime)) / \(Fmt.hm(settings.nightWorkLimitHours * 3600))",
                              caption: "\(Fmt.hm(night)) left · shift includes 00:00–04:00",
                              progress: st.workingTime / (settings.nightWorkLimitHours * 3600), symbol: "moon.stars.fill")
                } else {
                    InfoCard(title: "Shift working time", value: Fmt.hm(st.workingTime),
                             caption: "POA \(Fmt.hm(st.availability)) · breaks \(Fmt.hm(st.breaks))", symbol: "clock.fill")
                }
                LimitCard(title: "Week working", value: "\(Fmt.hm(s.weeklyWorkingTime)) / 60h",
                          caption: "Excludes breaks and POA", progress: s.weeklyWorkingTime / Limits.wtdWeeklyMaximum,
                          symbol: "briefcase.fill")
                LimitCard(title: "\(s.averageWeeks)-week average", value: "\(Fmt.hm(s.averageWeeklyWorkingTime)) / 48h",
                          caption: s.averageWeeks < settings.wtdReferenceWeeks ? "Only \(s.averageWeeks) week(s) of data" : "Rolling \(settings.wtdReferenceWeeks)-week reference",
                          progress: s.averageWeeklyWorkingTime / Limits.wtdWeeklyAverage, symbol: "chart.bar.fill", cautionAt: 0.95)
            }
        }

        if s.gbApplies {
            SectionHeader(title: "GB domestic")
            LazyVGrid(columns: columns, spacing: 10) {
                LimitCard(title: "Driving", value: "\(Fmt.hm(st.allDriving)) / 10h", caption: "Per working day",
                          progress: st.allDriving / Limits.gbDailyDriving, symbol: "steeringwheel")
                LimitCard(title: "Duty", value: "\(Fmt.hm(st.workingTime)) / 11h", caption: "Driving + other work",
                          progress: st.workingTime / Limits.gbDailyDuty, symbol: "clock.fill")
            }
        }

        let tonight = Calendar.hgv.startOfDay(for: s.now)
        let hasNightOut = nightOuts.contains { Calendar.hgv.isDate($0.date, inSameDayAs: tonight) }
        Button {
            toggleNightOut(on: tonight, existing: hasNightOut)
        } label: {
            Label(hasNightOut ? "Night out logged for tonight" : "Log a night out tonight",
                  systemImage: hasNightOut ? "checkmark.circle.fill" : "bed.double.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .padding(.top, 4)
    }

    // MARK: Captions

    private func driveCaption(_ s: ComplianceStatus) -> String {
        if s.isOnDailyRest { return "You're on daily rest" }
        if s.breakRemaining > 0 { return "After your break: \(Fmt.hm(min(Limits.continuousDriving, s.dailyDrivingRemaining, s.weeklyDrivingRemaining)))" }
        var limits: [String] = []
        if s.driveAvailableNow == s.continuousDrivingRemaining { limits.append("4h30 break rule") }
        if s.driveAvailableNow == s.dailyDrivingRemaining { limits.append("daily limit") }
        if s.driveAvailableNow == s.weeklyDrivingRemaining { limits.append("weekly limit") }
        if s.gbApplies && s.driveAvailableNow == min(s.gbDrivingRemaining, s.gbDutyRemaining) { limits.append("GB domestic") }
        return limits.isEmpty ? "Before any limit" : "Limited by " + limits.joined(separator: ", ")
    }

    private func restDeadlineCaption(_ s: ComplianceStatus) -> String {
        guard let latest = s.restStartByLatest, let full = s.restStartByFull else { return "" }
        if s.currentShift?.period.multiManned == true { return "Double-manned: 9h rest within 30h" }
        if latest == full { return "For 11h rest (no reduced rests left)" }
        return "9h reduced rest · \(Fmt.time(full)) for 11h"
    }

    private func restProgressCaption(_ s: ComplianceStatus) -> String {
        let r = s.currentRestLength
        let next: (TimeInterval, String)? = [
            (Limits.regularDailyRest, "11h regular daily"),
            (Limits.reducedWeeklyRest, "24h reduced weekly"),
            (Limits.regularWeeklyRest, "45h regular weekly")
        ].first { r < $0.0 }
        guard let next else { return "Regular weekly rest complete" }
        return "\(next.1) at \(Fmt.time(s.currentSince.addingTimeInterval(next.0)))"
    }

    // MARK: Actions

    private func toggleNightOut(on day: Date, existing: Bool) {
        if existing {
            for night in nightOuts where Calendar.hgv.isDate(night.date, inSameDayAs: day) {
                context.delete(night)
            }
        } else {
            context.insert(NightOut(date: day))
        }
        try? context.save()
    }

}
