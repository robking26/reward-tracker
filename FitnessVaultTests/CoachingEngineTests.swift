import XCTest
@testable import FitnessVault

/// Shared fixtures: Monday 19 October 2026 in London, shaped like a normal work-from-home day.
private enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    static let monday = DayKey(year: 2026, month: 10, day: 19)

    static func at(_ hour: Int, _ minute: Int = 0, on day: DayKey = monday) -> Date {
        day.startDate(calendar: calendar).addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    static func event(_ title: String, _ start: (Int, Int), _ end: (Int, Int), _ kind: BlockKind,
                      role: CalendarRole = .work) -> ClassifiedEvent {
        ClassifiedEvent(event: CalendarEventInfo(id: title, calendarID: role.rawValue, title: title,
                                                 start: at(start.0, start.1), end: at(end.0, end.1), isAllDay: false),
                        role: role, kind: kind)
    }

    /// Stand-up, design review, afternoon focus, Becky's gym class.
    static let workday: [ClassifiedEvent] = [
        event("Stand-up", (9, 30), (9, 45), .workMeeting),
        event("Design review", (11, 0), (12, 0), .workMeeting),
        event("Focus time", (13, 0), (16, 0), .workFocus),
        event("Gym class", (18, 0), (19, 0), .sharedInfo, role: .shared),
    ]

    static func input(now: Date = at(6, 30), events: [ClassifiedEvent] = workday, existing: Set<CommitmentKind> = [],
                      workouts: Int = 0, consecutive: Int = 0, lastUpper: Bool? = nil, isWorkday: Bool = true,
                      houseTask: HouseTaskSuggestion? = nil) -> RecommendationInput {
        let settings = CoachSettings()
        let windows = Availability.windows(on: monday, shape: settings.shape(isWorkday: isWorkday),
                                           blocks: CalendarClassifier.blocks(from: events), notBefore: now, calendar: calendar)
        return RecommendationInput(day: monday, now: now, calendar: calendar, settings: settings, isWorkday: isWorkday,
                                   windows: windows, events: events, existingKinds: existing, workoutsThisWeek: workouts,
                                   consecutiveWorkoutDays: consecutive, lastWorkoutWasUpper: lastUpper, houseTask: houseTask)
    }
}

final class RecommendationEngineTests: XCTestCase {
    func testWorkFromHomeMorning() {
        // Scenario A: one suggestion per thing, in time order, nothing inside work or focus time.
        let suggestions = RecommendationEngine.morning(Fixture.input())
        XCTAssertEqual(suggestions.map(\.kind), [.walk, .workout, .selfCare])
        XCTAssertEqual(suggestions[0].start, Fixture.at(12, 5), "Five minutes to get ready, then out at lunch")
        XCTAssertEqual(suggestions[1].start, Fixture.at(17, 20), "Lined up with Becky's class and back before dinner")
        XCTAssertTrue(suggestions[1].reason.contains("Becky"))
        XCTAssertEqual(suggestions[1].durationMinutes, 100, "Door to door: travel both ways, changing and the session")
        XCTAssertEqual(suggestions[2].start, Fixture.at(21, 30))
        XCTAssertNotNil(suggestions[1].alternative)
    }

    func testGymNeverDisplacesDinner() {
        let suggestions = RecommendationEngine.morning(Fixture.input())
        let gym = suggestions.first { $0.kind == .workout }!
        let end = gym.start!.addingTimeInterval(TimeInterval(gym.durationMinutes * 60))
        XCTAssertLessThanOrEqual(end, Fixture.at(19))
    }

    func testRehabIsSeparateOnlyWhenThereIsNoGym() {
        let met = RecommendationEngine.morning(Fixture.input(workouts: 2))
        XCTAssertFalse(met.contains { $0.kind == .workout }, "Two sessions already this week in the first fortnight")
        XCTAssertTrue(met.contains { $0.kind == .rehab })
        let withGym = RecommendationEngine.morning(Fixture.input())
        XCTAssertFalse(withGym.contains { $0.kind == .rehab }, "Rehab sits inside the gym session")
    }

