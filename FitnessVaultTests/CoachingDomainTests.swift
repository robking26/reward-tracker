import XCTest
@testable import FitnessVault

final class CommitmentRulesTests: XCTestCase {
    func testHappyPath() throws {
        var state = CommitmentState.proposed
        state = try CommitmentRules.apply(.approve, to: state)
        XCTAssertEqual(state, .approved)
        state = try CommitmentRules.apply(.start, to: state)
        XCTAssertEqual(state, .inProgress)
        state = try CommitmentRules.apply(.complete, to: state)
        XCTAssertEqual(state, .completed)
    }

    func testCancelOnlyBeforeAgreement() {
        XCTAssertTrue(CommitmentRules.canApply(.cancel, to: .proposed))
        XCTAssertFalse(CommitmentRules.canApply(.cancel, to: .approved),
                       "Once agreed, a commitment is moved or excused with a reason, never quietly cancelled")
    }

    func testAMissCannotBeRescheduledAway() {
        XCTAssertFalse(CommitmentRules.canApply(.rescheduleLaterToday, to: .missed))
        XCTAssertFalse(CommitmentRules.canApply(.rescheduleToAnotherDay(.calendarConflict), to: .missed))
    }

    func testDayEndNeverMarksMissedDirectly() throws {
        XCTAssertEqual(try CommitmentRules.apply(.dayEnded, to: .approved), .pendingVerification,
                       "Silence isn't proof of a miss")
        XCTAssertEqual(try CommitmentRules.apply(.verificationExpired, to: .pendingVerification), .missed)
    }

    func testCorrectionsAreAllowedUntilTheMonthCloses() throws {
        XCTAssertEqual(try CommitmentRules.apply(.correct(to: .completed), to: .missed), .completed)
        XCTAssertEqual(try CommitmentRules.apply(.correct(to: .missed), to: .completed), .missed)
        XCTAssertThrowsError(try CommitmentRules.apply(.correct(to: .completed), to: .missed, monthClosed: true))
        XCTAssertFalse(CommitmentRules.canApply(.correct(to: .approved), to: .missed))
    }

    func testWeightIsFrozenOnceAgreed() {
        XCTAssertTrue(CommitmentRules.canChangeWeight(in: .proposed))
        XCTAssertFalse(CommitmentRules.canChangeWeight(in: .approved))
        XCTAssertEqual(CommitmentRules.clampedWeight(9), 5)
        XCTAssertEqual(CommitmentRules.clampedWeight(0), 1)
    }

    func testNotFancyingItIsNotAnExcuse() {
        // Scenario C: the excuse list only holds legitimate reasons.
        XCTAssertEqual(Set(ExcuseReason.allCases),
                       [.illness, .injurySymptoms, .restOrRecovery, .sleep, .calendarConflict, .outsideControl])
    }
}

final class DayScoringTests: XCTestCase {
    private let schedule = FineSchedule.trial
    private let allocation = Pence.pounds(500)

    private func item(_ state: CommitmentState, _ weight: Int) -> ScoredCommitment {
        ScoredCommitment(state: state, weight: weight)
    }

    func testBands() {
        XCTAssertEqual(schedule.fine(forPercent: 100), .zero)
        XCTAssertEqual(schedule.fine(forPercent: 80), .zero)
        XCTAssertEqual(schedule.fine(forPercent: 79), .pounds(5))
        XCTAssertEqual(schedule.fine(forPercent: 60), .pounds(5))
        XCTAssertEqual(schedule.fine(forPercent: 59), .pounds(10))
        XCTAssertEqual(schedule.fine(forPercent: 40), .pounds(10))
        XCTAssertEqual(schedule.fine(forPercent: 39), .pounds(15))
        XCTAssertEqual(schedule.fine(forPercent: 0), .pounds(15))
    }

    func testOnlyApplicableCommitmentsCount() {
        let score = DayScore([item(.completed, 4), item(.excused, 4), item(.rescheduled, 2),
                              item(.cancelled, 1), item(.proposed, 3), item(.missed, 1)])
        XCTAssertEqual(score.applicableWeight, 5)
        XCTAssertEqual(score.confirmedPercent, 80)
    }

