import Foundation

// Morning self-care for today's you, and evening self-care for tomorrow's you. Each has a weekday and a weekend
// version, at home and away. Missing a home routine halves that day's earnings. Pure and deterministic, so the rule
// can be tested and always gives the same answer for the same records.

enum RoutinePart: String, Codable, CaseIterable, Sendable, Identifiable {
    case morning, evening

    var id: String { rawValue }

    var title: String { self == .morning ? "Morning routine" : "Night routine" }
    var purpose: String { self == .morning ? "For today's you" : "For tomorrow's you" }
    var symbol: String { self == .morning ? "sunrise.fill" : "moon.stars.fill" }
}

enum RoutineDays: String, Codable, CaseIterable, Sendable {
    case weekday, weekend

    var title: String { self == .weekday ? "Weekdays" : "Weekends" }
}

enum RoutinePlace: String, Codable, CaseIterable, Sendable {
    case home, away

    var title: String { self == .home ? "At home" : "Away" }
    var symbol: String { self == .home ? "house.fill" : "suitcase.fill" }
}

/// One of the eight versions: morning or night, weekday or weekend, home or away.
struct RoutineKey: Hashable, Codable, Sendable, Identifiable {
    var part: RoutinePart
    var days: RoutineDays
    var place: RoutinePlace

    var id: String { "\(part.rawValue)|\(days.rawValue)|\(place.rawValue)" }

    var title: String {
        let when: String
        switch (part, days) {
        case (.morning, .weekday): when = "Weekday mornings"
        case (.morning, .weekend): when = "Weekend mornings"
        case (.evening, .weekday): when = "Nights before a weekday"
        case (.evening, .weekend): when = "Nights before the weekend"
        }
        return "\(when) · \(place.title.lowercased())"
    }

    static let all: [RoutineKey] = RoutinePlace.allCases.flatMap { place in
        RoutinePart.allCases.flatMap { part in RoutineDays.allCases.map { RoutineKey(part: part, days: $0, place: place) } }
    }
}

struct RoutineItem: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var symbol: String
}

/// When a routine opens and when it has to be finished, as minutes after midnight.
struct RoutineTimes: Codable, Hashable, Sendable {
    var start: Int
    var finish: Int
    /// Moves earlier so it's finished before the day's first calendar event, keeping its length.
    var beforeFirstEvent: Bool? = nil
    /// No set time: any time that evening, and no reminders.
    var adHoc: Bool? = nil

    var movesForEvents: Bool { beforeFirstEvent ?? false }
    var isAdHoc: Bool { adHoc ?? false }
}

struct RoutineSetup: Codable, Hashable, Sendable {
    /// Items for each version, keyed by `RoutineKey.id`.
    var items: [String: [RoutineItem]] = [:]
    var times: [String: RoutineTimes] = [:]
    /// The first day a missed home routine costs anything; nil until the questionnaire is done.
    var penaltyFrom: DayKey?
    /// The share of items that makes a routine done. Nil (older setups) means 80%.
    var completionShare: Double? = nil

    var isSetUp: Bool { penaltyFrom != nil }
    var share: Double { min(max(completionShare ?? 0.8, 0.1), 1) }

    func items(_ key: RoutineKey) -> [RoutineItem] { items[key.id] ?? [] }
    func times(_ key: RoutineKey) -> RoutineTimes { times[key.id] ?? Self.defaultTimes(key) }

