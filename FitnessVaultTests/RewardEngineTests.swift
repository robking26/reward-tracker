import XCTest
@testable import FitnessVault

final class RewardEngineTests: XCTestCase {
    private let day = DayKey(year: 2026, month: 10, day: 14)
    private let rates = RewardRates.standard
    private let targets = NutritionTargets.standard

    private func reward(_ category: RewardCategory, _ configure: (inout DailyMetrics) -> Void, nutrition: Bool = true) -> Pence {
        var metrics = DailyMetrics(day: day)
        configure(&metrics)
        return RewardEngine.rewards(for: metrics, rates: rates, targets: targets, includeNutritionTargets: nutrition)[category] ?? .zero
    }

    // Examples from the specification, section 6.2.

    func testStepsUseWholeIntervalsOnly() {
        // 1p per 20 steps.
        XCTAssertEqual(reward(.steps) { $0.steps = 19 }, .zero)
        XCTAssertEqual(reward(.steps) { $0.steps = 20 }, Pence(1))
        XCTAssertEqual(reward(.steps) { $0.steps = 259 }, Pence(12))
        XCTAssertEqual(reward(.steps) { $0.steps = 10_000 }, Pence(500))
    }

    func testSwimming() {
        XCTAssertEqual(reward(.swimming) { $0.swimmingMetres = 1_000 }, .pounds(2))
        XCTAssertEqual(reward(.swimming) { $0.swimmingMetres = 4 }, .zero)
    }

    func testStrength() {
        XCTAssertEqual(reward(.strength) { $0.strengthSeconds = 45 * 60 }, Pence(450))
        XCTAssertEqual(reward(.strength) { $0.strengthSeconds = 5 }, .zero)
    }

    func testExercise() {
        XCTAssertEqual(reward(.exercise) { $0.exerciseSeconds = 30 * 60 }, Pence(180))
    }

    func testActiveEnergy() {
        XCTAssertEqual(reward(.activeEnergy) { $0.activeKilocalories = 400 }, Pence(40))
        XCTAssertEqual(reward(.activeEnergy) { $0.activeKilocalories = 409 }, Pence(40))
    }

    func testFlights() {
        // 2p per flight.
        XCTAssertEqual(reward(.flights) { $0.flightsClimbed = 12 }, Pence(24))
    }

    func testMealPhotosEarnNothing() {
        XCTAssertEqual(reward(.mealPhoto) { $0.rewardEligibleMeals = 3 }, .zero)
        XCTAssertFalse(rates.isRewarded(.mealPhoto))
    }

    func testMealPhotoCapStillHoldsIfRewardsReturn() {
        var paid = rates
        paid.pencePerMealPhoto = 50
        var metrics = DailyMetrics(day: day)
        metrics.rewardEligibleMeals = 7
        let rewards = RewardEngine.rewards(for: metrics, rates: paid, targets: targets, includeNutritionTargets: false)
        XCTAssertEqual(rewards[.mealPhoto], Pence(150))
    }

    func testProteinTarget() {
        XCTAssertEqual(reward(.proteinTarget) { $0.proteinGrams = 149 }, .zero)
        XCTAssertEqual(reward(.proteinTarget) { $0.proteinGrams = 150 }, .pounds(1))
    }

    func testCalorieTargetIsARangeNotAMinimum() {
        XCTAssertEqual(reward(.calorieTarget) { $0.dietaryKilocalories = 2_000 }, Pence(50))
        XCTAssertEqual(reward(.calorieTarget) { $0.dietaryKilocalories = 800 }, .zero, "Eating too little must never pay")
        XCTAssertEqual(reward(.calorieTarget) { $0.dietaryKilocalories = 3_500 }, .zero)
    }

    func testCalorieRangeCannotBeConfiguredBelowSafeMinimum() {
        let unsafe = NutritionTargets(proteinGrams: 100, minimumKilocalories: 500, maximumKilocalories: 900)
        XCTAssertGreaterThanOrEqual(unsafe.calorieRange.lowerBound, NutritionTargets.lowestAllowedMinimum)
    }

    func testNutritionTargetsWaitForTheDayToEnd() {
        XCTAssertEqual(reward(.proteinTarget, { $0.proteinGrams = 200 }, nutrition: false), .zero)
        XCTAssertEqual(reward(.calorieTarget, { $0.dietaryKilocalories = 2_000 }, nutrition: false), .zero)
    }

    func testMaximumDailyNutritionRewardIsOnePoundFifty() {
        var metrics = DailyMetrics(day: day)
        metrics.rewardEligibleMeals = 10
        metrics.proteinGrams = 300
        metrics.dietaryKilocalories = 2_200
        let rewards = RewardEngine.rewards(for: metrics, rates: rates, targets: targets, includeNutritionTargets: true)
        let nutrition = ([.mealPhoto] + RewardCategory.nutrition).sum { rewards[$0] ?? .zero }
        XCTAssertEqual(nutrition, Pence(150), "Protein £1 + calories 50p; meal photos earn nothing")
    }

    func testCategoriesStack() {
        var metrics = DailyMetrics(day: day)
        metrics.steps = 10_000
        metrics.exerciseSeconds = 1_800
        metrics.activeKilocalories = 500
        let total = RewardEngine.total(RewardEngine.rewards(for: metrics, rates: rates, targets: targets, includeNutritionTargets: false))
        XCTAssertEqual(total, Pence(500 + 180 + 50))
    }

    func testDeterministic() {
        var metrics = DailyMetrics(day: day)
        metrics.steps = 7_777
        metrics.strengthSeconds = 2_000
        let first = RewardEngine.rewards(for: metrics, rates: rates, targets: targets, includeNutritionTargets: true)
        let second = RewardEngine.rewards(for: metrics, rates: rates, targets: targets, includeNutritionTargets: true)
        XCTAssertEqual(first, second)
    }

    func testNegativeMeasurementsNeverPay() {
        XCTAssertEqual(reward(.steps) { $0.steps = -500 }, .zero)
        XCTAssertEqual(reward(.flights) { $0.flightsClimbed = -3 }, .zero)
    }

    func testPenceFormatting() {
        XCTAssertEqual(Pence(1_230).formatted(), "£12.30")
        XCTAssertEqual(Pence.pounds(400).formatted(), "£400.00")
    }
}
