import XCTest
import SwiftData
@testable import FitnessVault

@MainActor
final class PlatformTests: XCTestCase {
    private var london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    private let monday = DayKey(year: 2026, month: 10, day: 19)

    private func at(_ hour: Int, _ minute: Int = 0, day: DayKey? = nil) -> Date {
        (day ?? monday).startDate(calendar: london).addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    private func make(_ clock: TestClock) async -> (CoachModel, RecordingCountdowns, ModelContainer) {
        let defaults = UserDefaults(suiteName: "platform.test.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.settings.demoMode = true
        let demo = DemoCalendarService(calendar: london)
        let countdowns = RecordingCountdowns()
        let container = Persistence.makeContainer(inMemory: true)
        let coach = CoachModel(container: container, settingsStore: settings, liveCalendar: demo, demoCalendar: demo,
                               defaults: defaults, reminders: RecordingReminderScheduler(), countdowns: countdowns,
                               languageModel: nil, calendar: london, now: { clock.date })
        await coach.start()
        return (coach, countdowns, container)
    }

    func testWidgetDoneCompletesTheCommitment() async {
        let clock = TestClock(at(12, 10))
        let (coach, _, _) = await make(clock)
        let walk = coach.addCommitment("Lunchtime walk", kind: .walk, start: at(12, 5), durationMinutes: 30)
        XCTAssertTrue(coach.complete(walk.id))
        XCTAssertEqual(walk.state, .completed)
        XCTAssertEqual(coach.history(for: walk).last?.reason, "Marked done from the widget")
        XCTAssertFalse(coach.complete(walk.id), "Already done")
        XCTAssertFalse(coach.complete(UUID()), "Unknown commitments are ignored")
    }

    func testWidgetActionRouterReachesTheCoach() async {
        let clock = TestClock(at(12, 10))
        let (coach, _, _) = await make(clock)
        let walk = coach.addCommitment("Lunchtime walk", kind: .walk, start: at(12, 5), durationMinutes: 30)
        let previous = WidgetActionRouter.handler
        defer { WidgetActionRouter.handler = previous }
        WidgetActionRouter.handler = { action in
            if case .complete(let id) = action { coach.complete(id) }
        }
        let intent = CompleteCommitmentIntent(commitmentID: walk.id.uuidString)
        _ = try? await intent.perform()
        XCTAssertEqual(walk.state, .completed)
    }

    func testWeekScoresForTheWidget() async {
        let clock = TestClock(at(7))
        let (coach, _, _) = await make(clock)
        let walk = coach.addCommitment("Walk", kind: .walk, start: nil, durationMinutes: 30)
        coach.transition(walk, .complete)
        clock.date = at(9, day: monday.adding(days: 1, calendar: london))
        await coach.refresh()
        let week = coach.weekScores()
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last ?? nil, 100, "Yesterday, the most recent day, comes last")
        XCTAssertNil(week.first ?? nil)
    }

    func testDepartureCountdownBeforeAnAgreedGymSession() async {
        let clock = TestClock(at(16, 30))
        let (coach, countdowns, _) = await make(clock)
        let gym = coach.addCommitment("Upper body at Nuffield", kind: .workout, start: at(17, 20), durationMinutes: 100)
        XCTAssertNil(countdowns.shown[.departure], "More than 45 minutes before")
        clock.date = at(16, 40)
        coach.reload()
        XCTAssertEqual(countdowns.shown[.departure]?.id, gym.id.uuidString)
        XCTAssertEqual(countdowns.shown[.departure]?.title, "Leave for the gym")
        XCTAssertEqual(countdowns.shown[.departure]?.endsAt, at(17, 20))
        clock.date = at(17, 21)
        coach.reload()
        XCTAssertNil(countdowns.shown[.departure], "Ends once it's time")
    }

    func testTaskCountdownFollowsTheTask() async {
        let clock = TestClock(at(10))
        let (coach, countdowns, _) = await make(clock)
        let task = coach.addCommitment("Sort the attic boxes", kind: .household, start: at(10), durationMinutes: 20)
        coach.transition(task, .start)
        XCTAssertEqual(countdowns.shown[.task]?.endsAt, at(10, 20))
        coach.transition(task, .complete)
        XCTAssertNil(countdowns.shown[.task])
        XCTAssertEqual(countdowns.endedKinds, [.task])

        let gym = coach.addCommitment("Gym", kind: .workout, start: at(11), durationMinutes: 90)
        coach.transition(gym, .start)
        XCTAssertNil(countdowns.shown[.task], "Workouts use the rest timer instead")
    }

    func testCookingTimer() async {
        let clock = TestClock(at(18))
        let (coach, _, container) = await make(clock)
        let countdowns = RecordingCountdowns()
        let kitchen = KitchenModel(container: container, coach: coach, reminders: RecordingReminderScheduler(),
                                   countdowns: countdowns, calendar: london, now: { clock.date })
        kitchen.start()
        let tonight = kitchen.tonight!
        let recipe = kitchen.recipes.first { $0.title == "Lemon chicken orzo" }!
        kitchen.swap(tonight, to: recipe)
        kitchen.startCooking(tonight)
        XCTAssertEqual(kitchen.cooking, tonight.id)
        XCTAssertEqual(countdowns.shown[.cooking]?.endsAt, at(18, 30), "Prep plus cook time")
        kitchen.markCooked(tonight)
        XCTAssertNil(countdowns.shown[.cooking])
        XCTAssertNil(kitchen.cooking)
    }

    func testLinksRouteToTheRightPlace() {
        let router = AppRouter()
        router.handle(AppLink.ready)
        XCTAssertEqual(router.pending, .ready)
        router.handle(AppLink.workout)
        XCTAssertEqual(router.pending, .workout)
        router.handle(AppLink.coach)
        XCTAssertEqual(router.pending, .coach)
        router.pending = nil
        router.handle(URL(string: "https://example.com/ready")!)
        XCTAssertNil(router.pending, "Other schemes are ignored")
    }

    func testWidgetSnapshotCarriesTheActionButNoMoney() async throws {
        let clock = TestClock(at(12, 10))
        let (coach, _, _) = await make(clock)
        let walk = coach.addCommitment("Lunchtime walk", kind: .walk, start: at(12, 5), durationMinutes: 30)
        let snapshot = coach.widgetSnapshot()
        XCTAssertEqual(snapshot.nextID, walk.id.uuidString)
        XCTAssertEqual(snapshot.nextKind, "walk")
        XCTAssertEqual(snapshot.week?.count, 7)
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self).lowercased()
        XCTAssertFalse(encoded.contains("fine"), "No fines in widget data")
        XCTAssertFalse(encoded.contains("pence"), "No money in the coach widget data")
    }
}
