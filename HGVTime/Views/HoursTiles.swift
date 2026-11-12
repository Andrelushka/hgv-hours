import SwiftUI
import SwiftData

/// Everything the hours tiles need to draw themselves.
struct HoursTileData {
    var status: ComplianceStatus
    var dash: Dashboard
    var settings: AppSettings
    var openEntry: ActivityEntry?
    var onShift: Bool

    var usesEU: Bool {
        settings.primaryRegime == .assimilated || status.stats.euDriving > 0 || status.weeklyDriving > 0
    }

    /// Whether a tile has something to show right now.
    func applies(_ tile: Tile) -> Bool {
        let s = status
        switch tile {
        case .driveLeft, .workLeft, .breakDue, .drivenToday, .workedToday, .shiftLength: return onShift
        case .restBy, .shiftLeft: return onShift && dash.restBy != nil
        case .restNow: return !onShift && s.hasData
        case .nextBreak: return onShift && Deadlines.breakPlan(s, applyWorkingTime: settings.applyWorkingTime) != nil
        case .comingUp, .tenHourDays, .fifteenHourDays, .restRules: return s.hasData
        case .beforeBreak, .dailyDriving, .weekDriving, .fortnight, .dailyRest, .reducedRests, .weeklyRest:
            return s.hasData && usesEU
        case .compensation: return s.hasData && usesEU && s.compensationOwed > 0 && s.compensationDueBy != nil
        case .wtdBreak, .shiftWorking, .weekWorking, .average: return s.hasData && settings.applyWorkingTime
        case .gbDriving, .gbDuty: return s.hasData && s.gbApplies
        case .allWarnings: return !s.warnings.isEmpty
        case .infringements: return !s.recentInfringements.isEmpty
        default: return true
        }
    }
}

