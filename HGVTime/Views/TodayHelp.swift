import SwiftUI

/// Builds the help messages shown on Today when a button is pressed, and the "Next" hint.
enum TodayHelp {

    /// Message after switching to `kind`. `s` is the status just before the switch.
    static func afterSwitch(to kind: DutyKind, status s: ComplianceStatus, settings: AppSettings, now: Date = .now) -> HelpMessage {
        let tenLeft = max(0, Limits.maxExtensionsPerWeek - s.extensionsUsed)
        switch kind {
        case .drive:
            let canDrive = s.driveAvailableNow
            var lines: [String] = []
            if s.breakRemaining > 0 {
                // Stopping a break early is allowed; it just doesn't reset the 4h30.
                if s.continuousDrivingRemaining <= 0 {
                    lines.append("Your break isn't finished (\(Fmt.hm(s.breakRemaining)) to go) and you've used your 4h30 — you can't drive yet without an infringement.")
                } else {
                    let firstPart = s.currentRestLength >= Limits.splitBreakFirst - 1 && !s.splitFirstPartTaken
                    lines.append(firstPart
                        ? "Break stopped after \(Fmt.hm(s.currentRestLength)): it counts as the 15 min first part of a split break. Your next break only needs 30 min."
                        : "Break stopped early (\(Fmt.hm(s.currentRestLength))), so it doesn't reset your 4h30. That's allowed — just take the full break before the 4h30 runs out.")
                    lines.append("You can drive \(Fmt.hm(canDrive)) before a break — until about \(Fmt.time(now.addingTimeInterval(canDrive))).")
                }
            } else {
                lines.append("You can drive \(Fmt.hm(canDrive)) before your next break — until about \(Fmt.time(now.addingTimeInterval(canDrive))).")
                if let plan = Deadlines.breakPlan(s, applyWorkingTime: settings.applyWorkingTime) {
                    lines.append("Next break: \(Fmt.hm(plan.recommended)) by \(Fmt.time(now.addingTimeInterval(plan.dueBy.timeIntervalSince(s.now)))) (\(plan.reason) rule).")
                } else {
                    lines.append("Then take a 45 min break (or 15 min + 30 min, in that order).")
                }
            }
            if settings.applyWorkingTime && s.wtdWorkBeforeBreak < s.continuousDrivingRemaining && s.continuousDrivingRemaining > 0 {
                lines.append("Working time comes first: driving counts as work, and you can't work more than 6h without a break (\(Fmt.hm(s.wtdWorkBeforeBreak)) left).")
            }
            lines.append("Driving left today: \(Fmt.hm(s.drivingLeftToday)) (\(Fmt.hm(s.stats.euDriving)) of \(Fmt.hm(s.dailyDrivingLimit)) driven). 10h days left this week: \(tenLeft) of 2.")
            return HelpMessage(symbol: "steeringwheel", color: .blue, title: "Driving", lines: lines)

        case .otherWork:
            var lines = ["Loading, unloading, checks, cleaning, paperwork. Counts as working time, not driving."]
            if settings.applyWorkingTime {
                lines.append("You can work \(Fmt.hm(s.wtdWorkBeforeBreak)) more before a working-time break — by \(Fmt.time(now.addingTimeInterval(s.wtdWorkBeforeBreak))) (no more than 6h in a row).")
                lines.append("Breaks needed today: 30 min if you work 6–9h, 45 min over 9h, in pieces of 15 min or more.")
            }
            return HelpMessage(symbol: "hammer.fill", color: .orange, title: "Other work", lines: lines)

        case .availability:
            return HelpMessage(symbol: "hourglass", color: .purple, title: "POA (period of availability)", lines: [
                "Waiting time when you know how long the wait is in advance, e.g. waiting to be tipped, or double-manned in the passenger seat.",
                "Not working time and not a break. It still counts towards your shift length.",
                s.restStartByLatest.map { "Start daily rest by \(Fmt.time($0))." } ?? ""
            ].filter { !$0.isEmpty })

        case .rest:
            var lines: [String] = []
            if s.stats.continuousDriving <= 0 {
                lines.append("No driving since your last full break, so this break isn't needed for the 4h30 rule — you have a fresh 4h30.")
            } else if s.splitFirstPartTaken {
                lines.append("SPLIT BREAK, part 2: you've already had 15 min. Take at least 30 min — done at \(Fmt.time(now.addingTimeInterval(Limits.splitBreakSecond))) — and your 4h30 resets.")
                lines.append("Shorter is allowed, but then the 4h30 doesn't reset: you'll still need the 30 min before \(Fmt.hm(s.continuousDrivingRemaining)) more driving.")
            } else {
                lines.append("FULL BREAK: 45 min — done at \(Fmt.time(now.addingTimeInterval(Limits.fullBreak))). Resets your 4h30.")
                lines.append("SPLIT BREAK: stop after at least 15 min (\(Fmt.time(now.addingTimeInterval(Limits.splitBreakFirst)))) and this counts as part 1. Then take 30 min later, before \(Fmt.hm(s.continuousDrivingRemaining)) more driving.")
                lines.append("Under 15 min doesn't count as a break.")
            }
            if settings.applyWorkingTime && s.wtdBreakNeededToday > 0 {
                lines.append("Working time: you still need \(Fmt.hm(s.wtdBreakNeededToday)) of breaks today (in pieces of 15 min or more).")
            }
            return HelpMessage(symbol: "cup.and.saucer.fill", color: .green, title: "Break", lines: lines)
        }
    }

