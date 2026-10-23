import Foundation

/// Things the planner fits into free time.
enum ActivityKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case gym, swim, aldiShop, batchCook, run, walk

    /// Written into the notes of an event added from a suggestion, so the planner knows it's booked.
    static let marker = "vaultality:"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gym: "Gym"
        case .swim: "Swim"
        case .aldiShop: "Aldi weekly shop"
        case .batchCook: "Batch cook lunches"
        case .run: "Run"
        case .walk: "Walk"
        }
    }

    var symbol: String {
        switch self {
        case .gym: "dumbbell.fill"
        case .swim: "figure.pool.swim"
        case .aldiShop: "cart.fill"
        case .batchCook: "fork.knife"
        case .run: "figure.run"
        case .walk: "figure.walk"
        }
    }

    /// Where it happens. Walks and runs start from wherever you are.
    var venue: PlaceID? {
        switch self {
        case .gym: .gym
        case .swim: .pool
        case .aldiShop: .aldi
        case .batchCook: .home
        case .run, .walk: nil
        }
    }

    var isOutdoor: Bool { self == .run || self == .walk }
}

struct PlannerSettings: Codable, Hashable, Sendable {
    var roles: [String: CalendarRole] = [:]
    var places = PlannerPlaces()
    var workStartMinute = 9 * 60
    var workEndMinute = 17 * 60 + 30
    /// Nothing is suggested before this or finishing after `dayEndMinute`.
    var dayStartMinute = 6 * 60 + 30
    var dayEndMinute = 21 * 60 + 30
    var gymPerWeek = 3
    var swimsPerWeek = 1
    var runsPerWeek = 2
    /// At least an hour working out.
    var gymMinutes = 60
    /// Changing and swimming.
    var swimMinutes = 60
    var shopMinutes = 45
    var walkMinutes = 30
    var runMinutes = 30
    /// Used when Apple Maps has no estimate yet.
    var fallbackTravelMinutes = 15
    /// Kept clear either side of your own events.
    var bufferMinutes = 10
    /// Off: the daily walks after lunch and tea are routines now, so the planner doesn't add its own.
    var suggestWalks = false

    init() {}

    // Decoded field by field so settings saved by an older version keep their values and pick up new defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = PlannerSettings()
        roles = try c.decodeIfPresent([String: CalendarRole].self, forKey: .roles) ?? base.roles
        places = try c.decodeIfPresent(PlannerPlaces.self, forKey: .places) ?? base.places
        workStartMinute = try c.decodeIfPresent(Int.self, forKey: .workStartMinute) ?? base.workStartMinute
        workEndMinute = try c.decodeIfPresent(Int.self, forKey: .workEndMinute) ?? base.workEndMinute
        dayStartMinute = try c.decodeIfPresent(Int.self, forKey: .dayStartMinute) ?? base.dayStartMinute
        dayEndMinute = try c.decodeIfPresent(Int.self, forKey: .dayEndMinute) ?? base.dayEndMinute
        gymPerWeek = try c.decodeIfPresent(Int.self, forKey: .gymPerWeek) ?? base.gymPerWeek
        swimsPerWeek = try c.decodeIfPresent(Int.self, forKey: .swimsPerWeek) ?? base.swimsPerWeek
        runsPerWeek = try c.decodeIfPresent(Int.self, forKey: .runsPerWeek) ?? base.runsPerWeek
        gymMinutes = try c.decodeIfPresent(Int.self, forKey: .gymMinutes) ?? base.gymMinutes
        swimMinutes = try c.decodeIfPresent(Int.self, forKey: .swimMinutes) ?? base.swimMinutes
        shopMinutes = try c.decodeIfPresent(Int.self, forKey: .shopMinutes) ?? base.shopMinutes
        walkMinutes = try c.decodeIfPresent(Int.self, forKey: .walkMinutes) ?? base.walkMinutes
        runMinutes = try c.decodeIfPresent(Int.self, forKey: .runMinutes) ?? base.runMinutes
        fallbackTravelMinutes = try c.decodeIfPresent(Int.self, forKey: .fallbackTravelMinutes) ?? base.fallbackTravelMinutes
        bufferMinutes = try c.decodeIfPresent(Int.self, forKey: .bufferMinutes) ?? base.bufferMinutes
        suggestWalks = try c.decodeIfPresent(Bool.self, forKey: .suggestWalks) ?? base.suggestWalks
    }
}

