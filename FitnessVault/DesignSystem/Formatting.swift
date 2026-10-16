import Foundation

/// Display formatting for measurements. Money formatting lives on `Pence`.
enum MeasureFormat {
    static func number(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func minutes(fromSeconds seconds: Int) -> String {
        number(seconds / 60)
    }

    static func distance(metres: Int) -> (String, String) {
        metres >= 1_000
            ? ((Double(metres) / 1_000).formatted(.number.precision(.fractionLength(2))), "km")
            : (number(metres), "m")
    }

    static func measurement(_ category: RewardCategory, _ metrics: DailyMetrics) -> (value: String, unit: String) {
        switch category {
        case .steps: (number(metrics.steps), "steps")
        case .exercise: (minutes(fromSeconds: metrics.exerciseSeconds), "min")
        case .strength: (minutes(fromSeconds: metrics.strengthSeconds), "min")
        case .activeEnergy: (number(metrics.activeKilocalories), "kcal")
        case .swimming: distance(metres: metrics.swimmingMetres)
        case .running: distance(metres: metrics.runningMetres)
        case .flights: (number(metrics.flightsClimbed), metrics.flightsClimbed == 1 ? "flight" : "flights")
        case .mealPhoto, .proteinTarget, .calorieTarget: ("–", "")
        }
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }
}
