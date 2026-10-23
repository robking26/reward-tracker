import XCTest
@testable import FitnessVault

/// A London calendar, Monday 2 November 2026, and labelled calendars.
struct PlannerFixtures {
    let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()
    /// Monday 2 November 2026.
    let monday = DayKey(year: 2026, month: 11, day: 2)
    let roles: [String: CalendarRole] = ["work": .work, "mine": .mine, "becky": .becky, "other": .ignored]

    func event(_ title: String, _ calendarID: String, _ day: DayKey, _ start: Int, _ end: Int, series: String? = nil,
               notes: String? = nil, allDay: Bool = false) -> CalendarEventInfo {
        let id = "\(calendarID)-\(title)-\(day)-\(start)"
        return CalendarEventInfo(id: id, seriesID: series ?? id, calendarID: calendarID, title: title,
                                 start: day.date(atMinute: start, calendar: london), end: day.date(atMinute: end, calendar: london),
                                 isAllDay: allDay, notes: notes)
    }
}

final class DayCalendarTests: XCTestCase {
    let fixtures = PlannerFixtures()
    var london: Calendar { fixtures.london }
    var monday: DayKey { fixtures.monday }
    var roles: [String: CalendarRole] { fixtures.roles }

    func event(_ title: String, _ calendarID: String, _ day: DayKey, _ start: Int, _ end: Int, series: String? = nil,
               notes: String? = nil, allDay: Bool = false) -> CalendarEventInfo {
        fixtures.event(title, calendarID, day, start, end, series: series, notes: notes, allDay: allDay)
    }

    func testNineAmFocusSetsWhereYouWork() {
        let tuesday = monday.adding(days: 1, calendar: london), wednesday = monday.adding(days: 2, calendar: london)
        let thursday = monday.adding(days: 3, calendar: london), saturday = monday.adding(days: 5, calendar: london)
        let events = [
            event("Office focus", "work", monday, 540, 570),
            event("Home Focus", "work", tuesday, 0, 1_440, allDay: true),
            event("Office focus", "work", wednesday, 840, 900),
            event("Stand-up", "work", thursday, 570, 585),
            event("Office focus", "mine", saturday, 540, 570),
        ]
        func location(_ day: DayKey) -> WorkLocation {
            DayCalendar.workLocation(on: day, events: events, roles: roles, calendar: london)
        }
        XCTAssertEqual(location(monday), .office)
        XCTAssertEqual(location(tuesday), .home)
        XCTAssertEqual(location(wednesday), .unknown, "Only the 9 am event counts")
        XCTAssertEqual(location(thursday), .unknown, "Meetings but no marker: a work day")
        XCTAssertEqual(location(saturday), .dayOff, "Only the work calendar sets it")
    }

    func testFocusMarkersShowAsTheLocationNotAsEvents() {
        let events = [event("Office focus", "work", monday, 540, 570), event("Stand-up", "work", monday, 570, 585)]
        let day = DayCalendar.events(on: monday, events: events, roles: roles, decisions: [:], calendar: london)
        XCTAssertEqual(day.map(\.event.title), ["Stand-up"])
    }

    func testBeckysEventsCountOnlyOnceShared() {
        let pilates = event("Pilates", "becky", monday, 1_080, 1_140, series: "pilates")
        let nextWeek = event("Pilates", "becky", monday.adding(days: 7, calendar: london), 1_080, 1_140, series: "pilates")
        let mine = event("Dentist", "mine", monday, 960, 1_005)
        let ignored = event("Bins", "other", monday, 420, 430)
        let all = [pilates, nextWeek, mine, ignored]
        let now = monday.date(atMinute: 480, calendar: london)

        var day = DayCalendar.events(on: monday, events: all, roles: roles, decisions: [:], calendar: london)
        XCTAssertEqual(day.map(\.event.title), ["Dentist", "Pilates"], "Unlabelled calendars are left out")
        XCTAssertTrue(day[0].blocksTime, "Everything in your own calendar counts")
        XCTAssertEqual(day[1].source, .beckyUnconfirmed)
        XCTAssertFalse(day[1].blocksTime, "Unconfirmed: visible, not relevant")
        XCTAssertEqual(DayCalendar.needsConfirming(all, roles: roles, decisions: [:], now: now).map(\.id), [pilates.id],
                       "One question per repeating event")

        day = DayCalendar.events(on: monday, events: all, roles: roles, decisions: ["pilates": true], calendar: london)
        XCTAssertTrue(day[1].blocksTime)
        XCTAssertTrue(DayCalendar.needsConfirming(all, roles: roles, decisions: ["pilates": true], now: now).isEmpty)

        day = DayCalendar.events(on: monday, events: all, roles: roles, decisions: ["pilates": false], calendar: london)
        XCTAssertEqual(day[1].source, .beckyVisible)
        XCTAssertFalse(day[1].blocksTime)
    }

