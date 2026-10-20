import SwiftUI
import WidgetKit

/// The coach's next action, today's commitments and Activity: small (2×2), medium (4×2) and large (4×4)
/// Home Screen sizes, plus circular, rectangular and inline Lock Screen widgets. No money or fines (WG1).
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("What's next, today's commitments and your activity.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let plan: CoachWidgetSnapshot?
}

/// The widget can't read Apple Health or the coach's store itself; it shows what the app last saved.
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .placeholder, plan: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        if context.isPreview {
            completion(TodayEntry(date: .now, snapshot: WidgetSnapshotStore.load() ?? .placeholder,
                                  plan: CoachWidgetStore.load() ?? .placeholder))
        } else {
            completion(TodayEntry(date: .now, snapshot: WidgetSnapshotStore.load(), plan: CoachWidgetStore.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshotStore.load()
        let plan = CoachWidgetStore.load()
        var entries = [TodayEntry(date: now, snapshot: snapshot, plan: plan)]
        // An entry at midnight so yesterday's numbers aren't shown as today's.
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) {
            entries.append(TodayEntry(date: midnight, snapshot: snapshot, plan: plan))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

enum WidgetPalette {
    static let background = Color(.sRGB, red: 0x17 / 255, green: 0x19 / 255, blue: 0x1B / 255, opacity: 1)
    static let elevated = Color(.sRGB, red: 0x30 / 255, green: 0x35 / 255, blue: 0x36 / 255, opacity: 1)
    static let textPrimary = Color(.sRGB, red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF3 / 255, opacity: 1)
    static let textSecondary = Color(.sRGB, red: 0xA7 / 255, green: 0xB0 / 255, blue: 0xAA / 255, opacity: 1)
    static let textTertiary = Color(.sRGB, red: 0x7F / 255, green: 0x88 / 255, blue: 0x84 / 255, opacity: 1)
    static let accent = Color(.sRGB, red: 0xC5 / 255, green: 0xF2 / 255, blue: 0x77 / 255, opacity: 1)
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    /// Health numbers saved on an earlier day aren't today's, so they're never shown as if they were.
    private var health: WidgetSnapshot? {
        guard let snapshot = entry.snapshot, snapshot.isForToday(entry.date) else { return nil }
        return snapshot
    }

    private var plan: CoachWidgetSnapshot? {
        guard let plan = entry.plan, plan.isForToday(entry.date) else { return nil }
        return plan
    }

    private var stepsText: String { health.map { $0.steps.formatted(.number) } ?? "–" }
    private var doneText: String { plan.map { "\($0.done) of \($0.total)" } ?? "–" }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            case .accessoryCircular: lockCircular
            case .accessoryRectangular: lockRectangular
            case .accessoryInline: lockInline
            default: large
            }
        }
        .foregroundStyle(WidgetPalette.textPrimary)
        .widgetURL(tapURL)
    }

    // MARK: Actions (Phase 7: widgets that do something, not just decorate)

    /// Where a tap anywhere on the widget goes. Small widgets can't hold links, so this matches their action.
    private var tapURL: URL {
        guard let plan else { return AppLink.today }
        if plan.nextKind == "workout" || plan.nextKind == "swim" { return AppLink.workout }
        if plan.briefingPending == true { return AppLink.ready }
        return AppLink.today
    }

    /// Done for the current commitment, right on the Home Screen. Runs in the app without opening it.
    @ViewBuilder
    private var actionButton: some View {
        if let plan, let id = plan.nextID, nextLabel == "Now" {
            Button(intent: CompleteCommitmentIntent(commitmentID: id)) {
                Label("Done", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WidgetPalette.accent)
            .foregroundStyle(WidgetPalette.background)
        } else if let plan, plan.nextKind == "workout" || plan.nextKind == "swim" {
            Link(destination: AppLink.workout) {
                Label("Start workout", systemImage: "dumbbell")
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(WidgetPalette.elevated, in: Capsule())
            }
        } else if plan?.briefingPending == true {
            Link(destination: AppLink.ready) {
                Label("I'm ready", systemImage: "sunrise")
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(WidgetPalette.elevated, in: Capsule())
            }
        }
    }

    // MARK: Shared pieces

    private var nextLabel: String {
        guard let plan, plan.nextTitle != nil else { return "Today" }
        if plan.nextInProgress { return "Now" }
        guard let start = plan.nextStart else { return "Next · any time" }
        return start <= entry.date ? "Now" : "Next · \(start.formatted(date: .omitted, time: .shortened))"
    }

    private var nextTitle: String {
        guard let plan else { return "Open Vaultality" }
        return plan.nextTitle ?? (plan.total > 0 && plan.done == plan.total ? "All done" : "Nothing agreed")
    }

    private func nextBlock(titleFont: Font, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nextLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(WidgetPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let symbol = plan?.nextSymbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetPalette.accent)
                }
                Text(nextTitle)
                    .font(titleFont)
                    .lineLimit(lines)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var doneBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(doneText)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
            Text("done today")
                .font(.caption2)
                .foregroundStyle(WidgetPalette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var metrics: [WidgetMetric] {
        if let metrics = health?.metrics, !metrics.isEmpty { return metrics }
        return [WidgetMetric(id: "steps", title: "Steps", symbol: "figure.walk", value: stepsText, unit: "")]
    }

    private var metricsStrip: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: metric.symbol)
                        Text(metric.title)
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WidgetPalette.textSecondary)
                    .lineLimit(1)
                    (Text(metric.value).font(.subheadline.weight(.semibold))
                        + Text(metric.unit.isEmpty ? "" : " " + metric.unit).font(.caption2).foregroundStyle(WidgetPalette.textTertiary))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Small (2×2)

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            nextBlock(titleFont: .headline, lines: hasAction ? 2 : 3)
            Spacer(minLength: 6)
            if hasAction {
                actionButton
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    doneBlock
                    Spacer(minLength: 0)
                    ActivityRingsView(rings: health?.rings, lineWidth: 6, spacing: 1.5)
                        .frame(width: 52, height: 52)
                }
            }
        }
    }

    private var hasAction: Bool {
        guard let plan else { return false }
        return (plan.nextID != nil && nextLabel == "Now") || plan.nextKind == "workout" || plan.nextKind == "swim"
            || plan.briefingPending == true
    }

    // MARK: Medium (4×2)

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                nextBlock(titleFont: .title3.weight(.semibold), lines: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    ActivityRingsView(rings: health?.rings, lineWidth: 6, spacing: 1.5)
                        .frame(width: 48, height: 48)
                    Text(doneText + " done")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(WidgetPalette.textSecondary)
                }
            }
            Spacer(minLength: 6)
            if hasAction {
                actionButton
            } else {
                metricsStrip
            }
        }
    }

    // MARK: Large (4×4)

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(WidgetPalette.accent)
                Text("Vaultality")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WidgetPalette.textSecondary)
                Spacer()
                if health?.isDemo == true {
                    Text("Demo")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetPalette.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(WidgetPalette.elevated, in: Capsule())
                }
            }
            Spacer(minLength: 10)
            HStack(alignment: .center, spacing: 16) {
                nextBlock(titleFont: .title2.weight(.semibold), lines: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ActivityRingsView(rings: health?.rings, lineWidth: 10, spacing: 2)
                    .frame(width: 84, height: 84)
            }
            Spacer(minLength: 12)
            if let stillDue = plan?.stillDue, !stillDue.isEmpty {
                Text("Still due")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.textSecondary)
                    .padding(.bottom, 4)
                ForEach(stillDue, id: \.self) { title in
                    Label(title, systemImage: "circle")
                        .font(.footnote)
                        .lineLimit(1)
                        .padding(.vertical, 2)
                }
                Spacer(minLength: 12)
            }
            if hasAction {
                actionButton
                Spacer(minLength: 10)
            }
            metricsStrip
            Spacer(minLength: 8)
            HStack {
                Text(doneText + " done today")
                Spacer()
                Text(footerTime)
            }
            .font(.caption2)
            .foregroundStyle(WidgetPalette.textTertiary)
        }
    }

    private var footerTime: String {
        guard let updated = health?.updatedAt ?? plan?.updatedAt else { return "Open Vaultality" }
        return "Updated \(updated.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: Lock Screen (discreet: sensitive titles and money never shown)

    private var lockTitle: String {
        guard let plan, plan.nextTitle != nil else { return nextTitle }
        return plan.nextIsSensitive ? "Next commitment" : nextTitle
    }

    private var lockCircular: some View {
        Gauge(value: Double(plan?.done ?? 0), in: 0...Double(max(1, plan?.total ?? 1))) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text(plan.map { "\($0.done)/\($0.total)" } ?? "–")
                .monospacedDigit()
                .minimumScaleFactor(0.4)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("\(doneText) commitments done today")
    }

    private var lockRectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(nextLabel)
                .font(.caption)
                .lineLimit(1)
            Text(lockTitle)
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(doneText) done · \(stepsText) steps")
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var lockInline: some View {
        // Inline widgets show a single line of text and one image only.
        Label(plan?.nextTitle == nil ? "\(doneText) done today" : "\(lockTitle) · \(nextLabel.replacingOccurrences(of: "Next · ", with: ""))",
              systemImage: "sun.max")
    }
}

