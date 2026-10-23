import Foundation

// Morning self-care for today's you, and evening self-care for tomorrow's you. Each has a weekday and a weekend
// version, at home and away. Missing a home routine halves that day's earnings. Pure and deterministic, so the rule
// can be tested and always gives the same answer for the same records.

enum RoutinePart: String, Codable, CaseIterable, Sendable, Identifiable {
    case morning, lunchWalk, teaWalk, evening

    var id: String { rawValue }

    /// Only the morning and night routines halve a day's earnings; the walks are for the streak.
    static let penalised: [RoutinePart] = [.morning, .evening]
    /// The parts the questionnaire builds.
    static let routines: [RoutinePart] = [.morning, .evening]

    var isWalk: Bool { self == .lunchWalk || self == .teaWalk }

    var title: String {
        switch self {
        case .morning: "Morning routine"
        case .lunchWalk: "Walk after lunch"
        case .teaWalk: "Walk after tea"
        case .evening: "Night routine"
        }
    }

    var shortTitle: String {
        switch self {
        case .morning: "Morning"
        case .lunchWalk: "Lunch"
        case .teaWalk: "Tea"
        case .evening: "Night"
        }
    }

    var purpose: String {
        switch self {
        case .morning: "For today's you"
        case .lunchWalk, .teaWalk: "20 minutes on your feet"
        case .evening: "For tomorrow's you"
        }
    }

    var symbol: String {
        switch self {
        case .morning: "sunrise.fill"
        case .lunchWalk: "sun.max.fill"
        case .teaWalk: "sunset.fill"
        case .evening: "moon.stars.fill"
        }
    }
}

/// On weekday mornings at home: Outlook's 9 am Home focus or Office focus, which adds that day's extras.
enum RoutineWorkDay: String, Codable, Sendable {
    case homeDay, officeDay
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
        case (.lunchWalk, _): when = "Walk after lunch"
        case (.teaWalk, _): when = "Walk after tea"
        }
        return "\(when) · \(place.title.lowercased())"
    }

    /// The eight questionnaire versions (the walks have one item each and aren't asked about).
    static let all: [RoutineKey] = RoutinePlace.allCases.flatMap { place in
        RoutinePart.routines.flatMap { part in RoutineDays.allCases.map { RoutineKey(part: part, days: $0, place: place) } }
    }
}

struct RoutineItem: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var symbol: String
    /// Roughly how long it takes, for the planned clock and pace.
    var minutes: Int? = nil
    /// Only on a home day or an office day (weekday mornings).
    var only: RoutineWorkDay? = nil
}

/// When a routine opens and when it has to be finished, as minutes after midnight.
struct RoutineTimes: Codable, Hashable, Sendable {
    var start: Int
    var finish: Int
    /// Moves earlier so it's finished before the day's first calendar event, keeping its length.
    var beforeFirstEvent: Bool? = nil
    /// No set time: any time that evening, and no reminders.
    var adHoc: Bool? = nil
    /// Finishes when the items' timings add up to (plus ten minutes' slack), so extras make it longer.
    var fitsItems: Bool? = nil

    var movesForEvents: Bool { beforeFirstEvent ?? false }
    var isAdHoc: Bool { adHoc ?? false }
    var isFitted: Bool { fitsItems ?? false }
}

struct RoutineSetup: Codable, Hashable, Sendable {
    /// Items for each version, keyed by `RoutineKey.id`.
    var items: [String: [RoutineItem]] = [:]
    var times: [String: RoutineTimes] = [:]
    /// The first day a missed home routine costs anything; nil until the questionnaire is done.
    var penaltyFrom: DayKey?
    /// The share of items that makes a routine done. Nil (older setups) means 80%.
    var completionShare: Double? = nil
    /// Which version of the built-in routines this was saved from, so new timings can be brought in once.
    var version: Int? = nil

    static let currentVersion = 2

