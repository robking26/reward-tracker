import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var period: ActivityPeriod = .day

    private let columns = [GridItem(.flexible(), spacing: Spacing.s), GridItem(.flexible(), spacing: Spacing.s)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Picker("Period", selection: $period) {
                        ForEach(ActivityPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    PeriodTotalCard(period: period)

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Movement")
                        LazyVGrid(columns: columns, spacing: Spacing.s) {
                            ForEach(RewardCategory.activity) { category in
                                ActivityMetricLink(category: category, period: period)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Nutrition")
                        LazyVGrid(columns: columns, spacing: Spacing.s) {
                            ForEach(RewardCategory.nutrition) { category in
                                ActivityMetricLink(category: category, period: period)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("History")
                        EarningsHistoryList(days: period.days(model: model))
                    }
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.xl)
                .animation(.snappy, value: period)
            }
            .pageBackground()
            .navigationTitle("Activity")
            .refreshable { await model.syncHealth() }
        }
    }
}

struct PeriodTotalCard: View {
    @Environment(AppModel.self) private var model
    let period: ActivityPeriod

    var body: some View {
        let days = period.days(model: model)
        let total = days.sum { model.earned(on: $0) }
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Earned · \(period.timeframe)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            MoneyText(amount: total, font: .largeTitle, weight: .medium, color: Palette.accent)
            Text("Updated \(MeasureFormat.relative(model.lastHealthSync))")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .surface(radius: Radius.hero, padding: Spacing.l)
        .accessibilityElement(children: .combine)
    }
}

/// Earnings per day, most recent first.
struct EarningsHistoryList: View {
    @Environment(AppModel.self) private var model
    let days: [DayKey]

    var body: some View {
        let rows = days.sorted(by: >)
        if rows.allSatisfy({ !model.earned(on: $0).isPositive }) {
            ContentUnavailableView("No earnings yet", systemImage: "sterlingsign.circle",
                                   description: Text("Money appears here as Apple Health records your activity."))
                .foregroundStyle(Palette.textSecondary)
                .surface()
        } else {
            VStack(spacing: 0) {
                ForEach(rows, id: \.self) { day in
                    NavigationLink {
                        DayDetailView(day: day)
                    } label: {
                        HStack {
                            Text(DayLabel.text(day, model: model))
                                .font(.subheadline)
                                .foregroundStyle(Palette.textPrimary)
                            Spacer()
                            Text("+\(model.earned(on: day).formatted())")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(model.earned(on: day).isPositive ? Palette.accent : Palette.textTertiary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.vertical, Spacing.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if day != rows.last { Divider().overlay(Palette.border) }
                }
            }
            .surface(padding: Spacing.m)
        }
    }
}

enum DayLabel {
    @MainActor
    static func text(_ day: DayKey, model: AppModel) -> String {
        if day == model.today { return "Today" }
        if day == model.today.adding(days: -1, calendar: model.calendar) { return "Yesterday" }
        return day.startDate(calendar: model.calendar).formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

/// "See All" destination: every category in a group, with its reward rate.
struct CategoryListView: View {
    let title: String
    let categories: [RewardCategory]
    private let columns = [GridItem(.flexible(), spacing: Spacing.s), GridItem(.flexible(), spacing: Spacing.s)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.s) {
                ForEach(categories) { category in
                    ActivityMetricLink(category: category, period: .day, showsRate: true)
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.vertical, Spacing.m)
        }
        .pageBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}
