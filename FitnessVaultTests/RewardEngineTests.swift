import XCTest
@testable import FitnessVault

final class RewardEngineTests: XCTestCase {
    private let day = DayKey(year: 2026, month: 10, day: 14)
    private let rates = RewardRates.standard

    private func reward(_ category: RewardCategory, _ configure: (inout DailyMetrics) -> Void) -> Pence {
        var metrics = DailyMetrics(day: day)
        configure(&metrics)
        return RewardEngine.rewards(for: metrics, rates: rates)[category] ?? .zero
    }

    // MARK: Steps

    func testStepsUpToBaselineEarnNothing() {
        XCTAssertEqual(reward(.steps) { $0.steps = 0 }, .zero)
        XCTAssertEqual(reward(.steps) { $0.steps = 2_500 }, .zero)
    }

    func testOnePennyPerFullTwentyStepsOverBaseline() {
        XCTAssertEqual(reward(.steps) { $0.steps = 2_501 }, .zero)
        XCTAssertEqual(reward(.steps) { $0.steps = 2_519 }, .zero)
        XCTAssertEqual(reward(.steps) { $0.steps = 2_520 }, Pence(1))
        XCTAssertEqual(reward(.steps) { $0.steps = 2_539 }, Pence(1))
        XCTAssertEqual(reward(.steps) { $0.steps = 2_540 }, Pence(2))
        XCTAssertEqual(reward(.steps) { $0.steps = 5_000 }, Pence(125))
        XCTAssertEqual(reward(.steps) { $0.steps = 12_500 }, .pounds(5))
    }

    func testStepsCappedAtTenPoundsADay() {
        XCTAssertEqual(rates.stepsForCap, 22_500)
        XCTAssertEqual(reward(.steps) { $0.steps = 22_499 }, Pence(999))
        XCTAssertEqual(reward(.steps) { $0.steps = 22_500 }, .pounds(10))
        XCTAssertEqual(reward(.steps) { $0.steps = 40_000 }, .pounds(10))
    }

    // MARK: Other activity

    func testSwimmingPaysThreePencePerFullTwentyFiveMetres() {
        XCTAssertEqual(reward(.swimming) { $0.swimmingMetres = 24 }, .zero)
        XCTAssertEqual(reward(.swimming) { $0.swimmingMetres = 25 }, Pence(3))
        XCTAssertEqual(reward(.swimming) { $0.swimmingMetres = 49 }, Pence(3))
        XCTAssertEqual(reward(.swimming) { $0.swimmingMetres = 1_500 }, Pence(180))
    }

    func testStrengthPaysOnePennyPerTwelveSeconds() {
        XCTAssertEqual(reward(.strength) { $0.strengthSeconds = 11 }, .zero)
        XCTAssertEqual(reward(.strength) { $0.strengthSeconds = 60 * 60 }, .pounds(3))
    }

    func testRunningPaysOnePennyPerTwentyMetres() {
        XCTAssertEqual(reward(.running) { $0.runningMetres = 19 }, .zero)
        XCTAssertEqual(reward(.running) { $0.runningMetres = 5_000 }, Pence(250))
    }

    func testGymSwimAndRunEarnSimilarAmounts() {
        func session(_ configure: (inout DailyMetrics) -> Void) -> Pence {
            var metrics = DailyMetrics(day: day)
            configure(&metrics)
            return RewardEngine.total(RewardEngine.rewards(for: metrics, rates: rates))
        }
        let gym = session { $0.strengthSeconds = 3_600; $0.exerciseSeconds = 2_700; $0.activeKilocalories = 350 }
        let swim = session { $0.swimmingMetres = 1_500; $0.exerciseSeconds = 2_400; $0.activeKilocalories = 400 }
        let run = session { $0.runningMetres = 5_000; $0.exerciseSeconds = 1_800; $0.activeKilocalories = 350 }
        XCTAssertEqual(gym, Pence(605))
        XCTAssertEqual(swim, Pence(460))
        XCTAssertEqual(run, Pence(465))
    }

    func testExercise() {
        XCTAssertEqual(reward(.exercise) { $0.exerciseSeconds = 30 * 60 }, Pence(180))
    }

    func testActiveEnergy() {
        XCTAssertEqual(reward(.activeEnergy) { $0.activeKilocalories = 400 }, Pence(40))
        XCTAssertEqual(reward(.activeEnergy) { $0.activeKilocalories = 409 }, Pence(40))
    }

    func testFlights() {
        // 5p per flight.
        XCTAssertEqual(reward(.flights) { $0.flightsClimbed = 1 }, Pence(5))
        XCTAssertEqual(reward(.flights) { $0.flightsClimbed = 12 }, Pence(60))
    }

    func testCategoriesStack() {
        var metrics = DailyMetrics(day: day)
        metrics.steps = 10_000
        metrics.exerciseSeconds = 1_800
        metrics.activeKilocalories = 500
        let total = RewardEngine.total(RewardEngine.rewards(for: metrics, rates: rates))
        XCTAssertEqual(total, Pence(375 + 180 + 50))
    }

