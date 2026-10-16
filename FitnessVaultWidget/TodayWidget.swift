import SwiftUI
import WidgetKit

/// Money earned today, steps and Activity rings: small (2×2), medium (4×2) and large (4×4)
/// Home Screen sizes, plus circular, rectangular and inline Lock Screen widgets.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Money earned today, your steps and Activity rings.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// The widget can't read Apple Health itself; it shows what the app last saved and says when that was.
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, snapshot: context.isPreview ? (WidgetSnapshotStore.load() ?? .placeholder) : WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshotStore.load()
        var entries = [TodayEntry(date: now, snapshot: snapshot)]
        // Add an entry at midnight so yesterday's numbers aren't shown as today's.
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) {
            entries.append(TodayEntry(date: midnight, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

enum WidgetPalette {
    static let background = Color(.sRGB, red: 0x17 / 255, green: 0x19 / 255, blue: 0x1B / 255, opacity: 1)
    static let elevated = Color(.sRGB, red: 0x2C / 255, green: 0x30 / 255, blue: 0x32 / 255, opacity: 1)
    static let textPrimary = Color(.sRGB, red: 0xF7 / 255, green: 0xF8 / 255, blue: 0xF7 / 255, opacity: 1)
    static let textSecondary = Color(.sRGB, red: 0xAD / 255, green: 0xB3 / 255, blue: 0xB1 / 255, opacity: 1)
    static let textTertiary = Color(.sRGB, red: 0x7F / 255, green: 0x88 / 255, blue: 0x84 / 255, opacity: 1)
    static let accent = Color(.sRGB, red: 0xC5 / 255, green: 0xF2 / 255, blue: 0x77 / 255, opacity: 1)
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    /// Numbers saved on an earlier day aren't today's, so they're never shown as if they were.
    private var current: WidgetSnapshot? {
        guard let snapshot, snapshot.isForToday(entry.date) else { return nil }
        return snapshot
    }

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
    }

    // MARK: Lock Screen

    /// Today's earnings inside a ring showing how much of the month's vault is unlocked.
    private var lockCircular: some View {
        Gauge(value: monthProgress) {
            Image(systemName: "sterlingsign")
        } currentValueLabel: {
            Text(current.map { WidgetMoney.format(pence: $0.earnedTodayPence) } ?? "–")
                .monospacedDigit()
                .minimumScaleFactor(0.4)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("Earned today \(earnedText). \(Int(monthProgress * 100)) percent of this month unlocked.")
    }

    private var lockRectangular: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(earnedText)
                    .font(.headline)
                    .monospacedDigit()
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(current == nil ? "Open app to update" : "earned today")
                    .font(.caption)
                    .lineLimit(1)
                Label(stepsText + " steps", systemImage: "figure.walk")
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ActivityRingsView(rings: current?.rings, lineWidth: 5, spacing: 1)
                .frame(width: 46, height: 46)
        }
        .accessibilityElement(children: .combine)
    }

    private var lockInline: some View {
        // Inline widgets show a single line of text and one image only.
        Label(current == nil ? "Open Fitness Vault" : "\(earnedText) today · \(stepsText) steps",
              systemImage: "sterlingsign.circle")
    }

    private var monthProgress: Double {
        guard let snapshot, snapshot.monthAllocationPence > 0 else { return 0 }
        return min(1, Double(snapshot.monthEarnedPence) / Double(snapshot.monthAllocationPence))
    }

    // MARK: Small (2×2)

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Earned today")
                .font(.caption.weight(.medium))
                .foregroundStyle(WidgetPalette.textSecondary)
            Text(earnedText)
                .font(.system(size: 30, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Spacer(minLength: 6)
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(stepsText)
                        .font(.headline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("steps")
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.textSecondary)
                }
                Spacer(minLength: 0)
                ActivityRingsView(rings: current?.rings, lineWidth: 7, spacing: 1.5)
                    .frame(width: 58, height: 58)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Medium (4×2)

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 6)
                Text("Earned today")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WidgetPalette.textSecondary)
                Text(earnedText)
                    .font(.system(size: 34, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(WidgetPalette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Spacer(minLength: 6)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.footnote)
                        .foregroundStyle(WidgetPalette.textSecondary)
                    Text(stepsText)
                        .font(.headline)
                        .monospacedDigit()
                    Text("steps")
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.textSecondary)
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ActivityRingsView(rings: current?.rings, lineWidth: 12, spacing: 2.5)
                .frame(width: 112, height: 112)
        }
    }

    // MARK: Large (4×4)

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 12)
            earned
            Spacer(minLength: 16)
            HStack(alignment: .center, spacing: 20) {
                ActivityRingsView(rings: current?.rings, lineWidth: 15, spacing: 3)
                    .frame(width: 128, height: 128)
                ringLegend
            }
            Spacer(minLength: 16)
            steps
            Spacer(minLength: 14)
            month
            Spacer(minLength: 10)
            footer
        }
    }

    private var earnedText: String {
        current.map { WidgetMoney.format(pence: $0.earnedTodayPence) } ?? "–"
    }

    private var stepsText: String {
        current.map { $0.steps.formatted(.number) } ?? "–"
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sterlingsign.circle.fill")
                .foregroundStyle(WidgetPalette.accent)
            Text("Fitness Vault")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WidgetPalette.textSecondary)
            Spacer()
            if current?.isDemo == true {
                Text("Demo")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WidgetPalette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WidgetPalette.elevated, in: Capsule())
            }
        }
    }

    private var earned: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Earned today")
                .font(.subheadline)
                .foregroundStyle(WidgetPalette.textSecondary)
            Text(earnedText)
                .font(.system(size: 46, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private var ringLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let rings = current?.rings {
                legendRow("Move", rings.move, unit: rings.moveUnit, color: ActivityRingsView.moveColor)
                legendRow("Exercise", rings.exercise, unit: "min", color: ActivityRingsView.exerciseColor)
                legendRow("Stand", rings.stand, unit: "hr", color: ActivityRingsView.standColor)
            } else {
                Text(current == nil ? "Open the app to update today's rings." : "Rings appear when Apple Health has today's activity.")
                    .font(.footnote)
                    .foregroundStyle(WidgetPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendRow(_ title: String, _ ring: RingProgress, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text("\(Int(ring.value))/\(Int(ring.goal)) \(unit)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private var steps: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.headline)
                .foregroundStyle(WidgetPalette.textSecondary)
            Text(stepsText)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text("steps")
                .font(.subheadline)
                .foregroundStyle(WidgetPalette.textSecondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var month: some View {
        let earned = snapshot?.monthEarnedPence ?? 0
        let allocation = snapshot?.monthAllocationPence ?? 0
        let progress = allocation > 0 ? min(1, Double(earned) / Double(allocation)) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("This month")
                    .foregroundStyle(WidgetPalette.textSecondary)
                Spacer()
                Text("\(WidgetMoney.format(pence: earned)) of \(WidgetMoney.format(pence: allocation, wholePounds: true))")
                    .monospacedDigit()
            }
            .font(.caption.weight(.medium))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(WidgetPalette.elevated)
                    Capsule().fill(WidgetPalette.accent)
                        .frame(width: progress > 0 ? max(4, proxy.size.width * progress) : 0)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        Group {
            if let snapshot {
                if current == nil {
                    Text("Open Fitness Vault to update today's numbers")
                } else {
                    Text("Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                }
            } else {
                Text("Open Fitness Vault to set up this widget")
            }
        }
        .font(.caption2)
        .foregroundStyle(WidgetPalette.textTertiary)
    }
}

extension WidgetSnapshot {
    static let placeholder = WidgetSnapshot(
        day: WidgetSnapshot.dayString(for: .now), earnedTodayPence: 842, steps: 8_412,
        rings: ActivityRingsSnapshot(
            move: RingProgress(value: 420, goal: 600), exercise: RingProgress(value: 24, goal: 30),
            stand: RingProgress(value: 8, goal: 12), moveUnit: "kcal"),
        monthEarnedPence: 12_345, monthAllocationPence: 40_000, isDemo: false, updatedAt: .now)
}

#if DEBUG
#Preview(as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .accessoryCircular) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemLarge) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
    TodayEntry(date: .now, snapshot: nil)
}
#endif