    func testEveningRoutineKeepsTheDayOpen() {
        // Scenario J: everything in the daytime is done, the evening routine is still due.
        let score = DayScore([item(.completed, 4), item(.completed, 2), item(.approved, 2)])
        XCTAssertEqual(score.confirmedPercent, 75, "Must not show 100% while the evening routine is due")
        XCTAssertEqual(score.possiblePercent, 100)
        XCTAssertFalse(score.isSettled)
        let projection = DayProjection(score: score, schedule: schedule, monthToDateFines: .zero, allocation: allocation)
        XCTAssertEqual(projection.bestCaseFine, .zero)
        XCTAssertEqual(projection.worstCaseFine, .pounds(5))
    }

    func testEmptyDayHasNoScoreAndNoFine() {
        let outcome = DayReconciliation.finalise([], schedule: schedule, monthToDateFines: .zero, allocation: allocation)
        XCTAssertNil(outcome.scorePercent)
        XCTAssertEqual(outcome.fine, .zero)
    }

    func testIllnessIsNeverFined() {
        // Scenario O: everything excused, nothing applicable.
        let outcome = DayReconciliation.finalise([item(.excused, 4), item(.excused, 2)], schedule: schedule,
                                                 monthToDateFines: .zero, allocation: allocation)
        XCTAssertEqual(outcome.fine, .zero)
    }

    func testCalendarConflictRemovesTheWorkoutFromTheScore() throws {
        // Scenario B: the gym is excused for an unavoidable meeting; the walk was done.
        let gym = try CommitmentRules.apply(.excuse(.calendarConflict), to: .approved)
        let outcome = DayReconciliation.finalise([item(gym, 4), item(.completed, 2)], schedule: schedule,
                                                 monthToDateFines: .zero, allocation: allocation)
        XCTAssertEqual(outcome.scorePercent, 100)
        XCTAssertEqual(outcome.fine, .zero)
    }

    func testMonthlyCapIsNeverExceeded() {
        // Scenario K.
        XCTAssertEqual(schedule.cappedFine(.pounds(15), monthToDate: .pounds(90), allocation: allocation), .pounds(10))
        XCTAssertEqual(schedule.cappedFine(.pounds(15), monthToDate: .pounds(100), allocation: allocation), .zero)
        XCTAssertEqual(schedule.cappedFine(.pounds(15), monthToDate: .pounds(120), allocation: allocation), .zero,
                       "Never negative, even if the cap was lowered mid-month")
        XCTAssertEqual(schedule.cappedFine(.pounds(15), monthToDate: .zero, allocation: .pounds(8)), .pounds(8),
                       "Never more than the allocation")

        var total = Pence.zero
        for _ in 0..<31 {
            let outcome = DayReconciliation.finalise([item(.missed, 4)], schedule: schedule,
                                                     monthToDateFines: total, allocation: allocation)
            total = total + outcome.fine
        }
        XCTAssertEqual(total, .pounds(100))
    }

    func testCapExplanation() {
        let outcome = DayReconciliation.finalise([item(.missed, 4)], schedule: schedule,
                                                 monthToDateFines: .pounds(100), allocation: allocation)
        XCTAssertEqual(outcome.uncappedFine, .pounds(15))
        XCTAssertEqual(outcome.fine, .zero)
        XCTAssertTrue(outcome.explanation.contains("cap"))
    }

    func testTransferEstimate() {
        let projection = DayProjection(score: DayScore([item(.completed, 2)]), schedule: schedule,
                                       monthToDateFines: .pounds(20), allocation: allocation)
        XCTAssertEqual(projection.transferEstimate, .pounds(480))
    }
}

