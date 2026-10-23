import XCTest
@testable import FitnessVault

final class RoutineRulesTests: XCTestCase {
    let london = PlannerFixtures().london
    /// Monday 2 November 2026.
    let monday = PlannerFixtures().monday

    private func day(_ offset: Int) -> DayKey { monday.adding(days: offset, calendar: london) }
    private func at(_ day: DayKey, _ hour: Int, _ minute: Int = 0) -> Date { day.date(atMinute: hour * 60 + minute, calendar: london) }

    private func setup(from start: DayKey? = nil) -> RoutineSetup {
        var setup = RoutineSetup()
        for key in RoutineKey.all { setup.items[key.id] = RoutineCatalogue.defaults(for: key) }
        setup.penaltyFrom = start ?? monday
        return setup
    }

    private func finished(_ part: RoutinePart, on day: DayKey, at date: Date, place: RoutinePlace = .home,
                          setup: RoutineSetup) -> RoutineRecord {
        let key = RoutineRules.key(part, on: day, place: place, calendar: london)
        return RoutineRecord(day: day, part: part, place: place, ticked: Set(setup.items(key).map(\.id)), completedAt: date)
    }

    func testNightsFollowTomorrow() {
        XCTAssertEqual(RoutineRules.days(for: .morning, on: day(5), calendar: london), .weekend, "Saturday morning")
        XCTAssertEqual(RoutineRules.days(for: .morning, on: day(4), calendar: london), .weekday, "Friday morning")
        XCTAssertEqual(RoutineRules.days(for: .evening, on: day(4), calendar: london), .weekend, "Friday night")
        XCTAssertEqual(RoutineRules.days(for: .evening, on: day(6), calendar: london), .weekday, "Sunday night, before Monday")
    }

    func testHomeTimesAreSixAmAndNinePm() {
        let setup = setup()
        let morning = RoutineRules.window(RoutineRules.key(.morning, on: monday, place: .home, calendar: london), on: monday,
                                          setup: setup, calendar: london)
        XCTAssertEqual(morning.start, at(monday, 6))
        let night = RoutineRules.window(RoutineRules.key(.evening, on: monday, place: .home, calendar: london), on: monday,
                                        setup: setup, calendar: london)
        XCTAssertEqual(night.start, at(monday, 21))
        let saturday = RoutineRules.window(RoutineRules.key(.morning, on: day(5), place: .home, calendar: london), on: day(5),
                                           setup: setup, calendar: london)
        XCTAssertEqual(saturday.start, at(day(5), 8), "A different weekend version")
    }

    func testStatusThroughTheMorning() {
        let setup = setup()
        func status(_ record: RoutineRecord?, _ now: Date) -> RoutineStatus {
            RoutineRules.status(.morning, on: monday, record: record, setup: setup, now: now, calendar: london)
        }
        XCTAssertEqual(status(nil, at(monday, 5)), .upcoming)
        XCTAssertEqual(status(nil, at(monday, 6, 30)), .open)
        XCTAssertEqual(status(finished(.morning, on: monday, at: at(monday, 7), setup: setup), at(monday, 8)), .done)
        XCTAssertEqual(status(nil, at(monday, 7, 31)), .missed)
        XCTAssertEqual(status(finished(.morning, on: monday, at: at(monday, 7, 45), setup: setup), at(monday, 8)), .missed,
                       "Finishing late doesn't count")
        var partial = finished(.morning, on: monday, at: at(monday, 7), setup: setup)
        partial.ticked.removeFirst()
        partial.completedAt = nil
        XCTAssertEqual(status(partial, at(monday, 8)), .missed, "Everything has to be ticked")
    }

