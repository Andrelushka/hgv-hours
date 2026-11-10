import Foundation

// MARK: - Output types

struct ComplianceIssue: Identifiable, Hashable {
    enum Severity: Int, Comparable, Hashable {
        case info = 0, caution, violation
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Family: String, Hashable {
        case driversHours = "Drivers' hours"
        case workingTime = "Working time"
        case gbDomestic = "GB domestic"
    }

    let id = UUID()
    var severity: Severity
    var family: Family
    var title: String
    var detail: String
    var date: Date? = nil
}

/// Totals and counters for one duty period.
struct PeriodStats: Equatable {
    var euDriving: TimeInterval = 0
    var gbDriving: TimeInterval = 0
    var otherWork: TimeInterval = 0
    var availability: TimeInterval = 0
    var breaks: TimeInterval = 0

    /// Assimilated/AETR driving since the last qualifying break (45 min, or 15 + 30).
    var continuousDriving: TimeInterval = 0
    var maxContinuousDriving: TimeInterval = 0
    var splitBreakFirstTaken = false

    /// RT(WT)R working time since the last 30 min of breaks (in pieces of ≥ 15 min).
    var wtdWorkSinceBreak: TimeInterval = 0
    var wtdMaxWorkWithoutBreak: TimeInterval = 0
    var wtdPendingBreak: TimeInterval = 0
    /// Total of break pieces ≥ 15 min during the period.
    var wtdBreakTotal: TimeInterval = 0

    var nightWork = false
    var hasGB = false
    var multiManned = false
    /// A rest of ≥ 3h inside the period: the first part of a split daily rest.
    var splitRestFirstPartTaken = false

    var allDriving: TimeInterval { euDriving + gbDriving }
    /// Driving + other work (excludes breaks and POA).
    var workingTime: TimeInterval { allDriving + otherWork }
}

enum DailyRestKind: String {
    case regular = "Regular daily rest"
    case reduced = "Reduced daily rest"
    case split = "Split daily rest"
    case weeklyRegular = "Regular weekly rest"
    case weeklyReduced = "Reduced weekly rest"
    case insufficient = "Insufficient rest"
}

struct ShiftSummary: Identifiable {
    var period: DutyPeriod
    var stats: PeriodStats
    var restKind: DailyRestKind?
    /// Rest taken inside the 24h (30h multi-manned) window.
    var restWithinWindow: TimeInterval
    var issues: [ComplianceIssue]
    var id: Date { period.start }
}

struct WeekSummary: Identifiable {
    var weekStart: Date
    var euDriving: TimeInterval
    var allDriving: TimeInterval
    var previousWeekEuDriving: TimeInterval
    var workingTime: TimeInterval
    var availability: TimeInterval
    var shifts: [ShiftSummary]
    var weeklyRests: [Segment]
    var issues: [ComplianceIssue]
    var id: Date { weekStart }

    var fortnightDriving: TimeInterval { euDriving + previousWeekEuDriving }
    var allIssues: [ComplianceIssue] { shifts.flatMap(\.issues) + issues }
}

struct Analysis {
    var segments: [Segment]
    var shifts: [ShiftSummary]
    var weeks: [WeekSummary]
}

/// Live position against every limit, shown on the Today screen.
struct ComplianceStatus {
    var now: Date
    var hasData = false
    var currentKind: DutyKind = .rest
    var currentSince: Date = .now
    var currentShift: ShiftSummary?
    var stats = PeriodStats()

    // Breaks (assimilated/AETR)
    var continuousDrivingRemaining: TimeInterval = Limits.continuousDriving
    /// Break length that would reset the 4h30 counter (45 or 30 min); 0 if not needed.
    var breakNeeded: TimeInterval = 0
    /// While on a break: time left until it qualifies.
    var breakRemaining: TimeInterval = 0

    // Daily driving
    var dailyDrivingLimit: TimeInterval = Limits.extendedDailyDriving
    var dailyDrivingRemaining: TimeInterval = Limits.extendedDailyDriving
    var extensionsUsed = 0

    // Weekly driving
    var weekStart: Date = .now
    var weeklyDriving: TimeInterval = 0
    var previousWeekDriving: TimeInterval = 0
    var weeklyDrivingRemaining: TimeInterval = Limits.weeklyDriving

    /// The most you can drive right now before hitting any limit.
    var driveAvailableNow: TimeInterval = Limits.continuousDriving

