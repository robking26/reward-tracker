import XCTest
import SwiftData
@testable import FitnessVault

final class AccountabilityDomainTests: XCTestCase {
    func testMonthClosesOnTheThirdOfTheNextMonth() {
        let october = MonthKey(year: 2026, month: 10)
        XCTAssertEqual(MonthCloseRule.closesOn(october), DayKey(year: 2026, month: 11, day: 3))
        XCTAssertEqual(MonthCloseRule.closesOn(MonthKey(year: 2026, month: 12)), DayKey(year: 2027, month: 1, day: 3))
        XCTAssertFalse(MonthCloseRule.canClose(october, today: DayKey(year: 2026, month: 11, day: 2)),
                       "31 October can still be confirmed on 1 November")
        XCTAssertTrue(MonthCloseRule.canClose(october, today: DayKey(year: 2026, month: 11, day: 3)))
    }

    func testLedgerRecordsFirstReconciliationAndRealChangesOnly() {
        let first = FineLedger.change(wasFinalised: false, before: .zero, after: .zero, scorePercent: 90)
        XCTAssertEqual(first?.after, .zero, "A £0 day still gets an entry")
        XCTAssertEqual(first?.reason, "Day reconciled at 90%")
        XCTAssertNil(FineLedger.change(wasFinalised: true, before: .pounds(5), after: .pounds(5), scorePercent: 70))
        let corrected = FineLedger.change(wasFinalised: true, before: .pounds(15), after: .zero, scorePercent: 100)
        XCTAssertEqual(corrected?.before, .pounds(15))
        XCTAssertEqual(corrected?.after, .zero)
        XCTAssertTrue(corrected?.reason.contains("correction") ?? false)
    }

    private func day(_ d: Int, _ score: Int?, fine: Int, uncapped: Int? = nil) -> ScoredDay {
        ScoredDay(day: DayKey(year: 2026, month: 10, day: d), scorePercent: score, fine: .pounds(fine), uncappedFine: .pounds(uncapped ?? fine))
    }

    func testStatementIsAllocationMinusCappedFines() {
        let days = [day(20, 90, fine: 0), day(21, 50, fine: 10), day(22, 30, fine: 15), day(23, nil, fine: 0)]
        let summary = MonthStatementSummary(month: MonthKey(year: 2026, month: 10), days: days, allocation: .pounds(500), schedule: .trial)
        XCTAssertEqual(summary.fines, .pounds(25))
        XCTAssertEqual(summary.transferable, .pounds(475))
        XCTAssertEqual(summary.daysScored, 3, "A day with nothing agreed isn't scored")
        XCTAssertEqual(summary.daysWithFines, 2)
        XCTAssertEqual(summary.averageScore, 56)
    }

    func testStatementNeverExceedsTheCapOrTheAllocation() {
        // A corrupted record can't push the total past the cap.
        let days = (1...12).map { day($0, 10, fine: 15) }
        let summary = MonthStatementSummary(month: MonthKey(year: 2026, month: 10), days: days, allocation: .pounds(500), schedule: .trial)
        XCTAssertEqual(summary.fines, .pounds(100))
        XCTAssertEqual(summary.transferable, .pounds(400))
        let small = MonthStatementSummary(month: MonthKey(year: 2026, month: 10), days: days, allocation: .pounds(50), schedule: .trial)
        XCTAssertEqual(small.fines, .pounds(50), "Never more than the allocation")
        XCTAssertEqual(small.transferable, .zero, "No debt")
    }