    func testMissedHomeRoutineHalvesTheDayOnce() {
        let setup = setup()
        let late = at(monday, 23, 30)
        XCTAssertTrue(RoutineRules.isPenalised(monday, records: [:], setup: setup, now: late, calendar: london))
        let morning = finished(.morning, on: monday, at: at(monday, 7), setup: setup)
        XCTAssertTrue(RoutineRules.isPenalised(monday, records: [.morning: morning], setup: setup, now: late, calendar: london),
                      "The night routine still counts")
        let night = finished(.evening, on: monday, at: at(monday, 22), setup: setup)
        XCTAssertFalse(RoutineRules.isPenalised(monday, records: [.morning: morning, .evening: night], setup: setup,
                                                now: late, calendar: london))
        XCTAssertFalse(RoutineRules.isPenalised(monday, records: [.morning: morning], setup: setup, now: at(monday, 21, 30),
                                                calendar: london), "Not until the night routine's time has passed")
    }

    func testAwayRoutinesNeverCost() {
        let setup = setup()
        let away = RoutineRecord(day: monday, part: .morning, place: .away)
        let night = RoutineRecord(day: monday, part: .evening, place: .away)
        XCTAssertFalse(RoutineRules.isPenalised(monday, records: [.morning: away, .evening: night], setup: setup,
                                                now: at(monday, 23, 30), calendar: london))
        XCTAssertEqual(RoutineRules.status(.morning, on: monday, record: away, setup: setup, now: at(monday, 10), calendar: london),
                       .awayMissed)
    }

    func testNothingBeforeThePenaltyStarts() {
        let setup = setup(from: day(1))
        XCTAssertFalse(RoutineRules.isPenalised(monday, records: [:], setup: setup, now: at(day(1), 9), calendar: london))
        XCTAssertFalse(RoutineRules.isPenalised(monday, records: [:], setup: RoutineSetup(), now: at(day(1), 9), calendar: london),
                       "Not set up: nothing")
    }

    func testHalvingRoundsInYourFavour() {
        let halved = RoutineRules.halved([.steps: Pence(101), .exercise: Pence(40), .swimming: .zero])
        XCTAssertEqual(halved[.steps], Pence(51))
        XCTAssertEqual(halved[.exercise], Pence(20))
        XCTAssertEqual(halved[.swimming], .zero)
    }

    func testFinishTimeIsTheLastTick() {
        let items = [RoutineItem(id: "a", title: "A", symbol: "star"), RoutineItem(id: "b", title: "B", symbol: "star")]
        var record = RoutineRecord(day: monday, part: .morning)
        record = RoutineRules.toggle("a", in: record, items: items, at: at(monday, 6, 10))
        XCTAssertNil(record.completedAt)
        record = RoutineRules.toggle("b", in: record, items: items, at: at(monday, 6, 20))
        XCTAssertEqual(record.completedAt, at(monday, 6, 20))
        record = RoutineRules.toggle("a", in: record, items: items, at: at(monday, 6, 25))
        XCTAssertNil(record.completedAt, "Unticking undoes it")
    }

    func testEveryVersionHasSuggestionsAndDefaults() {
        XCTAssertEqual(RoutineKey.all.count, 8)
        for key in RoutineKey.all {
            XCTAssertFalse(RoutineCatalogue.defaults(for: key).isEmpty, key.id)
        }
        XCTAssertEqual(Set(RoutineCatalogue.morning.map(\.id)).count, RoutineCatalogue.morning.count)
    }
}

@MainActor
final class RoutineModelTests: XCTestCase {
    let fixtures = PlannerFixtures()

    private func make(at now: @escaping () -> Date) -> (RoutineModel, RecordingReminderScheduler) {
        let reminders = RecordingReminderScheduler()
        let routines = RoutineModel(container: Persistence.makeContainer(inMemory: true), reminders: reminders,
                                    defaults: UserDefaults(suiteName: "tests.routines.\(UUID().uuidString)")!,
                                    calendar: fixtures.london, now: now)
        return (routines, reminders)
    }

