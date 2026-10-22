import CoreLocation
import EventKit
import Foundation
import MapKit

// The Day tab's services. Each has a live and a stand-in version so tests, previews and demo mode never touch
// EventKit, location or the network.

// MARK: Calendars

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

@MainActor
protocol CalendarProviding: AnyObject {
    var access: CalendarAccess { get }
    func requestAccess() async -> CalendarAccess
    func calendars() -> [CalendarInfo]
    func events(from start: Date, to end: Date) -> [CalendarEventInfo]
    /// Adds an event to one of your own calendars. Never changes or deletes anything else.
    func add(title: String, start: Date, end: Date, location: String?, notes: String, calendarIDs: [String]) throws
}

/// EventKit, on device. Becky's calendar shows here once she shares it with your iCloud account, and Outlook once the
/// work account is added in Settings › Calendar › Accounts.
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
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source?.title ?? "",
                                allowsAdding: $0.allowsContentModifications) }
            .sorted { lhs, rhs in
                lhs.sourceTitle == rhs.sourceTitle ? lhs.title < rhs.title : lhs.sourceTitle < rhs.sourceTitle
            }
    }

    func events(from start: Date, to end: Date) -> [CalendarEventInfo] {
        guard access == .granted, end > start else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            // Bound through optionals so this compiles whether the SDK marks these as optional or not.
            let startValue: Date? = event.startDate, endValue: Date? = event.endDate
            let calendarValue: EKCalendar? = event.calendar, titleValue: String? = event.title
            guard let eventStart = startValue, let eventEnd = endValue, let calendar = calendarValue else { return nil }
            let item = event.calendarItemIdentifier
            let series: String? = event.calendarItemExternalIdentifier
            // Repeating occurrences share an identifier, so the start time keeps each one unique.
            return CalendarEventInfo(id: "\(item)@\(Int(eventStart.timeIntervalSince1970))", seriesID: series ?? item,
                                     calendarID: calendar.calendarIdentifier, title: titleValue ?? "Busy",
                                     start: eventStart, end: eventEnd, isAllDay: event.isAllDay,
                                     showsAsFree: event.availability == .free, location: event.location, notes: event.notes)
        }
    }

    func add(title: String, start: Date, end: Date, location: String?, notes: String, calendarIDs: [String]) throws {
        let own = calendarIDs.compactMap { store.calendar(withIdentifier: $0) }.filter(\.allowsContentModifications)
        let fallback: EKCalendar? = store.defaultCalendarForNewEvents
        let target = own.first { $0.calendarIdentifier == fallback?.calendarIdentifier } ?? own.first
        guard let target else { throw PlannerError.noCalendar }
        let event = EKEvent(eventStore: store)
        event.calendar = target
        event.title = title
        event.startDate = start
        event.endDate = end
        event.location = location
        event.notes = notes
        try store.save(event, span: .thisEvent)
    }
}

enum PlannerError: LocalizedError {
    case noCalendar

    var errorDescription: String? {
        switch self {
        case .noCalendar: "Label one of your own calendars as \"Mine\" in Day settings first."
        }
    }
}

/// A sample week for demo mode, previews and screenshots: Outlook with office and home focus days, your own plans,
/// and Becky's calendar with one shared event, one not, and one still to confirm.
@MainActor
final class DemoCalendarService: CalendarProviding {
    static let workID = "demo-work"
    static let mineID = "demo-mine"
    static let beckyID = "demo-becky"
    static let roles: [String: CalendarRole] = [workID: .work, mineID: .mine, beckyID: .becky]

    var calendar: Calendar
    var added: [CalendarEventInfo] = []

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    var access: CalendarAccess { .granted }
    func requestAccess() async -> CalendarAccess { .granted }

    func calendars() -> [CalendarInfo] {
        [CalendarInfo(id: Self.workID, title: "Calendar", sourceTitle: "Outlook (demo)"),
         CalendarInfo(id: Self.mineID, title: "Home", sourceTitle: "iCloud (demo)", allowsAdding: true),
         CalendarInfo(id: Self.beckyID, title: "Becky", sourceTitle: "iCloud (demo)")]
    }

    func events(from start: Date, to end: Date) -> [CalendarEventInfo] {
        var result: [CalendarEventInfo] = []
        var day = DayKey(start, calendar: calendar)
        while day.startDate(calendar: calendar) < end {
            result += sample(on: day)
            day = day.adding(days: 1, calendar: calendar)
        }
        return (result + added).filter { $0.end > start && $0.start < end }
    }

    func add(title: String, start: Date, end: Date, location: String?, notes: String, calendarIDs: [String]) throws {
        let id = "added-\(added.count)"
        added.append(CalendarEventInfo(id: id, seriesID: id, calendarID: Self.mineID, title: title, start: start, end: end,
                                       isAllDay: false, location: location, notes: notes))
    }