final class AvailabilityTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    private let day = DayKey(year: 2026, month: 10, day: 21) // A Wednesday

    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        day.startDate(calendar: calendar).addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    private func block(_ start: (Int, Int), _ end: (Int, Int), _ kind: BlockKind) -> BusyBlock {
        BusyBlock(interval: DateInterval(start: time(start.0, start.1), end: time(end.0, end.1)), kind: kind)
    }

    func testWorkHoursAreNotFreeTime() {
        let windows = Availability.windows(on: day, shape: DayShape(), blocks: [], calendar: calendar)
        let gym = ActivityNeed(activeMinutes: 60, travelMinutesEachWay: 15, preparationMinutes: 10)
        let fit = Availability.firstFit(gym, in: windows)
        XCTAssertEqual(fit?.kind, .free)
        XCTAssertEqual(fit?.interval.start, time(5, 55), "Before work is the first free time")
    }

    func testLunchWalkFitsButGymDoesNot() {
        let windows = Availability.windows(on: day, shape: DayShape(), blocks: [], notBefore: time(9), calendar: calendar)
        let walk = ActivityNeed(activeMinutes: 30, preparationMinutes: 5, allowedKinds: [.lunch])
        XCTAssertEqual(Availability.firstFit(walk, in: windows)?.kind, .lunch)
        let gym = ActivityNeed(activeMinutes: 50, travelMinutesEachWay: 15, preparationMinutes: 10, allowedKinds: [.lunch])
        XCTAssertNil(Availability.firstFit(gym, in: windows),
                     "An hour-long gym trip doesn't fit an hour's lunch once travel is included")
    }

    func testFocusBlocksAreProtectedAndGapsOnlyHoldShortTasks() {
        let blocks = [block((13, 0), (16, 0), .workFocus), block((9, 0), (9, 50), .workMeeting)]
        let windows = Availability.windows(on: day, shape: DayShape(), blocks: blocks, notBefore: time(8), calendar: calendar)
        XCTAssertFalse(windows.contains { $0.interval.intersects(DateInterval(start: time(13, 30), end: time(14))) && $0.kind != .free })
        let laundry = ActivityNeed(activeMinutes: 5, allowedKinds: [.workGap])
        XCTAssertEqual(Availability.firstFit(laundry, in: windows)?.interval.start, time(8))
        let decorating = ActivityNeed(activeMinutes: 30, allowedKinds: [.workGap])
        XCTAssertNil(Availability.firstFit(decorating, in: windows), "Work gaps only hold short tasks")
    }

    func testBeckysEventsDontMakeTheUserBusy() {
        let blocks = [block((18, 0), (19, 0), .sharedInfo)]
        let windows = Availability.windows(on: day, shape: DayShape(), blocks: blocks, notBefore: time(16), calendar: calendar)
        XCTAssertEqual(windows.first?.interval, DateInterval(start: time(16), end: time(22, 30)))
    }

    func testNewMeetingRemovesTheGymSlot() {
        // Scenario B: a 16:00–17:00 meeting appears over the planned 16:00 gym.
        let gym = ActivityNeed(activeMinutes: 60, travelMinutesEachWay: 15, preparationMinutes: 10)
        let before = Availability.windows(on: day, shape: DayShape(), blocks: [], notBefore: time(15), calendar: calendar)
        XCTAssertEqual(Availability.firstFit(gym, in: before)?.interval.start, time(16))
        let after = Availability.windows(on: day, shape: DayShape(), blocks: [block((16, 0), (17, 0), .workMeeting)],
                                         notBefore: time(15), calendar: calendar)
        XCTAssertEqual(Availability.firstFit(gym, in: after)?.interval.start, time(17))
    }

    func testWeekendHasNoWorkProtection() {
        var shape = DayShape()
        shape.isWorkday = false
        let windows = Availability.windows(on: day, shape: shape, blocks: [], notBefore: time(10), calendar: calendar)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.kind, .free)
    }

    func testSubtractSplitsAroundBlocks() {
        let whole = DateInterval(start: time(8), end: time(12))
        let pieces = Availability.subtract([DateInterval(start: time(9), end: time(10)),
                                            DateInterval(start: time(11), end: time(13))], from: whole)
        XCTAssertEqual(pieces, [DateInterval(start: time(8), end: time(9)), DateInterval(start: time(10), end: time(11))])
    }
}

