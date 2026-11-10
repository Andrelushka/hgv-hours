import SwiftUI

/// The next break that satisfies both driving and working-time rules.
struct BreakPlanCard: View {
    var plan: BreakPlan
    var now: Date

    var body: some View {
        let left = plan.dueBy.timeIntervalSince(now)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Take").font(.caption).foregroundStyle(.secondary)
                    Text(Fmt.hm(plan.recommended)).font(.title.weight(.bold).monospacedDigit()).foregroundStyle(.green)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("by").font(.caption).foregroundStyle(.secondary)
                    Text(Fmt.time(plan.dueBy)).font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(left < 900 ? .red : (left < 1800 ? .orange : .primary))
                }
            }
            Text("In \(Fmt.hm(left)) · \(plan.reason) rule · minimum \(Fmt.hm(plan.minimum))")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(plan.lines, id: \.self) { line in
                Label(line, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Estimated clock time for every upcoming limit.
struct DeadlineList: View {
    var deadlines: [Deadline]
    var now: Date

    var body: some View {
        VStack(spacing: 0) {
            ForEach(deadlines) { d in
                HStack(spacing: 10) {
                    Image(systemName: d.symbol)
                        .frame(width: 24)
                        .foregroundStyle(d.urgent ? .orange : .accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.title).font(.subheadline.weight(.semibold))
                        Text(d.condition).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Calendar.hgv.isDate(d.time, inSameDayAs: now) ? Fmt.time(d.time) : Fmt.dayTime(d.time))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(d.urgent ? .orange : .primary)
                        Text(d.time > now ? "in \(Fmt.hm(d.time.timeIntervalSince(now)))" : "now")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                if d.id != deadlines.last?.id { Divider() }
            }
        }
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Split break, split daily rest, weekly rest type and compensation.
struct RestRulesCard: View {
    var status: ComplianceStatus
    var allowConsecutiveReduced: Bool

    var body: some View {
        let s = status
        return VStack(alignment: .leading, spacing: 10) {
            rule("cup.and.saucer.fill", "Split break (15 + 30)",
                 s.stats.splitBreakFirstTaken ? "15 min taken — your next break only needs 30 min." : "Not started. A 15 min break now means only 30 min later.",
                 active: s.stats.splitBreakFirstTaken)
            rule("moon.haze.fill", "Split daily rest (3h + 9h)",
                 s.stats.splitRestFirstPartTaken ? "3h first part taken — finish with at least 9h rest (doesn't use a reduced rest)." : "Take 3h+ during the shift, then 9h at the end (12h total).",
                 active: s.stats.splitRestFirstPartTaken)
            if let last = s.lastWeeklyRest {
                let regular = last.duration >= Limits.regularWeeklyRest - Limits.tolerance
                rule("house.fill", "Last weekly rest",
                     "\(regular ? "Regular" : "Reduced") \(Fmt.hm(last.duration)), ended \(Fmt.dayTime(last.end)).",
                     active: false)
            }
            rule("house.lodge.fill", "Next weekly rest",
                 s.nextWeeklyMustBeRegular
                    ? "Must be a regular 45h rest\(allowConsecutiveReduced ? " (two reduced already taken)" : " (last one was reduced)")."
                    : "Can be reduced (24h) or regular (45h).\(allowConsecutiveReduced ? " International: two reduced in a row allowed outside the UK." : "")",
                 active: s.nextWeeklyMustBeRegular)
            if s.compensationOwed > 0, let due = s.compensationDueBy {
                rule("arrow.uturn.backward.circle.fill", "Compensation owed",
                     "\(Fmt.hm(s.compensationOwed)) — add it to a rest of 9h+ before \(Fmt.day(due)).", active: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func rule(_ symbol: String, _ title: String, _ detail: String, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(active ? .orange : .teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