    private func sample(on day: DayKey) -> [CalendarEventInfo] {
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        func at(_ hour: Int, _ minute: Int = 0) -> Date { day.date(atMinute: hour * 60 + minute, calendar: calendar) }
        func event(_ title: String, _ calendarID: String, _ start: Date, _ end: Date, series: String? = nil) -> CalendarEventInfo {
            CalendarEventInfo(id: "\(calendarID)-\(title)-\(day)", seriesID: series ?? "\(calendarID)-\(title)-\(day)",
                              calendarID: calendarID, title: title, start: start, end: end, isAllDay: false)
        }
        switch weekday {
        case 1:
            return [event("Sunday lunch at Mum's", Self.beckyID, at(13), at(15, 30), series: "becky-lunch")]
        case 7:
            return [event("Parkrun", Self.beckyID, at(9), at(10), series: "becky-parkrun"),
                    event("Haircut", Self.mineID, at(11), at(11, 45))]
        default:
            let office = weekday == 3 || weekday == 5
            var list = [
                event(office ? "Office focus" : "Home focus", Self.workID, at(9), at(9, 30)),
                event("Stand-up", Self.workID, at(9, 30), at(9, 45), series: "standup"),
                event("Design review", Self.workID, at(11), at(12)),
                event("Pilates", Self.beckyID, at(18), at(19), series: "becky-pilates"),
            ]
            if weekday == 4 { list.append(event("Dinner with Sam and Jo", Self.beckyID, at(19, 30), at(22), series: "becky-dinner")) }
            if weekday == 6 { list.append(event("Dentist", Self.mineID, at(16), at(16, 45))) }
            return list
        }
    }
}

// MARK: Weather

protocol WeatherProviding: Sendable {
    func forecast(for coordinate: Coordinate) async throws -> [HourlyWeather]
}

/// Open-Meteo: free, no key, no account. Only a coordinate rounded to about 1 km is sent.
struct OpenMeteoWeatherService: WeatherProviding {
    func forecast(for coordinate: Coordinate) async throws -> [HourlyWeather] {
        guard let url = OpenMeteoParser.url(for: coordinate) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try OpenMeteoParser.parse(data)
    }
}

struct FixedWeatherService: WeatherProviding {
    var hours: [HourlyWeather]
    func forecast(for coordinate: Coordinate) async throws -> [HourlyWeather] { hours }
}

// MARK: Location (when in use, only with your permission)

@MainActor
protocol LocationProviding: AnyObject {
    var isAuthorised: Bool { get }
    var canAsk: Bool { get }
    func requestPermission()
    func currentLocation() async -> Coordinate?
}

@MainActor
final class CoreLocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: [CheckedContinuation<Coordinate?, Never>] = []
    var onChange: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorised: Bool { [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) }
    var canAsk: Bool { manager.authorizationStatus == .notDetermined }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func currentLocation() async -> Coordinate? {
        guard isAuthorised else { return nil }
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
            if pending.count == 1 { manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        Task { @MainActor in self.finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.onChange?() }
    }

    private func finish(_ coordinate: Coordinate?) {
        let waiting = pending
        pending = []
        waiting.forEach { $0.resume(returning: coordinate) }
    }
}

@MainActor
final class FixedLocationService: LocationProviding {
    var coordinate: Coordinate?
    init(_ coordinate: Coordinate?) { self.coordinate = coordinate }
    var isAuthorised: Bool { coordinate != nil }
    var canAsk: Bool { false }
    func requestPermission() {}
    func currentLocation() async -> Coordinate? { coordinate }
}

// MARK: Travel

protocol TravelProviding: Sendable {
    /// Driving minutes, traffic-aware where Apple has data, leaving at `departure`.
    func drivingMinutes(from: Coordinate, to: Coordinate, departure: Date) async throws -> Int
    /// Places matching a search near a coordinate, e.g. "Aldi" or a postcode.
    func search(_ query: String, near: Coordinate) async throws -> [PlaceResult]
}

struct PlaceResult: Hashable, Sendable, Identifiable {
    var place: SavedPlace
    var address: String

    var id: String { "\(place.name)|\(place.coordinate.latitude)|\(place.coordinate.longitude)" }
}

/// Apple Maps journey times. Google's Directions API needs a permanent key in the app, which isn't allowed here, so
/// Google Maps is used for the drive itself (the Directions button) and Apple Maps for the planning estimate.
struct MapKitTravelService: TravelProviding {
    func drivingMinutes(from: Coordinate, to: Coordinate, departure: Date) async throws -> Int {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.location))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.location))
        request.transportType = .automobile
        request.departureDate = max(departure, .now)
        let response = try await MKDirections(request: request).calculateETA()
        return max(1, Int((response.expectedTravelTime / 60).rounded(.up)))
    }

    func search(_ query: String, near: Coordinate) async throws -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: near.location, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(8).map { item in
            let coordinate = item.placemark.coordinate
            let address: String? = item.placemark.title
            return PlaceResult(place: SavedPlace(name: item.name ?? query,
                                                 coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)),
                               address: address ?? "")
        }
    }
}

struct FixedTravelService: TravelProviding {
    var minutes: Int
    var results: [PlaceResult] = []
    func drivingMinutes(from: Coordinate, to: Coordinate, departure: Date) async throws -> Int { minutes }
    func search(_ query: String, near: Coordinate) async throws -> [PlaceResult] { results }
}

extension Coordinate {
    var location: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Google Maps directions, driving. Opens the Google Maps app if it's installed, otherwise the website.
enum GoogleMapsLink {
    static func directions(to place: SavedPlace) -> URL? {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(place.coordinate.latitude),\(place.coordinate.longitude)"),
            URLQueryItem(name: "travelmode", value: "driving"),
        ]
        return components?.url
    }
}
