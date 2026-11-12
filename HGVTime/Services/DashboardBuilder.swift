import Foundation

extension Dashboard {
    /// Builds the headline numbers from the rules engine status.
    @MainActor static func make(status s: ComplianceStatus, settings: AppSettings, openEntry: ActivityEntry?) -> Dashboard {
        var d = Dashboard()
        d.generatedAt = s.now
        d.hasData = s.hasData
        d.onShift = openEntry.map { !$0.endsShift } ?? false
        d.kind = s.hasData ? s.currentKind : .rest
        d.restTypeRaw = openEntry?.restType?.rawValue ?? ""
        d.since = s.hasData ? s.currentSince : s.now
        d.autoDetect = settings.autoDetectEnabled

        // Driving left = what's left of today's driving (daily, weekly, GB limits). The break clocks are shown
        // separately ("Break due in"), so this doesn't drop to zero during a break.
        d.driveLeft = s.drivingLeftToday
        d.breakDueIn = settings.applyWorkingTime ? min(s.continuousDrivingRemaining, s.wtdWorkBeforeBreak) : s.continuousDrivingRemaining
        if s.currentKind == .rest, let reset = s.breakResetAt, reset > s.now {
            if let split = s.breakSplitPartAt, split > s.now {
                d.driveLeftReason = "On break: 15 min split part at \(Fmt.time(split)), full 45 min at \(Fmt.time(reset))"
            } else {
                d.driveLeftReason = s.splitFirstPartTaken
                    ? "On break: 30 min completes your split at \(Fmt.time(reset))"
                    : "On break: 15 min part done — full reset at \(Fmt.time(reset))"
            }
        } else if s.drivingLeftToday <= 0 {
            d.driveLeftReason = s.weeklyDrivingRemaining <= 0 ? "Weekly / fortnightly driving used up" : "Daily driving used up"
        } else {
            let breakIn = s.continuousDrivingRemaining
            var reason = breakIn <= 0
                ? "Take a \(Fmt.hm(s.breakNeeded > 0 ? s.breakNeeded : Limits.fullBreak)) break before driving more"
                : "Break due after \(Fmt.hm(breakIn)) more driving"
            if settings.applyWorkingTime && s.wtdWorkBeforeBreak < breakIn {
                reason = s.wtdWorkBeforeBreak <= 0 ? "Working-time break due now (6h rule)" : "Working-time break due in \(Fmt.hm(s.wtdWorkBeforeBreak)) (6h rule)"
            }
            d.driveLeftReason = reason
        }

        // Working left = working time left in this shift: until daily rest must start, capped by the 60h week,
        // the night-work limit and GB duty. The 6h-without-a-break clock is the "Break due" tile, not this.
        var work: [(TimeInterval, String)] = []
        if d.onShift, let latest = s.restStartByLatest {
            work.append((max(0, latest.timeIntervalSince(s.now)), "until daily rest by \(Fmt.time(latest))"))
        }
        if settings.applyWorkingTime {
            work.append((max(0, Limits.wtdWeeklyMaximum - s.weeklyWorkingTime), "60h weekly limit"))
            if let night = s.nightWorkRemaining { work.append((night, "night-shift limit")) }
        }
        if s.gbApplies { work.append((s.gbDutyRemaining, "GB 11h duty limit")) }
        if let tightest = work.min(by: { $0.0 < $1.0 }) {
            d.workLeft = tightest.0
            d.workLeftReason = tightest.1
            if settings.applyWorkingTime && d.onShift && s.wtdWorkBeforeBreak < tightest.0 {
                d.workLeftReason += " · break in \(Fmt.hm(s.wtdWorkBeforeBreak))"
            }
        } else {
            d.workLeft = max(0, Limits.wtdWeeklyMaximum - s.weeklyWorkingTime)
            d.workLeftReason = "Working time rules off"
        }

        d.restBy = d.onShift ? s.restStartByLatest : nil
        d.dailyDriving = s.stats.euDriving
        d.dailyDrivingLimit = s.dailyDrivingLimit
        d.weeklyDriving = s.weeklyDriving
        d.weeklyWorking = s.weeklyWorkingTime
        d.shiftWorking = s.stats.workingTime
        d.restLength = s.currentRestLength
        if let plan = Deadlines.breakPlan(s, applyWorkingTime: settings.applyWorkingTime) {
            d.breakBy = plan.dueBy
            d.breakLength = plan.recommended
            d.breakReason = plan.reason
        }
        d.nextStart = Deadlines.nextStart(s)?.time
        d.dailyRestRegularBy = d.onShift ? s.restStartByFull : nil
        d.weeklyRestBy = s.weeklyRestDueBy
        d.tenHourDaysLeft = max(0, Limits.maxExtensionsPerWeek - s.extensionsUsed)
        if !settings.region.isEuropean, let world = WorldRulesCache.status {
            d.driveLeft = world.driveLeft
            d.workLeft = world.workLeft
            d.breakDueIn = world.breakBy.map { $0.timeIntervalSince(s.now) } ?? world.driveLeft
            d.driveLeftReason = world.driveReason.isEmpty ? "" : "Then: \(world.driveReason)"
            d.workLeftReason = world.workReason
            d.breakBy = world.breakBy
            d.breakLength = world.breakLength
            d.breakReason = world.breakReason
            d.nextStart = world.nextStart
            d.restBy = nil
            d.dailyRestRegularBy = nil
        }
        d.reducedRestsLeft = max(0, Limits.maxReducedDailyRests - s.reducedRestsUsed)
        return d
    }
}

/// The latest non-European status, computed alongside the EU one.
@MainActor
enum WorldRulesCache {
    static var status: WorldStatus?

    /// Recomputes for the current snapshots (call before Dashboard.make on screens that tick).
    @discardableResult
    static func refresh(_ snaps: [EntrySnapshot], now: Date, settings: AppSettings) -> WorldStatus? {
        status = settings.region.isEuropean ? nil : WorldRules.status(snaps, now: now, region: settings.region, usCycle70: settings.usCycle70)
        return status
    }
}
