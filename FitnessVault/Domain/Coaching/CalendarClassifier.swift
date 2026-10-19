import Foundation

/// How the user labelled each calendar visible in iOS (D-009).
enum CalendarRole: String, Codable, CaseIterable, Sendable, Identifiable {
    case work, personal, shared, ignored

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: "Work"
        case .personal: "Personal"
        case .shared: "Shared with Becky"
        case .ignored: "Don't use"
        }
    }
}

/// A calendar event reduced to what the coach needs. Built from EventKit by `CalendarService`,
/// so classification and availability never touch EventKit and can be unit tested.
struct CalendarEventInfo: Hashable, Sendable, Identifiable {
    var id: String
    var calendarID: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    /// EventKit availability "free": shown, never blocking.
    var showsAsFree: Bool = false
    var location: String? = nil
}

/// Where the user works today, read from the calendar rather than assumed by weekday (S2).
enum WorkLocation: String, Codable, Sendable {
    case home, office, unknown

    var title: String {
        switch self {
        case .home: "Working from home"
        case .office: "In the office"
        case .unknown: "Work location unknown"
        }
    }
}

/// A classified event ready for the consolidated calendar.
struct ClassifiedEvent: Hashable, Sendable, Identifiable {
    var event: CalendarEventInfo
    var role: CalendarRole
    var kind: BlockKind

    var id: String { event.id }
}

enum CalendarClassifier {
    static let focusKeywords = ["focus", "deep work", "heads down", "heads-down", "do not book", "dnb", "no meetings"]
    static let officeKeywords = ["in office", "in the office", "office day", "at office", "on site", "onsite"]
    static let homeKeywords = ["wfh", "work from home", "working from home", "remote day", "home working"]
    static let leaveKeywords = ["annual leave", "holiday", "day off", "out of office", "ooo", "pto", "leave"]

    /// Events from unlabelled calendars are left out until the user labels them, so the coach
    /// never guesses that a calendar is (or isn't) work.
    static func classify(_ events: [CalendarEventInfo], roles: [String: CalendarRole]) -> [ClassifiedEvent] {
        events.compactMap { event in
            guard let role = roles[event.calendarID], role != .ignored else { return nil }
            return ClassifiedEvent(event: event, role: role, kind: kind(of: event, role: role))
        }
        .sorted { ($0.event.start, $0.event.title) < ($1.event.start, $1.event.title) }
    }

    static func kind(of event: CalendarEventInfo, role: CalendarRole) -> BlockKind {
        if event.isAllDay { return .allDayInfo }
        switch role {
        case .shared: return .sharedInfo
        case .ignored: return .allDayInfo
        case .personal: return event.showsAsFree ? .allDayInfo : .personal
        case .work:
            if matches(event.title, focusKeywords) { return .workFocus }
            return event.showsAsFree ? .allDayInfo : .workMeeting
        }
    }

    /// Office or home, from all-day or titled markers on work or personal calendars. Unknown if there's no signal.
    static func workLocation(from events: [ClassifiedEvent]) -> WorkLocation {
        let own = events.filter { $0.role == .work || $0.role == .personal }
        if own.contains(where: { matches($0.event.title, homeKeywords) || matches($0.event.location ?? "", homeKeywords) }) {
            return .home
        }
        if own.contains(where: { matches($0.event.title, officeKeywords) || matches($0.event.location ?? "", officeKeywords) }) {
            return .office
        }
        return .unknown
    }

    /// True when a work or personal all-day event says the user is off.
    static func isOnLeave(_ events: [ClassifiedEvent]) -> Bool {
        events.contains { $0.event.isAllDay && $0.role != .shared && matches($0.event.title, leaveKeywords) }
    }

    /// Busy blocks for the availability engine.
    static func blocks(from events: [ClassifiedEvent]) -> [BusyBlock] {
        events.compactMap { item in
            guard item.event.end > item.event.start else { return nil }
            return BusyBlock(interval: DateInterval(start: item.event.start, end: item.event.end),
                             kind: item.kind, title: item.event.title)
        }
    }

    static func matches(_ text: String, _ keywords: [String]) -> Bool {
        let lowered = text.lowercased()
        return keywords.contains { keyword in
            // Whole-word match so "leave" doesn't fire on "leaves" and "dnb" doesn't fire inside other words.
            lowered.range(of: "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b", options: .regularExpression) != nil
        }
    }
}
