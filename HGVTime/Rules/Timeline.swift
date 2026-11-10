import Foundation

/// Value-type copy of an `ActivityEntry`, so the rules engine stays pure and testable.
struct EntrySnapshot: Equatable {
    var kind: DutyKind
    var regime: Regime
    var start: Date
    var end: Date?
    var multiManned: Bool = false
}

/// A clean, non-overlapping piece of the timeline.
struct Segment: Equatable {
    var kind: DutyKind
    var regime: Regime
    var start: Date
    var end: Date
    var multiManned: Bool

    var duration: TimeInterval { end.timeIntervalSince(start) }
    /// Working time under RT(WT)R / duty under GB rules: driving + other work.
    var isWork: Bool { kind == .drive || kind == .otherWork }

    func overlap(with start: Date, _ end: Date) -> TimeInterval {
        max(0, min(self.end, end).timeIntervalSince(max(self.start, start)))
    }
}

enum Timeline {
    /// Turns raw entries into a continuous, sorted timeline:
    /// - overlapping entries are clipped (a later entry wins),
    /// - the open entry runs until `now`,
    /// - gaps between entries count as rest,
    /// - consecutive rests are merged into one block.
    static func build(_ entries: [EntrySnapshot], now: Date) -> [Segment] {
        let sorted = entries.filter { $0.start < now }.sorted { $0.start < $1.start }
        var raw: [Segment] = []
        for (index, entry) in sorted.enumerated() {
            var end = min(entry.end ?? now, now)
            if index + 1 < sorted.count {
                end = min(end, sorted[index + 1].start)
            }
            guard end > entry.start else { continue }
            raw.append(Segment(kind: entry.kind, regime: entry.regime, start: entry.start, end: end, multiManned: entry.multiManned))
        }

        var result: [Segment] = []
        for segment in raw {
            if let last = result.last, segment.start > last.end {
                append(Segment(kind: .rest, regime: last.regime, start: last.end, end: segment.start, multiManned: false), to: &result)
            }
            append(segment, to: &result)
        }
        if let last = result.last, last.end < now {
            append(Segment(kind: .rest, regime: last.regime, start: last.end, end: now, multiManned: false), to: &result)
        }
        return result
    }

    private static func append(_ segment: Segment, to list: inout [Segment]) {
        if segment.kind == .rest, let last = list.last, last.kind == .rest, last.end >= segment.start {
            list[list.count - 1].end = max(last.end, segment.end)
        } else {
            list.append(segment)
        }
    }

    /// Splits the timeline into duty periods ("shifts") separated by rests of 9 hours or more.
    static func dutyPeriods(from segments: [Segment]) -> [DutyPeriod] {
        var periods: [DutyPeriod] = []
        var current: [Segment] = []
        var restBefore: Segment?
        for segment in segments {
            if segment.kind == .rest && segment.duration >= Limits.reducedDailyRest {
                if !current.isEmpty {
                    periods.append(DutyPeriod(segments: current, restBefore: restBefore, restAfter: segment))
                }
                current = []
                restBefore = segment
            } else {
                if current.isEmpty && segment.kind == .rest { continue }
                current.append(segment)
            }
        }
        if !current.isEmpty {
            periods.append(DutyPeriod(segments: current, restBefore: restBefore, restAfter: nil))
        }
        return periods
    }
}

/// Everything between two daily (or weekly) rests.
struct DutyPeriod: Identifiable, Equatable {
    var segments: [Segment]
    var restBefore: Segment?
    /// The rest (≥ 9h) that closed this period. `nil` while the shift is still open.
    var restAfter: Segment?

    var id: Date { start }
    /// Start of the first activity (= end of the previous daily rest).
    var start: Date { segments.first?.start ?? .distantPast }
    /// End of the last activity that isn't rest.
    var end: Date { segments.last(where: { $0.kind != .rest })?.end ?? start }
    var isOpen: Bool { restAfter == nil }
    var multiManned: Bool { segments.contains { $0.multiManned } }
}