/// Draws one hours tile (countdowns, limits, rest and working time).
struct HoursTileView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    var tile: Tile
    var data: HoursTileData
    @State private var showingInfringements = false

    var body: some View {
        let s = data.status
        let d = data.dash
        let st = s.stats
        let settings = data.settings
        switch tile {
        case .driveLeft:
            RingTile(title: "Driving left", value: Fmt.hm(d.driveLeft), caption: d.driveLeftReason,
                     fraction: d.driveLeft / Limits.continuousDriving, color: .blue, symbol: "steeringwheel")
        case .workLeft:
            RingTile(title: "Working left", value: Fmt.hm(d.workLeft), caption: d.workLeftReason,
                     fraction: d.workLeft / Limits.wtdMaxWorkWithoutBreak, color: .orange, symbol: "briefcase.fill")
        case .restBy:
            if let restBy = d.restBy {
                let left = restBy.timeIntervalSince(s.now)
                InfoCard(title: "Start daily rest by", value: Fmt.time(restBy), caption: restDeadlineCaption(s), symbol: "moon.zzz.fill",
                         tint: left < 0 ? .red : (left < 3600 ? .orange : .primary))
            }
        case .shiftLeft:
            if let restBy = d.restBy {
                let left = restBy.timeIntervalSince(s.now)
                InfoCard(title: "Shift time left", value: left < 0 ? "Overdue" : Fmt.hm(left), caption: "Until you must start daily rest",
                         symbol: "hourglass", tint: left < 0 ? .red : .primary)
            }
        case .breakDue:
            InfoCard(title: "Break due in", value: Fmt.hm(d.breakDueIn), caption: "45 min break after 4h30 driving or 6h work",
                     symbol: "cup.and.saucer.fill", tint: d.breakDueIn < 1800 ? .orange : .primary)
        case .drivenToday:
            LimitCard(title: "Driven today", value: "\(Fmt.hm(d.dailyDriving)) / \(Fmt.hm(d.dailyDrivingLimit))",
                      caption: "This shift", progress: d.dailyDrivingLimit > 0 ? d.dailyDriving / d.dailyDrivingLimit : 0, symbol: "sun.max.fill")
        case .workedToday:
            InfoCard(title: "Worked today", value: Fmt.hm(d.shiftWorking), caption: "Driving + other work this shift", symbol: "clock.fill")
        case .restNow:
            restCard(s)
        case .nextBreak:
            if let plan = Deadlines.breakPlan(s, applyWorkingTime: settings.applyWorkingTime) {
                BreakPlanCard(plan: plan, now: s.now)
            }
        case .comingUp:
            DeadlineList(deadlines: Deadlines.all(s, applyWorkingTime: settings.applyWorkingTime), now: s.now)
        case .tenHourDays:
            CountCard(title: "10h driving days", left: max(0, Limits.maxExtensionsPerWeek - s.extensionsUsed), of: Limits.maxExtensionsPerWeek,
                      caption: "left this week (normally 9h)", color: .blue)
        case .fifteenHourDays:
            CountCard(title: "15h days", left: max(0, Limits.maxReducedDailyRests - s.reducedRestsUsed), of: Limits.maxReducedDailyRests,
                      caption: "9h reduced rests left before weekly rest", color: .teal)
        case .shiftLength:
            shiftLengthCard(s)
        case .restRules:
            RestRulesCard(status: s, allowConsecutiveReduced: settings.allowConsecutiveReducedWeekly)
        case .beforeBreak:
            LimitCard(title: "Before break", value: Fmt.hm(s.continuousDrivingRemaining),
                      caption: s.breakNeeded == Limits.splitBreakSecond ? "15 min taken — 30 min completes the break" : "\(Fmt.hm(st.continuousDriving)) of 4h30 driven",
                      progress: st.continuousDriving / Limits.continuousDriving, symbol: "cup.and.saucer.fill")
        case .dailyDriving:
            LimitCard(title: "Daily driving", value: "\(Fmt.hm(st.euDriving)) / \(Fmt.hm(s.dailyDrivingLimit))",
                      caption: "10h extensions used this week: \(s.extensionsUsed) of 2",
                      progress: st.euDriving / s.dailyDrivingLimit, symbol: "sun.max.fill")
        case .weekDriving:
            LimitCard(title: "This week", value: "\(Fmt.hm(s.weeklyDriving)) / 56h", caption: "Week from \(Fmt.day(s.weekStart))",
                      progress: s.weeklyDriving / Limits.weeklyDriving, symbol: "calendar")
        case .fortnight:
            LimitCard(title: "Fortnight", value: "\(Fmt.hm(s.weeklyDriving + s.previousWeekDriving)) / 90h",
                      caption: "Last week \(Fmt.hm(s.previousWeekDriving))",
                      progress: (s.weeklyDriving + s.previousWeekDriving) / Limits.fortnightlyDriving, symbol: "calendar.badge.clock")
        case .dailyRest:
            if s.isOnDailyRest {
                InfoCard(title: "Resting for", value: Fmt.hm(s.currentRestLength), caption: restProgressCaption(s), symbol: "bed.double.fill", tint: .green)
            } else if let latest = s.restStartByLatest {
                InfoCard(title: "Start daily rest by", value: Fmt.time(latest), caption: restDeadlineCaption(s), symbol: "moon.fill",
                         tint: s.now > latest ? .red : (latest.timeIntervalSince(s.now) < .hours(1) ? .orange : .primary))
            } else {
                InfoCard(title: "Daily rest", value: "—", caption: "Starts counting when your shift starts", symbol: "moon.fill")
            }
        case .reducedRests:
            InfoCard(title: "Reduced rests", value: "\(s.reducedRestsUsed) of 3", caption: "9h rests since your last weekly rest",
                     symbol: "moon.haze.fill", tint: s.reducedRestsUsed >= 3 ? .orange : .primary)
        case .weeklyRest:
            if let due = s.weeklyRestDueBy {
                InfoCard(title: "Weekly rest by", value: Fmt.dayTime(due),
                         caption: s.nextWeeklyMustBeRegular ? "Must be a regular 45h rest" : "24h reduced or 45h regular",
                         symbol: "house.fill", tint: s.now > due ? .red : .primary)
            } else {
                InfoCard(title: "Weekly rest", value: s.currentRestLength >= Limits.reducedWeeklyRest ? "In progress" : "—",
                         caption: s.currentRestLength >= Limits.reducedWeeklyRest ? restProgressCaption(s) : "Shows once a 24h+ rest is logged",
                         symbol: "house.fill")
            }
        case .compensation:
            if let due = s.compensationDueBy {
                InfoCard(title: "Compensation owed", value: Fmt.hm(s.compensationOwed),
                         caption: "Attach to a 9h+ rest before \(Fmt.day(due))", symbol: "arrow.uturn.backward.circle", tint: .orange)
            }
        case .wtdBreak:
            LimitCard(title: "Before 6h break", value: Fmt.hm(s.wtdWorkBeforeBreak),
                      caption: s.wtdBreakNeededToday > 0 ? "Need \(Fmt.hm(s.wtdBreakNeededToday)) more breaks today" : "Breaks taken: \(Fmt.hm(st.wtdBreakTotal))",
                      progress: st.wtdWorkSinceBreak / Limits.wtdMaxWorkWithoutBreak, symbol: "figure.walk")
        case .shiftWorking:
            if let night = s.nightWorkRemaining {
                LimitCard(title: "Night shift work", value: "\(Fmt.hm(st.workingTime)) / \(Fmt.hm(settings.nightWorkLimitHours * 3600))",
                          caption: "\(Fmt.hm(night)) left · shift includes 00:00–04:00",
                          progress: st.workingTime / (settings.nightWorkLimitHours * 3600), symbol: "moon.stars.fill")
            } else {
                InfoCard(title: "Shift working time", value: Fmt.hm(st.workingTime),
                         caption: "POA \(Fmt.hm(st.availability)) · breaks \(Fmt.hm(st.breaks))", symbol: "clock.fill")
            }
        case .weekWorking:
            LimitCard(title: "Week working", value: "\(Fmt.hm(s.weeklyWorkingTime)) / 60h", caption: "Excludes breaks and POA",
                      progress: s.weeklyWorkingTime / Limits.wtdWeeklyMaximum, symbol: "briefcase.fill")
        case .average:
            LimitCard(title: "\(s.averageWeeks)-week average", value: "\(Fmt.hm(s.averageWeeklyWorkingTime)) / 48h",
                      caption: s.averageWeeks < settings.wtdReferenceWeeks ? "Only \(s.averageWeeks) week(s) of data" : "Rolling \(settings.wtdReferenceWeeks)-week reference",
                      progress: s.averageWeeklyWorkingTime / Limits.wtdWeeklyAverage, symbol: "chart.bar.fill", cautionAt: 0.95)
        case .gbDriving:
            LimitCard(title: "GB driving", value: "\(Fmt.hm(st.allDriving)) / 10h", caption: "Per working day",
                      progress: st.allDriving / Limits.gbDailyDriving, symbol: "steeringwheel")
        case .gbDuty:
            LimitCard(title: "GB duty", value: "\(Fmt.hm(st.workingTime)) / 11h", caption: "Driving + other work",
                      progress: st.workingTime / Limits.gbDailyDuty, symbol: "clock.fill")
        case .allWarnings:
            VStack(spacing: 10) { ForEach(s.warnings) { IssueRow(issue: $0) } }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        case .infringements:
            Button { showingInfringements = true } label: {
                Label("\(s.recentInfringements.count) infringement\(s.recentInfringements.count == 1 ? "" : "s") in the last 28 days",
                      systemImage: "exclamationmark.octagon")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .sheet(isPresented: $showingInfringements) {
                NavigationStack {
                    List(s.recentInfringements) { IssueRow(issue: $0, showDate: true) }
                        .navigationTitle("Last 28 days")
                        .toolbar { Button("Done") { showingInfringements = false } }
                }
            }
        case .nightOut:
            NightOutTile(now: s.now)
        default:
            EmptyView()
        }
    }

    private func shiftLengthCard(_ s: ComplianceStatus) -> some View {
        let reducedLeft = max(0, Limits.maxReducedDailyRests - s.reducedRestsUsed)
        let shiftStart = s.currentShift?.period.start ?? s.now
        let spread = s.now.timeIntervalSince(shiftStart)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Shift length", systemImage: "arrow.left.and.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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

    private func restCard(_ s: ComplianceStatus) -> some View {
        let type = data.openEntry?.restType ?? .daily
        let rest = s.currentRestLength
        let target: TimeInterval = type == .weekly ? Limits.regularWeeklyRest : Limits.regularDailyRest
        let minimum: TimeInterval = type == .weekly ? Limits.reducedWeeklyRest : Limits.reducedDailyRest
        let since = s.currentSince
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(type == .weekly ? "Weekly rest" : "Daily rest", systemImage: type.symbol).font(.headline).foregroundStyle(type.color)
                Spacer()
                Text("\(Fmt.hm(rest)) of \(Fmt.hm(target))").font(.headline.monospacedDigit())
            }
            ProgressView(value: min(rest / target, 1)).tint(type.color)
            HStack {
                VStack(alignment: .leading) {
                    Text(type == .weekly ? "Reduced (24h)" : "Reduced (9h)").font(.caption).foregroundStyle(.secondary)
                    Text(rest >= minimum ? "Done" : Fmt.dayTime(since.addingTimeInterval(minimum))).font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(type == .weekly ? "Regular (45h)" : "Regular (11h)").font(.caption).foregroundStyle(.secondary)
                    Text(rest >= target ? "Done" : Fmt.dayTime(since.addingTimeInterval(target))).font(.subheadline.weight(.semibold))
                }
            }
            if let due = s.weeklyRestDueBy, type == .daily {
                Text("Next weekly rest due by \(Fmt.dayTime(due))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(type.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
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
}

/// Square night-out tile: tap to log or remove tonight's night out.
struct NightOutTile: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    var now: Date
    @State private var refresh = 0

    var body: some View {
        let tonight = Calendar.hgv.startOfDay(for: now)
        let _ = refresh
        let has = !ActivityController.nightOuts(on: tonight, context: context).isEmpty
        Button {
            let existing = ActivityController.nightOuts(on: tonight, context: context)
            if existing.isEmpty { context.insert(NightOut(date: tonight)) } else { existing.forEach { context.delete($0) } }
            try? context.save()
            refresh += 1
            ActivityController.refreshSideEffects(context: context, settings: store.settings)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label("Night out", systemImage: "bed.double.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Image(systemName: has ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(has ? .green : .accentColor)
                Text(has ? "Logged for tonight" : "Tap to log tonight").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(has ? Color.green.opacity(0.12) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: has)
    }
}

/// Today's date in the driver's chosen style.
struct DateTile: View {
    @Environment(SettingsStore.self) private var store
    var now: Date

    var body: some View {
        HStack {
            Image(systemName: "calendar").foregroundStyle(.tint)
            Text(store.settings.formattedDate(now)).font(.headline)
            Spacer()
            if BankHolidays.isBankHoliday(now) {
                Text("Bank holiday").font(.caption.weight(.bold)).foregroundStyle(.red)
            }
            Menu {
                Picker("Date style", selection: Binding(get: { store.settings.dateStyle }, set: { store.settings.dateStyle = $0 })) {
                    ForEach(AppSettings.dateStyles, id: \.id) { Text($0.title).tag($0.id) }
                }
            } label: {
                Image(systemName: "textformat").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityLabel("Date style")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Shown in edit mode for a tile that has nothing to show right now.
struct TilePlaceholder: View {
    var tile: Tile
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(tile.title, systemImage: tile.symbol).font(.caption.weight(.semibold))
            Text("Shows when it applies").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
    }
}