    // Daily rest
    var restStartByFull: Date?
    var restStartByLatest: Date?
    var reducedRestsUsed = 0
    var currentRestLength: TimeInterval = 0
    var isOnDailyRest: Bool { currentKind == .rest && currentRestLength >= Limits.reducedDailyRest }

    // Weekly rest
    var lastWeeklyRest: Segment?
    var weeklyRestDueBy: Date?
    var nextWeeklyMustBeRegular = false
    var compensationOwed: TimeInterval = 0
    var compensationDueBy: Date?

    // Working time
    var wtdWorkBeforeBreak: TimeInterval = Limits.wtdMaxWorkWithoutBreak
    var wtdBreakNeededToday: TimeInterval = 0
    var nightWorkRemaining: TimeInterval?
    var weeklyWorkingTime: TimeInterval = 0
    var averageWeeklyWorkingTime: TimeInterval = 0
    var averageWeeks = 0

    // GB domestic
    var gbApplies = false
    var gbDrivingRemaining: TimeInterval = Limits.gbDailyDriving
    var gbDutyRemaining: TimeInterval = Limits.gbDailyDuty

    var warnings: [ComplianceIssue] = []
    var recentInfringements: [ComplianceIssue] = []
}

// MARK: - Engine

enum RulesEngine {

    // MARK: Period statistics

    static func stats(for segments: [Segment], config: RuleConfig) -> PeriodStats {
        var s = PeriodStats()
        for segment in segments {
            let d = segment.duration
            if segment.multiManned { s.multiManned = true }
            if segment.regime == .gbDomestic && segment.kind != .rest { s.hasGB = true }

            switch segment.kind {
            case .drive:
                if segment.regime == .assimilated {
                    s.euDriving += d
                    s.continuousDriving += d
                    s.maxContinuousDriving = max(s.maxContinuousDriving, s.continuousDriving)
                } else {
                    // GB domestic driving counts as "other work" under assimilated rules.
                    s.gbDriving += d
                }
            case .otherWork:
                s.otherWork += d
            case .availability:
                s.availability += d
            case .rest:
                s.breaks += d
                if d >= Limits.splitRestFirstPart { s.splitRestFirstPartTaken = true }

                // Assimilated/AETR break: 45 min, or 15 min followed later by 30 min.
                if d >= Limits.fullBreak - 1 || (s.splitBreakFirstTaken && d >= Limits.splitBreakSecond - 1) {
                    s.continuousDriving = 0
                    s.splitBreakFirstTaken = false
                } else if d >= Limits.splitBreakFirst - 1 {
                    s.splitBreakFirstTaken = true
                }

                // RT(WT)R: breaks in pieces of at least 15 min.
                if d >= Limits.wtdBreakPiece - 1 {
                    s.wtdBreakTotal += d
                    s.wtdPendingBreak += d
                    if s.wtdPendingBreak >= Limits.wtdBreakShortDay - 1 {
                        s.wtdWorkSinceBreak = 0
                        s.wtdPendingBreak = 0
                    }
                }
            }

            if segment.isWork {
                s.wtdWorkSinceBreak += d
                s.wtdMaxWorkWithoutBreak = max(s.wtdMaxWorkWithoutBreak, s.wtdWorkSinceBreak)
                if overlapsNight(segment, config: config) { s.nightWork = true }
            }
        }
        return s
    }

