import Foundation

/// Which country's (or region's) driving-hours rules you work under.
enum RuleRegion: String, Codable, CaseIterable, Identifiable {
    case uk, eu, aetr, usa, canada, australia, newZealand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uk: "United Kingdom"
        case .eu: "EU / EEA / Switzerland"
        case .aetr: "AETR countries"
        case .usa: "United States (FMCSA)"
        case .canada: "Canada (south of 60°)"
        case .australia: "Australia (NHVR standard hours)"
        case .newZealand: "New Zealand"
        }
    }

    var flag: String {
        switch self {
        case .uk: "🇬🇧"
        case .eu: "🇪🇺"
        case .aetr: "🌍"
        case .usa: "🇺🇸"
        case .canada: "🇨🇦"
        case .australia: "🇦🇺"
        case .newZealand: "🇳🇿"
        }
    }

    /// UK, EU and AETR use the tachograph rules engine (EC 561/2006 and equivalents).
    var isEuropean: Bool { self == .uk || self == .eu || self == .aetr }

    var lawName: String {
        switch self {
        case .uk: "Assimilated Regulation (EC) 561/2006, AETR, GB domestic rules; Road Transport (Working Time) Regulations 2005"
        case .eu: "Regulation (EC) 561/2006; Directive 2002/15/EC (road transport working time)"
        case .aetr: "AETR Agreement (European Agreement concerning the Work of Crews of Vehicles engaged in International Road Transport)"
        case .usa: "FMCSA Hours of Service, 49 CFR Part 395 (property-carrying)"
        case .canada: "Commercial Vehicle Drivers Hours of Service Regulations (SOR/2005-313), south of latitude 60°N"
        case .australia: "Heavy Vehicle National Law — Standard Hours (solo drivers, fatigue-regulated heavy vehicles)"
        case .newZealand: "Land Transport Rule: Work Time and Logbooks 2007"
        }
    }
}

/// One limit in the generic engine.
struct WorldLimit: Identifiable {
    let id = UUID()
    var title: String
    var used: TimeInterval
    var limit: TimeInterval
    var note: String
    /// Counts down while you drive (true) or while you work (false).
    var drivingOnly: Bool
    var remaining: TimeInterval { max(0, limit - used) }
    var exceeded: Bool { used > limit + 59 }
}

/// Live status for non-European rules.
struct WorldStatus {
    var region: RuleRegion
    var limits: [WorldLimit] = []
    var driveLeft: TimeInterval = 0
    var workLeft: TimeInterval = 0
    var driveReason = ""
    var workReason = ""
    var breakBy: Date?
    var breakLength: TimeInterval = 0
    var breakReason = ""
    /// Minimum rest to reset the day, and when the next shift could start if you stopped now.
    var dailyRest: TimeInterval = 0
    var nextStart: Date?
    var violations: [ComplianceIssue] = []
}

/// Hours engine for the USA, Canada, Australia and New Zealand.
/// POA (availability) counts as on-duty / work time in these countries.
enum WorldRules {
    private struct Span { var start: Date; var end: Date; var work: Bool; var drive: Bool; var duration: TimeInterval { end.timeIntervalSince(start) } }