    func testRecoveryAfterTwoDaysInARow() {
        let suggestions = RecommendationEngine.morning(Fixture.input(consecutive: 2))
        XCTAssertFalse(suggestions.contains { $0.kind == .workout })
    }

    func testUpperAndLowerAlternate() {
        let suggestions = RecommendationEngine.morning(Fixture.input(lastUpper: true))
        XCTAssertEqual(suggestions.first { $0.kind == .workout }?.title, "Lower body at Nuffield")
    }

    func testNothingSuggestedTwice() {
        let suggestions = RecommendationEngine.morning(Fixture.input(existing: [.walk, .selfCare, .workout]))
        XCTAssertEqual(suggestions.map(\.kind), [.rehab])
    }

    func testNoGymWhenNoWindowFitsTheTrip() {
        var events = Fixture.workday
        events.append(Fixture.event("Parents' evening", (16, 0), (21, 30), .personal, role: .personal))
        let suggestions = RecommendationEngine.morning(Fixture.input(events: events))
        XCTAssertFalse(suggestions.contains { $0.kind == .workout })
    }

    func testDayOffOffersAHouseTask() {
        let task = HouseTaskSuggestion(title: "Measure the missing sections", minutes: 15)
        let suggestions = RecommendationEngine.morning(Fixture.input(now: Fixture.at(8), events: [], isWorkday: false,
                                                                     houseTask: task))
        XCTAssertTrue(suggestions.contains { $0.title == "Measure the missing sections" && $0.objective == .homeMove })
        let walk = suggestions.first { $0.kind == .walk }
        XCTAssertNotNil(walk)
    }

    func testWorkoutTargetRampsUp() {
        let calendar = Fixture.calendar
        XCTAssertEqual(RecommendationEngine.weeklyWorkoutTarget(on: DayKey(year: 2026, month: 10, day: 19), calendar: calendar), 2)
        XCTAssertEqual(RecommendationEngine.weeklyWorkoutTarget(on: DayKey(year: 2026, month: 11, day: 2), calendar: calendar), 3)
        XCTAssertEqual(RecommendationEngine.weeklyWorkoutTarget(on: DayKey(year: 2026, month: 11, day: 16), calendar: calendar), 4)
    }
}

final class ReplannerTests: XCTestCase {
    private let gym = ScheduledItem(id: UUID(), interval: DateInterval(start: Fixture.at(16), end: Fixture.at(17, 40)))

    func testNewMeetingClashesWithTheGym() {
        // Scenario B.
        let meeting = Fixture.event("Exec sync", (16, 0), (17, 0), .workMeeting)
        let conflicts = Replanner.conflicts([gym], events: Fixture.workday + [meeting], now: Fixture.at(14))
        XCTAssertEqual(conflicts.map(\.eventTitle), ["Exec sync"])
    }

    func testBeckysEventsNeverClash() {
        let becky = Fixture.event("Nails", (16, 0), (17, 0), .sharedInfo, role: .shared)
        XCTAssertTrue(Replanner.conflicts([gym], events: [becky], now: Fixture.at(14)).isEmpty)
    }

    func testPastCommitmentsAreLeftAlone() {
        let meeting = Fixture.event("Exec sync", (16, 0), (17, 0), .workMeeting)
        XCTAssertTrue(Replanner.conflicts([gym], events: [meeting], now: Fixture.at(16, 30)).isEmpty)
    }

    func testAlternativeAfterTheMeeting() {
        let meeting = Fixture.event("Exec sync", (16, 0), (17, 0), .workMeeting)
        let windows = Availability.windows(on: Fixture.monday, shape: CoachSettings().shape(isWorkday: true),
                                           blocks: CalendarClassifier.blocks(from: Fixture.workday + [meeting]),
                                           notBefore: Fixture.at(14), calendar: Fixture.calendar)
        let need = ActivityNeed(activeMinutes: 60, travelMinutesEachWay: 15, preparationMinutes: 10)
        XCTAssertEqual(Replanner.alternative(for: need, in: windows, notBefore: Fixture.at(14)), Fixture.at(17))
    }
}

