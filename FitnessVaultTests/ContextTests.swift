import XCTest
import SwiftData
@testable import FitnessVault

private enum Context {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    static let monday = DayKey(year: 2026, month: 10, day: 19)

    static func at(_ hour: Int, _ minute: Int = 0, on day: DayKey = monday) -> Date {
        day.startDate(calendar: calendar).addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    static func event(_ title: String, _ start: (Int, Int), _ end: (Int, Int), _ kind: BlockKind, role: CalendarRole = .work,
                      day: DayKey = monday) -> ClassifiedEvent {
        ClassifiedEvent(event: CalendarEventInfo(id: title, calendarID: role.rawValue, title: title,
                                                 start: at(start.0, start.1, on: day), end: at(end.0, end.1, on: day), isAllDay: false),
                        role: role, kind: kind)
    }

    static let workday: [ClassifiedEvent] = [
        event("Stand-up", (9, 30), (9, 45), .workMeeting),
        event("Design review", (11, 0), (12, 0), .workMeeting),
        event("Focus time", (13, 0), (16, 0), .workFocus),
        event("Gym class", (18, 0), (19, 0), .sharedInfo, role: .shared),
    ]

    /// Hourly forecast for Monday 06:00–22:00; `wet` hours have rain.
    static func forecast(wet: Set<Int>) -> [HourlyWeather] {
        (6...22).map { hour in
            HourlyWeather(date: at(hour), temperature: Double(8 + hour / 3), precipitationProbability: wet.contains(hour) ? 80 : 10,
                          precipitation: wet.contains(hour) ? 1.2 : 0)
        }
    }

    static func input(events: [ClassifiedEvent] = workday, forecast: [HourlyWeather] = [], recovery: RecoveryStatus = .clear,
                      travel: Int? = nil, busyness: [BusynessReport] = [], social: Date? = nil,
                      windows: [OpportunityWindow]? = nil, isWorkday: Bool = true) -> RecommendationInput {
        let settings = CoachSettings()
        let now = at(6, 30)
        let computed = windows ?? Availability.windows(on: monday, shape: settings.shape(isWorkday: isWorkday),
                                                       blocks: CalendarClassifier.blocks(from: events), notBefore: now, calendar: calendar)
        return RecommendationInput(day: monday, now: now, calendar: calendar, settings: settings, isWorkday: isWorkday,
                                   windows: computed, events: events, existingKinds: [], workoutsThisWeek: 0,
                                   consecutiveWorkoutDays: 0, lastWorkoutWasUpper: nil, houseTask: nil,
                                   forecast: forecast, recovery: recovery, gymTravelMinutes: travel, busyness: busyness,
                                   socialEveningStart: social)
    }
}

final class ContextDomainTests: XCTestCase {
    // MARK: Weather

    func testOpenMeteoParsing() throws {
        let json = """
        {"hourly":{"time":[1792400400,1792404000,1792407600],"temperature_2m":[9.4,10.1,null],
        "precipitation_probability":[5,70,20],"precipitation":[0.0,1.4,0.0]}}
        """
        let hours = try OpenMeteoParser.parse(Data(json.utf8))
        XCTAssertEqual(hours.count, 2, "Hours without a temperature are dropped")
        XCTAssertEqual(hours[0].date, Date(timeIntervalSince1970: 1_792_400_400))
        XCTAssertFalse(hours[0].isWet)
        XCTAssertTrue(hours[1].isWet)
    }

    func testWeatherRequestUsesARoundedLocation() {
        let url = OpenMeteoParser.url(for: Coordinate(latitude: 53.57891, longitude: -2.42913))!.absoluteString
        XCTAssertTrue(url.contains("latitude=53.58"))
        XCTAssertTrue(url.contains("longitude=-2.43"))
        XCTAssertTrue(url.hasPrefix("https://api.open-meteo.com/"))
    }

