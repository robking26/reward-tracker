import SwiftUI
import WidgetKit

// MARK: - Day (2×2)

/// The next three hours of your day, hour by hour, from the Day tab's calendar.
struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PlannerWidgetStore.dayKind, provider: DayProvider()) { entry in
            DayWidgetView(entry: entry)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("Day")
        .description("The next few hours from your calendars, suggestions and routines.")
        .supportedFamilies([.systemSmall])
    }
}

struct DayEntry: TimelineEntry {
    let date: Date
    let snapshot: DayWidgetSnapshot?
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(DayEntry(date: .now, snapshot: PlannerWidgetStore.loadDay() ?? (context.isPreview ? .placeholder : nil)))
    }

    /// A new entry every 15 minutes for the next 12 hours, so the window and the now line keep moving.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let snapshot = PlannerWidgetStore.loadDay()
        let now = Date.now
        let step: TimeInterval = 15 * 60
        let first = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / step).rounded(.down) * step)
        let entries = (0..<48).map { DayEntry(date: max(now, first.addingTimeInterval(Double($0) * step)), snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(12 * 3_600))))
    }
}

struct DayWidgetView: View {
    let entry: DayEntry

    private var calendar: Calendar { .current }
    private var isToday: Bool { entry.snapshot?.day == WidgetSnapshot.dayString(for: entry.date, calendar: calendar) }

    /// From the start of this hour, three hours.
    private var window: DateInterval {
        let start = calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
        return DateInterval(start: start, duration: 3 * 3_600)
    }

