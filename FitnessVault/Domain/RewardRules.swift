import Foundation

/// Every independent reward ledger. Activities stack across categories but never within one.
enum RewardCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case steps
    case exercise
    case strength
    case activeEnergy
    case swimming
    case flights
    // Retired: nutrition is no longer part of the app. These cases remain so older ledger
    // entries still load and any unsettled amounts are corrected back to zero.
    case mealPhoto
    case proteinTarget
    case calorieTarget

    var id: String { rawValue }

    /// The categories that earn money.
    static let activity: [RewardCategory] = [.steps, .exercise, .strength, .activeEnergy, .swimming, .flights]

    var isRetired: Bool { !Self.activity.contains(self) }

    var title: String {
        switch self {
        case .steps: "Steps"
        case .exercise: "Exercise"
        case .strength: "Strength"
        case .activeEnergy: "Active Energy"
        case .swimming: "Swimming"
        case .flights: "Flights Climbed"
        case .mealPhoto: "Meal Photos (retired)"
        case .proteinTarget: "Protein Target (retired)"
        case .calorieTarget: "Calorie Target (retired)"
        }
    }

    var symbol: String {
        switch self {
        case .steps: "figure.walk"
        case .exercise: "figure.run"
        case .strength: "dumbbell.fill"
        case .activeEnergy: "flame.fill"
        case .swimming: "figure.pool.swim"
        case .flights: "figure.stairs"
        case .mealPhoto, .proteinTarget, .calorieTarget: "archivebox"
        }
    }
}

/// Reward rates. Each rate is "one penny per N units" or a fixed amount.
struct RewardRates: Codable, Hashable, Sendable {
    var stepsPerPenny = 10
    /// Steps up to this many each day earn nothing. Passing it earns 1p, then 1p per full 10 steps beyond it.
    var stepsBaseline = 2_500
    /// The most steps can earn in a day.
    var stepsDailyCap: Pence = 1_000
    var swimmingMetresPerPenny = 5
    var strengthSecondsPerPenny = 6
    var exerciseSecondsPerPenny = 10
    var activeKilocaloriesPerPenny = 10
    var pencePerFlight: Pence = 2

    /// The current rates. Days that are already final keep the rates they were calculated with.
    static let standard = RewardRates()

    /// The step count at which the daily steps cap is reached.
    var stepsForCap: Int { stepsBaseline + Swift.max(1, stepsDailyCap.value) * stepsPerPenny }

    /// Whether a category currently earns anything.
    func isRewarded(_ category: RewardCategory) -> Bool {
        switch category {
        case .flights: pencePerFlight.isPositive
        case .mealPhoto, .proteinTarget, .calorieTarget: false
        default: true
        }
    }

    func rateDescription(for category: RewardCategory) -> String {
        switch category {
        case .steps: "1p per \(stepsPerPenny) steps over \(stepsBaseline.formatted()), up to \(stepsDailyCap.formatted()) a day"
        case .swimming: "1p per \(swimmingMetresPerPenny) m"
        case .strength: "1p per \(strengthSecondsPerPenny) seconds"
        case .exercise: "1p per \(exerciseSecondsPerPenny) seconds"
        case .activeEnergy: "1p per \(activeKilocaloriesPerPenny) kcal"
        case .flights: "\(pencePerFlight.formatted()) per flight"
        case .mealPhoto, .proteinTarget, .calorieTarget: "No longer rewarded"
        }
    }
}
