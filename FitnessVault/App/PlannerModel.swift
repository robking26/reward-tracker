import Foundation
import Observation

/// The Day tab: your calendar, work and Becky's together, plus suggestions for the gym, a swim, the Aldi shop, the
/// batch cook, runs and walks. Reads calendars; only ever adds events you accept to your own calendar.
@MainActor
@Observable
final class PlannerModel {
    @ObservationIgnored let calendarService: CalendarProviding
    @ObservationIgnored let location: LocationProviding
    @ObservationIgnored private let weatherService: WeatherProviding
    @ObservationIgnored private let travelService: TravelProviding
    @ObservationIgnored private let defaults: UserDefaults
    let calendar: Calendar
    let now: () -> Date

    private(set) var settings: PlannerSettings
    /// Becky's events by series: true for shared, false for "not for me".
    private(set) var decisions: [String: Bool]
    private(set) var dismissed: Set<String>
    private(set) var shopsDone: Set<DayKey>
    private(set) var cooksDone: Set<DayKey>
    /// Suggestions you've moved: when to leave instead.
    private(set) var pinned: [String: Date]
    private(set) var chores: [Chore]

    private(set) var access: CalendarAccess
    private(set) var calendars: [CalendarInfo] = []
    private(set) var events: [CalendarEventInfo] = []
    private(set) var weather: [HourlyWeather] = []
    private(set) var travel = TravelTable()
    private(set) var currentLocation: Coordinate?
    private(set) var pictures: [DayPicture] = []
    private(set) var isRefreshing = false
    /// Bumped on every rebuild, so the calendar and widget follow along.
    private(set) var revision = 0
    var message: String?

    // From the Gym and Kitchen, refreshed by the Day tab.
    @ObservationIgnored private var gymDays: Set<DayKey> = []
    @ObservationIgnored private var swimDays: Set<DayKey> = []
    @ObservationIgnored private var kneeSettled = true
    @ObservationIgnored private var batchCook: [DayKey: CookPlan] = [:]
    @ObservationIgnored private var weatherFetchedAt: Date?
    @ObservationIgnored private var travelFetchedAt: Date?
    @ObservationIgnored private var travelOrigin: Coordinate?

    static let settingsKey = "planner.settings"
    static let decisionsKey = "planner.beckyShared"
    static let dismissedKey = "planner.dismissed"
    static let shopsKey = "planner.shopsDone"
    static let cooksKey = "planner.cooksDone"
    static let pinnedKey = "planner.pinned"
    static let choresKey = "planner.chores"
    static let horizonDays = 7

    init(calendarService: CalendarProviding? = nil, location: LocationProviding? = nil, weather: WeatherProviding? = nil,
         travel: TravelProviding? = nil, defaults: UserDefaults = .standard, calendar: Calendar = .current,
         now: @escaping () -> Date = { .now }) {
        let service = calendarService ?? EventKitCalendarService()
        self.calendarService = service
        self.location = location ?? CoreLocationService()
        weatherService = weather ?? OpenMeteoWeatherService()
        travelService = travel ?? MapKitTravelService()
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        settings = defaults.data(forKey: Self.settingsKey).flatMap { try? JSONDecoder().decode(PlannerSettings.self, from: $0) }
            ?? PlannerSettings()
        decisions = (defaults.dictionary(forKey: Self.decisionsKey) as? [String: Bool]) ?? [:]
        dismissed = Set(defaults.stringArray(forKey: Self.dismissedKey) ?? [])
        shopsDone = Set((defaults.stringArray(forKey: Self.shopsKey) ?? []).compactMap(DayKey.init(string:)))
        cooksDone = Set((defaults.stringArray(forKey: Self.cooksKey) ?? []).compactMap(DayKey.init(string:)))
        pinned = ((defaults.dictionary(forKey: Self.pinnedKey) as? [String: Double]) ?? [:])
            .mapValues { Date(timeIntervalSinceReferenceDate: $0) }
        chores = defaults.data(forKey: Self.choresKey).flatMap { try? JSONDecoder().decode([Chore].self, from: $0) } ?? []
        access = service.access
        loadCalendars()
        rebuild()
    }

    // MARK: State

    var today: DayKey { DayKey(now(), calendar: calendar) }
    var days: [DayKey] { (0..<Self.horizonDays).map { today.adding(days: $0, calendar: calendar) } }

    func picture(for day: DayKey) -> DayPicture? { pictures.first { $0.day == day } }

