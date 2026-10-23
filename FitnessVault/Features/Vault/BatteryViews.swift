import Charts
import SwiftUI

/// The year's transformation on the Vault: a battery that the gym, swims and runs charge, and misses drain.
struct BatteryCard: View {
    @Environment(AppModel.self) private var model
    @Environment(TrainingModel.self) private var training
    @Environment(PlannerModel.self) private var planner
    @Environment(LifeBatteryModel.self) private var battery

    var body: some View {
        NavigationLink {
            BatteryDetailView()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Transformation")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("\(battery.daysLeft) days to go")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(BatteryStyle.percent(battery.result.percent))
                        .font(.display(44))
                        .monospacedDigit()
                        .foregroundStyle(BatteryStyle.tint(battery.result.percent))
                        .contentTransition(.numericText(value: battery.result.percent))
                    Text(BatteryStyle.signed(battery.thisWeek) + " this week")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(battery.thisWeek < 0 ? Palette.error : Palette.textSecondary)
                }
                BatteryGauge(percent: battery.result.percent, charging: chargedToday)
                    .frame(height: 64)
                Text(projectionText)
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .surface(radius: Radius.hero, padding: Spacing.l)
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transformation battery, \(BatteryStyle.percent(battery.result.percent)). \(projectionText)")
        .task(id: model.lastHealthSync) { refresh() }
        .onAppear(perform: refresh)
    }

    private var chargedToday: Bool {
        battery.result.events.contains { $0.day == battery.today && $0.quarters > 0 }
    }

    private var projectionText: String {
        guard let projected = battery.projection else {
            return "Gym +0.5% · swim or run +0.25% · missed gym −0.5% · missed steps −0.25%"
        }
        return "At this pace: \(BatteryStyle.percent(projected)) by \(battery.end.startDate(calendar: battery.calendar).formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    private func refresh() {
        battery.refresh(model: model, training: training, gymPerWeek: planner.settings.gymPerWeek)
    }
}

/// A horizontal battery: a rounded shell, a terminal, and a fill that changes colour as it charges.
struct BatteryGauge: View {
    let percent: Double
    var charging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        let tint = BatteryStyle.tint(percent)
        HStack(spacing: 4) {
            GeometryReader { proxy in
                let inset: CGFloat = 5
                let width = max(0, proxy.size.width - inset * 2)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 2.5)
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(shown > 0 ? 10 : 0, width * shown / 100))
                        .padding(inset)
                        .shadow(color: tint.opacity(0.45), radius: 10)
                    // Tenths, like the cells of a battery.
                    HStack(spacing: 0) {
                        ForEach(1..<10) { _ in
                            Spacer()
                            Rectangle().fill(Palette.background.opacity(0.35)).frame(width: 1.5)
                        }
                        Spacer()
                    }
                    .padding(.vertical, inset + 6)
                    if charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Palette.border)
                .frame(width: 7, height: 24)
        }
        .onAppear { update(animated: !reduceMotion) }
        .onChange(of: percent) { update(animated: !reduceMotion) }
        .accessibilityHidden(true)
    }

    private func update(animated: Bool) {
        if animated {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { shown = percent }
        } else {
            shown = percent
        }
    }
}

// MARK: - Detail

struct BatteryDetailView: View {
    @Environment(LifeBatteryModel.self) private var battery

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(BatteryStyle.percent(battery.result.percent))
                        .font(.display(56))
                        .monospacedDigit()
                        .foregroundStyle(BatteryStyle.tint(battery.result.percent))
                    BatteryGauge(percent: battery.result.percent)
                        .frame(height: 72)
                    HStack(spacing: Spacing.s) {
                        StatTile(value: BatteryStyle.signed(battery.thisWeek), label: "This week", symbol: "calendar",
                                 tint: Palette.accent)
                        StatTile(value: battery.projection.map(BatteryStyle.percent) ?? "–", label: "At this pace",
                                 symbol: "chart.line.uptrend.xyaxis", tint: Palette.frost)
                        StatTile(value: String(format: "%.1f%%", battery.neededPerWeek), label: "Per week to 100%",
                                 symbol: "target", tint: Palette.kitchen)
                    }
                }
                .surface()

                if battery.result.history.count >= 2 {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        CardHeader(title: "Charge over time", symbol: "battery.75percent", tint: Palette.accent,
                                   subtitle: "Started \(battery.start.startDate(calendar: battery.calendar).formatted(.dateTime.day().month(.wide).year()))")
                        Chart {
                            ForEach(battery.result.history.indices, id: \.self) { index in
                                let point = battery.result.history[index]
                                AreaMark(x: .value("Day", point.day.startDate(calendar: battery.calendar)),
                                         y: .value("Charge", point.percent))
                                    .foregroundStyle(LinearGradient(colors: [Palette.accent.opacity(0.35), Palette.accent.opacity(0)],
                                                                    startPoint: .top, endPoint: .bottom))
                                LineMark(x: .value("Day", point.day.startDate(calendar: battery.calendar)),
                                         y: .value("Charge", point.percent))
                                    .foregroundStyle(Palette.accent)
                                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            }
                        }
                        .chartYScale(domain: 0...max(10, (battery.result.history.map(\.percent).max() ?? 0) + 5))
                        .frame(height: 180)
                    }
                    .surface()
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    CardHeader(title: "How it charges", symbol: "bolt.fill", tint: Palette.accent)
                    rule("dumbbell.fill", "Each gym session", "+0.5%", Palette.accent)
                    rule("figure.pool.swim", "Each swim", "+0.25%", Palette.frost)
                    rule("figure.run", "Each run", "+0.25%", Palette.rose)
                    rule("calendar.badge.minus", "Each planned gym session missed in a week", "−0.5%", Palette.error)
                    rule("figure.walk", "Each day under the Gym tab's step target", "−0.25%", Palette.error)
                    Footnote("Gym sessions are ones logged in the Gym tab or 20+ minutes of strength in Apple Health. Swims and runs come from Apple Health. Missed gym sessions are counted at the end of each week against your weekly gym target; it never drops below 0%.")
                }
                .surface()

                SectionTitle(title: "Recent changes")
                VStack(spacing: 0) {
                    let events = Array(battery.result.events.prefix(40))
                    if events.isEmpty {
                        Text("Nothing yet. Your first gym session puts the first charge in.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(events.indices, id: \.self) { index in
                        let event = events[index]
                        HStack(spacing: Spacing.s) {
                            IconTile(symbol: event.kind.symbol, tint: event.quarters > 0 ? Palette.accent : Palette.error, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.kind.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.textPrimary)
                                Text(event.day.startDate(calendar: battery.calendar).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(.caption)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            Spacer()
                            Text(event.quarters == 0 ? "at 100%" : BatteryStyle.signed(event.percent))
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(event.quarters > 0 ? Palette.accent : Palette.error)
                        }
                        .frame(minHeight: 52)
                        if index < events.count - 1 { RowDivider() }
                    }
                }
                .surface()
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle("Transformation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rule(_ symbol: String, _ text: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }
}

enum BatteryStyle {
    static func tint(_ percent: Double) -> Color {
        switch percent {
        case ..<20: Palette.error
        case ..<50: Palette.warning
        default: Palette.accent
        }
    }

    /// "12.25%", "12.5%", "12%".
    static func percent(_ value: Double) -> String {
        let text = value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value))
            : String(format: "%.2f", value).replacingOccurrences(of: #"0$"#, with: "", options: .regularExpression)
        return text + "%"
    }

    static func signed(_ value: Double) -> String {
        value > 0 ? "+" + percent(value) : (value < 0 ? "−" + percent(-value) : "±0%")
    }
}