/// A suggested slot: when to leave, the activity itself, and when you're back.
struct Suggestion: Hashable, Sendable, Identifiable {
    var kind: ActivityKind
    var day: DayKey
    var leaveAt: Date
    var start: Date
    var end: Date
    var backAt: Date
    var origin: PlaceID
    var travelThere: Int
    var travelBack: Int
    /// No Apple Maps estimate yet, so the travel time is your fallback setting.
    var travelIsEstimate: Bool
    var venueName: String?
    var detail: String

    var id: String { "\(kind.rawValue)|\(day)" }
    var block: DateInterval { DateInterval(start: leaveAt, end: max(backAt, leaveAt)) }
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

struct FreeWindow: Hashable, Sendable {
    var interval: DateInterval
    /// Where you set off from.
    var origin: PlaceID
    /// A lunch break inside work hours: walks only.
    var isLunch: Bool = false
    /// Where you need to be afterwards: back to work for a gap in the working day, otherwise home.
    var returnTo: PlaceID = .home

    var minutes: Int { Int(interval.duration / 60) }
}

struct DayPicture: Sendable {
    var day: DayKey
    var location: WorkLocation
    var work: DateInterval?
    var events: [DayEvent]
    var free: [FreeWindow]
    var suggestions: [Suggestion]
    var weather: String?

    var timedEvents: [DayEvent] { events.filter { !$0.event.isAllDay } }
    var allDayEvents: [DayEvent] { events.filter(\.event.isAllDay) }
    var freeMinutes: Int { free.filter { !$0.isLunch }.reduce(0) { $0 + $1.minutes } }
}

struct CookPlan: Hashable, Sendable {
    var title: String
    var minutes: Int
}

struct PlannerInput {
    var days: [DayKey]
    var now: Date
    var calendar: Calendar
    var events: [CalendarEventInfo]
    var settings: PlannerSettings
    /// Becky's events by series: true for shared, false for "not for me".
    var decisions: [String: Bool] = [:]
    var travel = TravelTable()
    var weather: [HourlyWeather] = []
    var hasCurrentLocation = false
    /// Days with a gym session logged (rehab-only sessions don't count).
    var gymDays: Set<DayKey> = []
    var swimDays: Set<DayKey> = []
    /// Mondays whose Aldi shop or batch cook is already done.
    var shopsDone: Set<DayKey> = []
    var cooksDone: Set<DayKey> = []
    /// The batch-cooked lunch for the week starting on each Monday.
    var batchCook: [DayKey: CookPlan] = [:]
    var kneeSettled = true
    /// Suggestion IDs you've waved away.
    var dismissed: Set<String> = []
}

enum DayPlanner {
    static let lunchStartMinute = 12 * 60
    static let lunchEndMinute = 14 * 60

    // MARK: The picture of each day

    static func plan(_ input: PlannerInput) -> [DayPicture] {
        var pictures = input.days.map { picture(for: $0, input: input) }
        var chosen: [DayKey: [Suggestion]] = [:]
        let weeks = Dictionary(grouping: input.days) { monday(of: $0, input.calendar) }
        for monday in weeks.keys.sorted() {
            let days = (weeks[monday] ?? []).sorted()
            planWeek(days, monday: monday, pictures: pictures, input: input, chosen: &chosen)
        }
        for index in pictures.indices {
            pictures[index].suggestions = (chosen[pictures[index].day] ?? []).sorted { $0.leaveAt < $1.leaveAt }
        }
        return pictures
    }

