import Foundation

/// Every independent reward ledger. Activities stack across categories but never within one.
enum RewardCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case steps
    case exercise
    case strength
    case activeEnergy
    case swimming
    case flights
    case mealPhoto
    case proteinTarget
    case calorieTarget

    var id: String { rawValue }

    static let activity: [RewardCategory] = [.steps, .exercise, .strength, .activeEnergy, .swimming, .flights]
    static let nutrition: [RewardCategory] = [.proteinTarget, .calorieTarget]

    var title: String {
        switch self {
        case .steps: "Steps"
        case .exercise: "Exercise"
        case .strength: "Strength"
        case .activeEnergy: "Active Energy"
        case .swimming: "Swimming"
        case .flights: "Flights Climbed"
        case .mealPhoto: "Meal Photos"
        case .proteinTarget: "Protein Target"
        case .calorieTarget: "Calorie Target"
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
        case .mealPhoto: "camera.fill"
        case .proteinTarget: "fork.knife"
        case .calorieTarget: "chart.bar.fill"
        }
    }

    /// Whether this category is rewarded only once the day's logging window has closed.
    var settlesAfterDayEnds: Bool {
        self == .proteinTarget || self == .calorieTarget
    }
}

/// Reward rates. Each rate is "one penny per N units" or a fixed amount, so every reward
/// is a whole number of completed intervals and partial progress is never rounded up.
struct RewardRates: Codable, Hashable, Sendable {
    var stepsPerPenny = 10
    /// Steps up to this many each day earn nothing; only steps beyond it count.
    var stepsBaseline = 2_500
    /// The most steps can earn in a day.
    var stepsDailyCap: Pence = 1_000
    var swimmingMetresPerPenny = 5
    var strengthSecondsPerPenny = 6
    var exerciseSecondsPerPenny = 10
    var activeKilocaloriesPerPenny = 10
    var pencePerFlight: Pence = 2
    /// Meal photos are logged for nutrition but earn nothing.
    var pencePerMealPhoto: Pence = 0
    var maxRewardedMealPhotosPerDay = 3
    var proteinTargetReward: Pence = 100
    var calorieTargetReward: Pence = 50

    /// The current rates. Days that are already final keep the rates they were calculated with.
    static let standard = RewardRates()

    /// The step count at which the daily steps cap is reached.
    var stepsForCap: Int { stepsBaseline + stepsDailyCap.value * stepsPerPenny }

    /// Whether a category currently earns anything.
    func isRewarded(_ category: RewardCategory) -> Bool {
        switch category {
        case .mealPhoto: pencePerMealPhoto.isPositive && maxRewardedMealPhotosPerDay > 0
        case .flights: pencePerFlight.isPositive
        case .proteinTarget: proteinTargetReward.isPositive
        case .calorieTarget: calorieTargetReward.isPositive
        default: true
        }
    }

    func rateDescription(for category: RewardCategory) -> String {
        switch category {
        case .steps: "1p per \(stepsPerPenny) steps after \(stepsBaseline.formatted()), up to \(stepsDailyCap.formatted()) a day"
        case .swimming: "1p per \(swimmingMetresPerPenny) m"
        case .strength: "1p per \(strengthSecondsPerPenny) seconds"
        case .exercise: "1p per \(exerciseSecondsPerPenny) seconds"
        case .activeEnergy: "1p per \(activeKilocaloriesPerPenny) kcal"
        case .flights: "\(pencePerFlight.formatted()) per flight"
        case .mealPhoto: pencePerMealPhoto.isPositive
            ? "\(pencePerMealPhoto.formatted()) per meal, up to \(maxRewardedMealPhotosPerDay) a day"
            : "Not rewarded"
        case .proteinTarget: "\(proteinTargetReward.formatted()) when reached"
        case .calorieTarget: "\(calorieTargetReward.formatted()) when within range"
        }
    }
}

/// User-defined nutrition targets. Calories use a range so the app never rewards
/// eating as little as possible.
struct NutritionTargets: Codable, Hashable, Sendable {
    var proteinGrams = 150
    var minimumKilocalories = 1_900
    var maximumKilocalories = 2_500

    static let standard = NutritionTargets()

    /// A guard against configuring an unsafe calorie range.
    static let lowestAllowedMinimum = 1_200

    var calorieRange: ClosedRange<Int> {
        let lower = max(minimumKilocalories, Self.lowestAllowedMinimum)
        return lower...max(lower, maximumKilocalories)
    }
}