    func testDryWindowsAndSummary() {
        let forecast = Context.forecast(wet: [12, 13])
        XCTAssertEqual(WeatherAdvisor.isDry(DateInterval(start: Context.at(12, 5), duration: 1800), forecast: forecast), false)
        XCTAssertEqual(WeatherAdvisor.isDry(DateInterval(start: Context.at(15), duration: 1800), forecast: forecast), true)
        XCTAssertNil(WeatherAdvisor.isDry(DateInterval(start: Context.at(15), duration: 1800), forecast: []), "Never guessed")
        let window = OpportunityWindow(interval: DateInterval(start: Context.at(11, 30), end: Context.at(15)), kind: .free)
        let dry = WeatherAdvisor.firstDryStart(in: [window], minutes: 30, forecast: forecast, notBefore: Context.at(11, 30))
        XCTAssertEqual(dry?.start, Context.at(11, 30))
        let afterRain = WeatherAdvisor.firstDryStart(in: [window], minutes: 30, forecast: forecast, notBefore: Context.at(11, 45))
        XCTAssertEqual(afterRain?.start, Context.at(14), "Skips the wet hours")

        XCTAssertEqual(WeatherAdvisor.summary(for: Context.monday, forecast: Context.forecast(wet: []), calendar: Context.calendar), "Dry, 10–14°")
        XCTAssertTrue(WeatherAdvisor.summary(for: Context.monday, forecast: Context.forecast(wet: Set(15...22)), calendar: Context.calendar)?
            .hasPrefix("Rain likely from") ?? false)
        XCTAssertTrue(WeatherAdvisor.summary(for: Context.monday, forecast: Context.forecast(wet: Set(6...22)), calendar: Context.calendar)?
            .hasPrefix("Wet all day") ?? false)
    }

    // MARK: Places and travel

    func testModeComesFromYourChoiceThenCalendarThenLocation() {
        let home = Coordinate(latitude: 53.60, longitude: -2.50)
        let places = SavedPlaces(home: SavedPlace(name: "Home", coordinate: home), office: nil, gym: nil)
        let nearby = Coordinate(latitude: 53.6010, longitude: -2.5010)
        XCTAssertLessThan(home.distance(to: nearby), 300)
        XCTAssertEqual(PlaceMode.infer(current: nearby, places: places), .home)
        XCTAssertNil(PlaceMode.infer(current: Coordinate(latitude: 53.70, longitude: -2.50), places: places))
        XCTAssertEqual(PlaceMode.resolve(override: .office, calendar: .home, location: .home), .office)
        XCTAssertEqual(PlaceMode.resolve(override: nil, calendar: .home, location: .office), .home)
        XCTAssertEqual(PlaceMode.resolve(override: nil, calendar: .unknown, location: .office), .office)
        XCTAssertEqual(PlaceMode.resolve(override: nil, calendar: .unknown, location: nil), .unknown)
    }

    func testTravelUsesFreshLiveEstimatesOnly() {
        let now = Context.at(16)
        let fresh = TravelEstimate(minutes: 20, source: .live, updatedAt: now.addingTimeInterval(-600))
        XCTAssertEqual(TravelPlanner.gymMinutes(live: fresh, setting: 15, now: now).minutes, 25, "20 + 10% + 3 for parking, rounded up to 5")
        let stale = TravelEstimate(minutes: 20, source: .live, updatedAt: now.addingTimeInterval(-3 * 3600))
        XCTAssertEqual(TravelPlanner.gymMinutes(live: stale, setting: 15, now: now).source, .setting)
        XCTAssertEqual(TravelPlanner.leaveBy(Context.at(17, 30), travelMinutes: 20), Context.at(17))
    }

    func testBusynessComesOnlyFromYourReports() {
        let calendar = Context.calendar
        let tuesday = Context.monday.adding(days: 1, calendar: calendar)
        let reports = [BusynessReport(date: Context.at(17, 10), level: .busy),
                       BusynessReport(date: Context.at(17, 40, on: tuesday), level: .busy),
                       BusynessReport(date: Context.at(18, 5, on: tuesday), level: .normal)]
        let estimate = GymBusynessEstimator.estimate(at: Context.at(17, 30), reports: reports, calendar: calendar)
        XCTAssertEqual(estimate?.level, .busy)
        XCTAssertEqual(estimate?.label, "Usually busy then (from 3 of your visits)")
        XCTAssertNil(GymBusynessEstimator.estimate(at: Context.at(9), reports: reports, calendar: calendar), "No reports, no estimate")
        let saturday = DayKey(year: 2026, month: 10, day: 24)
        XCTAssertNil(GymBusynessEstimator.estimate(at: Context.at(17, 30, on: saturday), reports: reports, calendar: calendar),
                     "Weekdays don't predict weekends")
    }

    // MARK: Social and recovery

