import SwiftUI

struct NutritionGrid: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.flexible(), spacing: Spacing.s), GridItem(.flexible(), spacing: Spacing.s)]

    var body: some View {
        let today = model.todayMetrics
        let targets = model.settings.nutrition
        LazyVGrid(columns: columns, spacing: Spacing.s) {
            NavigationLink { CategoryDetailView(category: .calorieTarget) } label: {
                MetricCard(title: "Calories", symbol: "flame", timeframe: "\(MeasureFormat.number(targets.calorieRange.lowerBound))–\(MeasureFormat.number(targets.calorieRange.upperBound)) kcal",
                           measurement: MeasureFormat.number(today.dietaryKilocalories), unit: "kcal",
                           progress: DailyGoals.progress(.calorieTarget, today, settings: model.settings), earned: nil,
                           earnedCaption: caption(.calorieTarget))
            }
            .buttonStyle(CardButtonStyle())

            NavigationLink { CategoryDetailView(category: .proteinTarget) } label: {
                MetricCard(title: "Protein", symbol: "fork.knife", timeframe: "Target \(targets.proteinGrams) g",
                           measurement: MeasureFormat.number(today.proteinGrams), unit: "g",
                           progress: DailyGoals.progress(.proteinTarget, today, settings: model.settings), earned: nil,
                           earnedCaption: caption(.proteinTarget))
            }
            .buttonStyle(CardButtonStyle())

            MetricCard(title: "Fat", symbol: "drop", timeframe: "Today",
                       measurement: MeasureFormat.number(today.fatGrams), unit: "g",
                       progress: nil, earned: nil, earnedCaption: "Tracked, not rewarded", showsChevron: false)

            MetricCard(title: "Carbs", symbol: "leaf", timeframe: "Today",
                       measurement: MeasureFormat.number(today.carbohydrateGrams), unit: "g",
                       progress: nil, earned: nil, earnedCaption: "Tracked, not rewarded", showsChevron: false)
        }
    }

    private func caption(_ category: RewardCategory) -> String {
        let reward = model.provisionalNutritionReward(category)
        return reward.isPositive ? "On track for +\(reward.formatted())" : "Confirmed after today"
    }
}

