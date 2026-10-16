import Charts
import SwiftUI

/// Detail for one reward category: this month's earnings, a daily chart, the rate and day-by-day history.
struct CategoryDetailView: View {
    @Environment(AppModel.self) private var model
    let category: RewardCategory

    var body: some View {
        let days = ActivityPeriod.month.days(model: model)
        let monthEarned = model.earned(category, in: days)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Label(category.title, systemImage: category.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    MoneyText(amount: monthEarned, font: .largeTitle, weight: .medium, color: Palette.accent)
                    Text("Earned this month")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)

                    Chart(days, id: \.self) { day in
                        BarMark(
                            x: .value("Day", day.startDate(calendar: model.calendar), unit: .day),
                            y: .value("Earned", Double(model.earningsByDay[day]?[category]?.value ?? 0) / 100))
                            .foregroundStyle(day == model.today ? Palette.accent : Palette.textTertiary)
                            .cornerRadius(2)
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing) { _ in
                            AxisGridLine().foregroundStyle(Palette.border)
                            AxisValueLabel(format: FloatingPointFormatStyle<Double>.Currency(code: "GBP").precision(.fractionLength(0)))
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisValueLabel(format: .dateTime.day())
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .frame(height: 160)
                    .padding(.top, Spacing.s)
                    .accessibilityLabel("Daily earnings chart for \(category.title)")
                }
                .surface(radius: Radius.hero, padding: Spacing.l)

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader("How it earns")
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(model.settings.rates.rateDescription(for: category))
                            .font(.headline)
                            .foregroundStyle(Palette.textPrimary)
                        Text(explanation)
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .surface()
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader("By day")
                    VStack(spacing: 0) {
                        let rows = days.sorted(by: >)
                        ForEach(rows, id: \.self) { day in
                            let metrics = model.metricsByDay[day] ?? DailyMetrics(day: day)
                            let measure = MeasureFormat.measurement(category, metrics)
                            let earned = model.earningsByDay[day]?[category] ?? .zero
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(DayLabel.text(day, model: model))
                                        .font(.subheadline)
                                        .foregroundStyle(Palette.textPrimary)
                                    Text("\(measure.value) \(measure.unit)")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.textTertiary)
                                }
                                Spacer()
                                Text("+\(earned.formatted())")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(earned.isPositive ? Palette.accent : Palette.textTertiary)
                            }
                            .padding(.vertical, Spacing.s)
                            .accessibilityElement(children: .combine)
                            if day != rows.last { Divider().overlay(Palette.border) }
                        }
                    }
                    .surface()
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var explanation: String {
        switch category {
        case .steps:
            "The first \(model.settings.rates.stepsBaseline.formatted()) steps each day earn nothing. Step \((model.settings.rates.stepsBaseline + 1).formatted()) earns your first 1p, then 1p for every full \(model.settings.rates.stepsPerPenny) steps over \(model.settings.rates.stepsBaseline.formatted()), up to \(model.settings.rates.stepsDailyCap.formatted()) a day (reached at \(model.settings.rates.stepsForCap.formatted()) steps)."
        case .activeEnergy, .flights:
            "Calculated from your cumulative daily total in Apple Health. Only whole intervals count; partial progress carries on through the day."
        case .exercise:
            "Uses Apple's Exercise minutes from Apple Health, as recorded by your iPhone and Apple Watch. Heart rate alone never counts."
        case .strength:
            "Uses the duration of Traditional and Functional Strength Training workouts in Apple Health. Each workout counts once."
        case .swimming:
            "Uses swimming distance recorded in Apple Health. Every full \(model.settings.rates.swimmingMetresPerInterval) m earns \(model.settings.rates.pencePerSwimInterval.formatted())."
        case .running:
            "Uses the distance of Running workouts in Apple Health, indoor or outdoor. Walking never counts here, and your running steps still count towards Steps."
        case .mealPhoto, .proteinTarget, .calorieTarget:
            "Nutrition has been removed from Fitness Vault. This category no longer earns anything; past amounts are kept in your history."
        }
    }
}

/// Everything earned on one day, by category.
struct DayDetailView: View {
    @Environment(AppModel.self) private var model
    let day: DayKey

    var body: some View {
        let metrics = model.metricsByDay[day] ?? DailyMetrics(day: day)
        List {
            Section {
                HStack {
                    Text("Total")
                    Spacer()
                    MoneyText(amount: model.earned(on: day), font: .headline, weight: .semibold, color: Palette.accent)
                }
            }
            .listRowBackground(Palette.surface)

            Section("By category") {
                // Current categories, plus any retired ones that still hold money for this day.
                ForEach(RewardCategory.allCases.filter { !$0.isRetired || (model.earningsByDay[day]?[$0] ?? .zero) != .zero }) { category in
                    let measure = MeasureFormat.measurement(category, metrics)
                    let earned = model.earningsByDay[day]?[category] ?? .zero
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title).foregroundStyle(Palette.textPrimary)
                                Text("\(measure.value) \(measure.unit)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.textTertiary)
                            }
                        } icon: {
                            Image(systemName: category.symbol).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Text("+\(earned.formatted())")
                            .monospacedDigit()
                            .foregroundStyle(earned.isPositive ? Palette.accent : Palette.textTertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(DayLabel.text(day, model: model))
        .navigationBarTitleDisplayMode(.inline)
    }
}
