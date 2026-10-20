import Foundation
import Observation
import SwiftData

/// Phase 6: where the user is, the weather, travel to the gym, social plans, recovery and outing ideas.
/// Feeds the recommendation engine through `CoachModel`; never touches commitments' scores itself.
@MainActor
@Observable
final class SituationModel {
    let context: ModelContext
    let calendar: Calendar
    let now: () -> Date
    @ObservationIgnored private weak var coach: CoachModel?
    @ObservationIgnored private weak var kitchen: KitchenModel?
    @ObservationIgnored private let weather: WeatherProviding
    @ObservationIgnored let location: LocationProviding
    @ObservationIgnored private let travel: TravelProviding

    private(set) var forecast: [HourlyWeather] = []
    private(set) var forecastFetchedAt: Date? = nil
    private(set) var weatherProblem: String? = nil
    private(set) var travelEstimate: TravelEstimate? = nil
    private(set) var currentLocation: Coordinate? = nil
    private(set) var upcomingSocial: [DetectedSocial] = []
    private(set) var plans: [SocialPlan] = []
    private(set) var recoveries: [RecoveryPeriod] = []
    private(set) var outingIdea: OutingIdea? = nil
    private(set) var freeWeekend: DayKey? = nil
    /// The eight-week calendar scan for a free weekend runs once a day, not on every refresh (performance).
    @ObservationIgnored private var weekendCheckedOn: DayKey? = nil

    init(container: ModelContainer, coach: CoachModel?, kitchen: KitchenModel? = nil,
         weather: WeatherProviding = OpenMeteoWeatherService(), location: LocationProviding? = nil,
         travel: TravelProviding = MapKitTravelService(), calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        context = container.mainContext
        self.coach = coach
        self.kitchen = kitchen
        self.weather = weather
        self.location = location ?? CoreLocationService()
        self.travel = travel
        self.calendar = calendar
        self.now = now
        coach?.situation = self
        reload()
    }

    var settings: CoachSettings { coach?.coach ?? CoachSettings() }
    var today: DayKey { DayKey(now(), calendar: calendar) }

    // MARK: Refresh

    func refresh() async {
        detectSocial()
        if settings.locationConsent, location.isAuthorised {
            currentLocation = await location.currentLocation()
        }
        await refreshWeather()
        await refreshTravel()
        computeOutings()
        cleanUpRecoveries()
        reload()
    }

    func refreshWeather(force: Bool = false) async {
        guard settings.weatherEnabled else {
            forecast = []
            return
        }
        if !force, let fetched = forecastFetchedAt, now().timeIntervalSince(fetched) < 3600 { return }
        let coordinate = (settings.locationConsent ? currentLocation : nil) ?? settings.places.home?.coordinate ?? .bolton
        do {
            forecast = try await weather.forecast(for: coordinate)
            forecastFetchedAt = now()
            weatherProblem = nil
        } catch {
            weatherProblem = "Weather isn't available right now, so walks aren't planned around rain."
        }
    }

    func refreshTravel(force: Bool = false) async {
        guard settings.locationConsent, let gym = settings.places.gym else { return }
        if !force, let estimate = travelEstimate, now().timeIntervalSince(estimate.updatedAt) < 30 * 60 { return }
        guard let origin = currentLocation ?? settings.places.home?.coordinate else { return }
        if let minutes = try? await travel.drivingMinutes(from: origin, to: gym.coordinate) {
            travelEstimate = TravelEstimate(minutes: minutes, source: .live, updatedAt: now())
        }
    }

    /// One-way gym travel the planner should use, if a live estimate is fresh.
    var gymTravelMinutes: Int? {
        let result = TravelPlanner.gymMinutes(live: travelEstimate, setting: settings.gymTravelMinutes, now: now())
        return result.source == .live ? result.minutes : nil
    }

    var weatherSummary: String? {
        WeatherAdvisor.summary(for: today, forecast: forecast, calendar: calendar)
    }

    /// Home or office from where the phone is (only with consent and saved places).
    var inferredMode: WorkLocation? {
        settings.locationConsent ? PlaceMode.infer(current: currentLocation, places: settings.places) : nil
    }

