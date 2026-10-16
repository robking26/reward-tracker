import SwiftUI
import WidgetKit

/// Money earned today, what earned it, and Activity rings: small (2×2), medium (4×2) and
/// large (4×4) Home Screen sizes, plus circular, rectangular and inline Lock Screen widgets.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Money earned today, what earned it, and your Activity rings.")
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
    static let elevated = Color(.sRGB, red: 0x30 / 255, green: 0x35 / 255, blue: 0x36 / 255, opacity: 1)
    static let textPrimary = Color(.sRGB, red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF3 / 255, opacity: 1)
    static let textSecondary = Color(.sRGB, red: 0xA7 / 255, green: 0xB0 / 255, blue: 0xAA / 255, opacity: 1)
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
    private var breakdown: [WidgetCategoryLine] { current?.breakdown ?? [] }
    private var earnedText: String { current.map { WidgetMoney.format(pence: $0.earnedTodayPence) } ?? "–" }
    private var stepsText: String { current.map { $0.steps.formatted(.number) } ?? "–" }

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

    // MARK: Shared pieces

    private func earnedBlock(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Earned today")
                .font(.caption.weight(.medium))
                .foregroundStyle(WidgetPalette.textSecondary)
            Text(earnedText)
                .font(.system(size: size, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    /// One input's contribution: icon, name (and measurement when there's room), and money earned.
    private func line(_ item: WidgetCategoryLine, showsDetail: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WidgetPalette.textSecondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if showsDetail {
                    Text(item.detail)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(WidgetPalette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text("+" + WidgetMoney.format(pence: item.earnedPence))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.accent)
                .lineLimit(1)
        }
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func breakdownList(limit: Int, showsDetail: Bool) -> some View {
        if current == nil {
            emptyMessage("Open the app to update today.")
        } else if breakdown.isEmpty {
            emptyMessage("Nothing earned yet today.")
        } else {
            VStack(alignment: .leading, spacing: showsDetail ? 8 : 4) {
                ForEach(breakdown.prefix(limit)) { item in
                    line(item, showsDetail: showsDetail)
                }
                if breakdown.count > limit {
                    Text("+\(breakdown.count - limit) more")
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.textTertiary)
                }
            }
        }
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(WidgetPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
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
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                earnedBlock(size: 30)
                Spacer(minLength: 6)
                breakdownList(limit: 3, showsDetail: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ActivityRingsView(rings: current?.rings, lineWidth: 11, spacing: 2.5)
                .frame(width: 104, height: 104)
        }
    }

    // MARK: Large (4×4)

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 10)
            HStack(alignment: .center, spacing: 16) {
                earnedBlock(size: 42)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ActivityRingsView(rings: current?.rings, lineWidth: 10, spacing: 2)
                    .frame(width: 84, height: 84)
            }
            Spacer(minLength: 12)
            Text("What earned it")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetPalette.textSecondary)
                .padding(.bottom, 6)
            breakdownGrid
            Spacer(minLength: 12)
            month
            Spacer(minLength: 8)
            footer
        }
    }

    /// Up to six inputs in two even columns, so no single input dominates.
    @ViewBuilder
    private var breakdownGrid: some View {
        if current == nil {
            emptyMessage("Open the app to update today's numbers.")
        } else if breakdown.isEmpty {
            emptyMessage("Nothing earned yet today. Every step, workout and swim adds up.")
        } else {
            let items = Array(breakdown.prefix(6))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                ForEach(0..<((items.count + 1) / 2), id: \.self) { row in
                    GridRow {
                        line(items[row * 2], showsDetail: true)
                        if row * 2 + 1 < items.count {
                            line(items[row * 2 + 1], showsDetail: true)
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sterlingsign.circle.fill")
                .foregroundStyle(WidgetPalette.accent)
            Text("Vaultality")
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

    private var month: some View {
        let earned = snapshot?.monthEarnedPence ?? 0
        let allocation = snapshot?.monthAllocationPence ?? 0
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
                        .frame(width: monthProgress > 0 ? max(4, proxy.size.width * monthProgress) : 0)
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
                    Text("Open Vaultality to update today's numbers")
                } else {
                    Text("Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                }
            } else {
                Text("Open Vaultality to set up this widget")
            }
        }
        .font(.caption2)
        .foregroundStyle(WidgetPalette.textTertiary)
    }

    private var monthProgress: Double {
        guard let snapshot, snapshot.monthAllocationPence > 0 else { return 0 }
        return min(1, Double(snapshot.monthEarnedPence) / Double(snapshot.monthAllocationPence))
    }

    // MARK: Lock Screen

    /// Today's earnings inside a ring showing how much of the month's vault is unlocked.
    private var lockCircular: some View {
        Gauge(value: monthProgress) {
            Image(systemName: "sterlingsign")
        } currentValueLabel: {
            Text(earnedText)
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
        Label(current == nil ? "Open Vaultality" : "\(earnedText) today · \(stepsText) steps",
              systemImage: "sterlingsign.circle")
    }
}

extension WidgetSnapshot {
    static let placeholder = WidgetSnapshot(
        day: WidgetSnapshot.dayString(for: .now), earnedTodayPence: 842, steps: 8_412,
        breakdown: [
            WidgetCategoryLine(id: "exercise", title: "Exercise", symbol: "figure.run", detail: "32 min", earnedPence: 192),
            WidgetCategoryLine(id: "steps", title: "Steps", symbol: "figure.walk", detail: "8,412 steps", earnedPence: 168),
            WidgetCategoryLine(id: "strength", title: "Strength", symbol: "dumbbell.fill", detail: "15 min", earnedPence: 150),
            WidgetCategoryLine(id: "swimming", title: "Swimming", symbol: "figure.pool.swim", detail: "1.20 km", earnedPence: 240),
            WidgetCategoryLine(id: "flights", title: "Flights Climbed", symbol: "figure.stairs", detail: "8 flights", earnedPence: 80),
            WidgetCategoryLine(id: "activeEnergy", title: "Active Energy", symbol: "flame.fill", detail: "520 kcal", earnedPence: 52),
        ],
        rings: ActivityRingsSnapshot(
            move: RingProgress(value: 420, goal: 600), exercise: RingProgress(value: 32, goal: 30),
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

#Preview(as: .systemLarge) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
    TodayEntry(date: .now, snapshot: nil)
}

#Preview(as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
}
#endif
