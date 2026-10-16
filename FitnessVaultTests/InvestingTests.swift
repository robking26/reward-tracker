import XCTest
@testable import FitnessVault

final class InvestingTests: XCTestCase {
    // MARK: Forfeited spending

    func testForfeitedIsTheUnearnedAllowance() {
        XCTAssertEqual(MonthEnd.forfeited(allocation: .pounds(500), finalEarned: .pounds(365)), .pounds(135))
        XCTAssertEqual(MonthEnd.forfeited(allocation: .pounds(500), finalEarned: .pounds(500)), .zero)
        XCTAssertEqual(MonthEnd.forfeited(allocation: .pounds(500), finalEarned: .zero), .pounds(500))
    }

    func testForfeitedIsNeverNegative() {
        XCTAssertEqual(MonthEnd.forfeited(allocation: .pounds(500), finalEarned: .pounds(510)), .zero)
    }

    func testMonthClosesOnlyAfterTheSecondAndAFreshSync() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let october = MonthKey(year: 2026, month: 10)
        let first = DayKey(year: 2026, month: 11, day: 1).startDate(calendar: calendar)
        let second = DayKey(year: 2026, month: 11, day: 2).startDate(calendar: calendar)
        let later = second.addingTimeInterval(3_600)

        XCTAssertFalse(MonthEnd.isReadyToClose(october, now: first, lastSuccessfulSync: first, calendar: calendar))
        XCTAssertFalse(MonthEnd.isReadyToClose(october, now: later, lastSuccessfulSync: first, calendar: calendar),
                       "A sync from before the 2nd may have missed late activity")
        XCTAssertFalse(MonthEnd.isReadyToClose(october, now: later, lastSuccessfulSync: nil, calendar: calendar))
        XCTAssertTrue(MonthEnd.isReadyToClose(october, now: later, lastSuccessfulSync: later, calendar: calendar))
    }

    // MARK: Order sizing

    func testQuantityForPencePrice() {
        // £135 at 3,500p a share with a 2% buffer: £132.30 / £35 = 3.78 shares.
        XCTAssertEqual(OrderSizing.quantity(cash: .pounds(135), price: 3_500, currencyCode: "GBX", minQuantity: Decimal(string: "0.01")!),
                       Decimal(string: "3.78"))
    }

    func testQuantityForPoundPrice() {
        XCTAssertEqual(OrderSizing.quantity(cash: .pounds(135), price: 35, currencyCode: "GBP", minQuantity: Decimal(string: "0.01")!),
                       Decimal(string: "3.78"))
    }

    func testQuantityNeverExceedsBudget() {
        let quantity = OrderSizing.quantity(cash: Pence(1_000), price: 333, currencyCode: "GBX", minQuantity: Decimal(string: "0.01")!)!
        XCTAssertLessThanOrEqual(quantity * 333, Decimal(1_000))
    }

    func testOtherCurrenciesAreNotTraded() {
        XCTAssertNil(OrderSizing.quantity(cash: .pounds(135), price: 40, currencyCode: "USD", minQuantity: 1))
    }

    func testBelowMinimumQuantityIsRejected() {
        XCTAssertNil(OrderSizing.quantity(cash: Pence(500), price: 3_500, currencyCode: "GBX", minQuantity: 1))
        XCTAssertNil(OrderSizing.quantity(cash: .zero, price: 3_500, currencyCode: "GBX", minQuantity: Decimal(string: "0.01")!))
    }

    func testPoundsToPenceRoundsDown() {
        XCTAssertEqual(OrderSizing.pence(fromPounds: Decimal(string: "132.4567")!), Pence(13_245))
    }

    // MARK: States

    func testUnresolvedOrdersBlockNewOrders() {
        XCTAssertTrue(InvestmentStatus.orderSubmitted.blocksNewOrders)
        XCTAssertTrue(InvestmentStatus.partiallyFilled.blocksNewOrders)
        XCTAssertTrue(InvestmentStatus.reconciliationRequired.blocksNewOrders)
        XCTAssertFalse(InvestmentStatus.cashAvailable.blocksNewOrders)
        XCTAssertFalse(InvestmentStatus.purchased.blocksNewOrders)
    }

    func testOnlyUnfundedAllocationsAreHeldInTheSpace() {
        XCTAssertTrue(InvestmentStatus.awaitingFunding.isStillInSpace)
        XCTAssertFalse(InvestmentStatus.fundingProcessing.isStillInSpace)
        XCTAssertFalse(InvestmentStatus.purchased.isStillInSpace)
    }
}