    static func status(_ entries: [EntrySnapshot], now: Date, region: RuleRegion, usCycle70: Bool = true) -> WorldStatus {
        var spans: [Span] = Timeline.build(entries, now: now).map {
            Span(start: $0.start, end: $0.end, work: $0.kind != .rest, drive: $0.kind == .drive)
        }
        // Treat a still-open rest as continuing to now (Timeline already ends it at now).
        spans.sort { $0.start < $1.start }
        var s = WorldStatus(region: region)
        guard !spans.isEmpty else { return s }

        func lastRest(atLeast d: TimeInterval) -> Span? {
            // Merge consecutive rest spans.
            var merged: [Span] = []
            for sp in spans where !sp.work {
                if let last = merged.last, abs(last.end.timeIntervalSince(sp.start)) < 1 {
                    merged[merged.count - 1].end = sp.end
                } else {
                    merged.append(sp)
                }
            }
            return merged.last { $0.duration >= d }
        }
        func total(from: Date, to: Date = now, _ include: (Span) -> Bool) -> TimeInterval {
            spans.filter(include).reduce(0) { sum, sp in
                let a = max(sp.start, from), b = min(sp.end, to)
                return sum + max(0, b.timeIntervalSince(a))
            }
        }
        let current = spans.last!

        switch region {
        case .usa:
            let reset = lastRest(atLeast: .hours(10))
            let dutyStart = reset.map { $0.end } ?? spans.first!.start
            let drove = total(from: dutyStart) { $0.drive }
            let window = now.timeIntervalSince(dutyStart)
            // 30-min break after 8h of driving: any 30 consecutive minutes not driving.
            var nonDriving: [Span] = []
            for sp in spans where !sp.drive {
                if let last = nonDriving.last, abs(last.end.timeIntervalSince(sp.start)) < 1 { nonDriving[nonDriving.count - 1].end = sp.end } else { nonDriving.append(sp) }
            }
            let lastBreak = nonDriving.last { $0.duration >= .minutes(30) }?.end ?? dutyStart
            let droveSinceBreak = total(from: max(lastBreak, dutyStart)) { $0.drive }
            let cycleDays: Double = usCycle70 ? 8 : 7
            let cycleLimit: TimeInterval = usCycle70 ? .hours(70) : .hours(60)
            let restart = lastRest(atLeast: .hours(34))?.end ?? .distantPast
            let cycleFrom = max(now.addingTimeInterval(-cycleDays * 86_400), restart)
            let onDuty = total(from: cycleFrom) { $0.work }
            s.limits = [
                WorldLimit(title: "Driving (11h)", used: drove, limit: .hours(11), note: "After 10 consecutive hours off duty", drivingOnly: true),
                WorldLimit(title: "14-hour window", used: window, limit: .hours(14), note: "No driving after the 14th hour on duty", drivingOnly: false),
                WorldLimit(title: "Driving before 30-min break", used: droveSinceBreak, limit: .hours(8), note: "Any 30 consecutive minutes off driving", drivingOnly: true),
                WorldLimit(title: usCycle70 ? "70 hours / 8 days" : "60 hours / 7 days", used: onDuty, limit: cycleLimit, note: "34 hours off restarts the cycle", drivingOnly: false)
            ]
            s.driveLeft = min(s.limits[0].remaining, s.limits[1].remaining, s.limits[2].remaining, s.limits[3].remaining)
            s.workLeft = min(s.limits[1].remaining, s.limits[3].remaining)
            s.breakBy = now.addingTimeInterval(s.limits[2].remaining)
            s.breakLength = .minutes(30)
            s.breakReason = "8h driving"
            s.dailyRest = .hours(10)

        case .canada:
            let reset = lastRest(atLeast: .hours(8))
            let dutyStart = reset.map { $0.end } ?? spans.first!.start
            let drove = total(from: dutyStart) { $0.drive }
            let onDutyDay = total(from: dutyStart) { $0.work }
            let window = now.timeIntervalSince(dutyStart)
            let reset36 = lastRest(atLeast: .hours(36))?.end ?? .distantPast
            let cycle = total(from: max(now.addingTimeInterval(-7 * 86_400), reset36)) { $0.work }
            s.limits = [
                WorldLimit(title: "Driving (13h)", used: drove, limit: .hours(13), note: "After 8 consecutive hours off duty", drivingOnly: true),
                WorldLimit(title: "On duty (14h)", used: onDutyDay, limit: .hours(14), note: "Driving and other on-duty time", drivingOnly: false),
                WorldLimit(title: "16-hour window", used: window, limit: .hours(16), note: "No driving after 16 hours since the shift started", drivingOnly: false),
                WorldLimit(title: "Cycle 1: 70 hours / 7 days", used: cycle, limit: .hours(70), note: "36 hours off resets the cycle", drivingOnly: false)
            ]
            s.driveLeft = s.limits.map(\.remaining).min() ?? 0
            s.workLeft = min(s.limits[1].remaining, s.limits[2].remaining, s.limits[3].remaining)
            s.dailyRest = .hours(10)

        case .australia:
            // Rest counts only in blocks of 15 minutes or more; shorter rests count as work.
            let restBlocks = spans.filter { !$0.work && $0.duration >= .minutes(15) }
            func workIn(_ hours: Double) -> TimeInterval {
                let from = now.addingTimeInterval(-hours * 3600)
                let elapsed = now.timeIntervalSince(max(from, spans.first!.start))
                let rested = restBlocks.reduce(0.0) { sum, sp in sum + max(0, min(sp.end, now).timeIntervalSince(max(sp.start, from))) }
                return max(0, elapsed - rested)
            }
            s.limits = [
                WorldLimit(title: "5h15 work in any 5½ hours", used: workIn(5.5), limit: .minutes(315), note: "Needs 15 min rest", drivingOnly: false),
                WorldLimit(title: "7h30 work in any 8 hours", used: workIn(8), limit: .minutes(450), note: "Needs 30 min rest (15-min blocks)", drivingOnly: false),
                WorldLimit(title: "10h work in any 11 hours", used: workIn(11), limit: .hours(10), note: "Needs 60 min rest (15-min blocks)", drivingOnly: false),
                WorldLimit(title: "12h work in any 24 hours", used: workIn(24), limit: .hours(12), note: "Needs 7 hours continuous stationary rest", drivingOnly: false),
                WorldLimit(title: "72h work in any 7 days", used: workIn(168), limit: .hours(72), note: "Needs 24 hours continuous stationary rest", drivingOnly: false)
            ]
            let tightest = s.limits.min { $0.remaining < $1.remaining }!
            s.workLeft = tightest.remaining
            s.driveLeft = tightest.remaining
            s.breakBy = now.addingTimeInterval(s.limits[0].remaining)
            s.breakLength = .minutes(15)
            s.breakReason = "5½-hour"
            s.dailyRest = .hours(7)

        case .newZealand:
            var rests: [Span] = []
            for sp in spans where !sp.work {
                if let last = rests.last, abs(last.end.timeIntervalSince(sp.start)) < 1 { rests[rests.count - 1].end = sp.end } else { rests.append(sp) }
            }
            let since30 = rests.last { $0.duration >= .minutes(30) }?.end ?? spans.first!.start
            let since10h = rests.last { $0.duration >= .hours(10) }?.end ?? spans.first!.start
            let since24h = rests.last { $0.duration >= .hours(24) }?.end ?? spans.first!.start
            s.limits = [
                WorldLimit(title: "5½ hours continuous work", used: total(from: since30) { $0.work }, limit: .hours(5.5), note: "Then a 30-minute break", drivingOnly: false),
                WorldLimit(title: "13 hours work in a work day", used: total(from: since10h) { $0.work }, limit: .hours(13), note: "Then 10 hours continuous rest", drivingOnly: false),
                WorldLimit(title: "70 hours in a work period", used: total(from: since24h) { $0.work }, limit: .hours(70), note: "Then 24 hours continuous rest", drivingOnly: false)
            ]
            s.workLeft = s.limits.map(\.remaining).min() ?? 0
            s.driveLeft = s.workLeft
            s.breakBy = now.addingTimeInterval(s.limits[0].remaining)
            s.breakLength = .minutes(30)
            s.breakReason = "5½-hour"
            s.dailyRest = .hours(10)

        case .uk, .eu, .aetr:
            return s
        }

        if let tight = s.limits.min(by: { $0.remaining < $1.remaining }) {
            s.driveReason = tight.title
            s.workReason = (s.limits.filter { !$0.drivingOnly }.min { $0.remaining < $1.remaining })?.title ?? tight.title
        }
        s.nextStart = (current.work ? now : current.start).addingTimeInterval(s.dailyRest)
        for l in s.limits where l.exceeded {
            s.violations.append(ComplianceIssue(severity: .violation, family: .driversHours, title: "\(l.title) exceeded",
                                                detail: "\(Fmt.hm(l.used)) against a limit of \(Fmt.hm(l.limit)). \(l.note).", date: now))
        }
        return s
    }
}