    /// From Rob's questionnaire: up at 6 on weekdays and done by 6:45; weekend and away mornings 10 to 11 or the
    /// hour before the first thing in the calendar; in bed by 9:30 on work nights, 10:30 on Friday and Saturday;
    /// nights away whenever suits.
    static func defaultTimes(_ key: RoutineKey) -> RoutineTimes {
        switch (key.part, key.days, key.place) {
        case (.morning, .weekday, .home): RoutineTimes(start: 6 * 60, finish: 6 * 60 + 45)
        case (.morning, .weekend, .home), (.morning, _, .away):
            RoutineTimes(start: 10 * 60, finish: 11 * 60, beforeFirstEvent: true)
        case (.evening, .weekday, .home): RoutineTimes(start: 21 * 60, finish: 21 * 60 + 30)
        case (.evening, .weekend, .home): RoutineTimes(start: 22 * 60, finish: 22 * 60 + 30)
        case (.evening, _, .away): RoutineTimes(start: 18 * 60, finish: 23 * 60 + 59, adHoc: true)
        }
    }
}

/// What happened with one routine on one day.
struct RoutineRecord: Hashable, Sendable {
    var day: DayKey
    var part: RoutinePart
    var place: RoutinePlace = .home
    var ticked: Set<String> = []
    /// When enough items were ticked to count as done.
    var completedAt: Date?
    /// The version and times worked out while the routine was still open (a leave day, an early first event),
    /// kept so the rule never changes its mind about a day afterwards.
    var days: RoutineDays? = nil
    var window: DateInterval? = nil
}

enum RoutineStatus: Equatable, Sendable {
    case notSetUp
    case upcoming
    case open
    case done
    case missed
    /// Away routines are tracked but never cost anything.
    case awayOpen, awayDone, awayMissed
}

/// What the calendar and location say about a day, for working out its routines.
struct RoutineDayInfo: Hashable, Sendable {
    /// "Rob King AL": at home, the morning gets the weekend version.
    var isLeave = false
    /// The start of the day's first event that blocks time.
    var firstEvent: Date? = nil
    /// Not home by 8:30 pm, from the calendar or where the phone is: the night counts as away.
    var outAtHalfEight = false
}

enum RoutineRules {
    /// Nights out count as away if you're not home by this time.
    static let homeByMinute = 20 * 60 + 30

    /// Mornings follow the day itself. Nights follow the day after, because they're for tomorrow's you:
    /// Sunday to Thursday nights get the weekday version, Friday and Saturday nights the weekend one.
    static func days(for part: RoutinePart, on day: DayKey, calendar: Calendar) -> RoutineDays {
        let target = part == .morning ? day : day.adding(days: 1, calendar: calendar)
        let weekday = calendar.component(.weekday, from: target.startDate(calendar: calendar))
        return weekday == 1 || weekday == 7 ? .weekend : .weekday
    }

    /// A leave day at home is treated like a Saturday morning.
    static func days(for part: RoutinePart, on day: DayKey, place: RoutinePlace, info: RoutineDayInfo,
                     calendar: Calendar) -> RoutineDays {
        if part == .morning && place == .home && info.isLeave { return .weekend }
        return days(for: part, on: day, calendar: calendar)
    }

    static func key(_ part: RoutinePart, on day: DayKey, place: RoutinePlace, calendar: Calendar) -> RoutineKey {
        RoutineKey(part: part, days: days(for: part, on: day, calendar: calendar), place: place)
    }

    /// The key for a record: the version saved with it if there is one, otherwise the calendar's.
    static func key(for record: RoutineRecord?, part: RoutinePart, on day: DayKey, calendar: Calendar) -> RoutineKey {
        let place = record?.place ?? .home
        let days = record?.days ?? days(for: part, on: day, calendar: calendar)
        return RoutineKey(part: part, days: days, place: place)
    }

    static func window(_ key: RoutineKey, on day: DayKey, setup: RoutineSetup, firstEvent: Date? = nil,
                       calendar: Calendar) -> DateInterval {
        let times = setup.times(key)
        var start = day.date(atMinute: times.start, calendar: calendar)
        // Always finishes the same day, so a missed night routine belongs to that day's earnings.
        var finish = day.date(atMinute: min(max(times.finish, times.start + 5), 23 * 60 + 59), calendar: calendar)
        if times.movesForEvents, let firstEvent, firstEvent < finish, firstEvent > day.startDate(calendar: calendar) {
            let length = finish.timeIntervalSince(start)
            finish = firstEvent
            start = max(day.startDate(calendar: calendar), firstEvent.addingTimeInterval(-length))
        }
        return DateInterval(start: start, end: finish)
    }

