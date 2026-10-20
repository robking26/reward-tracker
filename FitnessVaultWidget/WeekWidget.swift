import SwiftUI
import WidgetKit

/// The week at a glance: the last seven days' scores as calm marks and gym sessions against this week's target.
/// Never money, fines or body measurements (WG1).
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.weekWidgetKind, provider: WeekProvider()) { entry in
            WeekWidgetView(plan: entry.plan)
                .containerBackground(WidgetPalette.background, for: .widget)
                .widgetURL(AppLink.today)
        }
        .configurationDisplayName("This week")
        .description("The last seven days and this week's gym sessions.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct WeekEntry: TimelineEntry {
    let date: Date
    let plan: CoachWidgetSnapshot?
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry { WeekEntry(date: .now, plan: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(WeekEntry(date: .now, plan: CoachWidgetStore.load() ?? (context.isPreview ? .placeholder : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let entry = WeekEntry(date: .now, plan: CoachWidgetStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(60 * 60))))
    }
}

struct WeekWidgetView: View {
    let plan: CoachWidgetSnapshot?
    @Environment(\.widgetFamily) private var family

    private var week: [Int?] { plan?.week ?? Array(repeating: nil, count: 7) }
    private var gymText: String {
        guard let done = plan?.workoutsThisWeek, let target = plan?.workoutTarget else { return "–" }
        return "\(done) of \(target)"
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("This week").font(.caption)
                marks(height: 14)
                Text("Gym \(gymText)").font(.caption).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Last 7 days")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.textSecondary)
                marks(height: family == .systemMedium ? 44 : 34)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "dumbbell").foregroundStyle(WidgetPalette.accent)
                    Text(gymText)
                        .font(.headline)
                        .monospacedDigit()
                    Text("gym sessions")
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.textSecondary)
                }
            }
            .foregroundStyle(WidgetPalette.textPrimary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
        }
    }

    /// One mark per day; taller for a stronger day. No streaks, no red (design bar §31).
    private func marks(height: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(week.enumerated()), id: \.offset) { item in
                RoundedRectangle(cornerRadius: 3)
                    .fill(colour(item.element))
                    .frame(height: barHeight(item.element, in: height))
                    .frame(maxHeight: height, alignment: .bottom)
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }

    private func colour(_ score: Int?) -> Color {
        guard let score else { return WidgetPalette.elevated }
        return score >= 80 ? WidgetPalette.accent : WidgetPalette.accent.opacity(0.55)
    }

    private func barHeight(_ score: Int?, in height: CGFloat) -> CGFloat {
        let fraction = CGFloat(score ?? 12) / 100
        return max(4, height * fraction)
    }

    private var accessibilitySummary: String {
        let scored = week.compactMap { $0 }
        let strong = scored.filter { $0 >= 80 }.count
        return "Last seven days: \(strong) of \(scored.count) scored days at 80 percent or more. Gym sessions this week: \(gymText)."
    }
}