    static func picture(for day: DayKey, input: PlannerInput) -> DayPicture {
        let calendar = input.calendar, settings = input.settings
        let location = DayCalendar.workLocation(on: day, events: input.events, roles: settings.roles, calendar: calendar)
        let events = DayCalendar.events(on: day, events: input.events, roles: settings.roles, decisions: input.decisions,
                                        calendar: calendar)
        var work: DateInterval?
        if location.isWorkDay {
            work = DateInterval(start: day.date(atMinute: settings.workStartMinute, calendar: calendar),
                                end: day.date(atMinute: max(settings.workEndMinute, settings.workStartMinute), calendar: calendar))
        }
        let free = freeWindows(day: day, location: location, work: work, events: events, input: input)
        return DayPicture(day: day, location: location, work: work, events: events, free: free, suggestions: [],
                          weather: WeatherAdvisor.summary(for: day, forecast: input.weather, calendar: calendar))
    }

    /// Free time between your events, Becky's shared ones and work. On office days the drive in comes off the
    /// morning, and the evening starts from the office.
    static func freeWindows(day: DayKey, location: WorkLocation, work: DateInterval?, events: [DayEvent],
                            input: PlannerInput) -> [FreeWindow] {
        let calendar = input.calendar, settings = input.settings
        let buffer = TimeInterval(settings.bufferMinutes * 60)
        var opens = day.date(atMinute: settings.dayStartMinute, calendar: calendar)
        let closes = day.date(atMinute: settings.dayEndMinute, calendar: calendar)
        let nowStart = roundedUp(input.now)
        let startsNow = nowStart > opens
        if startsNow { opens = nowStart }
        guard closes > opens else { return [] }

        typealias Block = (interval: DateInterval, endsAt: PlaceID, isWork: Bool)
        // On leave, work meetings don't count.
        var blocks: [Block] = events.filter { $0.blocksTime && !(location == .leave && $0.source == .work) }.map { item in
            let padded = DateInterval(start: item.event.start.addingTimeInterval(-buffer), end: item.event.end.addingTimeInterval(buffer))
            return (interval: padded, endsAt: PlaceID.home, isWork: false)
        }
        // "Blocked" and "Lunch walk" in Outlook open gaps in the working day.
        let freeForMe = events.filter { $0.source == .workFree }.map { DateInterval(start: $0.event.start, end: $0.event.end) }
        let workPlace: PlaceID = location == .office ? .office : .home
        if let work {
            var span = work
            if location == .office {
                let commute = travel(from: .home, to: .office, input: input).minutes
                span = DateInterval(start: work.start.addingTimeInterval(-TimeInterval(commute * 60)), end: work.end)
            }
            for piece in subtract(freeForMe, from: span) {
                blocks.append((interval: piece, endsAt: workPlace, isWork: true))
            }
        }
        blocks.sort { $0.interval.start < $1.interval.start }

        var windows: [FreeWindow] = []
        var cursor = opens
        var origin: PlaceID = startsNow && input.hasCurrentLocation ? .current : .home
        for block in blocks {
            if block.interval.start > cursor {
                let end = min(block.interval.start, closes)
                if end > cursor {
                    windows.append(FreeWindow(interval: DateInterval(start: cursor, end: end), origin: origin,
                                              returnTo: block.isWork ? workPlace : .home))
                }
            }
            if block.interval.end > cursor {
                cursor = block.interval.end
                origin = block.endsAt
            }
        }
        if closes > cursor { windows.append(FreeWindow(interval: DateInterval(start: cursor, end: closes), origin: origin)) }
        windows = windows.filter { $0.minutes >= 15 }

        if let work {
            let opened = windows.map(\.interval)
            windows += lunchWindows(day: day, location: location, work: work, events: events, input: input, opens: opens)
                .flatMap { lunch in
                    subtract(opened, from: lunch.interval)
                        .filter { $0.duration >= TimeInterval(settings.walkMinutes * 60) }
                        .map { FreeWindow(interval: $0, origin: lunch.origin, isLunch: true, returnTo: lunch.returnTo) }
                }
        }
        return windows.sorted { $0.interval.start < $1.interval.start }
    }

