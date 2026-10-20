import EventKit
import Foundation

enum CalendarAccess: String, Equatable, Sendable {
    case notDetermined, granted, denied, restricted, writeOnly

    var title: String {
        switch self {
        case .notDetermined: "Not set up"
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .restricted: "Restricted on this iPhone"
        case .writeOnly: "Add-only access"
        }
    }
}

/// A calendar visible in iOS (Apple, Outlook/Exchange if added, shared calendars).
struct CalendarInfo: Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    /// The account it belongs to, e.g. "iCloud" or "Exchange".
    var sourceTitle: String
}

/// Read-only calendar access (N4). The app never creates, moves or deletes external events.
@MainActor
protocol CalendarProviding: AnyObject {
    var access: CalendarAccess { get }
    func requestAccess() async -> CalendarAccess
    func calendars() -> [CalendarInfo]
    func events(from start: Date, to end: Date) -> [CalendarEventInfo]
}

/// EventKit, on device. Outlook appears here only if the work account has been added to iOS (D-008).
@MainActor
final class EventKitCalendarService: CalendarProviding {
    private let store = EKEventStore()

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .writeOnly: .writeOnly
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestAccess() async -> CalendarAccess {
        _ = try? await store.requestFullAccessToEvents()
        store.reset()
        return access
    }

    func calendars() -> [CalendarInfo] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source?.title ?? "") }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    func events(from start: Date, to end: Date) -> [CalendarEventInfo] {
        guard access == .granted, end > start else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            // Bound through optionals so this compiles whether the SDK marks these as optional or not.
            let startValue: Date? = event.startDate, endValue: Date? = event.endDate
            let calendarValue: EKCalendar? = event.calendar, titleValue: String? = event.title
            guard let eventStart = startValue, let eventEnd = endValue, let calendar = calendarValue else { return nil }
            // Recurring occurrences share an identifier, so the start time keeps each one unique.
            let id = "\(event.calendarItemIdentifier)@\(Int(eventStart.timeIntervalSince1970))"
            return CalendarEventInfo(id: id, calendarID: calendar.calendarIdentifier, title: titleValue ?? "Busy",
                                     start: eventStart, end: eventEnd, isAllDay: event.isAllDay,
                                     showsAsFree: event.availability == .free, location: event.location)
        }
    }
}

/// Sample calendars for demo mode and tests: a work day with meetings and a focus block, and Becky at the gym.
@MainActor
final class DemoCalendarService: CalendarProviding {
    static let workID = "demo-work"
    static let personalID = "demo-personal"
    static let sharedID = "demo-becky"
    static let roles: [String: CalendarRole] = [workID: .work, personalID: .personal, sharedID: .shared]

    var calendar: Calendar
    /// Extra events, e.g. a meeting added in a test (scenario B).
    var extraEvents: [CalendarEventInfo] = []

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    var access: CalendarAccess { .granted }
    func requestAccess() async -> CalendarAccess { .granted }

    func calendars() -> [CalendarInfo] {
        [CalendarInfo(id: Self.workID, title: "Work (demo)", sourceTitle: "Exchange"),
         CalendarInfo(id: Self.personalID, title: "Personal (demo)", sourceTitle: "iCloud"),
         CalendarInfo(id: Self.sharedID, title: "Becky (demo)", sourceTitle: "iCloud")]
    }

    func events(from start: Date, to end: Date) -> [CalendarEventInfo] {
        var result: [CalendarEventInfo] = []
        var day = DayKey(start, calendar: calendar)
        while day.startDate(calendar: calendar) < end {
            result += sample(on: day)
            day = day.adding(days: 1, calendar: calendar)
        }
        return (result + extraEvents).filter { $0.end > start && $0.start < end }
    }

    private func sample(on day: DayKey) -> [CalendarEventInfo] {
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            day.date(atMinute: hour * 60 + minute, calendar: calendar)
        }
        func event(_ title: String, _ calendarID: String, _ start: Date, _ end: Date) -> CalendarEventInfo {
            CalendarEventInfo(id: "\(calendarID)-\(title)-\(day)", calendarID: calendarID, title: title,
                              start: start, end: end, isAllDay: false)
        }
        guard (2...6).contains(weekday) else {
            return [event("Brunch with friends", Self.personalID, at(11), at(12, 30))]
        }
        return [
            event("Stand-up", Self.workID, at(9, 30), at(9, 45)),
            event("Design review", Self.workID, at(11), at(12)),
            event("Focus time", Self.workID, at(13), at(16)),
            event("Gym class", Self.sharedID, at(18), at(19)),
        ]
    }
}