    var needsConfirming: [CalendarEventInfo] {
        DayCalendar.needsConfirming(events, roles: settings.roles, decisions: decisions, now: now())
    }

    var isSetUp: Bool { access == .granted && settings.roles.values.contains(.mine) }

    /// Your own calendars, where accepted suggestions go.
    var ownCalendarIDs: [String] { calendars.filter { settings.roles[$0.id] == .mine && $0.allowsAdding }.map(\.id) }

    /// What a day means for the routines: annual leave, the first event that blocks time, and whether you're out at
    /// 8:30 pm (an event of yours or a shared one of Becky's at that time, or the phone away from home tonight).
    func routineInfo(for day: DayKey) -> RoutineDayInfo {
        var info = RoutineDayInfo()
        guard let picture = picture(for: day) else { return info }
        info.isLeave = picture.location == .leave
        let dayStart = day.startDate(calendar: calendar)
        info.firstEvent = picture.timedEvents.first { $0.blocksTime && $0.event.start > dayStart }?.event.start
        let halfEight = day.date(atMinute: RoutineRules.homeByMinute, calendar: calendar)
        let busyThen = picture.timedEvents.contains { item in
            (item.source == .mine || item.source == .beckyShared) && item.blocksTime
                && item.event.start <= halfEight && item.event.end > halfEight
        }
        var awayFromHome = false
        if day == today, now() >= halfEight, let here = currentLocation, let home = settings.places.home {
            awayFromHome = here.distance(to: home.coordinate) > 300
        }
        info.outAtHalfEight = busyThen || awayFromHome
        switch picture.location {
        case .office: info.workDay = .officeDay
        case .home: info.workDay = .homeDay
        default: info.workDay = nil
        }
        if let walk = picture.timedEvents.first(where: { $0.source == .workFree && DayCalendar.isLunchWalk($0.event) }) {
            info.lunchWalk = DateInterval(start: walk.event.start, end: max(walk.event.end, walk.event.start))
        }
        return info
    }

    var missingPlaces: [PlaceID] { [PlaceID.home, .gym, .pool, .aldi].filter { settings.places[$0] == nil } }

    // MARK: Refreshing

    /// Pulls in what the Gym and Kitchen know: sessions this week, swims, the knee and next week's batch cook.
    func update(training: TrainingModel, kitchen: KitchenModel, swims: [SwimSample]) {
        gymDays = Set(training.sessions().filter { !$0.isRehabOnly && $0.endedAt != nil }.compactMap { DayKey(string: $0.day) })
        swimDays = Set(swims.map { DayKey($0.date, calendar: calendar) })
        kneeSettled = training.kneeStatus == .settled
        var cook: [DayKey: CookPlan] = [:]
        let monday = DayPlanner.monday(of: today, calendar)
        for weeks in 0...2 {
            let start = monday.adding(days: weeks * 7, calendar: calendar)
            let meal = kitchen.meal(.lunch, on: start)
            cook[start] = CookPlan(title: meal.title, minutes: meal.prepMinutes + meal.cookMinutes + 15)
        }
        batchCook = cook
        rebuild()
    }

    func requestCalendarAccess() async {
        access = await calendarService.requestAccess()
        loadCalendars()
        await refresh()
    }

    func requestLocation() {
        location.requestPermission()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        access = calendarService.access
        loadCalendars()
        let start = today.startDate(calendar: calendar)
        let end = today.adding(days: 14, calendar: calendar).startDate(calendar: calendar)
        events = calendarService.events(from: start, to: end)
        currentLocation = await location.currentLocation()
        rebuild()
        await refreshWeather()
        await refreshTravel()
        rebuild()
    }

    private func loadCalendars() {
        calendars = calendarService.calendars()
        guard !calendars.isEmpty else { return }
        // First time: a best guess you can change in Day settings. Unlabelled calendars are left out.
        if settings.roles.isEmpty {
            var roles: [String: CalendarRole] = [:]
            for info in calendars {
                let text = "\(info.sourceTitle) \(info.title)".lowercased()
                if text.contains("becky") {
                    roles[info.id] = .becky
                } else if ["exchange", "outlook", "office 365"].contains(where: { text.contains($0) }) {
                    roles[info.id] = .work
                } else if info.allowsAdding && text.contains("icloud") {
                    roles[info.id] = .mine
                }
            }
            if !roles.isEmpty { setRoles(roles) }
        }
    }

