import XCTest
@testable import FitnessVault

final class SettlementTests: XCTestCase {
    typealias Transfer = (amount: Pence, status: TransferStatus)
    typealias Payment = (amount: Pence, status: PaymentStatus)

    // MARK: Releases

    func testReleasesAreBatched() {
        XCTAssertEqual(SettlementPlanner.releaseAmount(earned: Pence(80), transfers: [], spaceBalance: .pounds(400), force: false), .zero)
        XCTAssertEqual(SettlementPlanner.releaseAmount(earned: Pence(250), transfers: [], spaceBalance: .pounds(400), force: false), Pence(250))
    }

    func testSettlementReleasesAnyPositiveAmount() {
        XCTAssertEqual(SettlementPlanner.releaseAmount(earned: Pence(80), transfers: [], spaceBalance: .pounds(400), force: true), Pence(80))
    }

    func testReleaseNeverExceedsSpaceBalance() {
        XCTAssertEqual(SettlementPlanner.releaseAmount(earned: .pounds(50), transfers: [], spaceBalance: .pounds(20), force: true), .pounds(20))
    }

    func testPendingAndConfirmedTransfersAreNotReleasedTwice() {
        let transfers: [Transfer] = [(.pounds(10), .confirmed), (.pounds(5), .requested), (.pounds(3), .failed)]
        XCTAssertEqual(SettlementPlanner.releaseAmount(earned: .pounds(20), transfers: transfers, spaceBalance: .pounds(400), force: true), .pounds(5))
    }

    func testCorrectionsNeverProduceNegativeRelease() {
        let transfers: [Transfer] = [(.pounds(10), .confirmed)]
        XCTAssertEqual(SettlementPlanner.releaseAmount(earned: .pounds(8), transfers: transfers, spaceBalance: .pounds(400), force: true), .zero)
    }

    // MARK: Payments

    func testPaysOnlyFinalisedReleasedEarnings() {
        let decision = SettlementPlanner.paymentDecision(
            settleableEarned: .pounds(12), releasedConfirmed: .pounds(10), payments: [], mainBalance: .pounds(100))
        XCTAssertEqual(decision, .pay(.pounds(10)))
    }

    func testAwaitingApprovalBlocksANewPayment() {
        let payments: [Payment] = [(.pounds(10), .awaitingApproval)]
        let decision = SettlementPlanner.paymentDecision(
            settleableEarned: .pounds(30), releasedConfirmed: .pounds(30), payments: payments, mainBalance: .pounds(100))
        XCTAssertEqual(decision, .blockedByUnresolvedPayment, "A missed approval must not create a second payment")
    }

    func testUnknownOutcomeBlocksANewPayment() {
        let payments: [Payment] = [(.pounds(10), .reconciliationRequired)]
        let decision = SettlementPlanner.paymentDecision(
            settleableEarned: .pounds(30), releasedConfirmed: .pounds(30), payments: payments, mainBalance: .pounds(100))
        XCTAssertEqual(decision, .blockedByUnresolvedPayment)
    }

    func testPaidEarningsAreNotPaidAgain() {
        let payments: [Payment] = [(.pounds(10), .paid)]
        XCTAssertEqual(SettlementPlanner.paymentDecision(
            settleableEarned: .pounds(10), releasedConfirmed: .pounds(10), payments: payments, mainBalance: .pounds(100)),
                       .nothingToPay)
        XCTAssertEqual(SettlementPlanner.paymentDecision(
            settleableEarned: .pounds(14), releasedConfirmed: .pounds(14), payments: payments, mainBalance: .pounds(100)),
                       .pay(.pounds(4)))
    }

    func testRejectedPaymentsAreRetriedInTheNextPayment() {
        let payments: [Payment] = [(.pounds(10), .rejected), (.pounds(5), .paid)]
        XCTAssertEqual(SettlementPlanner.paymentDecision(
            settleableEarned: .pounds(15), releasedConfirmed: .pounds(15), payments: payments, mainBalance: .pounds(100)),
                       .pay(.pounds(10)))
    }

    func testPaymentNeverExceedsMainBalance() {
        XCTAssertEqual(SettlementPlanner.paymentDecision(
            settleableEarned: .pounds(50), releasedConfirmed: .pounds(50), payments: [], mainBalance: .pounds(7)),
                       .pay(.pounds(7)))
    }

    // MARK: Money flow

    func testMoneyFlowSeparatesStates() {
        let flow = MoneyFlow(
            earned: .pounds(40),
            transfers: [(.pounds(30), .confirmed), (.pounds(5), .requested)],
            payments: [(.pounds(10), .paid), (.pounds(8), .awaitingApproval), (.pounds(2), .failed)])
        XCTAssertEqual(flow.released, .pounds(30))
        XCTAssertEqual(flow.releasing, .pounds(5))
        XCTAssertEqual(flow.awaitingRelease, .pounds(5))
        XCTAssertEqual(flow.paid, .pounds(10))
        XCTAssertEqual(flow.awaitingApproval, .pounds(8))
        XCTAssertEqual(flow.failedOrRejected, .pounds(2))
    }

    func testOnlyBankConfirmedPaymentsCountAsPaid() {
        let flow = MoneyFlow(earned: .pounds(10), transfers: [],
                             payments: [(.pounds(10), .processing), (.pounds(3), .reconciliationRequired)])
        XCTAssertEqual(flow.paid, .zero)
    }

    // MARK: Vault funding

    func testOnlyTheShortfallIsToppedUp() {
        let plan = VaultFunding.plan(allocation: .pounds(400), spaceBalance: .pounds(150))
        XCTAssertEqual(plan.carriedForward, .pounds(150))
        XCTAssertEqual(plan.topUpRequired, .pounds(250))
        XCTAssertEqual(plan.heldBeyondAllocation, .zero)
    }

    func testSurplusIsHeldSeparately() {
        let plan = VaultFunding.plan(allocation: .pounds(400), spaceBalance: .pounds(520))
        XCTAssertEqual(plan.topUpRequired, .zero)
        XCTAssertEqual(plan.carriedForward, .pounds(400))
        XCTAssertEqual(plan.heldBeyondAllocation, .pounds(120))
    }

    func testPendingReleasesAreNotCountedAsAvailable() {
        let plan = VaultFunding.plan(allocation: .pounds(400), spaceBalance: .pounds(400), reservedForPendingReleases: .pounds(25))
        XCTAssertEqual(plan.topUpRequired, .pounds(25))
    }

    // MARK: Vault summary

    func testVaultSummary() {
        let summary = VaultSummary(month: MonthKey(year: 2026, month: 10), allocation: .pounds(400), earned: Pence(10_050))
        XCTAssertEqual(summary.remainingToUnlock, Pence(29_950))
        XCTAssertEqual(summary.percentUnlocked, 25)
        XCTAssertFalse(summary.isFullyUnlocked)
        XCTAssertTrue(VaultSummary(month: summary.month, allocation: .pounds(400), earned: .pounds(400)).isFullyUnlocked)
    }
}