    func testNewBeckyEventsAskAndPastOnesDont() {
        let past = event("Brunch", "becky", monday, 600, 660)
        let new = event("Cinema", "becky", monday, 1_200, 1_320)
        let now = monday.date(atMinute: 720, calendar: london)
        XCTAssertEqual(DayCalendar.needsConfirming([past, new], roles: roles, decisions: [:], now: now).map(\.title), ["Cinema"])
    }

    func testPlannedMarker() {
        XCTAssertEqual(event("Gym", "mine", monday, 0, 60, notes: "vaultality:gym\nLeave 17:45").plannedActivity, .gym)
        XCTAssertEqual(event("Shop", "mine", monday, 0, 60, notes: "vaultality:aldiShop").plannedActivity, .aldiShop)
        XCTAssertNil(event("Gym", "mine", monday, 0, 60, notes: "Leg day").plannedActivity)
    }
}

final class DayPlannerTests: XCTestCase {
    let helper = PlannerFixtures()
    var london: Calendar { helper.london }
    var monday: DayKey { helper.monday }

    private func place(_ name: String) -> SavedPlace { SavedPlace(name: name, coordinate: .bolton) }

    private func settings(gym: Int = 3, swims: Int = 1, runs: Int = 2) -> PlannerSettings {
        var settings = PlannerSettings()
        settings.roles = helper.roles
        settings.places = PlannerPlaces(home: place("Home"), office: place("Office"), gym: place("PureGym"),
                                        pool: place("Leisure centre"), aldi: place("Aldi"))
        settings.gymPerWeek = gym
        settings.swimsPerWeek = swims
        settings.runsPerWeek = runs
        return settings
    }

    private func travel(_ pairs: [(PlaceID, PlaceID, Int)]) -> TravelTable {
        var table = TravelTable()
        for (from, to, minutes) in pairs { table.set(minutes, from: from, to: to) }
        return table
    }

    private func input(days: [DayKey], events: [CalendarEventInfo] = [], settings: PlannerSettings,
                       travel: TravelTable = TravelTable()) -> PlannerInput {
        PlannerInput(days: days, now: monday.date(atMinute: 360, calendar: london), calendar: london, events: events,
                     settings: settings, travel: travel)
    }

    private func at(_ day: DayKey, _ hour: Int, _ minute: Int = 0) -> Date { day.date(atMinute: hour * 60 + minute, calendar: london) }

    private func week() -> [DayKey] { (0..<7).map { monday.adding(days: $0, calendar: london) } }

    func testGymFitsAfterWorkWithTheDriveBothWays() throws {
        let events = [helper.event("Home focus", "work", monday, 540, 570)]
        var plan = input(days: [monday], events: events, settings: settings(swims: 0, runs: 0),
                         travel: travel([(.home, .gym, 10)]))
        plan.settings.gymPerWeek = 1
        let gym = try XCTUnwrap(DayPlanner.plan(plan)[0].suggestions.first { $0.kind == .gym })
        XCTAssertEqual(gym.travelThere, 15, "10 minutes from Maps, plus 10% and parking")
        XCTAssertEqual(gym.minutes, 60, "At least an hour working out")
        XCTAssertEqual(gym.leaveAt, at(monday, 17, 45))
        XCTAssertEqual(gym.start, at(monday, 18))
        XCTAssertEqual(gym.backAt, at(monday, 19, 15))
        XCTAssertEqual(gym.origin, .home)
        XCTAssertFalse(gym.travelIsEstimate)
    }