    /// Meeting-free time between 12 and 2 on a work day, for a walk.
    private static func lunchWindows(day: DayKey, location: WorkLocation, work: DateInterval, events: [DayEvent],
                                     input: PlannerInput, opens: Date) -> [FreeWindow] {
        let calendar = input.calendar
        let start = max(day.date(atMinute: lunchStartMinute, calendar: calendar), work.start, opens)
        let end = min(day.date(atMinute: lunchEndMinute, calendar: calendar), work.end)
        guard end > start else { return [] }
        let busy = events.filter(\.blocksTime).map { DateInterval(start: $0.event.start, end: $0.event.end) }
        let origin: PlaceID = location == .office ? .office : .home
        return subtract(busy, from: DateInterval(start: start, end: end))
            .filter { $0.duration >= TimeInterval(input.settings.walkMinutes * 60) }
            .map { FreeWindow(interval: $0, origin: origin, isLunch: true, returnTo: origin) }
    }

    // MARK: Fitting activities into the week

    private static func planWeek(_ days: [DayKey], monday: DayKey, pictures: [DayPicture], input: PlannerInput,
                                 chosen: inout [DayKey: [Suggestion]]) {
        let calendar = input.calendar, settings = input.settings
        let byDay = Dictionary(uniqueKeysWithValues: pictures.map { ($0.day, $0) })
        let weekDays = (0..<7).map { monday.adding(days: $0, calendar: calendar) }
        let booked = bookedActivities(input)

        func has(_ kind: ActivityKind, _ day: DayKey) -> Bool {
            booked.contains(key(kind, day)) || (chosen[day] ?? []).contains { $0.kind == kind }
        }
        func place(_ kind: ActivityKind, on day: DayKey, notBefore: Date? = nil, detail: String,
                   minutes: Int) -> Suggestion? {
            guard let picture = byDay[day], !input.dismissed.contains(key(kind, day)) else { return nil }
            let taken = (chosen[day] ?? []).map(\.block)
            guard let suggestion = fit(kind, minutes: minutes, picture: picture, taken: taken, notBefore: notBefore,
                                       detail: detail, input: input) else { return nil }
            chosen[day, default: []].append(suggestion)
            return suggestion
        }

        // The Aldi shop, then the batch cook, over the weekend before the week they're for.
        let nextMonday = monday.adding(days: 7, calendar: calendar)
        let weekend = [5, 6, 4].map { monday.adding(days: $0, calendar: calendar) }.filter { days.contains($0) }
        let shopBooked = weekend.contains { has(.aldiShop, $0) }
        var shop: Suggestion?
        if !input.shopsDone.contains(nextMonday) && !shopBooked {
            let label = "For the week of \(nextMonday.startDate(calendar: calendar).formatted(.dateTime.day().month(.abbreviated)))"
            for day in weekend {
                shop = place(.aldiShop, on: day, detail: label, minutes: settings.shopMinutes)
                if shop != nil { break }
            }
        }
        let cookDays = [6, 5].map { monday.adding(days: $0, calendar: calendar) }.filter { days.contains($0) }
        if !input.cooksDone.contains(nextMonday), !cookDays.contains(where: { has(.batchCook, $0) }),
           let meal = input.batchCook[nextMonday] {
            for day in cookDays {
                if let shop, day < shop.day { continue }
                let after = shop?.day == day ? shop?.backAt : nil
                let detail = "\(meal.title) · 5 portions"
                if place(.batchCook, on: day, notBefore: after, detail: detail, minutes: meal.minutes) != nil { break }
            }
        }

        // Gym sessions, spread out where the diary allows.
        let gymDone = weekDays.filter { input.gymDays.contains($0) || booked.contains(key(.gym, $0)) }.count
        var gymLeft = max(0, settings.gymPerWeek - gymDone)
        var gymCount = gymDone
        for spread in [true, false] where gymLeft > 0 {
            for day in days where gymLeft > 0 && !has(.gym, day) && !input.gymDays.contains(day) {
                if spread {
                    let before = day.adding(days: -1, calendar: calendar), after = day.adding(days: 1, calendar: calendar)
                    let near = [before, after].contains { input.gymDays.contains($0) || has(.gym, $0) }
                    if near { continue }
                }
                let detail = "Session \(gymCount + 1) of \(settings.gymPerWeek) this week"
                if place(.gym, on: day, detail: detail, minutes: settings.gymMinutes) != nil {
                    gymLeft -= 1
                    gymCount += 1
                }
            }
        }

        // Swims, on days without the gym where possible.
        let swimDone = weekDays.filter { input.swimDays.contains($0) || booked.contains(key(.swim, $0)) }.count
        var swimLeft = max(0, settings.swimsPerWeek - swimDone)
        var swimCount = swimDone
        for avoidGym in [true, false] where swimLeft > 0 {
            for day in days where swimLeft > 0 && !has(.swim, day) && !input.swimDays.contains(day) {
                if avoidGym && (has(.gym, day) || input.gymDays.contains(day)) { continue }
                let detail = "Swim \(swimCount + 1) of \(settings.swimsPerWeek) this week"
                if place(.swim, on: day, detail: detail, minutes: settings.swimMinutes) != nil {
                    swimLeft -= 1
                    swimCount += 1
                }
            }
        }

        // Runs only while the knee is settled; a walk on the days without one. Both only when it's dry and light.
        let runsBooked = weekDays.filter { booked.contains(key(.run, $0)) }.count
        var runsLeft = input.kneeSettled ? max(0, settings.runsPerWeek - runsBooked) : 0
        for day in days where runsLeft > 0 && !has(.run, day) {
            if has(.gym, day) || has(.swim, day) || input.gymDays.contains(day) { continue }
            if place(.run, on: day, detail: "Easy pace, \(settings.runMinutes) min", minutes: settings.runMinutes) != nil {
                runsLeft -= 1
            }
        }
        for day in days where settings.suggestWalks && !has(.walk, day) && !has(.run, day) {
            _ = place(.walk, on: day, detail: "\(settings.walkMinutes) min, brisk", minutes: settings.walkMinutes)
        }
    }