final class CalendarClassifierTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(_ title: String, calendar: String, allDay: Bool = false, free: Bool = false) -> CalendarEventInfo {
        CalendarEventInfo(id: UUID().uuidString, calendarID: calendar, title: title, start: start,
                          end: start.addingTimeInterval(3_600), isAllDay: allDay, showsAsFree: free)
    }

    private let roles: [String: CalendarRole] = ["work": .work, "home": .personal, "becky": .shared, "junk": .ignored]

    func testKinds() {
        let classified = CalendarClassifier.classify([
            event("Sprint review", calendar: "work"),
            event("Focus time", calendar: "work"),
            event("Dentist", calendar: "home"),
            event("Nails", calendar: "becky"),
            event("Bank holiday", calendar: "home", allDay: true),
            event("Spam", calendar: "junk"),
            event("Unlabelled", calendar: "unknown"),
            event("Optional social", calendar: "work", free: true),
        ], roles: roles)
        let kinds = Dictionary(uniqueKeysWithValues: classified.map { ($0.event.title, $0.kind) })
        XCTAssertEqual(kinds["Sprint review"], .workMeeting)
        XCTAssertEqual(kinds["Focus time"], .workFocus)
        XCTAssertEqual(kinds["Dentist"], .personal)
        XCTAssertEqual(kinds["Nails"], .sharedInfo)
        XCTAssertEqual(kinds["Bank holiday"], .allDayInfo)
        XCTAssertEqual(kinds["Optional social"], .allDayInfo)
        XCTAssertNil(kinds["Spam"])
        XCTAssertNil(kinds["Unlabelled"], "Unlabelled calendars are never guessed")
    }

    func testWorkLocationComesFromTheCalendar() {
        let office = CalendarClassifier.classify([event("In office", calendar: "work", allDay: true)], roles: roles)
        XCTAssertEqual(CalendarClassifier.workLocation(from: office), .office)
        let home = CalendarClassifier.classify([event("WFH", calendar: "work", allDay: true)], roles: roles)
        XCTAssertEqual(CalendarClassifier.workLocation(from: home), .home)
        XCTAssertEqual(CalendarClassifier.workLocation(from: []), .unknown)
    }

    func testLeave() {
        let leave = CalendarClassifier.classify([event("Annual leave", calendar: "work", allDay: true)], roles: roles)
        XCTAssertTrue(CalendarClassifier.isOnLeave(leave))
        let becky = CalendarClassifier.classify([event("Holiday", calendar: "becky", allDay: true)], roles: roles)
        XCTAssertFalse(CalendarClassifier.isOnLeave(becky), "Becky's leave isn't the user's leave")
    }

    func testWholeWordMatching() {
        XCTAssertTrue(CalendarClassifier.matches("Focus: betslip", CalendarClassifier.focusKeywords))
        XCTAssertFalse(CalendarClassifier.matches("Refocus planning", CalendarClassifier.focusKeywords))
    }
}

final class CoachIntentTests: XCTestCase {
    func testCoreCommands() {
        XCTAssertEqual(CoachIntentParser.parse("What's next?"), .whatsNext)
        XCTAssertEqual(CoachIntentParser.parse("What\u{2019}s next"), .whatsNext)
        XCTAssertEqual(CoachIntentParser.parse("I'm ready"), .ready)
        XCTAssertEqual(CoachIntentParser.parse("Done."), .done)
        XCTAssertEqual(CoachIntentParser.parse("Park this"), .park)
        XCTAssertEqual(CoachIntentParser.parse("I'm back"), .back)
        XCTAssertEqual(CoachIntentParser.parse("I'm bored"), .bored)
        XCTAssertEqual(CoachIntentParser.parse("Not now"), .notNow)
        XCTAssertEqual(CoachIntentParser.parse("I don't fancy the gym"), .dontFancy)
        XCTAssertEqual(CoachIntentParser.parse("Something's blocking me"), .blocked)
    }

    func testTasksAndInventory() {
        XCTAssertEqual(CoachIntentParser.parse("Put cleaning the attic on my list"), .addTask("cleaning the attic"))
        XCTAssertEqual(CoachIntentParser.parse("Remind me to book the valuation"), .addTask("book the valuation"))
        XCTAssertEqual(CoachIntentParser.parse("We've run out of chicken."), .ranOut("chicken"))
        XCTAssertEqual(CoachIntentParser.parse("Add done laundry to my list"), .addTask("done laundry"))
    }

    func testHealthReports() {
        XCTAssertEqual(CoachIntentParser.parse("My knee hurts"), .unwell(.injurySymptoms))
        XCTAssertEqual(CoachIntentParser.parse("I'm ill"), .unwell(.illness))
    }

    func testUnknownFallsThrough() {
        XCTAssertEqual(CoachIntentParser.parse("Find us something to do Friday"), .unknown("Find us something to do Friday"))
    }
}