    private func refreshWeather() async {
        if let fetched = weatherFetchedAt, now().timeIntervalSince(fetched) < 3_600, !weather.isEmpty { return }
        let point = currentLocation ?? settings.places.home?.coordinate ?? .bolton
        if let forecast = try? await weatherService.forecast(for: point) {
            weather = forecast
            weatherFetchedAt = now()
        }
    }

    /// Apple Maps drive times between home, the office, where you are, and the gym, pool and Aldi. Kept for 30 minutes.
    private func refreshTravel() async {
        let moved = currentLocation != travelOrigin
        if let fetched = travelFetchedAt, now().timeIntervalSince(fetched) < 1_800, !moved { return }
        var origins: [(PlaceID, Coordinate)] = []
        if let here = currentLocation { origins.append((.current, here)) }
        for id in [PlaceID.home, .office] { if let place = settings.places[id] { origins.append((id, place.coordinate)) } }
        let targets = PlaceID.saveable.compactMap { id -> (PlaceID, Coordinate)? in
            guard let place = settings.places[id] else { return nil }
            return (id, place.coordinate)
        }
        var table = TravelTable()
        for (from, a) in origins {
            for (to, b) in targets where from != to && table.minutes(from: from, to: to) == nil {
                if let minutes = try? await travelService.drivingMinutes(from: a, to: b, departure: now()) {
                    table.set(minutes, from: from, to: to)
                }
            }
        }
        travel = table
        travelFetchedAt = now()
        travelOrigin = currentLocation
    }

    func rebuild() {
        let input = PlannerInput(days: days, now: now(), calendar: calendar, events: events, settings: settings,
                                 decisions: decisions, travel: travel, weather: weather,
                                 hasCurrentLocation: currentLocation != nil, gymDays: gymDays, swimDays: swimDays,
                                 shopsDone: shopsDone, cooksDone: cooksDone, batchCook: batchCook,
                                 kneeSettled: kneeSettled, dismissed: dismissed, pinned: pinned, chores: chores)
        pictures = DayPlanner.plan(input)
        revision += 1
    }

    // MARK: Becky

    func confirm(_ event: CalendarEventInfo, shared: Bool) {
        decisions[event.seriesID] = shared
        defaults.set(decisions, forKey: Self.decisionsKey)
        rebuild()
    }

    func resetBeckyAnswers() {
        decisions = [:]
        defaults.removeObject(forKey: Self.decisionsKey)
        rebuild()
    }

    // MARK: Suggestions

    /// Adds the slot, including the drive, to your own calendar. The planner then treats it as booked.
    func accept(_ suggestion: Suggestion) {
        let venue = suggestion.venue.flatMap { $0 == .home ? nil : settings.places[$0] }
        let title = suggestion.displayTitle
        var notes = "\(ActivityKind.marker)\(suggestion.kind.rawValue)\n"
        if suggestion.travelThere > 0 {
            notes += "Leave \(PlannerFormat.time(suggestion.leaveAt, calendar)), \(suggestion.travelThere) min drive. "
        }
        notes += "\(suggestion.title) \(PlannerFormat.range(suggestion.start, suggestion.end, calendar)). \(suggestion.detail)"
        do {
            try calendarService.add(title: title, start: suggestion.leaveAt, end: suggestion.backAt,
                                    location: venue?.name, notes: notes, calendarIDs: ownCalendarIDs)
            message = "Added to your calendar."
            // Booked chores aren't suggested again; tick them off in Chores once they're done.
            if let tag = suggestion.tag, suggestion.kind == .chore {
                let ids = Set(tag.split(separator: "+").map(String.init))
                updateChores { chores in
                    for index in chores.indices where ids.contains(chores[index].id) { chores[index].bookedOn = suggestion.day }
                }
            }
        } catch {
            message = error.localizedDescription
        }
        let start = today.startDate(calendar: calendar)
        events = calendarService.events(from: start, to: today.adding(days: 14, calendar: calendar).startDate(calendar: calendar))
        rebuild()
    }

    func dismiss(_ suggestion: Suggestion) {
        dismissed.insert(suggestion.id)
        // Only keep answers for the coming fortnight.
        let cutoff = today.adding(days: -7, calendar: calendar)
        dismissed = dismissed.filter { id in
            id.split(separator: "|").last.flatMap { DayKey(string: String($0)) }.map { $0 >= cutoff } ?? false
        }
        defaults.set(Array(dismissed), forKey: Self.dismissedKey)
        rebuild()
    }

