import Foundation

// The Day tab's picture of a day: your Apple calendar, your work Outlook calendar and Becky's calendar together.
// Pure and deterministic; EventKit, location, Apple Maps and the forecast feed it data.

/// What each calendar on the iPhone is. Calendars you haven't labelled are left out.
enum CalendarRole: String, Codable, CaseIterable, Sendable, Identifiable {
    case mine, becky, work, ignored

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mine: "Mine"
        case .becky: "Becky's"
        case .work: "Work (Outlook)"
        case .ignored: "Don't use"
        }
    }
}

/// A calendar visible on the iPhone: iCloud, a calendar Becky shares, or Outlook if the work account is added to iOS.
struct CalendarInfo: Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    /// The account it belongs to, e.g. "iCloud" or "Exchange".
    var sourceTitle: String
    var allowsAdding: Bool = false
}

/// A calendar event reduced to what the planner needs.
struct CalendarEventInfo: Hashable, Sendable, Identifiable {
    /// Unique per occurrence.
    var id: String
    /// The same for every occurrence of a repeating event, so Becky's weekly class is confirmed once.
    var seriesID: String
    var calendarID: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    /// Marked "free" in the calendar: shown, never blocking.
    var showsAsFree: Bool = false
    var location: String? = nil
    var notes: String? = nil

    /// The activity this event was added for, when it came from a suggestion.
    var plannedActivity: ActivityKind? {
        guard let notes, let range = notes.range(of: ActivityKind.marker) else { return nil }
        let rest = notes[range.upperBound...].prefix { $0.isLetter }
        return ActivityKind(rawValue: String(rest))
    }
}

/// Where you're working, from the Outlook event at 9 am.
enum WorkLocation: String, Codable, Sendable {
    case office, home
    /// A work day without an "Office focus" or "Home focus" at 9 am.
    case unknown
    case dayOff
    /// "Rob King AL" in Outlook.
    case leave

    var title: String {
        switch self {
        case .office: "Office day"
        case .home: "Home day"
        case .unknown: "Work day"
        case .dayOff: "Day off"
        case .leave: "Annual leave"
        }
    }

    var isWorkDay: Bool { self != .dayOff && self != .leave }
}

/// Whether one of Becky's events involves you. Only you decide; nothing is guessed.
enum BeckyStatus: String, Sendable {
    case shared, notShared, unconfirmed
}

/// Where a timeline event came from.
enum EventSource: Sendable {
    case mine, work, beckyShared, beckyVisible, beckyUnconfirmed
    /// "Blocked" or "Lunch walk" in Outlook: busy to work, free for you.
    case workFree

    /// Becky's events count only once you've said they're shared.
    var blocksTime: Bool {
        switch self {
        case .mine, .work, .beckyShared: true
        case .beckyVisible, .beckyUnconfirmed, .workFree: false
        }
    }
}

struct DayEvent: Hashable, Sendable, Identifiable {
    var event: CalendarEventInfo
    var source: EventSource

    var id: String { event.id }
    var blocksTime: Bool { source.blocksTime && !event.isAllDay && !event.showsAsFree && event.end > event.start }
}

enum DayCalendar {
    static let officeMarker = "office focus"
    static let homeMarker = "home focus"

    /// Outlook code words: busy to work but free for you, and annual leave. Whole words, any case.
    static let freeForMeWords = ["blocked", "lunch walk"]
    static let leaveWords = ["rob king al"]

    static func isFreeForMe(_ event: CalendarEventInfo) -> Bool { matches(event.title, freeForMeWords) }
    static func isLunchWalk(_ event: CalendarEventInfo) -> Bool { matches(event.title, ["lunch walk"]) }
    static func isLeave(_ event: CalendarEventInfo) -> Bool { matches(event.title, leaveWords) }

    static func matches(_ text: String, _ words: [String]) -> Bool {
        let lowered = text.lowercased()
        return words.contains { word in
            lowered.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression) != nil
        }
    }

    /// The work event at 9 am titled "Office focus" or "Home focus". A weekday with work events but no marker is a
    /// work day with an unknown location; a day with neither is a day off.
    static func workLocation(on day: DayKey, events: [CalendarEventInfo], roles: [String: CalendarRole],
                             calendar: Calendar) -> WorkLocation {
        let nine = day.date(atMinute: 9 * 60, calendar: calendar)
        let work = events.filter { roles[$0.calendarID] == .work && overlaps($0, day: day, calendar: calendar) }
        if work.contains(where: isLeave) { return .leave }
        for event in work where covers(event, nine) {
            let title = event.title.lowercased()
            if title.contains(officeMarker) { return .office }
            if title.contains(homeMarker) { return .home }
        }
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        let isWeekday = weekday != 1 && weekday != 7
        let meetings = work.filter { !$0.isAllDay && !isFreeForMe($0) }
        return isWeekday && !meetings.isEmpty ? .unknown : .dayOff
    }

    static func isFocusMarker(_ event: CalendarEventInfo) -> Bool {
        let title = event.title.lowercased()
        return title.contains(officeMarker) || title.contains(homeMarker)
    }

    static func beckyStatus(_ event: CalendarEventInfo, decisions: [String: Bool]) -> BeckyStatus {
        guard let shared = decisions[event.seriesID] else { return .unconfirmed }
        return shared ? .shared : .notShared
    }

    /// The day's events from labelled calendars, minus the 9 am focus markers (they show as the day's location).
    static func events(on day: DayKey, events: [CalendarEventInfo], roles: [String: CalendarRole],
                       decisions: [String: Bool], calendar: Calendar) -> [DayEvent] {
        events.compactMap { event -> DayEvent? in
            guard overlaps(event, day: day, calendar: calendar), let role = roles[event.calendarID] else { return nil }
            switch role {
            case .ignored:
                return nil
            case .mine:
                return DayEvent(event: event, source: .mine)
            case .work:
                if isFocusMarker(event) || isLeave(event) { return nil }
                return DayEvent(event: event, source: isFreeForMe(event) ? .workFree : .work)
            case .becky:
                switch beckyStatus(event, decisions: decisions) {
                case .shared: return DayEvent(event: event, source: .beckyShared)
                case .notShared: return DayEvent(event: event, source: .beckyVisible)
                case .unconfirmed: return DayEvent(event: event, source: .beckyUnconfirmed)
                }
            }
        }
        .sorted { lhs, rhs in
            if lhs.event.start != rhs.event.start { return lhs.event.start < rhs.event.start }
            return lhs.event.title < rhs.event.title
        }
    }

    /// Becky's events still to confirm, one per repeating series, soonest first. Past events don't need an answer.
    static func needsConfirming(_ events: [CalendarEventInfo], roles: [String: CalendarRole], decisions: [String: Bool],
                                now: Date) -> [CalendarEventInfo] {
        var seen = Set<String>()
        return events
            .filter { roles[$0.calendarID] == .becky && $0.end > now && decisions[$0.seriesID] == nil }
            .sorted { $0.start < $1.start }
            .filter { seen.insert($0.seriesID).inserted }
    }

    static func overlaps(_ event: CalendarEventInfo, day: DayKey, calendar: Calendar) -> Bool {
        let start = day.startDate(calendar: calendar), end = day.endDate(calendar: calendar)
        if event.start == event.end { return event.start >= start && event.start < end }
        return event.start < end && event.end > start
    }

    private static func covers(_ event: CalendarEventInfo, _ date: Date) -> Bool {
        if event.isAllDay { return event.start <= date && event.end > date }
        return event.start <= date && (event.end > date || event.start == date)
    }
}