    // MARK: Places (L2)

    func setLocationConsent(_ on: Bool) {
        update { $0.locationConsent = on }
        if on { location.requestPermission() } else {
            currentLocation = nil
            travelEstimate = nil
        }
    }

    /// Saves where the phone is now as home or the office.
    func saveCurrentLocation(as kind: WorkLocation) async -> Bool {
        guard settings.locationConsent, let here = await location.currentLocation() else { return false }
        currentLocation = here
        update { settings in
            let place = SavedPlace(name: kind == .home ? "Home" : "Office", coordinate: here)
            if kind == .home { settings.places.home = place } else { settings.places.office = place }
        }
        return true
    }

    /// Finds the gym with Apple Maps rather than assuming its address.
    func findGym(_ query: String = "Nuffield Health Bolton") async -> SavedPlace? {
        let near = currentLocation ?? settings.places.home?.coordinate ?? .bolton
        guard let place = try? await travel.search(query, near: near) else { return nil }
        update { $0.places.gym = place }
        await refreshTravel(force: true)
        return place
    }

    private func update(_ change: (inout CoachSettings) -> Void) {
        guard let coach else { return }
        change(&coach.settingsStore.settings.coach)
    }

    // MARK: Social plans (SO1–SO2)

    func detectSocial() {
        guard let coach else { return }
        let start = now()
        let raw = coach.calendarProvider.events(from: start, to: start.addingTimeInterval(7 * 86_400))
        let events = CalendarClassifier.classify(raw, roles: coach.calendarRoles)
        upcomingSocial = SocialDetector.detect(events, calendar: calendar)
            .filter { $0.end > start }
            .sorted { $0.start < $1.start }
    }

    func plan(for detected: DetectedSocial) -> SocialPlan {
        if let existing = plans.first(where: { $0.eventID == detected.eventID }) { return existing }
        let created = SocialPlan(detected)
        context.insert(created)
        save()
        reload()
        return created
    }

    /// The first social event in the next three days that hasn't been planned yet.
    var nextUnplannedSocial: DetectedSocial? {
        let horizon = now().addingTimeInterval(3 * 86_400)
        return upcomingSocial.first { social in
            social.start < horizon && social.kind.oftenInvolvesDrinking
                && !plans.contains { $0.eventID == social.eventID && ($0.drinking != .undecided || !$0.preparedSteps.isEmpty || !$0.going) }
        }
    }

    func save(_ plan: SocialPlan, drinking: DrinkingPlan, driving: Bool, going: Bool) {
        plan.drinking = drinking
        plan.driving = driving
        plan.going = going
        save()
        reload()
    }

    /// Carries out a preparation step. Returns what happened, for the user.
    @discardableResult
    func prepare(_ step: PrepStep, for plan: SocialPlan) -> String {
        var result = "Done."
        switch step.action {
        case .freezerMealNextDay:
            let nextDay = DayKey(plan.end.addingTimeInterval(-1), calendar: calendar).adding(days: 1, calendar: calendar)
            if let kitchen, let dinner = kitchen.dinner(on: nextDay), let meal = kitchen.freezerMeals().first(where: { $0.portions >= 2 }) {
                kitchen.useFreezer(dinner, meal: meal)
                result = "\(meal.title) is on for the day after, with a defrost reminder the night before."
            } else {
                result = "No freezer meal to use. Something easy from the cupboard or a takeaway is fine that day."
            }
        case .planRecovery:
            let start = DayKey(plan.end.addingTimeInterval(-1), calendar: calendar).adding(days: 1, calendar: calendar)
            let days = SocialPlanner.recoveryDays(plan: plan.drinking, eventDays: plan.days)
            if days > 0 {
                startRecovery(from: start, days: days, reason: "After \(plan.title)")
                result = "The \(days == 1 ? "day" : "\(days) days") after will be gentle."
            }
        case .reminder:
            break
        }
        if !plan.preparedSteps.contains(step.title) { plan.preparedSteps.append(step.title) }
        save()
        reload()
        return result
    }