    func testTransferPlanIsDescriptiveAndIdempotent() {
        let october = MonthKey(year: 2026, month: 10)
        let plan = TransferPlan(month: october, amount: .pounds(475), mode: .simulated)
        XCTAssertEqual(plan.idempotencyKey, TransferPlan(month: october, amount: .pounds(1), mode: .manual).idempotencyKey,
                       "One key per month, whatever the amount")
        XCTAssertTrue(plan.instruction.hasPrefix("Trial: no money moves."))
        XCTAssertTrue(plan.instruction.contains("£475.00"))
        XCTAssertTrue(plan.instruction.contains("stay in Starling"))
        let manual = TransferPlan(month: october, amount: .pounds(475), mode: .manual)
        XCTAssertTrue(manual.instruction.contains("yourself"))
        XCTAssertEqual(TransferPlan(month: october, amount: Pence(-100), mode: .manual).amount, .zero)
    }

    func testTrialReviewSummarisesWithoutPressure() {
        let days = (1...14).map { index in day(index, index <= 7 ? 85 : 45, fine: index <= 7 ? 0 : 10) }
        let outcomes = (0..<4).map { _ in TrialReview.Outcome(kind: .workout, state: .missed, assumedMissed: true) }
            + [TrialReview.Outcome(kind: .walk, state: .completed, assumedMissed: false),
               TrialReview.Outcome(kind: .walk, state: .excused, assumedMissed: false)]
        let review = TrialReview(days: days, outcomes: outcomes, schedule: .trial)
        XCTAssertTrue(review.isReady)
        XCTAssertEqual(review.daysScored, 14)
        XCTAssertEqual(review.averageScore, 65)
        XCTAssertEqual(review.bandCounts.map(\.label), ["80–100%", "60–79%", "40–59%", "Below 40%"])
        XCTAssertEqual(review.bandCounts.map(\.days), [7, 0, 7, 0])
        XCTAssertEqual(review.simulatedFines, .pounds(70))
        XCTAssertEqual(review.missedByKind.first?.kind, .workout)
        XCTAssertEqual(review.assumedMissed, 4)
        XCTAssertEqual(review.excused, 1)
        XCTAssertTrue(review.observations.contains { $0.contains("never answered") })
        XCTAssertTrue(review.observations.contains { $0.contains("Workout") })
        XCTAssertFalse(review.observations.joined().lowercased().contains("raise"), "Never suggests raising the stakes")
        XCTAssertFalse(TrialReview(days: Array(days.prefix(5)), outcomes: [], schedule: .trial).isReady)
    }
}

@MainActor
final class AccountabilityModelTests: XCTestCase {
    private var london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func at(_ day: DayKey, _ hour: Int) -> Date {
        day.startDate(calendar: london).addingTimeInterval(TimeInterval(hour * 3600))
    }