    /// How many ticks make a routine done: 80% of the items, rounded up.
    static func required(_ count: Int, share: Double) -> Int {
        guard count > 0 else { return 0 }
        return min(count, max(1, Int((Double(count) * share - 0.000_1).rounded(.up))))
    }

    static func status(_ part: RoutinePart, on day: DayKey, record: RoutineRecord?, setup: RoutineSetup, now: Date,
                       calendar: Calendar) -> RoutineStatus {
        guard setup.isSetUp else { return .notSetUp }
        let version = key(for: record, part: part, on: day, calendar: calendar)
        let items = setup.items(version)
        let due = record?.window ?? window(version, on: day, setup: setup, calendar: calendar)
        let finished = isComplete(record, items: items, share: setup.share)
            && (record?.completedAt.map { $0 <= due.end } ?? false)
        if version.place == .away {
            if finished { return .awayDone }
            return now > due.end ? .awayMissed : .awayOpen
        }
        if items.isEmpty { return .notSetUp }
        if finished { return .done }
        if now > due.end { return .missed }
        return now >= due.start ? .open : .upcoming
    }

    static func isComplete(_ record: RoutineRecord?, items: [RoutineItem], share: Double) -> Bool {
        guard let record, !items.isEmpty else { return false }
        let done = items.filter { record.ticked.contains($0.id) }.count
        return done >= required(items.count, share: share)
    }

    /// True when a home routine on `day` was missed: not done by its time, from the day penalties started.
    /// Morning and night together still only halve the day once.
    static func isPenalised(_ day: DayKey, records: [RoutinePart: RoutineRecord], setup: RoutineSetup, now: Date,
                            calendar: Calendar) -> Bool {
        guard let from = setup.penaltyFrom, day >= from else { return false }
        return RoutinePart.allCases.contains { part in
            status(part, on: day, record: records[part], setup: setup, now: now, calendar: calendar) == .missed
        }
    }

    /// Half of each category, rounded in your favour, so the day keeps at least half.
    static func halved(_ rewards: [RewardCategory: Pence]) -> [RewardCategory: Pence] {
        rewards.mapValues { amount in Pence(amount.value - amount.value / 2) }
    }

    /// Ticks or unticks an item. Done is the moment enough items are ticked, and is cleared if it drops below.
    static func toggle(_ itemID: String, in record: RoutineRecord, items: [RoutineItem], share: Double,
                       at date: Date) -> RoutineRecord {
        var next = record
        if next.ticked.contains(itemID) { next.ticked.remove(itemID) } else { next.ticked.insert(itemID) }
        next.completedAt = isComplete(next, items: items, share: share) ? (next.completedAt ?? date) : nil
        return next
    }
}

// MARK: - Questionnaire suggestions

enum RoutineCatalogue {
    /// Items that open the journal: writing the entry ticks them.
    static let journalPrompts: [String: String] = [
        "journal": "One intention for today",
        "wins": "Three wins from today",
    ]

    static let morning: [RoutineItem] = [
        item("water", "Big glass of water", "drop.fill"),
        item("tablets", "Tablets and supplements", "pills.fill"),
        item("weigh", "Weigh in", "scalemass.fill"),
        item("rehab", "Knee rehab, 5 minutes", "figure.cooldown"),
        item("stretch", "Stretch and mobility", "figure.flexibility"),
        item("shower", "Shower", "shower.fill"),
        item("skincare", "Skincare and SPF", "sparkles"),
        item("teeth", "Brush teeth", "mouth.fill"),
        item("bed", "Make the bed", "bed.double.fill"),
        item("breakfast", "Protein breakfast", "fork.knife"),
        item("sunlight", "20 minutes of sunlight", "sun.max.fill"),
        item("nophone", "No phone for the first 30 minutes", "iphone.slash"),
        item("plan", "Look at today in the Day tab", "calendar"),
        item("journal", "Journal: one intention for today", "book.fill"),
        item("breathe", "Five minutes breathing or meditation", "wind"),
        item("dressed", "Dressed and ready", "tshirt.fill"),
    ]

