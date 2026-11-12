#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// Lock Screen / Dynamic Island view of a snoozed wake-up or leave-home alarm.
@available(iOS 26.0, *)
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<WakeAlarmMetadata>.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.attributes.metadata?.kind == "leave" ? "car.fill" : "alarm.fill")
                    .font(.title2).foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.presentation.alert.title).font(.headline).lineLimit(1)
                    Text(subtitle(context.state.mode)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                countdown(context.state.mode).font(.title2.monospacedDigit().weight(.bold))
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill").foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state.mode).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.presentation.alert.title).font(.caption)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                countdown(context.state.mode).monospacedDigit().frame(maxWidth: 50)
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(context.attributes.tintColor)
            }
        }
    }

    private func subtitle(_ mode: AlarmPresentationState.Mode) -> String {
        switch mode {
        case .countdown: "Snoozed"
        case .paused: "Paused"
        default: "Alarm"
        }
    }

    @ViewBuilder
    private func countdown(_ mode: AlarmPresentationState.Mode) -> some View {
        switch mode {
        case .countdown(let c):
            Text(timerInterval: Date.now...max(Date.now, c.fireDate), countsDown: true)
        default:
            Text("")
        }
    }
}
#endif
