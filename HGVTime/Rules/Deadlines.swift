import Foundation

/// One upcoming deadline with an estimated clock time.
struct Deadline: Identifiable {
    enum Kind { case drivingBreak, workingBreak, dailyDriving, weeklyDriving, weeklyWorking, nightWork, gbDuty, startRest, weeklyRest, nextStart }
    let id = UUID()
    var kind: Kind
    var title: String
    var time: Date
    /// e.g. "if you keep driving" / "after 2h10 more work".
    var condition: String
    var symbol: String
    var urgent: Bool
}

/// The next break that satisfies both the drivers' hours (EU/AETR) and working-time rules.
struct BreakPlan {
    /// When the next break must start at the latest, if you keep going.
    var dueBy: Date
    /// Which rule makes it due.
    var reason: String
    /// Shortest break that's legal at that point.
    var minimum: TimeInterval
    /// Break length that covers both rules (driving break and today's working-time breaks).
    var recommended: TimeInterval
    var lines: [String]
}

enum Deadlines {

    /// Combined break advice. `nil` when not on a shift.
    static func breakPlan(_ s: ComplianceStatus, applyWorkingTime: Bool) -> BreakPlan? {
        guard s.currentShift != nil else { return nil }
        let now = s.now
        let driving = s.currentKind == .drive
        let working = s.currentKind == .drive || s.currentKind == .otherWork

        // Driving break: needed after 4h30 of driving. Working-time break: after 6h of work.
        let drivingNeed = s.breakNeeded > 0 ? s.breakNeeded : Limits.fullBreak
        let driveDue = s.continuousDrivingRemaining
        let workDue = applyWorkingTime ? s.wtdWorkBeforeBreak : .infinity
        // Working-time breaks still needed today: 30 min (6–9h work) or 45 min (over 9h), in pieces of 15+.
        let projectedWork = s.stats.workingTime + min(workDue, .hours(6))
        let wtdTotalNeed: TimeInterval = applyWorkingTime
            // At the break you've reached `projectedWork`; carrying on afterwards takes the day past it.
            ? (projectedWork >= Limits.wtdLongDayThreshold ? Limits.wtdBreakLongDay : (projectedWork >= Limits.wtdMaxWorkWithoutBreak ? Limits.wtdBreakShortDay : 0))
            : 0
        let wtdStillNeed = max(0, wtdTotalNeed - s.stats.wtdBreakTotal, s.wtdBreakNeededToday)

        var lines: [String] = []
        let dueIn: TimeInterval
        let reason: String
        var minimum: TimeInterval
        if driveDue <= workDue {
            dueIn = driveDue
            reason = "4h30 driving"
            minimum = drivingNeed
            lines.append(drivingNeed == Limits.splitBreakSecond
                ? "You've had 15 min, so 30 min completes your driving break."
                : "Driving needs a 45 min break (or 15 min, then 30 min later).")
        } else {
            dueIn = workDue
            reason = "6h working time"
            minimum = Limits.wtdBreakPiece
            lines.append("Working time: you can't work more than 6h in a row. A break of at least 15 min resets it.")
        }
        if applyWorkingTime && wtdStillNeed > 0 {
            lines.append("Working-time breaks still needed today: \(Fmt.hm(wtdStillNeed)) (30 min if you work 6–9h, 45 min over 9h, in pieces of 15 min or more).")
        }
        // A driving break also counts as a working-time break, so one break can cover both.
        let recommended = reason == "4h30 driving" ? max(drivingNeed, wtdStillNeed) : max(Limits.wtdBreakPiece, wtdStillNeed)
        if recommended > minimum {
            lines.append("Take \(Fmt.hm(recommended)) to cover both rules in one go.")
        }
        if reason == "6h working time" && s.stats.continuousDriving > 0 && drivingNeed > recommended {
            lines.append("Taking \(Fmt.hm(drivingNeed)) instead also resets your 4h30 driving.")
        }
        let dueBy: Date
        if (reason == "4h30 driving" && driving) || (reason == "6h working time" && working) {
            dueBy = now.addingTimeInterval(dueIn)
        } else {
            dueBy = now.addingTimeInterval(dueIn) // estimate if you start again now
            lines.append("Estimated as if you \(reason.hasPrefix("4h30") ? "drive" : "work") from now.")
        }
        return BreakPlan(dueBy: dueBy, reason: reason, minimum: minimum, recommended: recommended, lines: lines)
    }