/// Which rules each country uses (reference list for the rules matrix).
enum CountryRules {
    static let list: [(country: String, region: RuleRegion?)] = {
        let eu = ["Austria", "Belgium", "Bulgaria", "Croatia", "Cyprus", "Czechia", "Denmark", "Estonia", "Finland", "France", "Germany",
                  "Greece", "Hungary", "Iceland", "Ireland", "Italy", "Latvia", "Liechtenstein", "Lithuania", "Luxembourg", "Malta",
                  "Netherlands", "Norway", "Poland", "Portugal", "Romania", "Slovakia", "Slovenia", "Spain", "Sweden", "Switzerland"]
        let aetr = ["Albania", "Andorra", "Armenia", "Azerbaijan", "Belarus", "Bosnia and Herzegovina", "Georgia", "Kazakhstan", "Moldova",
                    "Monaco", "Montenegro", "North Macedonia", "Russia", "San Marino", "Serbia", "Turkey", "Turkmenistan", "Ukraine", "Uzbekistan"]
        let notYet = ["Brazil", "China", "India", "Japan", "Mexico", "Saudi Arabia", "South Africa", "United Arab Emirates"]
        var out: [(String, RuleRegion?)] = [("United Kingdom", .uk), ("United States", .usa), ("Canada", .canada),
                                            ("Australia", .australia), ("New Zealand", .newZealand)]
        out += eu.map { ($0, .eu) }
        out += aetr.map { ($0, .aetr) }
        out += notYet.map { ($0, nil) }
        return out.sorted { $0.0 < $1.0 }
    }()

    /// Key limits per rule set, for the matrix.
    static let columns = ["Daily driving", "Break", "Daily duty / window", "Daily rest", "Weekly / cycle"]
    static func row(_ r: RuleRegion) -> [String] {
        switch r {
        case .uk, .eu, .aetr: ["9h (10h twice a week)", "45 min after 4h30", "13h (15h with reduced rest)", "11h (9h ×3)", "56h week · 90h fortnight · 45h weekly rest"]
        case .usa: ["11h", "30 min after 8h driving", "14h window", "10h off", "60h/7 or 70h/8 days · 34h restart"]
        case .canada: ["13h", "—", "14h on duty · 16h window", "10h (8h in one block)", "70h/7 days · 36h reset"]
        case .australia: ["Work-based", "15 min in 5½h · 30 in 8h · 60 in 11h", "12h work in 24h", "7h stationary", "72h in 7 days · 24h rest"]
        case .newZealand: ["Work-based", "30 min after 5½h", "13h work", "10h", "70h · 24h rest"]
        }
    }
}
