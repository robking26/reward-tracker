import Foundation

/// A calendar day in the user's local time zone. Rewards are always assigned to the day the activity occurred.
struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Parses `yyyy-MM-dd`.
    init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var monthKey: MonthKey { MonthKey(year: year, month: month) }

    func startDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    func endDate(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: startDate(calendar: calendar)) ?? .distantFuture
    }

    /// Wall-clock time on this day, e.g. minute 355 is 05:55. Unlike midnight plus seconds, this stays right on
    /// the days the clocks change (the last Sundays of March and October in the UK).
    func date(atMinute minute: Int, calendar: Calendar = .current) -> Date {
        let minute = max(0, minute)
        let components = DateComponents(year: year, month: month, day: day, hour: minute / 60, minute: minute % 60)
        return calendar.date(from: components) ?? startDate(calendar: calendar).addingTimeInterval(TimeInterval(minute * 60))
    }

    func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        DayKey(calendar.date(byAdding: .day, value: days, to: startDate(calendar: calendar)) ?? .distantPast, calendar: calendar)
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// A calendar month. Each month has its own vault allocation.
struct MonthKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(_ date: Date, calendar: Calendar = .current) {
        self = DayKey(date, calendar: calendar).monthKey
    }

    init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        self.init(year: parts[0], month: parts[1])
    }

    var description: String { String(format: "%04d-%02d", year, month) }

    var firstDay: DayKey { DayKey(year: year, month: month, day: 1) }

    func days(calendar: Calendar = .current) -> [DayKey] {
        let start = firstDay.startDate(calendar: calendar)
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        return (1...count).map { DayKey(year: year, month: month, day: $0) }
    }

    var next: MonthKey { month == 12 ? MonthKey(year: year + 1, month: 1) : MonthKey(year: year, month: month + 1) }
    var previous: MonthKey { month == 1 ? MonthKey(year: year - 1, month: 12) : MonthKey(year: year, month: month - 1) }

    func title(calendar: Calendar = .current) -> String {
        firstDay.startDate(calendar: calendar).formatted(.dateTime.month(.wide).year())
    }

    func monthName(calendar: Calendar = .current) -> String {
        firstDay.startDate(calendar: calendar).formatted(.dateTime.month(.wide))
    }

    static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}
