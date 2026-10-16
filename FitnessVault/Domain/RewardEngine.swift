import Foundation

/// Cumulative totals for one calendar day. Measurements are whole units, truncated
/// (never rounded up) from Apple Health values.
struct DailyMetrics: Hashable, Sendable {
    var day: DayKey
    var steps = 0
    var swimmingMetres = 0
    var strengthSeconds = 0
    var exerciseSeconds = 0
    var activeKilocalories = 0
    var flightsClimbed = 0

    func measurement(for category: RewardCategory) -> Int {
        switch category {
        case .steps: steps
        case .exercise: exerciseSeconds
        case .strength: strengthSeconds
        case .activeEnergy: activeKilocalories
        case .swimming: swimmingMetres
        case .flights: flightsClimbed
        case .mealPhoto, .proteinTarget, .calorieTarget: 0
        }
    }
}

/// Pure, deterministic reward calculation. Calling it twice with the same input
/// always yields the same output, so repeated syncs can never create extra money.
enum RewardEngine {
    static func rewards(for metrics: DailyMetrics, rates: RewardRates) -> [RewardCategory: Pence] {
        var result: [RewardCategory: Pence] = [:]
        result[.steps] = stepsReward(metrics.steps, rates: rates)
        result[.swimming] = intervals(metrics.swimmingMetres, per: rates.swimmingMetresPerPenny)
        result[.strength] = intervals(metrics.strengthSeconds, per: rates.strengthSecondsPerPenny)
        result[.exercise] = intervals(metrics.exerciseSeconds, per: rates.exerciseSecondsPerPenny)
        result[.activeEnergy] = intervals(metrics.activeKilocalories, per: rates.activeKilocaloriesPerPenny)
        result[.flights] = Pence(max(0, metrics.flightsClimbed) * rates.pencePerFlight.value)
        // Retired categories always calculate to zero, so any unsettled amounts are corrected away.
        result[.mealPhoto] = .zero
        result[.proteinTarget] = .zero
        result[.calorieTarget] = .zero
        return result
    }

    static func total(_ rewards: [RewardCategory: Pence]) -> Pence {
        rewards.values.sum { $0 }
    }

    /// Nothing up to the baseline. Passing it earns 1p straight away; after that, 1p for each
    /// full 10 steps above the baseline (2,501-2,519 = 1p, 2,520 = 2p), up to the daily cap.
    static func stepsReward(_ steps: Int, rates: RewardRates) -> Pence {
        let beyond = steps - max(0, rates.stepsBaseline)
        guard beyond > 0, rates.stepsPerPenny > 0 else { return .zero }
        let earned = Swift.max(Pence(1), intervals(beyond, per: rates.stepsPerPenny))
        return Swift.min(earned, rates.stepsDailyCap.nonNegative)
    }

    /// Whole completed intervals only. 249 steps at 1p/50 = 4p.
    static func intervals(_ measurement: Int, per interval: Int) -> Pence {
        guard interval > 0, measurement > 0 else { return .zero }
        return Pence(measurement / interval)
    }
}