    func testOfficeDayEveningsStartFromTheOffice() throws {
        let events = [helper.event("Office focus", "work", monday, 540, 570)]
        let plan = input(days: [monday], events: events, settings: settings(gym: 1, swims: 0, runs: 0),
                         travel: travel([(.home, .office, 20), (.office, .gym, 5), (.gym, .home, 10)]))
        let picture = DayPlanner.plan(plan)[0]
        XCTAssertEqual(picture.location, .office)
        XCTAssertEqual(picture.free.first?.interval.end, at(monday, 8, 35), "The drive in comes off the morning")
        let gym = try XCTUnwrap(picture.suggestions.first { $0.kind == .gym })
        XCTAssertEqual(gym.origin, .office)
        XCTAssertEqual(gym.travelThere, 10)
        XCTAssertEqual(gym.travelBack, 15)
        XCTAssertEqual(gym.start, at(monday, 17, 55))
    }

    func testNoGymWhenTheGapIsTooShort() {
        let events = [helper.event("Home focus", "work", monday, 540, 570),
                      helper.event("Early start", "mine", monday, 360, 530),
                      helper.event("Dinner out", "mine", monday, 1_080, 1_290)]
        let plan = input(days: [monday], events: events, settings: settings(gym: 1, swims: 0, runs: 0),
                         travel: travel([(.home, .gym, 10)]))
        XCTAssertFalse(DayPlanner.plan(plan)[0].suggestions.contains { $0.kind == .gym })
    }

    func testBeckysUnconfirmedEventsDontBlockButSharedOnesDo() {
        let events = [helper.event("Home focus", "work", monday, 540, 570),
                      helper.event("Early start", "mine", monday, 360, 530),
                      helper.event("Pilates", "becky", monday, 1_050, 1_290, series: "pilates")]
        var plan = input(days: [monday], events: events, settings: settings(gym: 1, swims: 0, runs: 0),
                         travel: travel([(.home, .gym, 10)]))
        XCTAssertTrue(DayPlanner.plan(plan)[0].suggestions.contains { $0.kind == .gym })
        plan.decisions = ["pilates": true]
        XCTAssertFalse(DayPlanner.plan(plan)[0].suggestions.contains { $0.kind == .gym })
    }

    func testGymSessionsSpreadThroughTheWeek() {
        let plan = input(days: week(), settings: settings(gym: 3, swims: 1, runs: 0), travel: travel([(.home, .gym, 10)]))
        let pictures = DayPlanner.plan(plan)
        let gymDays = pictures.filter { $0.suggestions.contains { $0.kind == .gym } }.map(\.day)
        XCTAssertEqual(gymDays, [0, 2, 4].map { monday.adding(days: $0, calendar: london) })
        let swimDays = pictures.filter { $0.suggestions.contains { $0.kind == .swim } }.map(\.day)
        XCTAssertEqual(swimDays, [monday.adding(days: 1, calendar: london)], "On a day without the gym")
    }

    func testSessionsAlreadyDoneOrBookedCount() {
        var plan = input(days: week(), settings: settings(gym: 3, swims: 0, runs: 0), travel: travel([(.home, .gym, 10)]))
        plan.gymDays = [monday]
        let wednesday = monday.adding(days: 2, calendar: london)
        plan.events = [helper.event("Gym", "mine", wednesday, 1_065, 1_155, notes: "vaultality:gym")]
        let gyms = DayPlanner.plan(plan).flatMap(\.suggestions).filter { $0.kind == .gym }
        XCTAssertEqual(gyms.count, 1, "Three a week: one done, one booked")
        XCTAssertEqual(gyms.first?.detail, "Session 3 of 3 this week")
    }

    func testDismissingMovesItToAnotherDay() {
        var plan = input(days: Array(week().prefix(3)), settings: settings(gym: 1, swims: 0, runs: 0),
                         travel: travel([(.home, .gym, 10)]))
        XCTAssertEqual(DayPlanner.plan(plan).first { !$0.suggestions.filter { $0.kind == .gym }.isEmpty }?.day, monday)
        plan.dismissed = [DayPlanner.key(.gym, monday)]
        XCTAssertEqual(DayPlanner.plan(plan).first { !$0.suggestions.filter { $0.kind == .gym }.isEmpty }?.day,
                       monday.adding(days: 1, calendar: london))
    }

