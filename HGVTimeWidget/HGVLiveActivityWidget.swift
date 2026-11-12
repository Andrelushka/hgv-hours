import ActivityKit
import SwiftUI
import WidgetKit

struct HGVLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HGVActivityAttributes.self) { context in
            Group {
                if context.state.navInstruction != nil {
                    NavLockScreenView(state: context.state)
                } else {
                    LockScreenView(state: context.state)
                }
            }
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(state.kind.shortTitle, systemImage: state.kind.symbol)
                        .font(.headline)
                        .foregroundStyle(state.kind.color)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.startedAt, style: .timer)
                        .font(.headline.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let instruction = state.navInstruction {
                        HStack {
                            Image(systemName: state.navSymbol ?? "arrow.up").font(.title2.weight(.bold))
                            VStack(alignment: .leading) {
                                Text(state.navDistance ?? "").font(.headline)
                                Text(instruction).font(.caption).lineLimit(1)
                            }
                            Spacer()
                        }
                    } else {
                        CountdownLine(state: state)
                    }
                }
            } compactLeading: {
                Image(systemName: state.navSymbol ?? state.kind.symbol)
                    .foregroundStyle(state.navSymbol == nil ? state.kind.color : .green)
            } compactTrailing: {
                Group {
                    if let target = state.targetDate {
                        Text(target, style: .timer)
                    } else {
                        Text(state.startedAt, style: .timer)
                    }
                }
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 52)
                .foregroundStyle(state.isWarning ? .orange : .white)
            } minimal: {
                Image(systemName: state.kind.symbol)
                    .foregroundStyle(state.isWarning ? .orange : state.kind.color)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: HGVActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.kind.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(state.kind.color.gradient, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(state.kind.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(state.startedAt, style: .timer)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            if let target = state.targetDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(state.targetLabel)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(target, style: .timer)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(state.isWarning ? .orange : .white)
                }
            } else if !state.targetLabel.isEmpty {
                Text(state.targetLabel)
                    .font(.headline)
                    .foregroundStyle(.green)
            }
        }
        .padding()
    }
}

private struct CountdownLine: View {
    let state: HGVActivityAttributes.ContentState

    var body: some View {
        HStack {
            Text(state.targetLabel)
                .foregroundStyle(.secondary)
            Spacer()
            if let target = state.targetDate {
                Text(target, style: .timer)
                    .monospacedDigit()
                    .font(.title3.weight(.bold))
                    .foregroundStyle(state.isWarning ? .orange : .white)
            }
        }
    }
}


/// Lock Screen while navigating: big arrow, distance, instruction, road, arrival — and the tacho countdown underneath.
private struct NavLockScreenView: View {
    let state: HGVActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: state.navSymbol ?? "arrow.up")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.navDistance ?? "").font(.title2.weight(.bold)).foregroundStyle(.white)
                    Text(state.navInstruction ?? "").font(.subheadline).foregroundStyle(.white).lineLimit(2)
                }
                Spacer()
            }
            HStack {
                if let road = state.navRoad, !road.isEmpty {
                    Label(road, systemImage: "road.lanes").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                if let arrival = state.navArrival {
                    Text("Arrive \(arrival, style: .time)").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }
            if let target = state.targetDate {
                HStack {
                    Text(state.targetLabel).font(.caption).foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(target, style: .timer).font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(state.isWarning ? .orange : .white)
                }
            }
        }
        .padding()
    }
}