    /// Social plans the user is going to, starting today in the evening: the day's physical suggestions finish before them.
    func socialEveningStart(on day: DayKey) -> Date? {
        let evening = day.date(atMinute: 17 * 60, calendar: calendar)
        let end = day.endDate(calendar: calendar)
        let confirmed = upcomingSocial.filter { social in
            social.start >= evening && social.start < end
                && (plans.first { $0.eventID == social.eventID }?.going ?? !social.needsConfirmation)
        }
        return confirmed.map(\.start).min()
    }

    /// "Going out tonight": a plan without a calendar event.
    @discardableResult
    func addTonight(kind: SocialKind = .nightOut, title: String = "Night out") -> SocialPlan {
        let day = today
        let start = max(now(), day.date(atMinute: 19 * 60, calendar: calendar))
        let detected = DetectedSocial(eventID: "coach-\(day.description)", title: title, start: start,
                                      end: day.date(atMinute: 23 * 60 + 30, calendar: calendar),
                                      kind: kind, needsConfirmation: false, days: 1)
        if !upcomingSocial.contains(where: { $0.eventID == detected.eventID }) { upcomingSocial.append(detected) }
        return plan(for: detected)
    }

    // MARK: Recovery (SO3)

    func recoveryStatus(on day: DayKey) -> RecoveryStatus {
        let statuses = recoveries.compactMap { $0.window?.status(on: day, calendar: calendar) }
        if let recovering = statuses.first(where: { if case .recovering = $0 { return true } else { return false } }) {
            return recovering
        }
        return statuses.contains(.restarting) ? .restarting : .clear
    }

    var activeRecovery: RecoveryPeriod? {
        recoveries.first { period in
            guard let status = period.window?.status(on: today, calendar: calendar), case .recovering = status else { return false }
            return true
        }
    }

    func startRecovery(from start: DayKey, days: Int, reason: String) {
        if let existing = recoveries.first(where: { $0.startDay == start.description && $0.endedDay == nil }) {
            existing.days = max(existing.days, days)
        } else {
            context.insert(RecoveryPeriod(start: start, days: days, reason: reason))
        }
        save()
        reload()
    }

    /// "How are you feeling?" Back to normal ends recovery today, so today becomes the restart day.
    func setFeeling(_ feeling: RecoveryFeeling) {
        guard let period = activeRecovery else { return }
        period.feelingRaw = feeling.rawValue
        if feeling == .normal { period.endedDay = today.description }
        save()
        reload()
    }

    /// Without consent, finished recovery periods are deleted a week later (SO3: patterns only with consent).
    private func cleanUpRecoveries() {
        guard !settings.trackRecoveryPatterns else { return }
        let cutoff = today.adding(days: -7, calendar: calendar)
        for period in recoveries {
            guard let window = period.window else { continue }
            let end = window.endedOn ?? window.start.adding(days: window.days, calendar: calendar)
            if end < cutoff { context.delete(period) }
        }
        save()
    }

    // MARK: Gym busyness (L3)

    func reportGym(_ level: BusynessLevel, at date: Date? = nil) {
        context.insert(GymBusynessRecord(date: date ?? now(), level: level))
        save()
    }

    func busynessReports() -> [BusynessReport] {
        ((try? context.fetch(FetchDescriptor<GymBusynessRecord>())) ?? []).compactMap(\.report)
    }

    // MARK: Outings with Becky (RE1)