    func testDeterministic() {
        var metrics = DailyMetrics(day: day)
        metrics.steps = 7_777
        metrics.strengthSeconds = 2_000
        XCTAssertEqual(RewardEngine.rewards(for: metrics, rates: rates), RewardEngine.rewards(for: metrics, rates: rates))
    }

    func testNegativeMeasurementsNeverPay() {
        XCTAssertEqual(reward(.steps) { $0.steps = -500 }, .zero)
        XCTAssertEqual(reward(.flights) { $0.flightsClimbed = -3 }, .zero)
    }

    // MARK: Retired nutrition categories

    func testRetiredCategoriesAlwaysCalculateToZero() {
        var metrics = DailyMetrics(day: day)
        metrics.steps = 20_000
        let rewards = RewardEngine.rewards(for: metrics, rates: rates)
        for category in [RewardCategory.mealPhoto, .proteinTarget, .calorieTarget] {
            XCTAssertEqual(rewards[category], .zero, "\(category) must be present and zero so old amounts are corrected")
            XCTAssertTrue(category.isRetired)
            XCTAssertFalse(rates.isRewarded(category))
        }
    }

    func testRetiredEarningsInUnlockedDaysAreCorrectedAway() {
        let existing = [LedgerLine(id: "x", day: day, category: .mealPhoto, amount: Pence(50), kind: .accrual)]
        let calculated = [day: RewardEngine.rewards(for: DailyMetrics(day: day), rates: rates)]
        let result = LedgerReconciler.reconcile(existing: existing, calculated: calculated, lockedDays: [], allocation: .pounds(400))
        XCTAssertEqual((existing + result.newLines).sum(\.amount), .zero)
    }

    // MARK: Settings and formatting

    func testSavedSettingsFromOlderVersionsStillLoad() throws {
        // Settings saved by earlier versions (with rates and nutrition fields) must still decode, keeping the Starling setup.
        let old = #"{"monthlyAllocation":{"value":40000},"rates":{"stepsPerPenny":50},"nutrition":{"proteinGrams":160,"minimumKilocalories":1900,"maximumKilocalories":2500},"settlementMinuteOfDay":480,"notificationsEnabled":true,"saveMealsToHealth":true,"keepMealThumbnails":true,"mealAnalysisMode":"remote","mealAnalysisEndpoint":"https://example.com/analyse","bankingEnvironment":"sandbox","liveTransfersConfirmed":false,"starling":{"accountUID":"acc"},"demoMode":false,"lockAfterDays":7}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.starling.accountUID, "acc")
        XCTAssertEqual(decoded.settlementMinuteOfDay, 480)
        XCTAssertEqual(decoded.monthlyAllocation, .pounds(500), "The old £400 default moves to Vaultality's £500")
        XCTAssertEqual(decoded.trading212.environment, .demo)
        XCTAssertEqual(decoded.rates, .standard, "Rates always come from code, never from saved settings")
    }

    func testVersion2SettingsAdoptTheEarningsCutoverAndKeepGoldOff() throws {
        let saved = #"{"monthlyAllocation":{"value":50000},"settingsVersion":2,"starling":{"accountUID":"acc"}}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(saved.utf8))
        XCTAssertEqual(decoded.activityEarningsEnd, DayKey(year: 2026, month: 10, day: 18))
        XCTAssertFalse(decoded.goldInvestingEnabled)
        XCTAssertEqual(decoded.coach, CoachSettings(), "Coach settings start from defaults")
        XCTAssertEqual(decoded.coach.fineSchedule.monthlyCap, .pounds(100))
        XCTAssertTrue(decoded.coach.finesAreSimulated, "Fines are virtual until the trial is reviewed")
    }

    func testWorkdaysUseIsoWeekdays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let coach = CoachSettings()
        XCTAssertTrue(coach.isWorkday(DayKey(year: 2026, month: 10, day: 19), calendar: calendar))  // Monday
        XCTAssertTrue(coach.isWorkday(DayKey(year: 2026, month: 10, day: 23), calendar: calendar))  // Friday
        XCTAssertFalse(coach.isWorkday(DayKey(year: 2026, month: 10, day: 24), calendar: calendar)) // Saturday
        XCTAssertFalse(coach.isWorkday(DayKey(year: 2026, month: 10, day: 25), calendar: calendar)) // Sunday
    }

    func testCustomAllowanceIsKeptOnUpgrade() throws {
        let old = #"{"monthlyAllocation":{"value":30000},"starling":{}}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.monthlyAllocation, .pounds(300))
    }

    func testSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.trading212.instrument = GoldInstrument(ticker: "SGLNl_EQ", name: "iShares Physical Gold", isin: nil,
                                                        currencyCode: "GBX", minTradeQuantity: "0.01", confirmed: true)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    func testPenceFormatting() {
        XCTAssertEqual(Pence(1_230).formatted(), "£12.30")
        XCTAssertEqual(Pence.pounds(400).formatted(), "£400.00")
    }
}