    /// Every upcoming limit with an estimated time, soonest first.
    static func all(_ s: ComplianceStatus, applyWorkingTime: Bool) -> [Deadline] {
        let now = s.now
        var list: [Deadline] = []
        let onShift = s.currentShift != nil
        let driving = s.currentKind == .drive && onShift
        let working = (s.currentKind == .drive || s.currentKind == .otherWork) && onShift

        func cond(_ active: Bool, _ verb: String, _ left: TimeInterval) -> String {
            active ? "if you keep \(verb)" : "after \(Fmt.hm(left)) more \(verb == "driving" ? "driving" : "work")"
        }

        if onShift {
            list.append(Deadline(kind: .drivingBreak, title: "45 min driving break", time: now.addingTimeInterval(s.continuousDrivingRemaining),
                                 condition: cond(driving, "driving", s.continuousDrivingRemaining), symbol: "cup.and.saucer.fill",
                                 urgent: s.continuousDrivingRemaining < 1800))
            if applyWorkingTime {
                list.append(Deadline(kind: .workingBreak, title: "Working-time break (15 min+)", time: now.addingTimeInterval(s.wtdWorkBeforeBreak),
                                     condition: cond(working, "working", s.wtdWorkBeforeBreak), symbol: "figure.walk",
                                     urgent: s.wtdWorkBeforeBreak < 1800))
            }
            list.append(Deadline(kind: .dailyDriving, title: "Daily driving \(Fmt.hm(s.dailyDrivingLimit)) reached",
                                 time: now.addingTimeInterval(s.dailyDrivingRemaining),
                                 condition: "after \(Fmt.hm(s.dailyDrivingRemaining)) more driving", symbol: "sun.max.fill",
                                 urgent: s.dailyDrivingRemaining < 1800))
            if s.weeklyDrivingRemaining < .hours(15) {
                list.append(Deadline(kind: .weeklyDriving, title: "Weekly / fortnight driving limit", time: now.addingTimeInterval(s.weeklyDrivingRemaining),
                                     condition: "after \(Fmt.hm(s.weeklyDrivingRemaining)) more driving", symbol: "calendar", urgent: s.weeklyDrivingRemaining < 3600))
            }
            if applyWorkingTime {
                let weekLeft = max(0, Limits.wtdWeeklyMaximum - s.weeklyWorkingTime)
                if weekLeft < .hours(15) {
                    list.append(Deadline(kind: .weeklyWorking, title: "60h working week", time: now.addingTimeInterval(weekLeft),
                                         condition: cond(working, "working", weekLeft), symbol: "briefcase.fill", urgent: weekLeft < 3600))
                }
                if let night = s.nightWorkRemaining {
                    list.append(Deadline(kind: .nightWork, title: "Night-shift working limit", time: now.addingTimeInterval(night),
                                         condition: cond(working, "working", night), symbol: "moon.stars.fill", urgent: night < 3600))
                }
            }
            if s.gbApplies {
                list.append(Deadline(kind: .gbDuty, title: "GB 11h duty limit", time: now.addingTimeInterval(s.gbDutyRemaining),
                                     condition: cond(working, "working", s.gbDutyRemaining), symbol: "clock.fill", urgent: s.gbDutyRemaining < 1800))
            }
            if let full = s.restStartByFull {
                list.append(Deadline(kind: .startRest, title: "Start 11h daily rest by", time: full, condition: "13h day", symbol: "moon.zzz.fill",
                                     urgent: full.timeIntervalSince(now) < 3600))
            }
            if let latest = s.restStartByLatest, latest != s.restStartByFull {
                list.append(Deadline(kind: .startRest, title: "Latest: 9h reduced rest by", time: latest, condition: "15h day", symbol: "moon.haze.fill",
                                     urgent: latest.timeIntervalSince(now) < 3600))
            }
        }
        if let due = s.weeklyRestDueBy {
            list.append(Deadline(kind: .weeklyRest, title: s.nextWeeklyMustBeRegular ? "Start 45h weekly rest by" : "Start weekly rest by",
                                 time: due, condition: s.nextWeeklyMustBeRegular ? "must be a regular 45h rest" : "24h reduced or 45h regular",
                                 symbol: "house.fill", urgent: due.timeIntervalSince(now) < .hours(12)))
        }
        if let next = nextStart(s) {
            list.append(Deadline(kind: .nextStart, title: "Next shift can start", time: next.time, condition: next.note,
                                 symbol: "play.circle", urgent: false))
        }
        return list.sorted { $0.time < $1.time }
    }

    /// Earliest time the next shift can start, given the rest you're on (or would start now).
    static func nextStart(_ s: ComplianceStatus) -> (time: Date, note: String)? {
        let reducedLeft = max(0, Limits.maxReducedDailyRests - s.reducedRestsUsed)
        if s.currentShift != nil {
            let full = s.now.addingTimeInterval(Limits.regularDailyRest)
            if reducedLeft > 0 {
                return (s.now.addingTimeInterval(Limits.reducedDailyRest), "if you stop now: 9h reduced rest (11h → \(Fmt.time(full)))")
            }
            return (full, "if you stop now: 11h rest")
        }
        guard s.hasData, s.currentKind == .rest else { return nil }
        let since = s.currentSince
        if s.currentRestLength >= Limits.reducedWeeklyRest {
            return (since.addingTimeInterval(Limits.regularWeeklyRest), "after a regular 45h weekly rest (24h reduced: \(Fmt.dayTime(since.addingTimeInterval(Limits.reducedWeeklyRest))))")
        }
        if reducedLeft > 0 {
            return (since.addingTimeInterval(Limits.reducedDailyRest), "9h reduced rest · 11h at \(Fmt.time(since.addingTimeInterval(Limits.regularDailyRest)))")
        }
        return (since.addingTimeInterval(Limits.regularDailyRest), "11h daily rest (no reduced rests left)")
    }
}
