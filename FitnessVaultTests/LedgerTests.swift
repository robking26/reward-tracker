import XCTest
@testable import FitnessVault

final class LedgerTests: XCTestCase {
    private let d1 = DayKey(year: 2026, month: 10, day: 1)
    private let d2 = DayKey(year: 2026, month: 10, day: 2)
    private let allocation = Pence.pounds(400)

    private func reconcile(_ existing: [LedgerLine], _ calculated: [DayKey: [RewardCategory: Pence]],
                           locked: Set<DayKey> = [], allocation: Pence? = nil) -> LedgerReconciler.Result {
        LedgerReconciler.reconcile(existing: existing, calculated: calculated, lockedDays: locked,
                                   allocation: allocation ?? self.allocation)
    }

    func testFirstSyncRecordsEarnings() {
        let result = reconcile([], [d1: [.steps: Pence(100), .flights: Pence(30)]])
        XCTAssertEqual(result.newLines.sum(\.amount), Pence(130))
        XCTAssertEqual(result.cappedAmount, .zero)
    }

    func testRepeatedSyncIsIdempotent() {
        let calculated: [DayKey: [RewardCategory: Pence]] = [d1: [.steps: Pence(100)]]
        let first = reconcile([], calculated)
        let second = reconcile(first.newLines, calculated)
        XCTAssertTrue(second.newLines.isEmpty, "Syncing the same data twice must not create money")
    }

    func testCumulativeProgressOnlyAddsTheDifference() {
        let first = reconcile([], [d1: [.steps: Pence(4)]])      // 249 steps
        let second = reconcile(first.newLines, [d1: [.steps: Pence(5)]]) // 250 steps
        XCTAssertEqual(second.newLines.map(\.amount), [Pence(1)])
        XCTAssertEqual((first.newLines + second.newLines).sum(\.amount), Pence(5))
    }

    func testDeletedSamplesCreateACorrection() {
        let first = reconcile([], [d1: [.strength: Pence(450)]])
        let second = reconcile(first.newLines, [d1: [.strength: .zero]])
        XCTAssertEqual(second.newLines.count, 1)
        XCTAssertEqual(second.newLines.first?.amount, Pence(-450))
        XCTAssertEqual(second.newLines.first?.kind, .correction)
    }

    func testLockedDaysNeverChange() {
        let first = reconcile([], [d1: [.steps: Pence(100)]])
        let second = reconcile(first.newLines, [d1: [.steps: Pence(500)]], locked: [d1])
        XCTAssertTrue(second.newLines.isEmpty)
    }

    func testMonthlyCapIsNeverExceeded() {
        let result = reconcile([], [d1: [.steps: .pounds(300)], d2: [.steps: .pounds(300)]])
        XCTAssertEqual(result.newLines.sum(\.amount), .pounds(400))
        XCTAssertEqual(result.cappedAmount, .pounds(200))
    }

    func testCappedMonthStaysCappedOnResync() {
        let calculated: [DayKey: [RewardCategory: Pence]] = [d1: [.steps: .pounds(500)]]
        let first = reconcile([], calculated)
        let second = reconcile(first.newLines, calculated)
        XCTAssertTrue(second.newLines.isEmpty)
        XCTAssertEqual(first.newLines.sum(\.amount), .pounds(400))
    }

    func testCorrectionsFreeAllocationForLaterActivity() {
        let first = reconcile([], [d1: [.steps: .pounds(400)]])
        let second = reconcile(first.newLines, [d1: [.steps: .pounds(350)], d2: [.flights: .pounds(100)]])
        let total = (first.newLines + second.newLines).sum(\.amount)
        XCTAssertEqual(total, .pounds(400))
    }

    func testLineIdentifiersAreStableAndUnique() {
        let first = reconcile([], [d1: [.steps: Pence(4)]])
        let second = reconcile(first.newLines, [d1: [.steps: Pence(5)]])
        let ids = (first.newLines + second.newLines).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids, ["2026-10/2026-10-01/steps/0", "2026-10/2026-10-01/steps/1"])
    }

    func testZeroAllocationPaysNothing() {
        let result = reconcile([], [d1: [.steps: Pence(100)]], allocation: .zero)
        XCTAssertTrue(result.newLines.isEmpty)
    }
}