    /// The Aldi shop or batch cook is done for the coming week.
    func markDone(_ suggestion: Suggestion) {
        let monday = DayPlanner.monday(of: suggestion.day, calendar).adding(days: 7, calendar: calendar)
        switch suggestion.kind {
        case .aldiShop:
            shopsDone.insert(monday)
            defaults.set(shopsDone.map(\.description), forKey: Self.shopsKey)
        case .batchCook:
            cooksDone.insert(monday)
            defaults.set(cooksDone.map(\.description), forKey: Self.cooksKey)
        case .chore:
            let ids = Set((suggestion.tag ?? "").split(separator: "+").map(String.init))
            updateChores { chores in
                for index in chores.indices where ids.contains(chores[index].id) { chores[index].doneAt = now() }
            }
            message = "Chores ticked off."
            return
        default:
            dismiss(suggestion)
            return
        }
        rebuild()
    }

    // MARK: Moving suggestions

    /// Moves a suggestion to leave at a time you choose. It stays there until you put it back.
    func move(_ suggestion: Suggestion, leavingAt date: Date) {
        pinned[suggestion.id] = date
        savePinned()
        rebuild()
    }

    func resetTime(_ suggestion: Suggestion) {
        pinned[suggestion.id] = nil
        savePinned()
        rebuild()
    }

    private func savePinned() {
        // Only keep the coming fortnight.
        let cutoff = today.adding(days: -1, calendar: calendar)
        pinned = pinned.filter { id, _ in
            id.split(separator: "|").last.flatMap { DayKey(string: String($0)) }.map { $0 >= cutoff } ?? false
        }
        defaults.set(pinned.mapValues(\.timeIntervalSinceReferenceDate), forKey: Self.pinnedKey)
    }

    /// Re-reads the calendars and works everything out again from scratch: drive times, the forecast, suggestions.
    func refreshSuggestions() async {
        travelFetchedAt = nil
        weatherFetchedAt = nil
        await refresh()
        message = "Suggestions updated from your calendar."
    }

    // MARK: Chores

    var openChores: [Chore] { chores.filter { $0.doneAt == nil } }

    /// Adds each line of a written list, with a time estimate and whether it's outdoors.
    func addChores(from text: String) {
        let titles = ChoreEstimator.parse(text)
        guard !titles.isEmpty else { return }
        updateChores { chores in
            for title in titles {
                let estimate = ChoreEstimator.estimate(title)
                chores.append(Chore(id: UUID().uuidString, title: title, minutes: estimate.minutes, outdoor: estimate.outdoor,
                                    createdAt: now()))
            }
        }
    }

    func updateChores(_ change: (inout [Chore]) -> Void) {
        var copy = chores
        change(&copy)
        // Done chores are kept for a week, then let go.
        let cutoff = now().addingTimeInterval(-7 * 86_400)
        chores = copy.filter { ($0.doneAt ?? .distantFuture) > cutoff }
        if let data = try? JSONEncoder().encode(chores) { defaults.set(data, forKey: Self.choresKey) }
        rebuild()
    }

    /// Where a chore is planned: the suggestion that includes it, if any.
    func suggestion(for chore: Chore) -> Suggestion? {
        pictures.flatMap(\.suggestions).first { $0.kind == .chore && ($0.tag ?? "").split(separator: "+").contains { $0 == chore.id } }
    }

    // MARK: Settings

    func update(_ change: (inout PlannerSettings) -> Void) {
        var copy = settings
        change(&copy)
        settings = copy
        if let data = try? JSONEncoder().encode(copy) { defaults.set(data, forKey: Self.settingsKey) }
        rebuild()
    }

    func setRoles(_ roles: [String: CalendarRole]) {
        update { $0.roles = roles }
    }

    func setRole(_ role: CalendarRole, for calendarID: String) {
        update { $0.roles[calendarID] = role }
    }

    func setPlace(_ place: SavedPlace?, for id: PlaceID) {
        update { $0.places[id] = place }
        travelFetchedAt = nil
        Task { await refresh() }
    }

    func searchPlaces(_ query: String) async -> [PlaceResult] {
        let near = currentLocation ?? settings.places.home?.coordinate ?? .bolton
        return (try? await travelService.search(query, near: near)) ?? []
    }
}