    /// Activities already in your calendar from an earlier suggestion, as "kind|day".
    static func bookedActivities(_ input: PlannerInput) -> Set<String> {
        Set(input.events.compactMap { event -> String? in
            guard input.settings.roles[event.calendarID] == .mine, let kind = event.plannedActivity else { return nil }
            return key(kind, DayKey(event.start, calendar: input.calendar))
        })
    }

    static func key(_ kind: ActivityKind, _ day: DayKey) -> String { "\(kind.rawValue)|\(day)" }

    /// The best slot for `kind` on a day: enough free time for the drive there, the activity and the drive back,
    /// as close as possible to a sensible time of day. Walks and runs also need dry, light weather.
    static func fit(_ kind: ActivityKind, minutes: Int, picture: DayPicture, taken: [DateInterval], notBefore: Date?,
                    detail: String, input: PlannerInput) -> Suggestion? {
        let venueName: String?
        if let venue = kind.venue {
            if venue != .home && input.settings.places[venue] == nil { return nil }
            venueName = venue == .home ? "Home" : input.settings.places[venue]?.name
        } else {
            venueName = nil
        }
        let preferred = preferredStart(kind, picture: picture, input: input)
        var best: (suggestion: Suggestion, score: TimeInterval)?

        for window in picture.free where !window.isLunch || kind == .walk {
            for (index, part) in subtract(taken, from: window.interval).enumerated() {
                // After another suggestion you're back where that one returned you.
                let origin = index == 0 && part.start == window.interval.start ? window.origin : window.returnTo
                var there = (minutes: 0, estimate: false), back = (minutes: 0, estimate: false)
                if let venue = kind.venue {
                    there = travel(from: origin, to: venue, input: input)
                    back = travel(from: venue, to: window.returnTo, input: input)
                }
                let total = TimeInterval((there.minutes + minutes + back.minutes) * 60)
                var leave = max(part.start, notBefore.map(roundedUp) ?? part.start)
                while leave.addingTimeInterval(total) <= part.end {
                    let start = leave.addingTimeInterval(TimeInterval(there.minutes * 60))
                    let end = start.addingTimeInterval(TimeInterval(minutes * 60))
                    let outside = WeatherAdvisor.isGoodOutside(DateInterval(start: start, end: end), forecast: input.weather)
                    if !kind.isOutdoor || outside != false {
                        let score = abs(start.timeIntervalSince(preferred))
                        if best.map({ score < $0.score }) ?? true {
                            let suggestion = Suggestion(kind: kind, day: picture.day, leaveAt: leave, start: start, end: end,
                                                        backAt: end.addingTimeInterval(TimeInterval(back.minutes * 60)),
                                                        origin: origin, travelThere: there.minutes, travelBack: back.minutes,
                                                        travelIsEstimate: there.estimate || back.estimate,
                                                        venueName: venueName, detail: detail)
                            best = (suggestion, score)
                        }
                    }
                    leave = leave.addingTimeInterval(15 * 60)
                }
            }
        }
        return best?.suggestion
    }