    func testWalksWaitForDryDaylight() throws {
        let saturday = monday.adding(days: 5, calendar: london)
        var plan = input(days: [saturday], settings: settings(gym: 0, swims: 0, runs: 0))
        plan.shopsDone = [monday.adding(days: 7, calendar: london)]
        plan.weather = (0..<24).map { hour in
            HourlyWeather(date: at(saturday, hour), temperature: 11, precipitationProbability: hour == 15 ? 10 : 80,
                          precipitation: hour == 15 ? 0 : 1.2, isDaylight: (8...17).contains(hour))
        }
        let walk = try XCTUnwrap(DayPlanner.plan(plan)[0].suggestions.first { $0.kind == .walk })
        XCTAssertEqual(walk.start, at(saturday, 15))
        plan.weather = plan.weather.map { (hour: HourlyWeather) -> HourlyWeather in
            var wet = hour
            wet.precipitationProbability = 90
            wet.precipitation = 2
            return wet
        }
        XCTAssertFalse(DayPlanner.plan(plan)[0].suggestions.contains { $0.kind == .walk }, "Wet all day: no walk")
    }

    func testLunchtimeWalkOnAWorkDay() throws {
        let events = [helper.event("Home focus", "work", monday, 540, 570),
                      helper.event("Early start", "mine", monday, 360, 530),
                      helper.event("Evening plans", "mine", monday, 1_060, 1_290),
                      helper.event("Lunch meeting", "work", monday, 720, 760)]
        let plan = input(days: [monday], events: events, settings: settings(gym: 0, swims: 0, runs: 0))
        let walk = try XCTUnwrap(DayPlanner.plan(plan)[0].suggestions.first { $0.kind == .walk })
        XCTAssertEqual(walk.start, at(monday, 12, 40), "After the meeting, inside the lunch break")
    }

    func testRunsOnlyWhileTheKneeIsSettled() {
        var plan = input(days: week(), settings: settings(gym: 0, swims: 0, runs: 2))
        XCTAssertEqual(DayPlanner.plan(plan).flatMap(\.suggestions).filter { $0.kind == .run }.count, 2)
        plan.kneeSettled = false
        XCTAssertTrue(DayPlanner.plan(plan).flatMap(\.suggestions).filter { $0.kind == .run }.isEmpty)
    }

    func testAldiShopThenBatchCookAtTheWeekend() throws {
        var plan = input(days: week(), settings: settings(gym: 0, swims: 0, runs: 0), travel: travel([(.home, .aldi, 6)]))
        let nextMonday = monday.adding(days: 7, calendar: london)
        plan.batchCook = [nextMonday: CookPlan(title: "Chicken fajita rice bowls", minutes: 55)]
        let suggestions = DayPlanner.plan(plan).flatMap(\.suggestions)
        let shop = try XCTUnwrap(suggestions.first { $0.kind == .aldiShop })
        let cook = try XCTUnwrap(suggestions.first { $0.kind == .batchCook })
        XCTAssertEqual(shop.day, monday.adding(days: 5, calendar: london), "Saturday")
        XCTAssertEqual(shop.travelThere, 10)
        XCTAssertEqual(cook.day, monday.adding(days: 6, calendar: london), "Sunday, after the shop")
        XCTAssertEqual(cook.minutes, 55)
        XCTAssertEqual(cook.travelThere, 0, "At home")

        plan.shopsDone = [nextMonday]
        plan.cooksDone = [nextMonday]
        XCTAssertTrue(DayPlanner.plan(plan).flatMap(\.suggestions).filter { $0.kind == .aldiShop || $0.kind == .batchCook }.isEmpty)
    }

    func testNothingNeedingAPlaceYouHaventSaved() {
        var settings = settings(gym: 1, swims: 1, runs: 0)
        settings.places.gym = nil
        settings.places.pool = nil
        let plan = input(days: week(), settings: settings)
        let kinds = Set(DayPlanner.plan(plan).flatMap(\.suggestions).map(\.kind))
        XCTAssertFalse(kinds.contains(.gym))
        XCTAssertFalse(kinds.contains(.swim))
    }

