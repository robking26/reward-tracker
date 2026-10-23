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
}

struct RoutineSetup: Codable, Hashable, Sendable {
    /// Items for each version, keyed by `RoutineKey.id`.
    var items: [String: [RoutineItem]] = [:]
    var times: [String: RoutineTimes] = [:]
    /// The first day a missed home routine costs anything; nil until the questionnaire is done.
    var penaltyFrom: DayKey?

    var isSetUp: Bool { penaltyFrom != nil }

    func items(_ key: RoutineKey) -> [RoutineItem] { items[key.id] ?? [] }
    func times(_ key: RoutineKey) -> RoutineTimes { times[key.id] ?? Self.defaultTimes(key) }

    /// 6 am on weekdays and 9 pm at night at home, as asked; the rest are starting points for the questionnaire.
    static func defaultTimes(_ key: RoutineKey) -> RoutineTimes {
        switch (key.part, key.days, key.place) {
        case (.morning, .weekday, .home): RoutineTimes(start: 6 * 60, finish: 7 * 60 + 30)
        case (.morning, .weekend, .home): RoutineTimes(start: 8 * 60, finish: 10 * 60)
        case (.morning, _, .away): RoutineTimes(start: 7 * 60, finish: 9 * 60)
        case (.evening, _, .home): RoutineTimes(start: 21 * 60, finish: 22 * 60 + 30)
        case (.evening, _, .away): RoutineTimes(start: 21 * 60, finish: 23 * 60)
        }
    }
}

/// What happened with one routine on one day.
struct RoutineRecord: Hashable, Sendable {
    var day: DayKey
    var part: RoutinePart
    var place: RoutinePlace = .home
    var ticked: Set<String> = []
    /// When the last item was ticked, if everything is ticked.
    var completedAt: Date?
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

enum RoutineRules {
    /// Mornings follow the day itself. Nights follow the day after, because they're for tomorrow's you:
    /// Sunday to Thursday nights get the weekday version, Friday and Saturday nights the weekend one.
    static func days(for part: RoutinePart, on day: DayKey, calendar: Calendar) -> RoutineDays {
        let target = part == .morning ? day : day.adding(days: 1, calendar: calendar)
        let weekday = calendar.component(.weekday, from: target.startDate(calendar: calendar))
        return weekday == 1 || weekday == 7 ? .weekend : .weekday
    }

    static func key(_ part: RoutinePart, on day: DayKey, place: RoutinePlace, calendar: Calendar) -> RoutineKey {
        RoutineKey(part: part, days: days(for: part, on: day, calendar: calendar), place: place)
    }

    static func window(_ key: RoutineKey, on day: DayKey, setup: RoutineSetup, calendar: Calendar) -> DateInterval {
        let times = setup.times(key)
        let start = day.date(atMinute: times.start, calendar: calendar)
        // Always finishes the same day, so a missed night routine belongs to that day's earnings.
        let finish = day.date(atMinute: min(max(times.finish, times.start + 5), 23 * 60 + 59), calendar: calendar)
        return DateInterval(start: start, end: finish)
    }

    static func status(_ part: RoutinePart, on day: DayKey, record: RoutineRecord?, setup: RoutineSetup, now: Date,
                       calendar: Calendar) -> RoutineStatus {
        guard setup.isSetUp else { return .notSetUp }
        let place = record?.place ?? .home
        let version = key(part, on: day, place: place, calendar: calendar)
        let items = setup.items(version)
        let due = window(version, on: day, setup: setup, calendar: calendar)
        let finished = isComplete(record, items: items) && (record?.completedAt.map { $0 <= due.end } ?? false)
        if place == .away {
            if finished { return .awayDone }
            return now > due.end ? .awayMissed : .awayOpen
        }
        if items.isEmpty { return .notSetUp }
        if finished { return .done }
        if now > due.end { return .missed }
        return now >= due.start ? .open : .upcoming
    }

    static func isComplete(_ record: RoutineRecord?, items: [RoutineItem]) -> Bool {
        guard let record, !items.isEmpty else { return false }
        return items.allSatisfy { record.ticked.contains($0.id) }
    }

    /// True when a home routine on `day` was missed: not finished by its time, from the day penalties started.
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

    /// Ticks or unticks an item. Finishing time is the moment the last item goes in, and is cleared if one comes out.
    static func toggle(_ itemID: String, in record: RoutineRecord, items: [RoutineItem], at date: Date) -> RoutineRecord {
        var next = record
        if next.ticked.contains(itemID) { next.ticked.remove(itemID) } else { next.ticked.insert(itemID) }
        if isComplete(next, items: items) {
            next.completedAt = next.completedAt ?? date
        } else {
            next.completedAt = nil
        }
        return next
    }
}

// MARK: - Questionnaire suggestions

enum RoutineCatalogue {
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
        item("daylight", "Ten minutes of daylight", "sun.max.fill"),
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
        item("wins", "Write down three wins", "heart.text.square.fill"),
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

    /// A sensible starting selection for each version, which the questionnaire lets you change.
    static func defaults(for key: RoutineKey) -> [RoutineItem] {
        let ids: [String]
        switch (key.part, key.days, key.place) {
        case (.morning, .weekday, .home): ids = ["water", "tablets", "rehab", "shower", "teeth", "bed", "breakfast", "plan"]
        case (.morning, .weekend, .home): ids = ["water", "tablets", "stretch", "teeth", "bed", "breakfast", "daylight"]
        case (.morning, _, .away): ids = ["water", "tablets", "shower", "teeth", "breakfast", "plan"]
        case (.evening, .weekday, .home): ids = ["kitchen", "lunch", "clothes", "gymbag", "tomorrow", "charge", "floss", "alarm"]
        case (.evening, .weekend, .home): ids = ["kitchen", "reset", "charge", "read", "floss"]
        case (.evening, _, .away): ids = ["packbag", "route", "laptop", "charge", "floss", "alarm"]
        }
        let all = suggestions(for: key)
        return ids.compactMap { id in all.first { $0.id == id } }
    }

    private static func item(_ id: String, _ title: String, _ symbol: String) -> RoutineItem {
        RoutineItem(id: id, title: title, symbol: symbol)
    }
}