    private var items: [DayWidgetItem] {
        guard isToday, let snapshot = entry.snapshot else { return [] }
        return snapshot.items.filter { $0.end > window.start && $0.start < window.end }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetPalette.accent)
                Text(entry.date.formatted(.dateTime.day()))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetPalette.textPrimary)
                Spacer(minLength: 2)
                Text(isToday ? (entry.snapshot?.headline ?? "") : "Open the app")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WidgetPalette.textTertiary)
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                grid(size: proxy.size)
            }
        }
    }

    private func grid(size: CGSize) -> some View {
        let labelWidth: CGFloat = 16
        let hourHeight = size.height / 3
        let width = size.width - labelWidth - 4
        return ZStack(alignment: .topLeading) {
            ForEach(0..<4) { hour in
                let date = window.start.addingTimeInterval(Double(hour) * 3_600)
                HStack(spacing: 4) {
                    Text(hourLabel(date))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(WidgetPalette.textTertiary)
                        .frame(width: labelWidth, alignment: .trailing)
                    Rectangle()
                        .fill(WidgetPalette.elevated)
                        .frame(height: 0.5)
                }
                .offset(y: CGFloat(hour) * hourHeight - 5)
            }
            ForEach(layout(items)) { block in
                let top = max(0, block.item.start.timeIntervalSince(window.start)) / 3_600 * hourHeight
                let bottom = min(3 * 3_600, block.item.end.timeIntervalSince(window.start)) / 3_600 * hourHeight
                let columnWidth = width / CGFloat(block.columns)
                blockView(block.item, height: max(14, bottom - top - 1))
                    .frame(width: max(10, columnWidth - 2), alignment: .topLeading)
                    .offset(x: labelWidth + 4 + CGFloat(block.column) * columnWidth, y: top)
            }
            // Now.
            let nowOffset = entry.date.timeIntervalSince(window.start) / 3_600 * hourHeight
            HStack(spacing: 0) {
                Circle().fill(Color.red).frame(width: 5, height: 5)
                Rectangle().fill(Color.red).frame(height: 1)
            }
            .offset(x: labelWidth + 1, y: nowOffset - 2.5)
            if isToday && items.isEmpty {
                Text("Free")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetPalette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func blockView(_ item: DayWidgetItem, height: CGFloat) -> some View {
        let dashed = item.kind == .suggestion
        return Text(item.title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(WidgetPalette.textPrimary)
            .lineLimit(height > 24 ? 2 : 1)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .background(item.color.opacity(dashed ? 0.16 : 0.32), in: RoundedRectangle(cornerRadius: 3))
            .overlay(alignment: .leading) {
                Rectangle().fill(item.color).frame(width: 2)
            }
            .overlay {
                if dashed {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(item.color, style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func hourLabel(_ date: Date) -> String {
        let hour = calendar.component(.hour, from: date)
        return "\(hour)"
    }

    private struct Block: Identifiable {
        var item: DayWidgetItem
        var column: Int
        var columns: Int
        var id: String { item.id }
    }

    /// Side by side when items overlap.
    private func layout(_ items: [DayWidgetItem]) -> [Block] {
        let sorted = items.sorted { $0.start < $1.start }
        var blocks: [Block] = []
        var group: [Block] = []
        var groupEnd = Date.distantPast
        func flush() {
            let columns = (group.map(\.column).max() ?? 0) + 1
            blocks += group.map { Block(item: $0.item, column: $0.column, columns: columns) }
            group = []
        }
        for item in sorted {
            if item.start >= groupEnd { flush() }
            var column = 0
            while group.contains(where: { $0.column == column && $0.item.end > item.start }) { column += 1 }
            group.append(Block(item: item, column: column, columns: 1))
            groupEnd = max(groupEnd, item.end)
        }
        flush()
        return blocks
    }
}

// MARK: - Transformation battery (2×2)

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PlannerWidgetStore.batteryKind, provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("Transformation")
        .description("Your year's transformation battery.")
        .supportedFamilies([.systemSmall])
    }
}

struct BatteryEntry: TimelineEntry {
    let date: Date
    let snapshot: BatteryWidgetSnapshot?
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry { BatteryEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(BatteryEntry(date: .now, snapshot: PlannerWidgetStore.loadBattery() ?? (context.isPreview ? .placeholder : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let entry = BatteryEntry(date: .now, snapshot: PlannerWidgetStore.loadBattery())
        completion(Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(60 * 60))))
    }
}

struct BatteryWidgetView: View {
    let entry: BatteryEntry

    var body: some View {
        let snapshot = entry.snapshot
        let percent = snapshot?.percent ?? 0
        let tint = Self.tint(percent)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRANSFORMATION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetPalette.textTertiary)
                Spacer(minLength: 0)
                if snapshot?.chargedToday == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            Text(snapshot.map { Self.percentText($0.percent) } ?? "–")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            gauge(percent: percent, tint: tint)
                .frame(height: 24)
            Spacer(minLength: 0)
            if let snapshot {
                Text("\(Self.signed(Double(snapshot.thisWeekQuarters) / 4)) this week")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(snapshot.thisWeekQuarters < 0 ? Color.red : WidgetPalette.textSecondary)
                Text("\(snapshot.daysLeft) days to go")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WidgetPalette.textTertiary)
            } else {
                Text("Open the app to charge it")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WidgetPalette.textTertiary)
            }
        }
    }

    private func gauge(percent: Double, tint: Color) -> some View {
        HStack(spacing: 2) {
            GeometryReader { proxy in
                let inset: CGFloat = 3
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(WidgetPalette.elevated, lineWidth: 1.5)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint)
                        .frame(width: max(percent > 0 ? 4 : 0, (proxy.size.width - inset * 2) * percent / 100))
                        .padding(inset)
                }
            }
            RoundedRectangle(cornerRadius: 1.5)
                .fill(WidgetPalette.elevated)
                .frame(width: 3, height: 10)
        }
    }

    static func tint(_ percent: Double) -> Color {
        if percent < 20 { return Color(.sRGB, red: 0xEF / 255, green: 0x8E / 255, blue: 0x8E / 255, opacity: 1) }
        if percent < 50 { return Color(.sRGB, red: 0xE9 / 255, green: 0xBA / 255, blue: 0x73 / 255, opacity: 1) }
        return WidgetPalette.accent
    }

    static func percentText(_ value: Double) -> String {
        let text = value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value))
            : String(format: "%.2f", value).replacingOccurrences(of: #"0$"#, with: "", options: .regularExpression)
        return text + "%"
    }

    static func signed(_ value: Double) -> String {
        value > 0 ? "+" + percentText(value) : (value < 0 ? "−" + percentText(-value) : "±0%")
    }
}

/// A compact battery for the 4×2 Today widget.
struct BatteryMini: View {
    let snapshot: BatteryWidgetSnapshot?

    var body: some View {
        let percent = snapshot?.percent ?? 0
        let tint = BatteryWidgetView.tint(percent)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text("BATTERY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WidgetPalette.textTertiary)
                if snapshot?.chargedToday == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            Text(snapshot.map { BatteryWidgetView.percentText($0.percent) } ?? "–")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 1.5) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(WidgetPalette.elevated, lineWidth: 1.2)
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(tint)
                            .frame(width: max(percent > 0 ? 3 : 0, (proxy.size.width - 4) * percent / 100))
                            .padding(2)
                    }
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(WidgetPalette.elevated)
                    .frame(width: 2.5, height: 6)
            }
            .frame(height: 13)
            if let snapshot {
                Text("\(BatteryWidgetView.signed(Double(snapshot.thisWeekQuarters) / 4)) this week")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetPalette.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transformation battery \(snapshot.map { BatteryWidgetView.percentText($0.percent) } ?? "not set up")")
    }
}
