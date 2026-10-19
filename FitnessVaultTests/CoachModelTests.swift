import XCTest
import SwiftData
@testable import FitnessVault

/// A clock the tests can move forward.
final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor
final class CoachModelTests: XCTestCase {
    private var london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private let monday = DayKey(year: 2026, month: 10, day: 19)

    private func at(_ day: DayKey, _ hour: Int, _ minute: Int = 0) -> Date {
        day.startDate(calendar: london).addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    private func makeCoach(_ clock: TestClock, demo: Bool = true, live: DemoCalendarService? = nil) -> (CoachModel, DemoCalendarService) {
        let defaults = UserDefaults(suiteName: "coach.test.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.settings.demoMode = demo
        let demoCalendar = DemoCalendarService(calendar: london)
        let coach = CoachModel(container: Persistence.makeContainer(inMemory: true), settingsStore: settings,
                               liveCalendar: live ?? DemoCalendarService(calendar: london), demoCalendar: demoCalendar,
                               defaults: defaults, reminders: RecordingReminderScheduler(), languageModel: nil, calendar: london,
                               now: { clock.date })
        return (coach, demoCalendar)
    }

    func testSeedLoadsTheBriefOnceAndAgreesToNothing() async {
        let clock = TestClock(at(monday, 7))
        let (coach, _) = makeCoach(clock)
        await coach.start()
        XCTAssertEqual(coach.memories().count, SeedProfile.facts.count)
        XCTAssertTrue(coach.routines().allSatisfy { !$0.isEnabled }, "Suggested routines need agreement first")
        XCTAssertTrue(coach.commitments.isEmpty)
        XCTAssertTrue(coach.projection.score.isEmpty)
        XCTAssertFalse(coach.activeTasks().isEmpty, "The house-sale backlog is loaded")
        XCTAssertTrue(coach.memories().contains { $0.key == "Never" && $0.value.contains("Mushrooms") })
        coach.seedIfNeeded()
        XCTAssertEqual(coach.memories().count, SeedProfile.facts.count, "Seeding runs once")
    }

    func testEnablingARoutineLateNeverCreatesAMiss() async {
        let clock = TestClock(at(monday, 22))
        let (coach, _) = makeCoach(clock)
        await coach.start()
        let selfCare = coach.routines().first { $0.title == "Evening self-care" }!
        coach.setRoutine(selfCare, enabled: true)
        XCTAssertTrue(coach.commitments.isEmpty, "21:30 has passed, so tonight's self-care isn't added")
        let rehab = coach.routines().first { $0.kind == .rehab }!
        coach.setRoutine(rehab, enabled: true)
        XCTAssertEqual(coach.commitments.map(\.title), ["Knee rehab exercises"])
        XCTAssertEqual(coach.commitments.first?.state, .approved)
    }

    func testRoutinesAppearEachDayOnce() async {
        let clock = TestClock(at(monday, 7))
        let (coach, _) = makeCoach(clock)
        await coach.start()
        let walk = coach.routines().first { $0.kind == .walk }!
        coach.setRoutine(walk, enabled: true)
        await coach.refresh()
        await coach.refresh()
        XCTAssertEqual(coach.commitments.filter { $0.routineID == walk.id }.count, 1)
    }

    func testConversationAndTodayChangeTheSameRecord() async {
        let clock = TestClock(at(monday, 7))
        let (coach, _) = makeCoach(clock)
        await coach.start()
        let gym = coach.addCommitment("Upper body at Nuffield", kind: .workout, start: at(monday, 7, 15), durationMinutes: 60)
        coach.send("Done")
        XCTAssertEqual(gym.state, .completed)
        XCTAssertEqual(coach.messages.last?.toolSummary, "Marked done: Upper body at Nuffield")
        XCTAssertEqual(coach.projection.score.confirmedPercent, 100)
        XCTAssertEqual(coach.history(for: gym).map(\.toRaw), ["approved", "completed"])
    }

    func testDayEndsAsPendingThenAssumedMissedThenCorrectable() async {
        let clock = TestClock(at(monday, 7))
        let (coach, _) = makeCoach(clock)
        await coach.start()
        let walk = coach.addCommitment("Walk", kind: .walk, start: nil, durationMinutes: 30)

        clock.date = at(monday.adding(days: 1, calendar: london), 9)
        await coach.refresh()
        XCTAssertEqual(walk.state, .pendingVerification, "Silence isn't proof of a miss")
        XCTAssertEqual(coach.needsVerification.count, 1)
        XCTAssertNil(coach.dayRecord(monday)?.finalisedAt)
        XCTAssertEqual(coach.monthFines, .zero)

        clock.date = at(monday.adding(days: 2, calendar: london), 9)
        await coach.refresh()
        XCTAssertEqual(walk.state, .missed)
        XCTAssertTrue(walk.assumedMissed)
        XCTAssertEqual(coach.dayRecord(monday)?.fine, .pounds(15))
        XCTAssertTrue(coach.dayRecord(monday)?.isSimulation ?? false, "Fines are simulated during the trial")
        XCTAssertEqual(coach.monthFines, .pounds(15))

        XCTAssertTrue(coach.transition(walk, .correct(to: .completed), reason: "I did walk"))
        XCTAssertEqual(coach.dayRecord(monday)?.fine, .zero)
        XCTAssertEqual(coach.monthFines, .zero)
        XCTAssertFalse(walk.assumedMissed)
    }

    func testIllnessExcusesPhysicalCommitmentsOnly() async {
        let clock = TestClock(at(monday, 7))
        let (coach, _) = makeCoach(clock)
        await coach.start()
        let gym = coach.addCommitment("Gym", kind: .workout, start: at(monday, 17), durationMinutes: 60)
        let washing = coach.addCommitment("Wash up", kind: .household, start: at(monday, 20), durationMinutes: 10)
        coach.send("I'm ill")
        XCTAssertEqual(gym.state, .excused)
        XCTAssertEqual(gym.excuse, .illness)
        XCTAssertEqual(washing.state, .approved)
        XCTAssertEqual(coach.projection.worstCaseFine, .pounds(15), "Washing up still counts")
    }

    func testNotFancyingItIsChallengedNotExcused() async {
        let clock = TestClock(at(monday, 16, 50))
        let (coach, _) = makeCoach(clock)
        await coach.start()
        let gym = coach.addCommitment("Gym", kind: .workout, start: at(monday, 17), durationMinutes: 60)
        coach.send("I don't fancy the gym")
        XCTAssertEqual(gym.state, .approved)
        XCTAssertTrue(coach.messages.last?.text.contains("ten minutes") ?? false)
    }

    func testMovingToAnotherDayNeedsAReason() async {
        let clock = TestClock(at(monday, 16))
        let (coach, _) = makeCoach(clock)
        await coach.start()
        let gym = coach.addCommitment("Gym", kind: .workout, start: at(monday, 17), durationMinutes: 60)
        let tuesday = monday.adding(days: 1, calendar: london)
        XCTAssertNil(coach.reschedule(gym, to: at(tuesday, 17)))
        XCTAssertEqual(gym.state, .approved)
        let moved = coach.reschedule(gym, to: at(tuesday, 17), reason: .calendarConflict)
        XCTAssertEqual(gym.state, .rescheduled)
        XCTAssertEqual(moved?.day, tuesday.description)
        XCTAssertEqual(moved?.weight, gym.weight, "The weight agreed travels with it")
        XCTAssertTrue(coach.projection.score.isEmpty, "Moved for a real reason: today has nothing to fine")
    }

    func testAddingATaskInConversation() async {
        let clock = TestClock(at(monday, 7))
        let (coach, _) = makeCoach(clock)
        await coach.start()
        coach.send("Put sorting the loft boxes on my list")
        XCTAssertTrue(coach.activeTasks().contains { $0.title == "Sorting the loft boxes" })
        XCTAssertEqual(coach.messages.last?.toolSummary, "Added to your list: Sorting the loft boxes")
    }

    func testNewMeetingMovesTheNextOpportunity() async {
        // Scenario B, availability part.
        let clock = TestClock(at(monday, 15))
        let (coach, demo) = makeCoach(clock)
        await coach.start()
        XCTAssertEqual(coach.nextOpportunity?.interval.start, at(monday, 16))
        demo.extraEvents = [CalendarEventInfo(id: "late", calendarID: DemoCalendarService.workID, title: "Exec sync",
                                              start: at(monday, 16), end: at(monday, 17), isAllDay: false)]
        coach.refreshCalendar()
        coach.reload()
        XCTAssertEqual(coach.nextOpportunity?.interval.start, at(monday, 17))
    }

    func testBeckysEventsAreContextNotBusy() async {
        let clock = TestClock(at(monday, 17))
        let (coach, _) = makeCoach(clock)
        await coach.start()
        XCTAssertTrue(coach.events.contains { $0.event.title == "Gym class" && $0.kind == .sharedInfo })
        XCTAssertEqual(coach.nextOpportunity?.interval.start, at(monday, 17), "Becky's gym class doesn't block the evening")
    }

    func testMissingWorkCalendarIsReported() async {
        // Scenario M: live calendars granted but none labelled Work.
        let clock = TestClock(at(monday, 7))
        let (coach, _) = makeCoach(clock, demo: false)
        await coach.start()
        XCTAssertTrue(coach.hasNoWorkCalendar)
        coach.send("I'm ready")
        XCTAssertTrue(coach.messages.last?.text.contains("can't see a work calendar") ?? false)
    }

    func testDeleteAllCoachData() async {
        let clock = TestClock(at(monday, 7))
        let (coach, _) = makeCoach(clock)
        await coach.start()
        coach.addCommitment("Walk", kind: .walk, start: nil, durationMinutes: 30)
        coach.deleteAllCoachData()
        XCTAssertTrue(coach.memories().isEmpty)
        XCTAssertTrue(coach.commitments.isEmpty)
        XCTAssertTrue(coach.messages.isEmpty)
        XCTAssertTrue(coach.allTasks().isEmpty)
    }

    func testExportIsReadableJSON() async throws {
        let clock = TestClock(at(monday, 7))
        let (coach, _) = makeCoach(clock)
        await coach.start()
        let url = try coach.exportCoachData()
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertEqual((json?["memories"] as? [Any])?.count, SeedProfile.facts.count)
    }
}