    private func makeCoach(_ clock: TestClock) -> CoachModel {
        let defaults = UserDefaults(suiteName: "accountability.test.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.settings.demoMode = true
        let demo = DemoCalendarService(calendar: london)
        return CoachModel(container: Persistence.makeContainer(inMemory: true), settingsStore: settings, liveCalendar: demo,
                          demoCalendar: demo, defaults: defaults, reminders: RecordingReminderScheduler(), languageModel: nil,
                          calendar: london, now: { clock.date })
    }

    func testLedgerKeepsEveryChange() async {
        let monday = DayKey(year: 2026, month: 10, day: 19)
        let clock = TestClock(at(monday, 7))
        let coach = makeCoach(clock)
        await coach.start()
        let walk = coach.addCommitment("Walk", kind: .walk, start: nil, durationMinutes: 30)
        clock.date = at(monday.adding(days: 2, calendar: london), 9)
        await coach.refresh()
        XCTAssertEqual(walk.state, .missed)
        var ledger = coach.fineLedger(in: monday.monthKey)
        XCTAssertEqual(ledger.count, 1)
        XCTAssertEqual(ledger.first?.after, .pounds(15))
        XCTAssertTrue(ledger.first?.isSimulation ?? false)

        clock.date = clock.date.addingTimeInterval(600)
        coach.transition(walk, .correct(to: .completed), reason: "I did walk")
        await coach.refresh()
        ledger = coach.fineLedger(in: monday.monthKey)
        XCTAssertEqual(ledger.count, 2, "The original fine stays in the ledger; the correction is added")
        XCTAssertEqual(ledger.first?.before, .pounds(15))
        XCTAssertEqual(ledger.first?.after, .zero)
    }

    func testMonthClosesFreezesAndSimulatesTheTransfer() async {
        let friday = DayKey(year: 2026, month: 10, day: 30)
        let clock = TestClock(at(friday, 7))
        let coach = makeCoach(clock)
        await coach.start()
        let gym = coach.addCommitment("Gym", kind: .workout, start: nil, durationMinutes: 90)

        clock.date = at(DayKey(year: 2026, month: 11, day: 2), 9)
        await coach.refresh()
        XCTAssertEqual(gym.state, .missed)
        XCTAssertNil(coach.statement(for: friday.monthKey), "Not before the 3rd")

        clock.date = at(DayKey(year: 2026, month: 11, day: 3), 9)
        await coach.refresh()
        let statement = coach.statement(for: friday.monthKey)
        XCTAssertNotNil(statement)
        XCTAssertEqual(statement?.fines, .pounds(15))
        XCTAssertEqual(statement?.transferable, .pounds(485))
        XCTAssertEqual(statement?.status, .simulated)
        XCTAssertEqual(statement?.idempotencyKey, "vaultality-month-2026-10")
        XCTAssertTrue(coach.accountabilityAudit().contains { $0.kind == "month.closed" })
        XCTAssertFalse(coach.confirmManualTransfer(statement!), "Nothing to confirm in the trial")

        XCTAssertFalse(coach.transition(gym, .correct(to: .completed), reason: "Too late"), "A closed month is final")
        XCTAssertEqual(gym.state, .missed)
        XCTAssertEqual(coach.dayRecord(friday)?.fine, .pounds(15))

        await coach.refresh()
        XCTAssertEqual(coach.statements().count, 1, "One statement per month")
    }

    func testLiveModeNeedsAManualConfirmationAndNeverPays() async {
        let friday = DayKey(year: 2026, month: 10, day: 30)
        let clock = TestClock(at(friday, 7))
        let coach = makeCoach(clock)
        await coach.start()
        coach.setFinesLive(true)
        XCTAssertFalse(coach.coach.finesAreSimulated)
        _ = coach.addCommitment("Walk", kind: .walk, start: nil, durationMinutes: 30)
        clock.date = at(DayKey(year: 2026, month: 11, day: 3), 9)
        await coach.refresh()
        let statement = coach.statement(for: friday.monthKey)!
        XCTAssertEqual(statement.status, .awaitingManualTransfer)
        XCTAssertTrue(statement.plan?.instruction.contains("yourself") ?? false)
        XCTAssertTrue(coach.confirmManualTransfer(statement))
        XCTAssertEqual(statement.status, .manuallyTransferred)
        XCTAssertFalse(coach.confirmManualTransfer(statement), "Recorded once")
        XCTAssertEqual(coach.accountabilityAudit().filter { $0.kind == "month.transfer.confirmed" }.count, 1)

        coach.setFinesLive(false)
        XCTAssertTrue(coach.coach.finesAreSimulated)
    }

    func testTrialReviewNeedsTwoWeeksOfData() async {
        let monday = DayKey(year: 2026, month: 10, day: 19)
        let clock = TestClock(at(monday, 7))
        let coach = makeCoach(clock)
        await coach.start()
        let walk = coach.addCommitment("Walk", kind: .walk, start: nil, durationMinutes: 30)
        coach.transition(walk, .complete)
        clock.date = at(monday.adding(days: 1, calendar: london), 9)
        await coach.refresh()
        let review = coach.trialReview()
        XCTAssertEqual(review.daysScored, 1)
        XCTAssertFalse(review.isReady)
        XCTAssertEqual(review.averageScore, 100)
    }
}
