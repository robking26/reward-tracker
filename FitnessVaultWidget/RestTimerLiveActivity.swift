import ActivityKit
import SwiftUI
import WidgetKit

/// Rest countdown on the Lock Screen and in the Dynamic Island, so the timer is visible while you're in
/// another app between sets (W5, WG2). Counts down on its own; no updates needed while it runs.
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundStyle(WidgetPalette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.setLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetPalette.textSecondary)
                    Text(context.state.next)
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                RestCountdown(end: context.state.restEndsAt)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(WidgetPalette.textPrimary)
            }
            .padding(16)
            .activityBackgroundTint(WidgetPalette.background)
            .activitySystemActionForegroundColor(WidgetPalette.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetPalette.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(end: context.state.restEndsAt)
                        .font(.title2.weight(.medium))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.state.setLabel): \(context.state.next)")
                        .font(.footnote)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(WidgetPalette.accent)
            } compactTrailing: {
                RestCountdown(end: context.state.restEndsAt)
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(WidgetPalette.accent)
            }
        }
    }
}

/// A self-updating countdown that stops at zero rather than going negative.
private struct RestCountdown: View {
    let end: Date

    var body: some View {
        Text(timerInterval: Date.now...max(Date.now, end), countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}