extension CoachWidgetSnapshot {
    static let placeholder = CoachWidgetSnapshot(
        day: WidgetSnapshot.dayString(for: .now), nextTitle: "Lunchtime walk", nextSymbol: "figure.walk",
        nextStart: Calendar.current.date(bySettingHour: 12, minute: 10, second: 0, of: .now), nextIsSensitive: false,
        nextInProgress: false, stillDue: ["Wash up after dinner", "Evening self-care"], done: 2, total: 5, updatedAt: .now)
}

extension WidgetSnapshot {
    static let placeholder = WidgetSnapshot(
        day: WidgetSnapshot.dayString(for: .now), earnedTodayPence: 0, steps: 8_412,
        breakdown: [],
        rings: ActivityRingsSnapshot(
            move: RingProgress(value: 420, goal: 600), exercise: RingProgress(value: 32, goal: 30),
            stand: RingProgress(value: 8, goal: 12), moveUnit: "kcal"),
        metrics: [
            WidgetMetric(id: "steps", title: "Steps", symbol: "figure.walk", value: "8,412", unit: ""),
            WidgetMetric(id: "exercise", title: "Exercise", symbol: "stopwatch", value: "32", unit: "min"),
            WidgetMetric(id: "activeEnergy", title: "Energy", symbol: "flame.fill", value: "520", unit: "kcal"),
            WidgetMetric(id: "flights", title: "Flights", symbol: "figure.stairs", value: "8", unit: ""),
        ],
        monthEarnedPence: 0, monthAllocationPence: 50_000, isDemo: false, updatedAt: .now)
}

#if DEBUG
#Preview(as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder, plan: .placeholder)
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder, plan: .placeholder)
}

#Preview(as: .systemLarge) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder, plan: .placeholder)
    TodayEntry(date: .now, snapshot: nil, plan: nil)
}

#Preview(as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder, plan: .placeholder)
}
#endif
