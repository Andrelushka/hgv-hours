import Foundation

/// A warning or error about a planned shift.
struct PlanIssue: Identifiable, Hashable {
    enum Level { case error, warning, ok }
    let id = UUID()
    var level: Level
    var text: String
}

/// Checks a planned shift against the rest rules, using what's already recorded and other plans.
enum PlanCheck {
    static func check(start: Date, end: Date, excluding planID: UUID?, plans: [WorkPlan],
                      entries: [EntrySnapshot], settings: AppSettings, now: Date = .now) -> [PlanIssue] {
        var issues: [PlanIssue] = []
        let length = end.timeIntervalSince(start)
        let status = RulesEngine.status(entries, now: now, config: settings.ruleConfig)
        let reducedLeft = max(0, Limits.maxReducedDailyRests - status.reducedRestsUsed)

        if end <= start {
            return [PlanIssue(level: .error, text: "The finish time must be after the start time.")]
        }

        // Shift length (spread-over): 13h with an 11h rest, 15h max with a 9h reduced rest.
        if length > 15 * 3600 {
            issues.append(PlanIssue(level: .error, text: "\(Fmt.hm(length)) is longer than the 15h maximum (24h minus a 9h reduced rest)."))
        } else if length > 13 * 3600 {
            issues.append(PlanIssue(level: reducedLeft > 0 ? .warning : .error,
                                    text: reducedLeft > 0
                                        ? "\(Fmt.hm(length)) day: needs a 9h reduced rest after it (\(reducedLeft) of 3 left)."
                                        : "\(Fmt.hm(length)) day needs a 9h reduced rest, but none are left before your weekly rest. Keep it to 13h."))
        }

        // Rest before: last recorded shift or the previous plan.
        let analysis = RulesEngine.analyze(entries, now: now, config: settings.ruleConfig)
        var previousEnd: Date?
        var previousLabel = ""
        if let last = analysis.shifts.last(where: { $0.period.start < start }) {
            let lastEnd = last.period.isOpen ? max(now, last.period.end) : last.period.end
            previousEnd = lastEnd
            previousLabel = last.period.isOpen ? "your current shift (if you finished now)" : "your shift on \(Fmt.day(last.period.start))"
        }
        let others = plans.filter { $0.id != planID }
        if let prevPlan = others.filter({ $0.plannedEnd <= start.addingTimeInterval(1) && $0.plannedStart < start })
            .max(by: { $0.plannedEnd < $1.plannedEnd }), prevPlan.plannedEnd > (previousEnd ?? .distantPast) {
            previousEnd = prevPlan.plannedEnd
            previousLabel = "the planned shift on \(Fmt.day(prevPlan.plannedStart))"
        }
        if let previousEnd {
            let gap = start.timeIntervalSince(previousEnd)
            issues.append(contentsOf: restIssues(gap: gap, label: "before", other: previousLabel, earliest: previousEnd, reducedLeft: reducedLeft))
        }

        // Rest after: the next plan.
        if let next = others.filter({ $0.plannedStart >= end.addingTimeInterval(-1) || ($0.plannedStart > start && $0.plannedStart < end) })
            .min(by: { $0.plannedStart < $1.plannedStart }) {
            if next.plannedStart < end {
                issues.append(PlanIssue(level: .error, text: "Overlaps the planned shift on \(Fmt.day(next.plannedStart)) at \(Fmt.time(next.plannedStart))."))
            } else {
                let gap = next.plannedStart.timeIntervalSince(end)
                issues.append(contentsOf: restIssues(gap: gap, label: "after", other: "the planned shift on \(Fmt.day(next.plannedStart))",
                                                     earliest: end, reducedLeft: reducedLeft))
            }
        }

        // Weekly rest.
        if let due = status.weeklyRestDueBy, end > due {
            issues.append(PlanIssue(level: .warning, text: "Your weekly rest must start by \(Fmt.dayTime(due)). This shift finishes after that."))
        }

        if !issues.contains(where: { $0.level != .ok }) {
            issues.append(PlanIssue(level: .ok, text: "Enough rest before and after. Start daily rest by \(Fmt.time(start.addingTimeInterval(13 * 3600))) for a normal 13h day."))
        }
        return issues
    }

    private static func restIssues(gap: TimeInterval, label: String, other: String, earliest: Date, reducedLeft: Int) -> [PlanIssue] {
        if gap < 0 {
            return [PlanIssue(level: .error, text: "Overlaps \(other).")]
        }
        if gap < Limits.reducedDailyRest {
            let ok = earliest.addingTimeInterval(label == "before" ? Limits.reducedDailyRest : 0)
            let hint = label == "before"
                ? " Earliest start: \(Fmt.dayTime(ok)) (9h) or \(Fmt.dayTime(earliest.addingTimeInterval(Limits.regularDailyRest))) (11h)."
                : ""
            return [PlanIssue(level: .error, text: "Only \(Fmt.hm(gap)) rest \(label) \(other) — the minimum is 9h.\(hint)")]
        }
        if gap < Limits.regularDailyRest {
            return [PlanIssue(level: reducedLeft > 0 ? .warning : .error,
                              text: reducedLeft > 0
                                ? "\(Fmt.hm(gap)) rest \(label) \(other): counts as a 9h reduced rest (\(reducedLeft) of 3 left)."
                                : "\(Fmt.hm(gap)) rest \(label) \(other), but no reduced rests are left — you need 11h.")]
        }
        return []
    }
}