    var isSetUp: Bool { penaltyFrom != nil }
    var share: Double { min(max(completionShare ?? 0.8, 0.1), 1) }

    func items(_ key: RoutineKey) -> [RoutineItem] {
        if key.part.isWalk { return items[key.id] ?? [RoutineCatalogue.walk] }
        return items[key.id] ?? []
    }
    func times(_ key: RoutineKey) -> RoutineTimes { times[key.id] ?? Self.defaultTimes(key) }

    /// From Rob's questionnaire: up at 6 on weekdays and done by 6:45; weekend and away mornings 10 to 11 or the
    /// hour before the first thing in the calendar; in bed by 9:30 on work nights, 10:30 on Friday and Saturday;
    /// nights away whenever suits.
    static func defaultTimes(_ key: RoutineKey) -> RoutineTimes {
        switch (key.part, key.days, key.place) {
        case (.morning, .weekday, .home): RoutineTimes(start: 6 * 60, finish: 7 * 60 + 45, fitsItems: true)
        case (.morning, .weekend, .home), (.morning, _, .away):
            RoutineTimes(start: 10 * 60, finish: 11 * 60, beforeFirstEvent: true)
        case (.evening, .weekday, .home): RoutineTimes(start: 21 * 60, finish: 21 * 60 + 30)
        case (.evening, .weekend, .home): RoutineTimes(start: 22 * 60, finish: 22 * 60 + 30)
        case (.evening, _, .away): RoutineTimes(start: 18 * 60, finish: 23 * 60 + 59, adHoc: true)
        case (.lunchWalk, _, _): RoutineTimes(start: 12 * 60 + 30, finish: 13 * 60 + 30)
        case (.teaWalk, _, _): RoutineTimes(start: 18 * 60 + 30, finish: 19 * 60 + 30)
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
    /// Home day or office day, for a weekday morning's extras.
    var work: RoutineWorkDay? = nil
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
    /// Outlook's 9 am focus, on a weekday.
    var workDay: RoutineWorkDay? = nil
    /// A "Lunch walk" in Outlook: the walk after lunch goes there.
    var lunchWalk: DateInterval? = nil
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

    /// A weekday morning at home without a known focus counts as a home day, as the Day tab assumes.
    static func workDay(_ key: RoutineKey, saved: RoutineWorkDay?) -> RoutineWorkDay? {
        guard key.part == .morning, key.days == .weekday, key.place == .home else { return nil }
        return saved ?? .homeDay
    }

    /// The items for a version on the day: the home-day or office-day extras only on those days.
    static func items(_ key: RoutineKey, setup: RoutineSetup, work: RoutineWorkDay?) -> [RoutineItem] {
        let day = workDay(key, saved: work)
        return setup.items(key).filter { item in item.only == nil || item.only == day }
    }

    static func window(_ key: RoutineKey, on day: DayKey, setup: RoutineSetup, firstEvent: Date? = nil,
                       work: RoutineWorkDay? = nil, lunchWalk: DateInterval? = nil, calendar: Calendar) -> DateInterval {
        let times = setup.times(key)
        // An Outlook "Lunch walk" is when the walk after lunch happens.
        if key.part == .lunchWalk, let lunchWalk {
            return DateInterval(start: lunchWalk.start, end: max(lunchWalk.end, lunchWalk.start.addingTimeInterval(20 * 60)))
        }
        var start = day.date(atMinute: times.start, calendar: calendar)
        var finishMinute = times.finish
        if times.isFitted {
            let total = items(key, setup: setup, work: work).reduce(0) { $0 + ($1.minutes ?? 5) }
            finishMinute = times.start + total + 10
        }
        // Always finishes the same day, so a missed night routine belongs to that day's earnings.
        var finish = day.date(atMinute: min(max(finishMinute, times.start + 5), 23 * 60 + 59), calendar: calendar)
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
        let items = items(version, setup: setup, work: record?.work)
        let due = record?.window ?? window(version, on: day, setup: setup, work: record?.work, calendar: calendar)
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
        return RoutinePart.penalised.contains { part in
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

// MARK: - Keeping score

/// The quiet game: streaks, pace against the planned clock, and the week at a glance.
enum RoutineScore {
    /// Days in a row done (at home or away), counting back. Today counts once it's done and is skipped while
    /// it's still open; a miss ends the run.
    static func streak(_ statuses: [RoutineStatus]) -> Int {
        var count = 0
        for (index, status) in statuses.enumerated() {
            let stillGoing = status == .upcoming || status == .open || status == .awayOpen
            if index == 0 && stillGoing { continue }
            guard status == .done || status == .awayDone else { return count }
            count += 1
        }
        return count
    }

    /// When each item is due if you go in order from the start.
    static func plannedTimes(_ items: [RoutineItem], from start: Date) -> [Date] {
        var clock = start
        return items.map { item in
            defer { clock = clock.addingTimeInterval(TimeInterval((item.minutes ?? 5) * 60)) }
            return clock
        }
    }

    /// Minutes ahead (positive) or behind (negative): when the next thing to do was planned, against now.
    /// Nil once everything is ticked.
    static func pace(_ items: [RoutineItem], ticked: Set<String>, start: Date, now: Date) -> Int? {
        let times = plannedTimes(items, from: start)
        guard let next = items.indices.first(where: { !ticked.contains(items[$0].id) }) else { return nil }
        return Int((times[next].timeIntervalSince(now) / 60).rounded())
    }

    static func paceText(_ minutes: Int) -> String {
        if abs(minutes) < 3 { return "On pace" }
        return minutes > 0 ? "\(minutes) min ahead" : "\(-minutes) min behind"
    }
}

// MARK: - Questionnaire suggestions

enum RoutineCatalogue {
    /// Items that open the journal: writing the entry ticks them.
    static let journalPrompts: [String: String] = [
        "journal": "One intention for today",
        "journalcoffee": "One intention for today",
        "journaltrain": "One intention for today",
        "wins": "Three wins from today",
    ]

    /// The single item of each daily walk.
    static let walk = item("walk20", "20-minute walk", "figure.walk", 20)

    /// Rob's mornings, with rough timings. Order is the order they're done in.
    static let morning: [RoutineItem] = [
        item("run10", "10-minute run", "figure.run", 10),
        item("rehab15", "Knee rehab", "figure.cooldown", 15),
        item("showerteeth", "Shower and brush teeth", "shower.fill", 5),
        item("shave", "Shave and minoxidil", "comb.fill", 5),
        item("dressbreakfast", "Dressed, breakfast, wash up", "fork.knife", 10),
        item("breakfastwalk", "Walk after breakfast", "figure.walk", 20),
        item("facehair", "Face cream and hair", "sparkles", 5),
        item("journalcoffee", "Journal and coffee", "cup.and.saucer.fill", 5),
        item("journal", "Journal", "book.fill", 5),
        item("coffeeout", "Go for a coffee", "takeoutbag.and.cup.and.straw.fill", 5),
        item("gymkit", "Gym kit packed in the van", "bag.fill", 5),
        item("washon", "Journal, coffee and a wash on", "washer.fill", 5, only: .homeDay),
        item("preptea", "Prep tea", "frying.pan.fill", 25, only: .homeDay),
        item("workbag", "Work bag packed", "briefcase.fill", 5, only: .officeDay),
        item("station", "Get to the train station", "tram.fill", 10, only: .officeDay),
        item("journaltrain", "Journal on the train", "book.fill", 5, only: .officeDay),
        item("water", "Big glass of water", "drop.fill", 2),
        item("tablets", "Tablets and supplements", "pills.fill", 2),
        item("weigh", "Weigh in", "scalemass.fill", 2),
        item("stretch", "Stretch and mobility", "figure.flexibility", 5),
        item("breathe", "Five minutes breathing or meditation", "wind", 5),
        item("sunlight", "20 minutes of sunlight", "sun.max.fill", 20),
        item("plan", "Look at today in the Day tab", "calendar", 2),
    ]

    static let evening: [RoutineItem] = [
        item("kitchen", "Kitchen tidy, dishwasher on", "dishwasher.fill", 10),
        item("lunch", "Tomorrow's lunch in the fridge", "takeoutbag.and.cup.and.straw.fill", 5),
        item("breakfastready", "Breakfast ready to go", "cup.and.saucer.fill", 3),
        item("clothes", "Clothes laid out", "tshirt.fill", 3),
        item("gymbag", "Gym bag packed", "bag.fill", 5),
        item("tomorrow", "Check tomorrow in the Day tab", "calendar", 2),
        item("reset", "Ten-minute house reset", "sofa.fill", 10),
        item("charge", "Phone charging outside the bedroom", "battery.100.bolt", 1),
        item("screens", "Screens off", "iphone.slash", 1),
        item("read", "Read for 20 minutes", "text.book.closed.fill", 20),
        item("eveningskin", "Skincare", "sparkles", 3),
        item("floss", "Brush teeth and floss", "mouth.fill", 4),
        item("eveningtablets", "Evening tablets", "pills.fill", 1),
        item("alarm", "Alarm set", "alarm.fill", 1),
        item("wins", "Journal: three wins", "heart.text.square.fill", 5),
        item("lockup", "Lock up and lights off", "lock.fill", 2),
    ]

    /// Extras that only make sense when you're away from home.
    static let away: [RoutineItem] = [
        item("packbag", "Bag packed for tomorrow", "suitcase.fill", 5),
        item("route", "Tomorrow's journey checked", "car.fill", 2),
        item("laptop", "Laptop and chargers charged", "laptopcomputer", 1),
        item("iron", "Tomorrow's outfit ironed", "tshirt.fill", 5),
        item("roomtidy", "Room tidy, keys and wallet in one place", "key.fill", 3),
        item("walkaway", "Short walk outside", "figure.walk", 15),
    ]

    static func suggestions(for key: RoutineKey) -> [RoutineItem] {
        if key.part.isWalk { return [walk] }
        let base = key.part == .morning ? morning : evening
        return key.place == .away ? base + away : base
    }

    /// Rob's routines, as the starting point for each version.
    static func defaults(for key: RoutineKey) -> [RoutineItem] {
        let ids: [String]
        switch (key.part, key.days, key.place) {
        case (.morning, .weekday, .home):
            ids = ["run10", "rehab15", "showerteeth", "shave", "dressbreakfast", "breakfastwalk", "facehair", "washon",
                   "preptea", "gymkit", "workbag", "station", "journaltrain"]
        case (.morning, .weekend, .home):
            ids = ["showerteeth", "shave", "dressbreakfast", "breakfastwalk", "facehair", "journalcoffee"]
        case (.morning, _, .away):
            ids = ["showerteeth", "shave", "dressbreakfast", "breakfastwalk", "facehair", "journal", "coffeeout"]
        case (.evening, .weekday, .home):
            ids = ["kitchen", "lunch", "breakfastready", "clothes", "gymbag", "tomorrow", "reset", "charge", "eveningskin",
                   "floss", "wins"]
        case (.evening, .weekend, .home): ids = ["kitchen", "reset", "charge", "eveningskin", "floss"]
        case (.evening, _, .away): ids = ["packbag", "charge", "eveningskin", "floss"]
        case (.lunchWalk, _, _), (.teaWalk, _, _): return [walk]
        }
        // In the order given, which is the order they're done in.
        let all = suggestions(for: key)
        return ids.compactMap { id in all.first { $0.id == id } }
    }

    private static func item(_ id: String, _ title: String, _ symbol: String, _ minutes: Int,
                             only: RoutineWorkDay? = nil) -> RoutineItem {
        RoutineItem(id: id, title: title, symbol: symbol, minutes: minutes, only: only)
    }
}