final class NotificationPlannerTests: XCTestCase {
    private func item(_ kind: CommitmentKind, _ hour: Int, _ minute: Int = 0, state: CommitmentState = .approved) -> NotifiableCommitment {
        NotifiableCommitment(id: UUID(), title: kind.title, kind: kind, start: Fixture.at(hour, minute), state: state)
    }

    private func plan(_ items: [NotifiableCommitment], now: Date = Fixture.at(9), office: Bool = false) -> [PlannedNotification] {
        NotificationPlanner.plan(items, blocks: CalendarClassifier.blocks(from: Fixture.workday), now: now,
                                 quietFrom: Fixture.at(22, 30), quietUntil: Fixture.at(5, 55), office: office)
    }

    func testThreeLevelsForAnAgreedWalk() {
        let walk = item(.walk, 12, 5)
        let planned = plan([walk])
        XCTAssertEqual(planned.map(\.date), [Fixture.at(12), Fixture.at(12, 10), Fixture.at(12, 25)])
        XCTAssertEqual(planned.first?.body, "Five minutes until your walk. Finish what you're doing.")
        XCTAssertTrue(planned.last?.body.contains("genuine blocker") ?? false)
    }

    func testGymEscalation() {
        let planned = plan([item(.workout, 17, 20)])
        XCTAssertEqual(planned.map(\.date), [Fixture.at(17, 5), Fixture.at(17, 35), Fixture.at(17, 50)])
        XCTAssertEqual(planned.first?.body, "Your gym window starts soon. Kit ready?")
    }

    func testNothingDuringFocusTime() {
        XCTAssertTrue(plan([item(.rehab, 14)]).isEmpty, "Focus blocks are protected")
    }

    func testOnlyAgreedCommitmentsGetReminders() {
        XCTAssertTrue(plan([item(.walk, 12, 5, state: .completed), item(.walk, 12, 5, state: .proposed)]).isEmpty)
    }

    func testQuietHoursAndThePast() {
        let late = plan([item(.selfCare, 22, 20)])
        XCTAssertEqual(late.map(\.date), [Fixture.at(22, 15)], "Nothing after bedtime")
        XCTAssertTrue(plan([item(.walk, 8)], now: Fixture.at(9)).isEmpty)
    }

    func testOfficeIsDiscreet() {
        XCTAssertTrue(plan([item(.walk, 12, 5)], office: true).allSatisfy(\.isDiscreet))
    }
}

final class MemoryRetrieverTests: XCTestCase {
    private let items = [
        MemoryItem(store: .nutrition, key: "Never", value: "Mushrooms, courgette, cauliflower.", status: .confirmed),
        MemoryItem(store: .preference, key: "Gym", value: "Nuffield Health Bolton. Prefers quieter times.", status: .confirmed),
        MemoryItem(store: .preference, key: "Walking", value: "Enjoys walking at lunchtime; dislikes rain.", status: .confirmed),
        MemoryItem(store: .preference, key: "Old gym", value: "PureGym.", status: .superseded),
    ]

    func testFindsTheRelevantFact() {
        let found = MemoryRetriever.relevant(items, to: "Suggest a dinner without mushrooms")
        XCTAssertEqual(found.first?.key, "Never")
    }

    func testKeyMatchesRankFirstAndSupersededIsIgnored() {
        let found = MemoryRetriever.relevant(items, to: "Is the gym busy?")
        XCTAssertEqual(found.map(\.key), ["Gym"])
    }

    func testNothingRelevantReturnsNothing() {
        XCTAssertTrue(MemoryRetriever.relevant(items, to: "Hi").isEmpty)
    }
}
