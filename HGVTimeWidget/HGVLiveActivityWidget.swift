import ActivityKit
import SwiftUI
import WidgetKit

struct HGVLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HGVActivityAttributes.self) { context in
            LockScreenView(state: context.state)
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
                    CountdownLine(state: state)
                }
            } compactLeading: {
                Image(systemName: state.kind.symbol)
                    .foregroundStyle(state.kind.color)
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