@MainActor
final class MonthEndSettlementTests: XCTestCase {
    private func makeModel(now: Date) -> AppModel {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.settings.demoMode = true
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return AppModel(container: Persistence.makeContainer(inMemory: true), settingsStore: settings,
                        calendar: calendar, now: { now })
    }

    func testMonthEndCreatesOneGoldAllocationForTheUnearnedAllowance() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = DayKey(year: 2026, month: 11, day: 3).startDate(calendar: calendar).addingTimeInterval(9 * 3_600)
        let model = makeModel(now: now)
        let october = MonthKey(year: 2026, month: 10)

        model.context.insert(MonthlyVault(month: october, allocation: .pounds(500), openingSpaceBalance: nil, plan: nil))
        model.context.insert(RewardLedgerEntry(line: LedgerLine(
            id: "test", day: DayKey(year: 2026, month: 10, day: 12), category: .steps, amount: .pounds(365), kind: .accrual)))
        model.syncState().lastSuccessfulSync = now

        model.closeFinishedMonths()
        model.closeFinishedMonths() // Idempotent: a second run changes nothing.

        let allocations = model.goldAllocationRecords()
        XCTAssertEqual(allocations.count, 1)
        XCTAssertEqual(allocations.first?.allocated, .pounds(135))
        XCTAssertEqual(allocations.first?.status, .awaitingFunding)
        let vault = model.vaults().first { $0.month == october.description }
        XCTAssertEqual(vault?.forfeitedPence, 13_500)
        XCTAssertEqual(vault?.finalEarnedPence, 36_500)
        XCTAssertNotNil(vault?.closedAt)
        XCTAssertEqual(model.syncState().finalisedThroughDay, DayKey(year: 2026, month: 10, day: 31),
                       "A closed month is locked so it can't change afterwards")
    }

    func testFullyEarnedMonthCreatesNoAllocation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = DayKey(year: 2026, month: 11, day: 3).startDate(calendar: calendar)
        let model = makeModel(now: now)
        let october = MonthKey(year: 2026, month: 10)
        model.context.insert(MonthlyVault(month: october, allocation: .pounds(500), openingSpaceBalance: nil, plan: nil))
        model.context.insert(RewardLedgerEntry(line: LedgerLine(
            id: "full", day: DayKey(year: 2026, month: 10, day: 12), category: .steps, amount: .pounds(500), kind: .accrual)))
        model.syncState().lastSuccessfulSync = now

        model.closeFinishedMonths()
        XCTAssertTrue(model.goldAllocationRecords().isEmpty)
    }

    func testDemoGoldPurchaseFlow() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let model = makeModel(now: DayKey(year: 2026, month: 11, day: 3).startDate(calendar: calendar))
        let allocation = GoldAllocation(month: MonthKey(year: 2026, month: 10), allocated: .pounds(135))
        model.context.insert(allocation)
        model.settingsStore.settings.trading212.instrument = GoldInstrument(
            ticker: "DEMOGOLD_EQ", name: "Physical Gold ETC (demo)", isin: nil, currencyCode: "GBX",
            minTradeQuantity: "0.01", confirmed: true)

        // Cash hasn't arrived at the broker: nothing can be bought.
        allocation.status = .fundingProcessing
        await model.refreshGold(allocation)
        XCTAssertEqual(allocation.status, .fundingProcessing)

        await (model.demoBroker as! MockInvestingService).state.deposit(.pounds(135))
        await model.refreshGold(allocation)
        XCTAssertEqual(allocation.status, .cashAvailable)

        try await model.placeGoldOrder(allocation, manualPrice: nil)
        XCTAssertEqual(allocation.status, .purchased)
        XCTAssertEqual(allocation.filledQuantity, "3.78")
        XCTAssertEqual(allocation.filledValuePence, 13_230)
        XCTAssertEqual(allocation.residual, Pence(270))

        // A second order for the same allocation is refused.
        do {
            try await model.placeGoldOrder(allocation, manualPrice: nil)
            XCTFail("Expected the second order to be refused")
        } catch {}
    }
}
