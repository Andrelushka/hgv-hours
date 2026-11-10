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

        // Driving
        d.driveLeft = s.driveAvailableNow
        d.breakDueIn = settings.applyWorkingTime ? min(s.continuousDrivingRemaining, s.wtdWorkBeforeBreak) : s.continuousDrivingRemaining
        var driveReasons: [String] = []
        if s.driveAvailableNow < s.driveAvailableBeforeWorkingTime - 1 { driveReasons.append("working-time break (6h rule)") }
        if s.driveAvailableNow == s.continuousDrivingRemaining { driveReasons.append("45 min break due") }
        if s.driveAvailableNow == s.dailyDrivingRemaining { driveReasons.append("daily driving limit") }
        if s.driveAvailableNow == s.weeklyDrivingRemaining { driveReasons.append("weekly driving limit") }
        if s.gbApplies && s.driveAvailableNow == min(s.gbDrivingRemaining, s.gbDutyRemaining) { driveReasons.append("GB domestic limit") }
        d.driveLeftReason = s.breakRemaining > 0 ? "Take your break first" : (driveReasons.first.map { "Then: \($0)" } ?? "")

        // Working time: the tightest working-time limit.
        var work: [(TimeInterval, String)] = []
        if settings.applyWorkingTime {
            work.append((s.wtdWorkBeforeBreak, "working-time break due"))
            work.append((max(0, Limits.wtdWeeklyMaximum - s.weeklyWorkingTime), "60h weekly limit"))
            if let night = s.nightWorkRemaining { work.append((night, "night-shift limit")) }
        }
        if s.gbApplies { work.append((s.gbDutyRemaining, "GB 11h duty limit")) }
        if let tightest = work.min(by: { $0.0 < $1.0 }) {
            d.workLeft = tightest.0
            d.workLeftReason = tightest.1
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