    static func afterStartShift(status s: ComplianceStatus, settings: AppSettings, now: Date = .now) -> HelpMessage {
        let reducedLeft = max(0, Limits.maxReducedDailyRests - s.reducedRestsUsed)
        var lines = [
            "Shift started at \(Fmt.time(now)) with \(settings.shiftStartKind.title.lowercased()).",
            "Normal day (13h, then 11h rest): start rest by \(Fmt.time(now.addingTimeInterval(13 * 3600))).",
            reducedLeft > 0
                ? "Longest day (15h, then 9h reduced rest): by \(Fmt.time(now.addingTimeInterval(15 * 3600))). 15h days left: \(reducedLeft) of 3."
                : "No 15h days left — you need a full 11h rest tonight."
        ]
        if let due = s.weeklyRestDueBy { lines.append("Weekly rest must start by \(Fmt.dayTime(due)).") }
        return HelpMessage(symbol: "play.circle.fill", color: .green, title: "Shift started", lines: lines)
    }

    static func afterEndShift(_ type: RestType, status s: ComplianceStatus, now: Date = .now) -> HelpMessage {
        let reducedLeft = max(0, Limits.maxReducedDailyRests - s.reducedRestsUsed)
        if type == .weekly {
            return HelpMessage(symbol: "house.fill", color: .indigo, title: "Weekly rest started", lines: [
                "Regular weekly rest (45h) complete at \(Fmt.dayTime(now.addingTimeInterval(Limits.regularWeeklyRest))).",
                "Reduced weekly rest (24h) at \(Fmt.dayTime(now.addingTimeInterval(Limits.reducedWeeklyRest))) — the missing hours must be paid back within 3 weeks.",
                "Your 10h driving days and 9h reduced rests reset after weekly rest."
            ])
        }
        return HelpMessage(symbol: "moon.zzz.fill", color: .teal, title: "Daily rest started", lines: [
            "Regular daily rest (11h) complete at \(Fmt.time(now.addingTimeInterval(Limits.regularDailyRest))) — you can start work from then.",
            reducedLeft > 0
                ? "Reduced (9h) at \(Fmt.time(now.addingTimeInterval(Limits.reducedDailyRest))). Reduced rests left: \(reducedLeft) of 3."
                : "No reduced rests left — take the full 11h.",
            "Or split: 3h now and 9h later (12h in total)."
        ])
    }

    static func inCab(on: Bool, settings: AppSettings) -> HelpMessage {
        on
            ? HelpMessage(symbol: "box.truck.fill", color: .blue, title: "In cab — automatic", lines: [
                "When the vehicle moves above \(Int(settings.autoMovingSpeedKmh)) km/h for 8 seconds, Driving is recorded.",
                "When it's stopped for \(settings.autoStopDelaySeconds >= 60 ? "\(settings.autoStopDelaySeconds / 60) min" : "\(settings.autoStopDelaySeconds) s"), \(settings.autoStoppedKind == .rest ? "Break" : settings.autoStoppedKind.title) is recorded from the moment it stopped.",
                "Carrying or shaking the phone does nothing — it uses GPS speed and the motion sensor. Allow location “Always” so it works with the phone locked.",
                "You can still press Break or POA yourself while stopped."
            ])
            : HelpMessage(symbol: "figure.walk", color: .gray, title: "Walking — manual", lines: [
                "Nothing is recorded automatically. Press the buttons as you change activity, like the tacho mode switch."
            ])
    }

    /// A one-line "what's next" for the status card.
    static func next(status s: ComplianceStatus, openEntry: ActivityEntry?) -> String? {
        guard s.hasData, let open = openEntry else { return nil }
        let now = s.now
        if open.endsShift {
            let rest = s.currentRestLength
            if open.restType == .weekly {
                return rest < Limits.reducedWeeklyRest
                    ? "Next: 24h at \(Fmt.dayTime(s.currentSince.addingTimeInterval(Limits.reducedWeeklyRest))) · 45h at \(Fmt.dayTime(s.currentSince.addingTimeInterval(Limits.regularWeeklyRest)))"
                    : "Next: 45h regular weekly rest at \(Fmt.dayTime(s.currentSince.addingTimeInterval(Limits.regularWeeklyRest)))"
            }
            if rest < Limits.reducedDailyRest {
                return "Next shift from: 9h at \(Fmt.time(s.currentSince.addingTimeInterval(Limits.reducedDailyRest))) · 11h at \(Fmt.time(s.currentSince.addingTimeInterval(Limits.regularDailyRest)))"
            }
            return rest < Limits.regularDailyRest
                ? "Next: full 11h rest at \(Fmt.time(s.currentSince.addingTimeInterval(Limits.regularDailyRest))) — you can already start (9h done)"
                : "Rest complete — you can start your shift"
        }
        switch open.kind {
        case .drive, .otherWork:
            if let plan = Deadlines.breakPlan(s, applyWorkingTime: true) {
                return "Next: \(Fmt.hm(plan.recommended)) break by \(Fmt.time(plan.dueBy)) (in \(Fmt.hm(plan.dueBy.timeIntervalSince(now))), \(plan.reason))"
            }
            return nil
        case .rest:
            if let reset = s.breakResetAt, reset > now {
                if let split = s.breakSplitPartAt, split > now {
                    return "Split part 1 at \(Fmt.time(split)) · full 45 min break at \(Fmt.time(reset))"
                }
                return s.splitFirstPartTaken
                    ? "Split break: 30 min done at \(Fmt.time(reset)) (\(Fmt.hm(reset.timeIntervalSince(now))) to go)"
                    : "15 min part done — stop now (30 min needed later) or carry on to \(Fmt.time(reset)) for a full reset"
            }
            return "Break complete — 4h30 driving available"
        case .availability:
            return s.restStartByLatest.map { "Start daily rest by \(Fmt.time($0))" }
        }
    }
}