    private func saveDefaults(_ routines: RoutineModel) {
        var items: [String: [RoutineItem]] = [:]
        for key in RoutineKey.all { items[key.id] = RoutineCatalogue.defaults(for: key) }
        routines.save(items, times: [:])
    }

    func testTickingThroughTheMorningAndTheRuleStartingTomorrow() {
        let monday = fixtures.monday
        var clock = monday.date(atMinute: 6 * 60 + 5, calendar: fixtures.london)
        let (routines, reminders) = make { clock }
        saveDefaults(routines)
        XCTAssertEqual(routines.setup.penaltyFrom, monday.adding(days: 1, calendar: fixtures.london), "Starts tomorrow")
        XCTAssertEqual(routines.currentPart, .morning)
        XCTAssertTrue(reminders.latest.contains { $0.id.hasSuffix("evening.warn") })

        for item in routines.items(.morning, on: monday) { routines.toggle(item, part: .morning, on: monday) }
        XCTAssertEqual(routines.status(.morning, on: monday), .done)

        clock = monday.date(atMinute: 8 * 60, calendar: fixtures.london)
        XCTAssertEqual(routines.currentPart, .evening)
        let first = routines.items(.morning, on: monday)[0]
        routines.toggle(first, part: .morning, on: monday)
        XCTAssertEqual(routines.status(.morning, on: monday), .done, "Closed: can't be changed afterwards")

        clock = monday.date(atMinute: 23 * 60 + 59, calendar: fixtures.london).addingTimeInterval(30)
        XCTAssertFalse(routines.isPenalised(monday), "The first day doesn't count")
    }

    func testGoingAwayAvoidsThePenaltyOnlyBeforeTheDeadline() {
        let tuesday = fixtures.monday.adding(days: 1, calendar: fixtures.london)
        var clock = fixtures.monday.date(atMinute: 12 * 60, calendar: fixtures.london)
        let (routines, _) = make { clock }
        saveDefaults(routines)

        clock = tuesday.date(atMinute: 20 * 60, calendar: fixtures.london)
        routines.setPlace(.away, part: .evening, on: tuesday)
        clock = tuesday.date(atMinute: 8 * 60, calendar: fixtures.london)
        // The morning closed at 7:30, so it's too late to call it away.
        routines.setPlace(.away, part: .morning, on: tuesday)
        XCTAssertEqual(routines.place(.morning, on: tuesday), .home, "Too late to change")

        clock = tuesday.date(atMinute: 23 * 60 + 59, calendar: fixtures.london).addingTimeInterval(30)
        XCTAssertEqual(routines.status(.evening, on: tuesday), .awayMissed)
        XCTAssertTrue(routines.isPenalised(tuesday), "The home morning was still missed")
    }

    func testAMissedHomeRoutineHalvesThatDaysEarnings() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = DayKey(year: 2026, month: 11, day: 5).date(atMinute: 12 * 60, calendar: calendar)
        let yesterday = DayKey(year: 2026, month: 11, day: 4)
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.settings.demoMode = true
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), settingsStore: settings,
                             demoHealth: MockHealthService(calendar: calendar, now: { now }), calendar: calendar, now: { now })
        model.routinePenalty = { $0 == yesterday }
        await model.syncHealth()

        let full = model.earnedBeforeRoutines(on: yesterday)
        XCTAssertTrue(full.isPositive)
        let rewards = RewardEngine.rewards(for: model.metrics(for: yesterday), rates: model.settings.rates)
        XCTAssertEqual(model.earned(on: yesterday), RewardEngine.total(RoutineRules.halved(rewards)))
        let other = DayKey(year: 2026, month: 11, day: 3)
        XCTAssertEqual(model.earned(on: other), model.earnedBeforeRoutines(on: other), "Other days untouched")

        // Finding out the routine was done after all puts the money back while the day is still open.
        model.routinePenalty = { _ in false }
        model.applyRoutineChanges()
        XCTAssertEqual(model.earned(on: yesterday), full)
    }
}