    func testSocialDetection() {
        let saturday = DayKey(year: 2026, month: 10, day: 24)
        let events = [
            Context.event("Golf with Dave", (9, 0), (14, 0), .personal, role: .personal, day: saturday),
            Context.event("Barber", (10, 0), (10, 30), .personal, role: .personal),
            Context.event("Drinks with Jo and Sam", (19, 0), (23, 0), .sharedInfo, role: .shared),
            Context.event("Design review", (11, 0), (12, 0), .workMeeting),
        ]
        let detected = SocialDetector.detect(events, calendar: Context.calendar)
        XCTAssertEqual(detected.map(\.kind), [.golf, .nightOut])
        XCTAssertFalse(detected[0].needsConfirmation)
        XCTAssertTrue(detected[1].needsConfirmation, "Becky's shared plans are asked about, not assumed")
        let away = ClassifiedEvent(event: CalendarEventInfo(id: "away", calendarID: "p", title: "Weekend away in York",
                                                            start: Context.at(0, on: saturday),
                                                            end: Context.at(0, on: saturday.adding(days: 3, calendar: Context.calendar)),
                                                            isAllDay: true),
                                   role: .personal, kind: .allDayInfo)
        XCTAssertEqual(SocialDetector.detect([away], calendar: Context.calendar).first?.days, 3)
    }

    func testDrinkingPlansAndRecoveryLength() {
        XCTAssertEqual(SocialPlanner.recoveryDays(plan: .alcoholFree, eventDays: 2), 0)
        XCTAssertEqual(SocialPlanner.recoveryDays(plan: .lighter, eventDays: 1), 1)
        XCTAssertEqual(SocialPlanner.recoveryDays(plan: .moderate, eventDays: 1), 2)
        XCTAssertEqual(SocialPlanner.recoveryDays(plan: .undecided, eventDays: 1), 3, "48–72 hours after a big one")
        XCTAssertEqual(SocialPlanner.recoveryDays(plan: .moderate, eventDays: 3), 3, "Capped at three days")

        let driving = SocialPlanner.advice(kind: .golf, plan: .moderate, driving: true, eventDays: 1)
        XCTAssertTrue(driving.first?.contains("no alcohol before you drive") ?? false)
        let weekend = SocialPlanner.advice(kind: .weekendAway, plan: .undecided, driving: false, eventDays: 3).joined(separator: " ")
        XCTAssertTrue(weekend.contains("adds up"))
        let all = (SocialKind.allCases.flatMap { kind in DrinkingPlan.allCases.flatMap { SocialPlanner.advice(kind: kind, plan: $0, driving: false, eventDays: 2) } })
            .joined(separator: " ").lowercased()
        XCTAssertFalse(all.contains("safe"), "Never implies heavy drinking is risk-free")
        XCTAssertFalse(all.contains("betting") || all.contains("casino") || all.contains("gambl") || all.contains("bookie"), "No gambling suggestions")

        XCTAssertEqual(SocialPlanner.preparation(plan: .alcoholFree, eventDays: 1, nextDayHasWorkout: true).filter { $0.action != .reminder }.count, 0)
        let undecided = SocialPlanner.preparation(plan: .undecided, eventDays: 1, nextDayHasWorkout: false)
        XCTAssertTrue(undecided.contains { $0.action == .freezerMealNextDay })
        XCTAssertTrue(undecided.contains { $0.action == .planRecovery })
    }

    func testRecoveryWindowEndsWithARestartDay() {
        let calendar = Context.calendar
        let start = Context.monday
        let window = RecoveryWindow(start: start, days: 2, feeling: nil, endedOn: nil)
        XCTAssertEqual(window.status(on: start, calendar: calendar), .recovering(.rough))
        XCTAssertEqual(window.status(on: start.adding(days: 1, calendar: calendar), calendar: calendar), .recovering(.rough))
        XCTAssertEqual(window.status(on: start.adding(days: 2, calendar: calendar), calendar: calendar), .restarting)
        XCTAssertEqual(window.status(on: start.adding(days: 3, calendar: calendar), calendar: calendar), .clear)
        let early = RecoveryWindow(start: start, days: 3, feeling: .normal, endedOn: start.adding(days: 1, calendar: calendar))
        XCTAssertEqual(early.status(on: start.adding(days: 1, calendar: calendar), calendar: calendar), .restarting)
        XCTAssertTrue(RecoveryPlanner.guidance(.rough).joined().contains("No gym today"))
        XCTAssertFalse(RecoveryPlanner.guidance(.rough).joined().lowercased().contains("burn"), "No compensating")
    }

    // MARK: Outings