    func computeOutings() {
        guard let coach else { return }
        let day = today
        let evening = DateInterval(start: day.date(atMinute: 18 * 60, calendar: calendar), end: day.date(atMinute: 22 * 60, calendar: calendar))
        func overlapsEvening(_ event: ClassifiedEvent) -> Bool {
            !event.event.isAllDay && DateInterval(start: event.event.start, end: max(event.event.start, event.event.end))
                .intersection(with: evening).map { $0.duration > 0 } ?? false
        }
        let events = coach.events
        let ownEvening: Bool = events.contains { item in
            (item.role == .work || item.role == .personal) && overlapsEvening(item)
        }
        let commitmentEvening: Bool = coach.commitments.contains { item in
            guard item.state.isOpen, item.kind != .selfCare, let start = item.scheduledStart else { return false }
            return evening.contains(start)
        }
        let goingOut: Bool = socialEveningStart(on: day) != nil
        let userFree = !ownEvening && !commitmentEvening && !goingOut
        let beckyFree = !events.contains { $0.role == .shared && overlapsEvening($0) }
        let suggestions = (try? context.fetch(FetchDescriptor<OutingSuggestion>())) ?? []
        if let todays = suggestions.first(where: { $0.day == day.description && $0.ideaID != OutingPlanner.weekendAway.id }) {
            outingIdea = todays.accepted == false ? nil : OutingPlanner.evening.first { $0.id == todays.ideaID }
        } else {
            let earlier = suggestions.filter { $0.day < day.description && $0.ideaID != OutingPlanner.weekendAway.id }
                .sorted { $0.day < $1.day }
            let since = earlier.last.flatMap { DayKey(string: $0.day) }.map { MealPlanner.daysBetween($0, day) }
            let idea = OutingPlanner.tonight(day: day, userFreeEvening: userFree, beckyFreeEvening: beckyFree,
                                             eveningIsDry: WeatherAdvisor.isDry(DateInterval(start: evening.start, duration: 3 * 3600), forecast: forecast),
                                             recentIDs: earlier.map(\.ideaID), daysSinceLastIdea: since,
                                             recovering: recoveryStatus(on: day) != .clear, calendar: calendar)
            if let idea {
                context.insert(OutingSuggestion(ideaID: idea.id, day: day))
                save()
            }
            outingIdea = idea
        }
        // Looking further ahead, at most once a month (RE1).
        let lastWeekend = suggestions.filter { $0.ideaID == OutingPlanner.weekendAway.id }.compactMap { DayKey(string: $0.day) }.max()
        if let lastWeekend, MealPlanner.daysBetween(lastWeekend, day) < 30 {
            freeWeekend = nil
        } else if weekendCheckedOn != day {
            weekendCheckedOn = day
            let from = day.adding(days: 14, calendar: calendar).startDate(calendar: calendar)
            let to = day.adding(days: 58, calendar: calendar).startDate(calendar: calendar)
            let raw = coach.calendarProvider.events(from: from, to: to)
            let busy = CalendarClassifier.classify(raw, roles: coach.calendarRoles).filter { $0.role != .ignored }
            var busyDays = Set<DayKey>()
            for item in busy {
                var cursor = DayKey(item.event.start, calendar: calendar)
                let last = DayKey(max(item.event.start, item.event.end.addingTimeInterval(-1)), calendar: calendar)
                while cursor <= last {
                    busyDays.insert(cursor)
                    cursor = cursor.adding(days: 1, calendar: calendar)
                }
            }
            freeWeekend = OutingPlanner.freeWeekend(from: day, busyDays: busyDays, calendar: calendar)
        }
    }

    /// The user's answer to an idea, with a budget if it's a paid one.
    func respond(to idea: OutingIdea, accepted: Bool, budget: String? = nil) {
        let suggestions = (try? context.fetch(FetchDescriptor<OutingSuggestion>())) ?? []
        let record = suggestions.first { $0.ideaID == idea.id && $0.day == today.description } ?? {
            let created = OutingSuggestion(ideaID: idea.id, day: today)
            context.insert(created)
            return created
        }()
        record.accepted = accepted
        record.budget = budget
        if idea.id == OutingPlanner.weekendAway.id { freeWeekend = nil } else if !accepted { outingIdea = nil }
        save()
    }

    // MARK: Storage

    func reload() {
        plans = ((try? context.fetch(FetchDescriptor<SocialPlan>())) ?? []).sorted { $0.start < $1.start }
        recoveries = ((try? context.fetch(FetchDescriptor<RecoveryPeriod>())) ?? []).sorted { $0.startDay < $1.startDay }
    }

    func save() {
        try? context.save()
    }
}