    static func overlapsNight(_ segment: Segment, config: RuleConfig) -> Bool {
        let cal = config.calendar
        guard var day = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: segment.start)) else { return false }
        while day < segment.end {
            if let windowStart = cal.date(byAdding: .hour, value: config.nightStartHour, to: day),
               var windowEnd = cal.date(byAdding: .hour, value: config.nightEndHour, to: day) {
                if windowEnd <= windowStart { windowEnd = cal.date(byAdding: .day, value: 1, to: windowEnd) ?? windowEnd }
                if segment.overlap(with: windowStart, windowEnd) > 0 { return true }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return false
    }

    /// Sum of matching segments clipped to [from, to).
    static func total(_ segments: [Segment], from: Date, to: Date, where include: (Segment) -> Bool) -> TimeInterval {
        segments.reduce(0) { sum, seg in
            guard include(seg), seg.end > from, seg.start < to else { return sum }
            return sum + seg.overlap(with: from, to)
        }
    }

    // MARK: Daily rest classification

    static func classifyRest(after period: DutyPeriod, stats: PeriodStats) -> (DailyRestKind?, TimeInterval) {
        guard let rest = period.restAfter else { return (nil, 0) }
        let window = period.multiManned ? Limits.multiMannedRestWindow : Limits.dailyRestWindow
        let deadline = period.start.addingTimeInterval(window)
        let within = max(0, min(rest.end, deadline).timeIntervalSince(rest.start))

        if within < Limits.reducedDailyRest - Limits.tolerance { return (DailyRestKind.insufficient, within) }
        if rest.duration >= Limits.reducedWeeklyRest {
            let weekly: DailyRestKind = rest.duration >= Limits.regularWeeklyRest - Limits.tolerance ? .weeklyRegular : .weeklyReduced
            return (weekly, within)
        }
        if period.multiManned { return (DailyRestKind.regular, within) }
        if stats.splitRestFirstPartTaken { return (DailyRestKind.split, within) }
        let daily: DailyRestKind = within >= Limits.regularDailyRest - Limits.tolerance ? .regular : .reduced
        return (daily, within)
    }

    // MARK: Issues for a single shift

    static func issues(for period: DutyPeriod, stats st: PeriodStats, restKind: DailyRestKind?, within: TimeInterval, config: RuleConfig) -> [ComplianceIssue] {
        var list: [ComplianceIssue] = []
        let date = period.start
        let tol = Limits.tolerance

        if st.maxContinuousDriving > Limits.continuousDriving + tol {
            list.append(.init(severity: .violation, family: .driversHours,
                              title: "Drove over 4h30 without a break",
                              detail: "Longest stretch \(Fmt.hm(st.maxContinuousDriving)). A 45 min break (or 15 + 30) is required after 4h30.",
                              date: date))
        }
        if st.euDriving > Limits.extendedDailyDriving + tol {
            list.append(.init(severity: .violation, family: .driversHours,
                              title: "Daily driving over 10h",
                              detail: "Drove \(Fmt.hm(st.euDriving)). Limit is 9h, extendable to 10h twice a week.",
                              date: date))
        }
        if restKind == .insufficient {
            let window = period.multiManned ? "30h" : "24h"
            list.append(.init(severity: .violation, family: .driversHours,
                              title: "Daily rest too short",
                              detail: "Only \(Fmt.hm(within)) rest within \(window) of shift start. At least 9h is required.",
                              date: date))
        }
        if config.applyWorkingTime {
            if st.wtdMaxWorkWithoutBreak > Limits.wtdMaxWorkWithoutBreak + tol {
                list.append(.init(severity: .violation, family: .workingTime,
                                  title: "Worked over 6h without a break",
                                  detail: "Longest run \(Fmt.hm(st.wtdMaxWorkWithoutBreak)). Take 30 min (in 15 min pieces) before 6h.",
                                  date: date))
            }
            if st.workingTime > Limits.wtdLongDayThreshold + tol && st.wtdBreakTotal < Limits.wtdBreakLongDay - tol {
                list.append(.init(severity: .violation, family: .workingTime,
                                  title: "Under 45 min breaks on a 9h+ day",
                                  detail: "Worked \(Fmt.hm(st.workingTime)) with \(Fmt.hm(st.wtdBreakTotal)) of breaks.",
                                  date: date))
            } else if st.workingTime > Limits.wtdMaxWorkWithoutBreak + tol && st.wtdBreakTotal < Limits.wtdBreakShortDay - tol {
                list.append(.init(severity: .violation, family: .workingTime,
                                  title: "Under 30 min breaks on a 6h+ day",
                                  detail: "Worked \(Fmt.hm(st.workingTime)) with \(Fmt.hm(st.wtdBreakTotal)) of breaks.",
                                  date: date))
            }
            if st.nightWork && st.workingTime > config.nightWorkLimit + tol {
                list.append(.init(severity: .violation, family: .workingTime,
                                  title: "Night work over \(Fmt.hm(config.nightWorkLimit))",
                                  detail: "Worked \(Fmt.hm(st.workingTime)) in a shift that included night time (00:00–04:00).",
                                  date: date))
            }
        }
        if st.hasGB || config.primaryRegime == .gbDomestic {
            if st.allDriving > Limits.gbDailyDriving + tol {
                list.append(.init(severity: .violation, family: .gbDomestic,
                                  title: "Driving over 10h (GB domestic)",
                                  detail: "Drove \(Fmt.hm(st.allDriving)) in the working day.", date: date))
            }
            if st.workingTime > Limits.gbDailyDuty + tol {
                list.append(.init(severity: .violation, family: .gbDomestic,
                                  title: "Duty over 11h (GB domestic)",
                                  detail: "On duty \(Fmt.hm(st.workingTime)) in the working day.", date: date))
            }
        }
        return list
    }

    // MARK: Full analysis

    static func analyze(_ entries: [EntrySnapshot], now: Date, config: RuleConfig) -> Analysis {
        let cal = config.calendar
        let segments = Timeline.build(entries, now: now)
        let periods = Timeline.dutyPeriods(from: segments)

        // Shifts
        var shifts: [ShiftSummary] = periods.map { period in
            let st = stats(for: period.segments, config: config)
            let (kind, within) = classifyRest(after: period, stats: st)
            return ShiftSummary(period: period, stats: st, restKind: kind, restWithinWindow: within,
                                issues: issues(for: period, stats: st, restKind: kind, within: within, config: config))
        }

        // Max three reduced daily rests between weekly rests.
        var reducedCount = 0
        for index in shifts.indices {
            switch shifts[index].restKind {
            case .reduced:
                reducedCount += 1
                if reducedCount > Limits.maxReducedDailyRests {
                    shifts[index].issues.append(.init(severity: .violation, family: .driversHours,
                        title: "More than 3 reduced daily rests",
                        detail: "This was reduced daily rest number \(reducedCount) since the last weekly rest.",
                        date: shifts[index].period.start))
                }
            case .weeklyRegular, .weeklyReduced:
                reducedCount = 0
            default: break
            }
        }

        // Weeks
        var weeks: [WeekSummary] = []
        let weeklyRests = segments.filter { $0.kind == .rest && $0.duration >= Limits.reducedWeeklyRest }
        if let first = segments.first {
            var weekStart = cal.startOfFixedWeek(for: first.start)
            var previousEu: TimeInterval = 0
            while weekStart <= now {
                guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { break }
                let eu = total(segments, from: weekStart, to: weekEnd) { $0.kind == .drive && $0.regime == .assimilated }
                let allDrive = total(segments, from: weekStart, to: weekEnd) { $0.kind == .drive }
                let work = total(segments, from: weekStart, to: weekEnd) { $0.isWork }
                let poa = total(segments, from: weekStart, to: weekEnd) { $0.kind == .availability }
                let weekShifts = shifts.filter { $0.period.start >= weekStart && $0.period.start < weekEnd }
                let rests = weeklyRests.filter { $0.start >= weekStart && $0.start < weekEnd }

                var weekIssues: [ComplianceIssue] = []
                let tol = Limits.tolerance
                if eu > Limits.weeklyDriving + tol {
                    weekIssues.append(.init(severity: .violation, family: .driversHours, title: "Weekly driving over 56h",
                                            detail: "Drove \(Fmt.hm(eu)) this week.", date: weekStart))
                }
                if eu + previousEu > Limits.fortnightlyDriving + tol {
                    weekIssues.append(.init(severity: .violation, family: .driversHours, title: "Fortnightly driving over 90h",
                                            detail: "Drove \(Fmt.hm(eu + previousEu)) over this and last week.", date: weekStart))
                }
                let extensions = weekShifts.filter { $0.stats.euDriving > Limits.dailyDriving + tol }.count
                if extensions > Limits.maxExtensionsPerWeek {
                    weekIssues.append(.init(severity: .violation, family: .driversHours, title: "More than two 10h driving days",
                                            detail: "\(extensions) days over 9h this week. Only 2 extended days are allowed.", date: weekStart))
                }
                if config.applyWorkingTime && work > Limits.wtdWeeklyMaximum + tol {
                    weekIssues.append(.init(severity: .violation, family: .workingTime, title: "Working time over 60h",
                                            detail: "Worked \(Fmt.hm(work)) this week.", date: weekStart))
                }

                weeks.append(WeekSummary(weekStart: weekStart, euDriving: eu, allDriving: allDrive,
                                         previousWeekEuDriving: previousEu, workingTime: work, availability: poa,
                                         shifts: weekShifts, weeklyRests: rests, issues: weekIssues))
                previousEu = eu
                weekStart = weekEnd
            }
        }

        // Weekly rest spacing and consecutive reduced weekly rests.
        for (index, rest) in weeklyRests.enumerated() where index > 0 {
            let previous = weeklyRests[index - 1]
            guard let weekIndex = weeks.firstIndex(where: { rest.start >= $0.weekStart && rest.start < (cal.date(byAdding: .day, value: 7, to: $0.weekStart) ?? $0.weekStart) }) else { continue }
            let gap = rest.start.timeIntervalSince(previous.end)
            if gap > Limits.weeklyRestInterval + Limits.tolerance {
                weeks[weekIndex].issues.append(.init(severity: .violation, family: .driversHours, title: "Weekly rest started late",
                    detail: "Started \(Fmt.hm(gap)) after the previous weekly rest. It must start within 6 × 24h.", date: rest.start))
            }
            let isOngoing = rest.end >= now
            if !isOngoing && !config.allowConsecutiveReducedWeekly
                && rest.duration < Limits.regularWeeklyRest - Limits.tolerance
                && previous.duration < Limits.regularWeeklyRest - Limits.tolerance {
                weeks[weekIndex].issues.append(.init(severity: .violation, family: .driversHours, title: "Two reduced weekly rests in a row",
                    detail: "In any two consecutive weeks at least one weekly rest must be a regular 45h rest.", date: rest.start))
            }
        }

        return Analysis(segments: segments, shifts: shifts, weeks: weeks)
    }

    // MARK: Live status

    static func status(_ entries: [EntrySnapshot], now: Date, config: RuleConfig) -> ComplianceStatus {
        let analysis = analyze(entries, now: now, config: config)
        let segments = analysis.segments
        let cal = config.calendar
        var s = ComplianceStatus(now: now)
        guard let last = segments.last else { return s }

        s.hasData = true
        s.currentKind = last.kind
        s.currentSince = last.start
        s.currentRestLength = last.kind == .rest ? last.duration : 0

        let openShift = analysis.shifts.last.flatMap { $0.period.isOpen ? $0 : nil }
        s.currentShift = openShift
        s.stats = openShift?.stats ?? PeriodStats()
        let st = s.stats

        // --- Breaks
        if let shift = openShift, last.kind == .rest {
            let before = stats(for: Array(shift.period.segments.dropLast()), config: config)
            if before.continuousDriving > 0 {
                s.breakNeeded = before.splitBreakFirstTaken ? Limits.splitBreakSecond : Limits.fullBreak
                s.breakRemaining = max(0, s.breakNeeded - s.currentRestLength)
            }
        } else if st.continuousDriving > 0 {
            s.breakNeeded = st.splitBreakFirstTaken ? Limits.splitBreakSecond : Limits.fullBreak
        }
        s.continuousDrivingRemaining = max(0, Limits.continuousDriving - st.continuousDriving)

        // --- Daily driving
        s.weekStart = cal.startOfFixedWeek(for: now)
        s.extensionsUsed = analysis.shifts.filter {
            !$0.period.isOpen && $0.period.start >= s.weekStart && $0.stats.euDriving > Limits.dailyDriving + Limits.tolerance
        }.count
        s.dailyDrivingLimit = s.extensionsUsed < Limits.maxExtensionsPerWeek ? Limits.extendedDailyDriving : Limits.dailyDriving
        s.dailyDrivingRemaining = max(0, s.dailyDrivingLimit - st.euDriving)

        // --- Weekly driving
        let weekEnd = cal.date(byAdding: .day, value: 7, to: s.weekStart) ?? now
        let previousWeekStart = cal.date(byAdding: .day, value: -7, to: s.weekStart) ?? s.weekStart
        s.weeklyDriving = total(segments, from: s.weekStart, to: weekEnd) { $0.kind == .drive && $0.regime == .assimilated }
        s.previousWeekDriving = total(segments, from: previousWeekStart, to: s.weekStart) { $0.kind == .drive && $0.regime == .assimilated }
        s.weeklyDrivingRemaining = max(0, min(Limits.weeklyDriving - s.weeklyDriving,
                                              Limits.fortnightlyDriving - s.weeklyDriving - s.previousWeekDriving))

        // --- GB domestic
        s.gbApplies = config.primaryRegime == .gbDomestic || st.hasGB
        s.gbDrivingRemaining = max(0, Limits.gbDailyDriving - st.allDriving)
        s.gbDutyRemaining = max(0, Limits.gbDailyDuty - st.workingTime)

        var available = min(s.continuousDrivingRemaining, s.dailyDrivingRemaining, s.weeklyDrivingRemaining)
        if s.gbApplies { available = min(available, s.gbDrivingRemaining, s.gbDutyRemaining) }
        if config.primaryRegime == .gbDomestic && !openShiftHasEU(st) {
            available = min(s.gbDrivingRemaining, s.gbDutyRemaining)
        }
        if s.isOnDailyRest || (last.kind == .rest && s.breakRemaining > 0) { available = 0 }
        s.driveAvailableNow = available

        // --- Weekly rest
        let weeklyRests = segments.filter { $0.kind == .rest && $0.duration >= Limits.reducedWeeklyRest }
        let completedWeekly = weeklyRests.filter { $0.end < now }
        s.lastWeeklyRest = completedWeekly.last
        let onWeeklyRest = last.kind == .rest && last.duration >= Limits.reducedWeeklyRest
        if let lastWeekly = completedWeekly.last, !onWeeklyRest {
            s.weeklyRestDueBy = lastWeekly.end.addingTimeInterval(Limits.weeklyRestInterval)
            let lastReduced = lastWeekly.duration < Limits.regularWeeklyRest - Limits.tolerance
            if config.allowConsecutiveReducedWeekly {
                let previousReduced = completedWeekly.count >= 2
                    && completedWeekly[completedWeekly.count - 2].duration < Limits.regularWeeklyRest - Limits.tolerance
                s.nextWeeklyMustBeRegular = lastReduced && previousReduced
            } else {
                s.nextWeeklyMustBeRegular = lastReduced
            }
        }

        // Compensation for reduced weekly rest(s) in the last 4 weeks.
        let fourWeeksAgo = cal.date(byAdding: .day, value: -28, to: s.weekStart) ?? now
        var owed: TimeInterval = 0
        var oldestReduced: Segment?
        for rest in completedWeekly.reversed() {
            guard rest.start >= fourWeeksAgo, rest.duration < Limits.regularWeeklyRest - Limits.tolerance else { break }
            owed += Limits.regularWeeklyRest - rest.duration
            oldestReduced = rest
        }
        if owed > 0, let lastReduced = completedWeekly.last {
            let paid = segments.contains { seg in
                seg.kind == .rest && seg.start > lastReduced.end && (
                    (seg.duration < Limits.reducedWeeklyRest && seg.duration >= Limits.reducedDailyRest + owed - Limits.tolerance) ||
                    seg.duration >= Limits.regularWeeklyRest + owed - Limits.tolerance)
            }
            if !paid, let oldest = oldestReduced {
                s.compensationOwed = owed
                s.compensationDueBy = cal.date(byAdding: .day, value: 28, to: cal.startOfFixedWeek(for: oldest.start))
            }
        }

        // --- Daily rest deadline and reduced rests used
        if let lastWeekly = completedWeekly.last {
            s.reducedRestsUsed = analysis.shifts.filter { $0.period.start >= lastWeekly.end && $0.restKind == .reduced }.count
        } else {
            s.reducedRestsUsed = analysis.shifts.filter { $0.restKind == .reduced }.count
        }
        if let shift = openShift {
            let start = shift.period.start
            if shift.period.multiManned {
                let latest = start.addingTimeInterval(Limits.multiMannedRestWindow - Limits.reducedDailyRest)
                s.restStartByFull = latest
                s.restStartByLatest = latest
            } else {
                s.restStartByFull = start.addingTimeInterval(Limits.dailyRestWindow - Limits.regularDailyRest)
                let reducedOK = s.reducedRestsUsed < Limits.maxReducedDailyRests || st.splitRestFirstPartTaken
                s.restStartByLatest = reducedOK
                    ? start.addingTimeInterval(Limits.dailyRestWindow - Limits.reducedDailyRest)
                    : s.restStartByFull
            }
        }

        // --- Working time
        s.wtdWorkBeforeBreak = max(0, Limits.wtdMaxWorkWithoutBreak - st.wtdWorkSinceBreak)
        if st.workingTime > Limits.wtdLongDayThreshold - .minutes(30) {
            s.wtdBreakNeededToday = max(0, Limits.wtdBreakLongDay - st.wtdBreakTotal)
        } else if st.workingTime > Limits.wtdMaxWorkWithoutBreak - .minutes(30) {
            s.wtdBreakNeededToday = max(0, Limits.wtdBreakShortDay - st.wtdBreakTotal)
        }
        if st.nightWork { s.nightWorkRemaining = max(0, config.nightWorkLimit - st.workingTime) }
        s.weeklyWorkingTime = total(segments, from: s.weekStart, to: weekEnd) { $0.isWork }
        let refWeeks = analysis.weeks.suffix(max(1, config.wtdReferenceWeeks))
        s.averageWeeks = refWeeks.count
        if !refWeeks.isEmpty {
            s.averageWeeklyWorkingTime = refWeeks.reduce(0) { $0 + $1.workingTime } / Double(refWeeks.count)
        }

        // --- Warnings and recent infringements
        s.warnings = warnings(for: s, config: config)
        let cutoff = cal.date(byAdding: .day, value: -28, to: now) ?? now
        s.recentInfringements = analysis.weeks
            .flatMap(\.allIssues)
            .filter { ($0.date ?? .distantPast) >= cutoff }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return s
    }

    private static func openShiftHasEU(_ st: PeriodStats) -> Bool { st.euDriving > 0 }

    // MARK: Live warnings

    static func warnings(for s: ComplianceStatus, config: RuleConfig) -> [ComplianceIssue] {
        var w: [ComplianceIssue] = []
        let st = s.stats
        let soon: TimeInterval = .minutes(30)
        let usesEU = config.primaryRegime == .assimilated || st.euDriving > 0
        let working = s.currentKind == .drive || s.currentKind == .otherWork

        if usesEU {
            if st.continuousDriving >= Limits.continuousDriving - Limits.tolerance && s.currentKind == .drive {
                w.append(.init(severity: .violation, family: .driversHours, title: "Break required now",
                               detail: "You've driven \(Fmt.hm(st.continuousDriving)) without a break. Take \(Fmt.hm(max(s.breakNeeded, Limits.splitBreakSecond))) now."))
            } else if s.currentKind == .drive && s.continuousDrivingRemaining <= soon {
                w.append(.init(severity: .caution, family: .driversHours, title: "Break due in \(Fmt.hm(s.continuousDrivingRemaining))",
                               detail: "Plan a \(Fmt.hm(max(s.breakNeeded, Limits.splitBreakSecond))) break."))
            }
            if s.breakRemaining > 0 {
                w.append(.init(severity: .info, family: .driversHours, title: "Break: \(Fmt.hm(s.breakRemaining)) to go",
                               detail: s.breakNeeded == Limits.splitBreakSecond
                                   ? "You've taken the 15 min first part. This 30 min part completes your break."
                                   : "A 45 min break resets your 4h30 driving. You can split it 15 + 30."))
            }
            if st.euDriving > s.dailyDrivingLimit + Limits.tolerance {
                w.append(.init(severity: .violation, family: .driversHours, title: "Daily driving limit exceeded",
                               detail: "Driven \(Fmt.hm(st.euDriving)) of \(Fmt.hm(s.dailyDrivingLimit))."))
            } else if s.currentKind == .drive && s.dailyDrivingRemaining <= soon {
                w.append(.init(severity: .caution, family: .driversHours, title: "Daily driving ends in \(Fmt.hm(s.dailyDrivingRemaining))",
                               detail: s.dailyDrivingLimit > Limits.dailyDriving
                                   ? "Includes a 10h extension (\(Limits.maxExtensionsPerWeek - s.extensionsUsed) left this week)."
                                   : "No 10h extensions left this week."))
            }
            if s.weeklyDrivingRemaining <= 0 {
                w.append(.init(severity: .violation, family: .driversHours, title: "Weekly / fortnightly driving used up",
                               detail: "Week \(Fmt.hm(s.weeklyDriving)) of 56h · fortnight \(Fmt.hm(s.weeklyDriving + s.previousWeekDriving)) of 90h."))
            } else if s.weeklyDrivingRemaining < .hours(9) {
                w.append(.init(severity: .info, family: .driversHours, title: "\(Fmt.hm(s.weeklyDrivingRemaining)) driving left this week",
                               detail: "Limited by the 56h weekly / 90h fortnightly rule."))
            }
            if let latest = s.restStartByLatest, !s.isOnDailyRest {
                if s.now > latest {
                    w.append(.init(severity: .violation, family: .driversHours, title: "Daily rest overdue",
                                   detail: "Your daily rest should have started by \(Fmt.time(latest))."))
                } else if latest.timeIntervalSince(s.now) <= .hours(1) {
                    w.append(.init(severity: .caution, family: .driversHours, title: "Start daily rest by \(Fmt.time(latest))",
                                   detail: "That's the latest start that still fits a 9h rest in your 24h period."))
                } else if let full = s.restStartByFull, s.now > full, full != latest {
                    w.append(.init(severity: .info, family: .driversHours, title: "Tonight's rest will be reduced",
                                   detail: "Too late for a full 11h rest inside 24h. You need at least 9h, starting by \(Fmt.time(latest))."))
                }
            }
            if let due = s.weeklyRestDueBy {
                if s.now > due {
                    w.append(.init(severity: .violation, family: .driversHours, title: "Weekly rest overdue",
                                   detail: "It should have started by \(Fmt.dayTime(due))."))
                } else if due.timeIntervalSince(s.now) <= .hours(24) {
                    w.append(.init(severity: .caution, family: .driversHours, title: "Weekly rest due by \(Fmt.dayTime(due))",
                                   detail: s.nextWeeklyMustBeRegular ? "This one must be a regular 45h rest." : "At least 24h (reduced) or 45h (regular)."))
                }
            }
            if s.compensationOwed > 0, let due = s.compensationDueBy {
                w.append(.init(severity: .info, family: .driversHours, title: "Owe \(Fmt.hm(s.compensationOwed)) weekly rest compensation",
                               detail: "Add it en bloc to a rest of 9h+ before \(Fmt.day(due))."))
            }
        }

        if config.applyWorkingTime {
            if working && st.wtdWorkSinceBreak >= Limits.wtdMaxWorkWithoutBreak - Limits.tolerance {
                w.append(.init(severity: .violation, family: .workingTime, title: "6h worked without a break",
                               detail: "Working time rules: take at least 30 min (in 15 min pieces) now."))
            } else if working && s.wtdWorkBeforeBreak <= soon {
                w.append(.init(severity: .caution, family: .workingTime, title: "Working-time break due in \(Fmt.hm(s.wtdWorkBeforeBreak))",
                               detail: "You can't work more than 6h without a break."))
            }
            if s.wtdBreakNeededToday > 0 && st.workingTime > Limits.wtdLongDayThreshold - .minutes(30) {
                w.append(.init(severity: .caution, family: .workingTime, title: "Need \(Fmt.hm(s.wtdBreakNeededToday)) more break today",
                               detail: "Over 9h of work needs 45 min of breaks in total."))
            }
            if let night = s.nightWorkRemaining {
                if night <= 0 {
                    w.append(.init(severity: .violation, family: .workingTime, title: "Night-work limit reached",
                                   detail: "Shifts that include 00:00–04:00 are limited to \(Fmt.hm(config.nightWorkLimit)) of work."))
                } else if night <= .hours(1) {
                    w.append(.init(severity: .caution, family: .workingTime, title: "\(Fmt.hm(night)) work left (night limit)",
                                   detail: "This shift includes night time, so working time is limited to \(Fmt.hm(config.nightWorkLimit))."))
                }
            }
            if s.weeklyWorkingTime >= Limits.wtdWeeklyMaximum - Limits.tolerance {
                w.append(.init(severity: .violation, family: .workingTime, title: "60h working week reached",
                               detail: "Worked \(Fmt.hm(s.weeklyWorkingTime)) this week."))
            } else if s.weeklyWorkingTime >= .hours(55) {
                w.append(.init(severity: .caution, family: .workingTime, title: "\(Fmt.hm(Limits.wtdWeeklyMaximum - s.weeklyWorkingTime)) work left this week",
                               detail: "Max 60h working time in a single week."))
            }
            if s.averageWeeks >= 4 && s.averageWeeklyWorkingTime > Limits.wtdWeeklyAverage {
                w.append(.init(severity: .caution, family: .workingTime, title: "Average week \(Fmt.hm(s.averageWeeklyWorkingTime))",
                               detail: "Over 48h average across the last \(s.averageWeeks) weeks."))
            }
        }

        if s.gbApplies {
            if st.allDriving > Limits.gbDailyDriving + Limits.tolerance || st.workingTime > Limits.gbDailyDuty + Limits.tolerance {
                w.append(.init(severity: .violation, family: .gbDomestic, title: "GB domestic limit exceeded",
                               detail: "Driving \(Fmt.hm(st.allDriving)) of 10h · duty \(Fmt.hm(st.workingTime)) of 11h."))
            } else if working && min(s.gbDrivingRemaining, s.gbDutyRemaining) <= soon {
                w.append(.init(severity: .caution, family: .gbDomestic, title: "GB domestic limit in \(Fmt.hm(min(s.gbDrivingRemaining, s.gbDutyRemaining)))",
                               detail: "Max 10h driving and 11h duty per working day."))
            }
        }

        return w.sorted { $0.severity > $1.severity }
    }
}