    func testOutingIdeas() {
        let calendar = Context.calendar
        let day = Context.monday
        XCTAssertNil(OutingPlanner.tonight(day: day, userFreeEvening: true, beckyFreeEvening: false, eveningIsDry: true,
                                           recentIDs: [], daysSinceLastIdea: nil, recovering: false, calendar: calendar))
        XCTAssertNil(OutingPlanner.tonight(day: day, userFreeEvening: true, beckyFreeEvening: true, eveningIsDry: true,
                                           recentIDs: [], daysSinceLastIdea: 1, recovering: false, calendar: calendar), "Spaced out")
        XCTAssertNil(OutingPlanner.tonight(day: day, userFreeEvening: true, beckyFreeEvening: true, eveningIsDry: true,
                                           recentIDs: [], daysSinceLastIdea: nil, recovering: true, calendar: calendar))
        for offset in 0..<14 {
            let idea = OutingPlanner.tonight(day: day.adding(days: offset, calendar: calendar), userFreeEvening: true,
                                             beckyFreeEvening: true, eveningIsDry: false, recentIDs: ["cinema"],
                                             daysSinceLastIdea: nil, recovering: false, calendar: calendar)
            XCTAssertNotNil(idea)
            XCTAssertFalse(idea?.outdoor ?? true, "Nothing outdoors when it's wet")
            XCTAssertNotEqual(idea?.id, "cinema", "Not a recent repeat")
        }
        let busy: Set<DayKey> = [DayKey(year: 2026, month: 11, day: 7), DayKey(year: 2026, month: 11, day: 15)]
        XCTAssertEqual(OutingPlanner.freeWeekend(from: day, busyDays: busy, calendar: calendar), DayKey(year: 2026, month: 11, day: 21),
                       "Skips weekends with anything on either day")
    }

    func testMenuPicks() {
        let menu = """
        MAINS
        Wild mushroom risotto 14.50
        Grilled chicken skewers with flatbread £15.95
        Beer-battered fish and chips 16.00
        Halloumi burger 13.50
        Cheese and onion pie 12.00
        """
        let picks = MenuAdvisor.picks(from: menu)
        XCTAssertEqual(picks.first?.dish, "Grilled chicken skewers with flatbread")
        XCTAssertTrue(picks.first?.reason.contains("grilled") ?? false)
        XCTAssertFalse(picks.contains { $0.dish.lowercased().contains("mushroom") }, "Exclusions are never picked")
        XCTAssertFalse(picks.contains { $0.dish.contains("pie") })
        XCTAssertTrue(MenuAdvisor.footnote.contains("rough guide"))
    }
}

final class ContextRecommendationTests: XCTestCase {
    func testRainAtLunchMovesTheWalk() {
        let suggestions = RecommendationEngine.morning(Context.input(forecast: Context.forecast(wet: [12, 13])))
        let walk = suggestions.first { $0.kind == .walk }
        XCTAssertEqual(walk?.start, Context.at(16))
        XCTAssertTrue(walk?.reason.contains("Rain") ?? false)
    }

    func testNoWalkSuggestedInAllDayRain() {
        let suggestions = RecommendationEngine.morning(Context.input(forecast: Context.forecast(wet: Set(6...22))))
        XCTAssertFalse(suggestions.contains { $0.kind == .walk })
        XCTAssertTrue(suggestions.contains { $0.kind == .workout }, "The gym is indoors")
    }

    func testRecoveryDaysAskForNothingDemanding() {
        let rough = RecommendationEngine.morning(Context.input(recovery: .recovering(.rough)))
        XCTAssertEqual(rough.map(\.kind), [.selfCare])
        let better = RecommendationEngine.morning(Context.input(recovery: .recovering(.gettingThere)))
        XCTAssertEqual(better.map(\.kind), [.walk, .selfCare])
        XCTAssertEqual(better.first?.title, "Gentle walk")
        XCTAssertEqual(better.first?.durationMinutes, 20)
    }

    func testRestartDayIsOneEasyThing() {
        let suggestions = RecommendationEngine.morning(Context.input(recovery: .restarting))
        XCTAssertEqual(suggestions.map(\.kind), [.workout, .selfCare])
        XCTAssertEqual(suggestions.first?.title, "Easy upper body at Nuffield")
        XCTAssertEqual(suggestions.first?.durationMinutes, 80, "40 minutes training plus travel and changing")
    }

    func testSocialEveningKeepsTheGymOut() {
        let suggestions = RecommendationEngine.morning(Context.input(social: Context.at(18, 30)))
        XCTAssertFalse(suggestions.contains { $0.kind == .workout }, "No time for the full trip before getting ready to go out")
    }

    func testLiveTravelTimeLengthensTheTrip() {
        let suggestions = RecommendationEngine.morning(Context.input(travel: 25))
        XCTAssertEqual(suggestions.first { $0.kind == .workout }?.durationMinutes, 120)
    }