    static let evening: [RoutineItem] = [
        item("kitchen", "Kitchen tidy, dishwasher on", "dishwasher.fill"),
        item("lunch", "Tomorrow's lunch in the fridge", "takeoutbag.and.cup.and.straw.fill"),
        item("breakfastready", "Breakfast ready to go", "cup.and.saucer.fill"),
        item("clothes", "Clothes laid out", "tshirt.fill"),
        item("gymbag", "Gym bag packed", "bag.fill"),
        item("tomorrow", "Check tomorrow in the Day tab", "calendar"),
        item("reset", "Ten-minute house reset", "sofa.fill"),
        item("charge", "Phone charging outside the bedroom", "battery.100.bolt"),
        item("screens", "Screens off", "iphone.slash"),
        item("read", "Read for 20 minutes", "text.book.closed.fill"),
        item("eveningskin", "Skincare", "sparkles"),
        item("floss", "Brush teeth and floss", "mouth.fill"),
        item("eveningtablets", "Evening tablets", "pills.fill"),
        item("alarm", "Alarm set", "alarm.fill"),
        item("wins", "Journal: three wins", "heart.text.square.fill"),
        item("lockup", "Lock up and lights off", "lock.fill"),
    ]

    /// Extras that only make sense when you're away from home.
    static let away: [RoutineItem] = [
        item("packbag", "Bag packed for tomorrow", "suitcase.fill"),
        item("route", "Tomorrow's journey checked", "car.fill"),
        item("laptop", "Laptop and chargers charged", "laptopcomputer"),
        item("iron", "Tomorrow's outfit ironed", "tshirt.fill"),
        item("roomtidy", "Room tidy, keys and wallet in one place", "key.fill"),
        item("walkaway", "Short walk outside", "figure.walk"),
    ]

    static func suggestions(for key: RoutineKey) -> [RoutineItem] {
        let base = key.part == .morning ? morning : evening
        return key.place == .away ? base + away : base
    }

    /// Rob's answers to the questionnaire, as the starting point for each version.
    static func defaults(for key: RoutineKey) -> [RoutineItem] {
        let weekdayMorning = ["water", "tablets", "weigh", "rehab", "shower", "skincare", "teeth", "sunlight", "dressed",
                              "plan", "journal"]
        let ids: [String]
        switch (key.part, key.days, key.place) {
        case (.morning, .weekday, .home): ids = weekdayMorning
        case (.morning, .weekend, .home): ids = weekdayMorning + ["stretch", "breathe"]
        case (.morning, _, .away): ids = ["water", "tablets", "teeth", "dressed"]
        case (.evening, .weekday, .home):
            ids = ["kitchen", "lunch", "breakfastready", "clothes", "gymbag", "tomorrow", "reset", "charge", "eveningskin",
                   "floss", "wins"]
        case (.evening, .weekend, .home): ids = ["kitchen", "reset", "charge", "eveningskin", "floss"]
        case (.evening, _, .away): ids = ["packbag", "charge", "eveningskin", "floss"]
        }
        let all = suggestions(for: key)
        let chosen = Set(ids)
        // Keep the catalogue's order, so the checklist reads in a natural sequence.
        return all.filter { chosen.contains($0.id) }
    }

    private static func item(_ id: String, _ title: String, _ symbol: String) -> RoutineItem {
        RoutineItem(id: id, title: title, symbol: symbol)
    }
}