    func testRobKingALIsNotAWorkDay() {
        let events = [helper.event("Office focus", "work", monday, 540, 570),
                      helper.event("Rob King AL", "work", monday, 0, 1_440, allDay: true),
                      helper.event("Stand-up", "work", monday, 570, 585)]
        XCTAssertEqual(DayCalendar.workLocation(on: monday, events: events, roles: helper.roles, calendar: london), .leave)
        let picture = DayPlanner.plan(input(days: [monday], events: events, settings: settings(gym: 1, swims: 0, runs: 0),
                                            travel: travel([(.home, .gym, 10)])))[0]
        XCTAssertNil(picture.work, "No working hours on leave")
        XCTAssertEqual(picture.suggestions.first { $0.kind == .gym }?.start, at(monday, 10), "Day-off timing")
        XCTAssertFalse(picture.events.contains { $0.event.title == "Rob King AL" }, "Shown as the day, not an event")
        XCTAssertNotEqual(DayCalendar.workLocation(on: monday, events: [helper.event("Rob King all-hands", "work", monday, 600, 660)],
                                                   roles: helper.roles, calendar: london), .leave)
    }

    func testBlockedInOutlookIsFreeForYou() throws {
        let events = [helper.event("Home focus", "work", monday, 540, 570),
                      helper.event("Blocked", "work", monday, 840, 960),
                      helper.event("Evening plans", "mine", monday, 1_050, 1_290),
                      helper.event("Early start", "mine", monday, 360, 530)]
        let plan = input(days: [monday], events: events, settings: settings(gym: 1, swims: 0, runs: 0),
                         travel: travel([(.home, .gym, 10)]))
        let picture = DayPlanner.plan(plan)[0]
        XCTAssertEqual(picture.events.first { $0.event.title == "Blocked" }?.source, .workFree)
        XCTAssertTrue(picture.free.contains { $0.interval == DateInterval(start: at(monday, 14), end: at(monday, 16)) && !$0.isLunch })
        let gym = try XCTUnwrap(picture.suggestions.first { $0.kind == .gym })
        XCTAssertEqual(gym.leaveAt, at(monday, 14, 30), "Fits inside the blocked time, drive included")
        XCTAssertEqual(gym.backAt, at(monday, 16))
    }

    func testBlockedOnAnOfficeDayReturnsToTheOffice() throws {
        let events = [helper.event("Office focus", "work", monday, 540, 570),
                      helper.event("Blocked", "work", monday, 720, 870),
                      helper.event("Evening plans", "mine", monday, 1_050, 1_290),
                      helper.event("Early start", "mine", monday, 360, 530)]
        let plan = input(days: [monday], events: events, settings: settings(gym: 1, swims: 0, runs: 0),
                         travel: travel([(.home, .office, 20), (.office, .gym, 5), (.gym, .home, 30)]))
        let gym = try XCTUnwrap(DayPlanner.plan(plan)[0].suggestions.first { $0.kind == .gym })
        XCTAssertEqual(gym.origin, .office)
        XCTAssertEqual(gym.travelBack, 10, "Back to the office, not home")
    }

    func testLunchWalkInOutlookIsTheWalk() throws {
        let events = [helper.event("Home focus", "work", monday, 540, 570),
                      helper.event("Lunch walk", "work", monday, 750, 780),
                      helper.event("Evening plans", "mine", monday, 1_050, 1_290)]
        let plan = input(days: [monday], events: events, settings: settings(gym: 0, swims: 0, runs: 0))
        let picture = DayPlanner.plan(plan)[0]
        let walk = try XCTUnwrap(picture.suggestions.first { $0.kind == .walk })
        XCTAssertEqual(walk.start, at(monday, 12, 30))
        XCTAssertEqual(DayCalendar.workLocation(on: monday, events: [events[1]], roles: helper.roles, calendar: london), .dayOff,
                       "A lunch walk alone doesn't make a work day")
    }

    func testMissingDriveTimesFallBackAndSayso() throws {
        let plan = input(days: [monday], settings: settings(gym: 1, swims: 0, runs: 0))
        let gym = try XCTUnwrap(DayPlanner.plan(plan)[0].suggestions.first { $0.kind == .gym })
        XCTAssertEqual(gym.travelThere, 15)
        XCTAssertTrue(gym.travelIsEstimate)
    }

