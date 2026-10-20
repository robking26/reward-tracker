import ActivityKit
import SwiftUI
import WidgetKit

/// Leaving for the gym, a task in progress, or dinner cooking: a countdown on the Lock Screen and in the
/// Dynamic Island that ends on its own (WG2).
struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.attributes.symbol)
                    .font(.title2)
                    .foregroundStyle(WidgetPalette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.textPrimary)
                        .lineLimit(1)
                    Text(context.state.subtitle)
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                CountdownText(end: context.state.endsAt)
                    .font(.title.weight(.medium))
                    .foregroundStyle(WidgetPalette.textPrimary)
            }
            .padding(16)
            .activityBackgroundTint(WidgetPalette.background)
            .activitySystemActionForegroundColor(WidgetPalette.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.symbol)
                        .foregroundStyle(WidgetPalette.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(end: context.state.endsAt)
                        .font(.title3.weight(.medium))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.attributes.title) · \(context.state.subtitle)")
                        .font(.footnote)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbol).foregroundStyle(WidgetPalette.accent)
            } compactTrailing: {
                CountdownText(end: context.state.endsAt)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.attributes.symbol).foregroundStyle(WidgetPalette.accent)
            }
        }
    }
}

private struct CountdownText: View {
    let end: Date

    var body: some View {
        Text(timerInterval: Date.now...max(Date.now, end), countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}
