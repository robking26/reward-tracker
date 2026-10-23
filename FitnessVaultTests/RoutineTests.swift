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
        XCTAssertEqual(saturday.start, at(day(5), 10), "A different weekend version")
        XCTAssertEqual(saturday.end, at(day(5), 11))
        XCTAssertEqual(morning.end, at(monday, 6, 45))
        XCTAssertEqual(night.end, at(monday, 21, 30), "In bed for 9:30")
    }

    func testStatusThroughTheMorning() {
        let setup = setup()
        func status(_ record: RoutineRecord?, _ now: Date) -> RoutineStatus {
            RoutineRules.status(.morning, on: monday, record: record, setup: setup, now: now, calendar: london)
        }
        XCTAssertEqual(status(nil, at(monday, 5)), .upcoming)
        XCTAssertEqual(status(nil, at(monday, 6, 30)), .open)
        XCTAssertEqual(status(finished(.morning, on: monday, at: at(monday, 6, 40), setup: setup), at(monday, 8)), .done)
        XCTAssertEqual(status(nil, at(monday, 6, 46)), .missed)
        XCTAssertEqual(status(finished(.morning, on: monday, at: at(monday, 7), setup: setup), at(monday, 8)), .missed,
                       "Finishing late doesn't count")
        var mostly = finished(.morning, on: monday, at: at(monday, 6, 40), setup: setup)
        mostly.ticked.remove(mostly.ticked.sorted()[0])
        mostly.ticked.remove(mostly.ticked.sorted()[0])
        XCTAssertEqual(status(mostly, at(monday, 8)), .done, "9 of 11 is 80%")
        mostly.ticked.remove(mostly.ticked.sorted()[0])
        XCTAssertEqual(status(mostly, at(monday, 8)), .missed, "8 of 11 isn't")
    }

    func testMissedHomeRoutineHalvesTheDayOnce() {
        let setup = setup()
        let late = at(monday, 23, 30)
        XCTAssertTrue(RoutineRules.isPenalised(monday, records: [:], setup: setup, now: late, calendar: london))
        let morning = finished(.morning, on: monday, at: at(monday, 6, 40), setup: setup)
        XCTAssertTrue(RoutineRules.isPenalised(monday, records: [.morning: morning], setup: setup, now: late, calendar: london),
                      "The night routine still counts")
        let night = finished(.evening, on: monday, at: at(monday, 21, 20), setup: setup)
        XCTAssertFalse(RoutineRules.isPenalised(monday, records: [.morning: morning, .evening: night], setup: setup,
                                                now: late, calendar: london))
        XCTAssertFalse(RoutineRules.isPenalised(monday, records: [.morning: morning], setup: setup, now: at(monday, 21, 15),
                                                calendar: london), "Not until the night routine's time has passed")
    }

    func testAwayRoutinesNeverCost() {
        let setup = setup()
        let away = RoutineRecord(day: monday, part: .morning, place: .away)
        let night = RoutineRecord(day: monday, part: .evening, place: .away)
        XCTAssertFalse(RoutineRules.isPenalised(monday, records: [.morning: away, .evening: night], setup: setup,
                                                now: at(monday, 23, 30), calendar: london))
        XCTAssertEqual(RoutineRules.status(.morning, on: monday, record: away, setup: setup, now: at(monday, 11, 30), calendar: london),
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
        record = RoutineRules.toggle("a", in: record, items: items, share: 0.8, at: at(monday, 6, 10))
        XCTAssertNil(record.completedAt)
        record = RoutineRules.toggle("b", in: record, items: items, share: 0.8, at: at(monday, 6, 20))
        XCTAssertEqual(record.completedAt, at(monday, 6, 20))
        record = RoutineRules.toggle("a", in: record, items: items, share: 0.8, at: at(monday, 6, 25))
        XCTAssertNil(record.completedAt, "Unticking undoes it")
    }

    func testLeaveDaysAtHomeAreSaturdayMornings() {
        let leave = RoutineDayInfo(isLeave: true)
        XCTAssertEqual(RoutineRules.days(for: .morning, on: monday, place: .home, info: leave, calendar: london), .weekend)
        XCTAssertEqual(RoutineRules.days(for: .morning, on: monday, place: .away, info: leave, calendar: london), .weekday)
        XCTAssertEqual(RoutineRules.days(for: .evening, on: monday, place: .home, info: leave, calendar: london), .weekday)
    }

    func testWeekendAndAwayMorningsFinishBeforeTheFirstEvent() {
        let setup = setup()
        let saturday = day(5)
        let key = RoutineKey(part: .morning, days: .weekend, place: .home)
        let early = RoutineRules.window(key, on: saturday, setup: setup, firstEvent: at(saturday, 9, 30), calendar: london)
        XCTAssertEqual(early.start, at(saturday, 8, 30))
        XCTAssertEqual(early.end, at(saturday, 9, 30))
        let late = RoutineRules.window(key, on: saturday, setup: setup, firstEvent: at(saturday, 12), calendar: london)
        XCTAssertEqual(late.end, at(saturday, 11), "10 to 11, whichever is earlier")
        let away = RoutineKey(part: .morning, days: .weekday, place: .away)
        XCTAssertEqual(RoutineRules.window(away, on: monday, setup: setup, firstEvent: at(monday, 9), calendar: london).end,
                       at(monday, 9))
        let weekday = RoutineKey(part: .morning, days: .weekday, place: .home)
        XCTAssertEqual(RoutineRules.window(weekday, on: monday, setup: setup, firstEvent: at(monday, 6, 30), calendar: london).end,
                       at(monday, 6, 45), "Weekday home mornings stay at 6")
    }

    func testEightyPercentCounts() {
        XCTAssertEqual(RoutineRules.required(11, share: 0.8), 9)
        XCTAssertEqual(RoutineRules.required(5, share: 0.8), 4)
        XCTAssertEqual(RoutineRules.required(4, share: 0.8), 4)
        XCTAssertEqual(RoutineRules.required(0, share: 0.8), 0)
    }

    func testAnswersBecomeTheDefaults() {
        let weekday = RoutineCatalogue.defaults(for: RoutineKey(part: .morning, days: .weekday, place: .home)).map(\.id)
        XCTAssertEqual(weekday.count, 11)
        XCTAssertTrue(weekday.contains("sunlight") && weekday.contains("journal"))
        let weekend = RoutineCatalogue.defaults(for: RoutineKey(part: .morning, days: .weekend, place: .home)).map(\.id)
        XCTAssertEqual(Set(weekend), Set(weekday + ["stretch", "breathe"]))
        XCTAssertEqual(RoutineCatalogue.defaults(for: RoutineKey(part: .morning, days: .weekday, place: .away)).map(\.id),
                       ["water", "tablets", "teeth", "dressed"])
        XCTAssertEqual(RoutineCatalogue.defaults(for: RoutineKey(part: .evening, days: .weekend, place: .home)).count, 5)
        XCTAssertTrue(RoutineSetup.defaultTimes(RoutineKey(part: .evening, days: .weekday, place: .away)).isAdHoc)
        XCTAssertEqual(RoutineSetup.defaultTimes(RoutineKey(part: .evening, days: .weekend, place: .home)).start, 22 * 60)
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

        clock = monday.date(atMinute: 7 * 60, calendar: fixtures.london)
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

    func testNotHomeByHalfEightMakesTheNightAway() {
        let monday = fixtures.monday
        var clock = monday.date(atMinute: 12 * 60, calendar: fixtures.london)
        let (routines, reminders) = make { clock }
        saveDefaults(routines)
        XCTAssertTrue(reminders.latest.contains { $0.id.hasSuffix("evening.out") }, "An 8:30 pm check-in")
        var info = RoutineDayInfo()
        routines.dayInfo = { _ in info }

        clock = monday.date(atMinute: 20 * 60 + 40, calendar: fixtures.london)
        info.outAtHalfEight = true
        routines.refreshSchedule()
        XCTAssertEqual(routines.place(.evening, on: monday), .away)
        XCTAssertTrue(routines.isAutoAway(.evening, on: monday))

        routines.setPlace(.home, part: .evening, on: monday)
        routines.refreshSchedule()
        XCTAssertEqual(routines.place(.evening, on: monday), .home, "Your own choice wins")
    }

    func testLeaveAndEarlyEventsAreKeptOnceTheMorningCloses() {
        let tuesday = fixtures.monday.adding(days: 1, calendar: fixtures.london)
        var clock = fixtures.monday.date(atMinute: 20 * 60, calendar: fixtures.london)
        let (routines, _) = make { clock }
        saveDefaults(routines)
        var info = RoutineDayInfo(isLeave: true, firstEvent: tuesday.date(atMinute: 9 * 60 + 30, calendar: fixtures.london))
        routines.dayInfo = { _ in info }
        routines.refreshSchedule()
        XCTAssertEqual(routines.key(.morning, on: tuesday).days, .weekend, "Leave at home: a Saturday morning")
        XCTAssertEqual(routines.window(.morning, on: tuesday).end, tuesday.date(atMinute: 9 * 60 + 30, calendar: fixtures.london))

        clock = tuesday.date(atMinute: 10 * 60, calendar: fixtures.london)
        info = RoutineDayInfo()
        routines.refreshSchedule()
        XCTAssertEqual(routines.key(.morning, on: tuesday).days, .weekend, "Closed: it doesn't change afterwards")
        XCTAssertEqual(routines.status(.morning, on: tuesday), .missed)
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

final class JournalTests: XCTestCase {
    let london = PlannerFixtures().london
    let monday = PlannerFixtures().monday

    private func entry(_ dayOffset: Int, _ mood: Mood, _ feelings: [String] = []) -> JournalSnapshot {
        JournalSnapshot(date: monday.adding(days: dayOffset, calendar: london).date(atMinute: 21 * 60, calendar: london),
                        mood: mood, feelings: feelings)
    }

    func testTrends() {
        let entries = [entry(0, .low, ["Tired"]), entry(0, .good, ["Calm", "Tired"]), entry(1, .great, ["Proud"]),
                       entry(3, .okay, ["Tired"])]
        let series = JournalStats.dailyMood(entries, from: monday, through: monday.adding(days: 6, calendar: london),
                                            calendar: london)
        XCTAssertEqual(series.map { $0.mood }, [3, 5, 3], "Two entries in a day are averaged")
        XCTAssertEqual(JournalStats.average(entries, from: monday, through: monday.adding(days: 1, calendar: london),
                                            calendar: london), 11.0 / 3)
        XCTAssertEqual(JournalStats.topFeelings(entries).first?.feeling, "Tired")
        XCTAssertEqual(JournalStats.topFeelings(entries).first?.count, 3)
    }

    func testStreak() {
        let entries = [entry(0, .okay), entry(1, .okay), entry(2, .okay), entry(4, .okay)]
        XCTAssertEqual(JournalStats.streak(entries, today: monday.adding(days: 2, calendar: london), calendar: london), 3)
        XCTAssertEqual(JournalStats.streak(entries, today: monday.adding(days: 3, calendar: london), calendar: london), 3,
                       "Today not written yet still keeps yesterday's streak")
        XCTAssertEqual(JournalStats.streak(entries, today: monday.adding(days: 6, calendar: london), calendar: london), 0)
    }

    @MainActor
    func testJournalModelSavesEntries() {
        let journal = JournalModel(container: Persistence.makeContainer(inMemory: true), calendar: london,
                                   now: { self.monday.date(atMinute: 21 * 60, calendar: self.london) })
        let saved = journal.add(mood: .good, feelings: ["Proud"], text: "  1. Gym\n2. Lunch\n3. Walk  ", prompt: "Three wins",
                                routineItemID: "wins")
        XCTAssertEqual(journal.entries.count, 1)
        XCTAssertEqual(saved.text, "1. Gym\n2. Lunch\n3. Walk")
        XCTAssertEqual(journal.todaysMood, .good)
        XCTAssertEqual(journal.streak, 1)
        journal.delete(saved)
        XCTAssertTrue(journal.entries.isEmpty)
    }
}