    /// After work on work days; mid-morning on days off. Walks go at lunchtime on work days.
    static func preferredStart(_ kind: ActivityKind, picture: DayPicture, input: PlannerInput) -> Date {
        let calendar = input.calendar
        // A "Lunch walk" in Outlook is the walk.
        if kind == .walk, let walk = picture.events.first(where: { $0.source == .workFree && DayCalendar.isLunchWalk($0.event) }) {
            return walk.event.start
        }
        if let work = picture.work {
            let minute: Int
            switch kind {
            case .walk: minute = 12 * 60 + 30
            case .batchCook: minute = input.settings.workEndMinute + 90
            default: minute = input.settings.workEndMinute + 30
            }
            return kind == .walk ? picture.day.date(atMinute: minute, calendar: calendar)
                : max(work.end, picture.day.date(atMinute: minute, calendar: calendar))
        }
        let minute: Int
        switch kind {
        case .gym, .swim: minute = 10 * 60
        case .aldiShop: minute = 9 * 60 + 30
        case .batchCook: minute = 14 * 60
        case .run: minute = 9 * 60
        case .walk: minute = 11 * 60
        }
        return picture.day.date(atMinute: minute, calendar: calendar)
    }

    /// One-way minutes to plan with: Apple Maps plus parking, or the fallback setting.
    static func travel(from: PlaceID, to: PlaceID, input: PlannerInput) -> (minutes: Int, estimate: Bool) {
        if from == to { return (0, false) }
        if let drive = input.travel.minutes(from: from, to: to) { return (TravelTable.padded(drive), false) }
        return (input.settings.fallbackTravelMinutes, true)
    }

    // MARK: Helpers

    static func subtract(_ busy: [DateInterval], from interval: DateInterval) -> [DateInterval] {
        var parts = [interval]
        for block in busy {
            parts = parts.flatMap { part -> [DateInterval] in
                guard block.start < part.end, block.end > part.start else { return [part] }
                var pieces: [DateInterval] = []
                if block.start > part.start { pieces.append(DateInterval(start: part.start, end: block.start)) }
                if block.end < part.end { pieces.append(DateInterval(start: block.end, end: part.end)) }
                return pieces
            }
        }
        return parts
    }

    static func monday(of day: DayKey, _ calendar: Calendar) -> DayKey {
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        return day.adding(days: -((weekday + 5) % 7), calendar: calendar)
    }

    /// The next 5-minute mark.
    static func roundedUp(_ date: Date) -> Date {
        let step: TimeInterval = 300
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
    }
}