    func testTodayStartsFromNowAndFromWhereYouAre() throws {
        var plan = input(days: [monday], settings: settings(gym: 1, swims: 0, runs: 0),
                         travel: travel([(.current, .gym, 4), (.gym, .home, 10)]))
        plan.now = at(monday, 19, 2)
        plan.hasCurrentLocation = true
        let picture = DayPlanner.plan(plan)[0]
        XCTAssertEqual(picture.free.first?.interval.start, at(monday, 19, 5))
        let gym = try XCTUnwrap(picture.suggestions.first { $0.kind == .gym })
        XCTAssertEqual(gym.origin, .current)
        XCTAssertEqual(gym.travelThere, 10)
    }

    func testOldSettingsKeepTheirValues() throws {
        let decoded = try JSONDecoder().decode(PlannerSettings.self, from: Data(#"{"gymPerWeek": 4}"#.utf8))
        XCTAssertEqual(decoded.gymPerWeek, 4)
        XCTAssertEqual(decoded.gymMinutes, 60)
    }

    func testForecastParsing() throws {
        let json = #"{"hourly":{"time":[1793606400,1793610000],"temperature_2m":[9.5,10.1],"precipitation_probability":[5,70],"precipitation":[0,0.8],"is_day":[0,1]}}"#
        let hours = try OpenMeteoParser.parse(Data(json.utf8))
        XCTAssertEqual(hours.count, 2)
        XCTAssertFalse(hours[0].isDaylight)
        XCTAssertTrue(hours[1].isWet)
    }
}

@MainActor
final class PlannerModelTests: XCTestCase {
    func testAcceptingASuggestionBooksItInYourCalendar() async throws {
        let helper = PlannerFixtures()
        let london = helper.london
        let now = helper.monday.date(atMinute: 7 * 60, calendar: london)
        let service = DemoCalendarService(calendar: london)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "tests.planner.\(UUID().uuidString)"))
        let planner = PlannerModel(calendarService: service, location: FixedLocationService(nil),
                                   weather: FixedWeatherService(hours: []), travel: FixedTravelService(minutes: 10),
                                   defaults: defaults, calendar: london, now: { now })
        XCTAssertEqual(planner.settings.roles, DemoCalendarService.roles, "A first guess from the calendar names")
        for id in PlaceID.saveable {
            planner.update { $0.places[id] = SavedPlace(name: id.title, coordinate: .bolton) }
        }
        await planner.refresh()

        let today = try XCTUnwrap(planner.picture(for: helper.monday))
        XCTAssertEqual(today.location, .home)
        XCTAssertFalse(planner.needsConfirming.isEmpty, "Becky's Pilates needs an answer")
        let gym = try XCTUnwrap(today.suggestions.first { $0.kind == .gym })
        planner.accept(gym)
        XCTAssertEqual(service.added.count, 1)
        XCTAssertEqual(service.added.first?.plannedActivity, .gym)
        XCTAssertEqual(service.added.first?.start, gym.leaveAt)
        XCTAssertFalse(planner.picture(for: helper.monday)?.suggestions.contains { $0.kind == .gym } ?? true)

        let pilates = try XCTUnwrap(planner.needsConfirming.first { $0.title == "Pilates" })
        planner.confirm(pilates, shared: true)
        XCTAssertFalse(planner.needsConfirming.contains { $0.seriesID == pilates.seriesID })
    }
}

final class CalendarLayoutTests: XCTestCase {
    private func slot(_ id: String, _ start: Double, _ end: Double) -> CalendarSlot {
        CalendarSlot(id: id, start: Date(timeIntervalSinceReferenceDate: start * 3_600),
                     end: Date(timeIntervalSinceReferenceDate: end * 3_600))
    }

    func testOverlapsSitSideBySide() {
        let columns = CalendarLayout.columns([slot("a", 9, 10), slot("b", 9.5, 11), slot("c", 10, 10.5), slot("d", 12, 13)])
        XCTAssertEqual(columns["a"], CalendarColumn(column: 0, count: 2))
        XCTAssertEqual(columns["b"], CalendarColumn(column: 1, count: 2))
        XCTAssertEqual(columns["c"], CalendarColumn(column: 0, count: 2), "Takes the column a has left free")
        XCTAssertEqual(columns["d"], CalendarColumn(column: 0, count: 1), "On its own: full width")
    }

    func testBackToBackDoesntOverlap() {
        let columns = CalendarLayout.columns([slot("a", 9, 10), slot("b", 10, 11)])
        XCTAssertEqual(columns["a"]?.count, 1)
        XCTAssertEqual(columns["b"]?.count, 1)
    }
}
