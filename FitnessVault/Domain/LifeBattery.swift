import Foundation

// A year's transformation as a battery, from 0% to 100%. The gym, swims and runs charge it; missed gym sessions and
// missed step targets drain it. Kept in whole quarter-percents so the arithmetic is exact.

/// One day's activity, as the battery sees it.
struct BatteryDay: Hashable, Sendable {
    var gym = false
    var swim = false
    var run = false
    var steps = 0
    /// The Gym tab's walking target that day; nil when it isn't known yet.
    var stepTarget: Int?
}

struct BatteryEvent: Hashable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case gym, swim, run, stepsMissed, gymMissed

        var title: String {
            switch self {
            case .gym: "Gym"
            case .swim: "Swim"
            case .run: "Run"
            case .stepsMissed: "Steps target missed"
            case .gymMissed: "Gym session missed"
            }
        }

        var symbol: String {
            switch self {
            case .gym: "dumbbell.fill"
            case .swim: "figure.pool.swim"
            case .run: "figure.run"
            case .stepsMissed: "figure.walk"
            case .gymMissed: "calendar.badge.minus"
            }
        }
    }

    var day: DayKey
    var kind: Kind
    /// Quarter-percents, e.g. +2 is +0.5%.
    var quarters: Int
    /// For a missed gym session, which one in the week (so each has its own ID).
    var index = 0

    var id: String { "\(day)|\(kind.rawValue)|\(index)" }
    var percent: Double { Double(quarters) / 4 }
}

struct BatteryResult: Hashable, Sendable {
    /// 0 to 400 quarter-percents.
    var quarters: Int
    /// The level at the end of each day, oldest first.
    var history: [DayLevel]
    /// Newest first.
    var events: [BatteryEvent]

    struct DayLevel: Hashable, Sendable {
        var day: DayKey
        var quarters: Int
        var percent: Double { Double(quarters) / 4 }
    }

    var percent: Double { Double(quarters) / 4 }
    static let empty = BatteryResult(quarters: 0, history: [], events: [])
}

enum LifeBattery {
    static let full = 400
    static let gym = 2, gymMissed = -2, swim = 1, run = 1, stepsMissed = -1

    /// Walks every day from `start` to `today`. Gains count straight away; a missed step target counts once the day
    /// is over, and missed gym sessions at the end of each Monday-to-Sunday week. Never below 0% or above 100%.
    static func compute(start: DayKey, today: DayKey, days: [DayKey: BatteryDay], gymPerWeek: Int,
                        calendar: Calendar) -> BatteryResult {
        guard start <= today else { return .empty }
        var level = 0
        var history: [BatteryResult.DayLevel] = []
        var events: [BatteryEvent] = []

        func apply(_ event: BatteryEvent) {
            let before = level
            level = min(full, max(0, level + event.quarters))
            // Only what actually moved the battery is listed, so a miss at 0% isn't shown as a loss.
            var applied = event
            applied.quarters = level - before
            if applied.quarters != 0 || event.quarters > 0 { events.append(applied) }
        }

        var day = start
        while day <= today {
            let record = days[day] ?? BatteryDay()
            if record.gym { apply(BatteryEvent(day: day, kind: .gym, quarters: gym)) }
            if record.swim { apply(BatteryEvent(day: day, kind: .swim, quarters: swim)) }
            if record.run { apply(BatteryEvent(day: day, kind: .run, quarters: run)) }
            if day < today, let target = record.stepTarget, record.steps < target {
                apply(BatteryEvent(day: day, kind: .stepsMissed, quarters: stepsMissed))
            }
            // Sunday closes the week, once it's over.
            if day < today, calendar.component(.weekday, from: day.startDate(calendar: calendar)) == 1 {
                let monday = day.adding(days: -6, calendar: calendar)
                let first = max(monday, start)
                var count = 0
                var cursor = first
                while cursor <= day {
                    if days[cursor]?.gym == true { count += 1 }
                    cursor = cursor.adding(days: 1, calendar: calendar)
                }
                let target = weeklyTarget(gymPerWeek, days: daysBetween(first, day, calendar: calendar) + 1)
                for missed in 0..<max(0, target - count) {
                    apply(BatteryEvent(day: day, kind: .gymMissed, quarters: gymMissed, index: missed))
                }
            }
            history.append(.init(day: day, quarters: level))
            day = day.adding(days: 1, calendar: calendar)
        }
        return BatteryResult(quarters: level, history: history, events: events.reversed())
    }

    /// A first, partial week only asks for its share of the sessions: three a week from a Friday start is one.
    static func weeklyTarget(_ perWeek: Int, days: Int) -> Int {
        guard days < 7 else { return perWeek }
        return Int((Double(perWeek) * Double(days) / 7).rounded())
    }

    static func daysBetween(_ start: DayKey, _ end: DayKey, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start.startDate(calendar: calendar), to: end.startDate(calendar: calendar)).day ?? 0
    }

    /// Where the last four weeks' pace (or since the start, once there's a week of it) leads by the end of the year.
    static func projection(_ result: BatteryResult, today: DayKey, end: DayKey, calendar: Calendar) -> Double? {
        guard result.history.count >= 7, let latest = result.history.last else { return nil }
        let window = min(28, result.history.count - 1)
        let earlier = result.history[result.history.count - 1 - window]
        let perDay = Double(latest.quarters - earlier.quarters) / Double(window)
        let left = Double(max(0, daysBetween(today, end, calendar: calendar)))
        return min(100, max(0, (Double(latest.quarters) + perDay * left) / 4))
    }

    /// The change since a day, in percent.
    static func change(_ result: BatteryResult, since day: DayKey) -> Double {
        let before = result.history.last { $0.day < day }?.quarters ?? 0
        return Double(result.quarters - before) / 4
    }
}