    func testQuieterTimeIsPreferredFromYourReports() {
        let calendar = Context.calendar
        let lastWeek = Context.monday.adding(days: -7, calendar: calendar)
        let lastTuesday = lastWeek.adding(days: 1, calendar: calendar)
        let reports = [BusynessReport(date: Context.at(7, 15, on: lastWeek), level: .busy),
                       BusynessReport(date: Context.at(7, 20, on: lastTuesday), level: .busy),
                       BusynessReport(date: Context.at(14, 10, on: lastWeek), level: .quiet),
                       BusynessReport(date: Context.at(14, 30, on: lastTuesday), level: .quiet)]
        let windows = [OpportunityWindow(interval: DateInterval(start: Context.at(7), end: Context.at(9)), kind: .free),
                       OpportunityWindow(interval: DateInterval(start: Context.at(14), end: Context.at(16)), kind: .free)]
        let suggestions = RecommendationEngine.morning(Context.input(events: [], busyness: reports, windows: windows, isWorkday: false))
        let gym = suggestions.first { $0.kind == .workout }
        XCTAssertEqual(gym?.start, Context.at(14))
        XCTAssertTrue(gym?.reason.hasPrefix("Usually quiet then") ?? false)
    }
}

@MainActor
final class SituationModelTests: XCTestCase {
    private struct Harness {
        var coach: CoachModel
        var situation: SituationModel
        var clock: TestClock
    }

    private func make(at date: Date) async -> Harness {
        let clock = TestClock(date)
        let container = Persistence.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "context.test.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.settings.demoMode = true
        let demo = DemoCalendarService(calendar: Context.calendar)
        let coach = CoachModel(container: container, settingsStore: settings, liveCalendar: demo, demoCalendar: demo,
                               defaults: defaults, reminders: RecordingReminderScheduler(), languageModel: nil,
                               calendar: Context.calendar, now: { clock.date })
        await coach.start()
        let situation = SituationModel(container: container, coach: coach,
                                       weather: FixedWeatherService(hours: Context.forecast(wet: [])),
                                       location: FixedLocationService(nil), travel: FixedTravelService(minutes: 18, place: nil),
                                       calendar: Context.calendar, now: { clock.date })
        await situation.refresh()
        return Harness(coach: coach, situation: situation, clock: clock)
    }

    func testRefreshLoadsWeatherWithoutLocation() async {
        let h = await make(at: Context.at(8))
        XCTAssertEqual(h.situation.weatherSummary, "Dry, 10–14°")
        XCTAssertNil(h.situation.currentLocation, "Location stays off until the user turns it on")
        XCTAssertNil(h.situation.gymTravelMinutes)
    }

    func testWorkModeFromConversation() async {
        let h = await make(at: Context.at(8))
        _ = h.coach.respond(to: "I'm working from home today")
        XCTAssertEqual(h.coach.workLocation, .home)
        _ = h.coach.respond(to: "I'm in the office today")
        XCTAssertEqual(h.coach.workLocation, .office)
    }

    func testGymBusynessReport() async {
        let h = await make(at: Context.at(18))
        let reply = h.coach.respond(to: "The gym was rammed")
        XCTAssertTrue(reply.text.contains("quieter"))
        XCTAssertEqual(h.situation.busynessReports().map(\.level), [.busy])
    }

    func testGoingOutPlansRecoveryForTheDayAfter() async {
        let h = await make(at: Context.at(10))
        let reply = h.coach.respond(to: "Going out tonight")
        XCTAssertEqual(reply.quickReplies, ["Alcohol-free", "Lighter", "Moderate", "Not decided"])
        XCTAssertNotNil(h.situation.socialEveningStart(on: Context.monday))
        let plan = h.coach.respond(to: "Lighter")
        XCTAssertTrue(plan.text.hasPrefix("Lighter."))
        let tuesday = Context.monday.adding(days: 1, calendar: Context.calendar)
        XCTAssertEqual(h.situation.recoveryStatus(on: tuesday), .recovering(.rough))
        XCTAssertEqual(h.situation.recoveryStatus(on: tuesday.adding(days: 1, calendar: Context.calendar)), .restarting)
    }

    func testFeelingRoughExcusesTheGymAndBackToNormalRestarts() async {
        let h = await make(at: Context.at(9))
        let gym = h.coach.addCommitment("Upper body at Nuffield", kind: .workout, start: Context.at(17), durationMinutes: 100)
        let reply = h.coach.respond(to: "I'm hungover")
        XCTAssertEqual(gym.state, .excused, "Recovery is never fined")
        XCTAssertTrue(reply.text.contains("no fine"))
        XCTAssertEqual(h.situation.recoveryStatus(on: Context.monday), .recovering(.rough))
        _ = h.coach.respond(to: "Back to normal")
        XCTAssertEqual(h.situation.recoveryStatus(on: Context.monday), .restarting)
    }
}
