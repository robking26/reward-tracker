import Foundation

// Phase 6 context: weather, places, travel and gym busyness. Pure and deterministic; services feed it data.

// MARK: Weather

struct HourlyWeather: Codable, Hashable, Sendable {
    var date: Date
    var temperature: Double
    /// 0–100.
    var precipitationProbability: Int
    /// Millimetres in the hour.
    var precipitation: Double

    /// Rain the user would rather not walk in (K2).
    var isWet: Bool { precipitationProbability >= 50 || precipitation >= 0.3 }
}

/// Parses Open-Meteo's hourly forecast requested with `timeformat=unixtime`.
enum OpenMeteoParser {
    private struct Response: Decodable {
        struct Hourly: Decodable {
            var time: [Double]
            var temperature_2m: [Double?]
            var precipitation_probability: [Int?]?
            var precipitation: [Double?]?
        }
        var hourly: Hourly
    }

    static func parse(_ data: Data) throws -> [HourlyWeather] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let hourly = response.hourly
        return hourly.time.indices.compactMap { index in
            guard index < hourly.temperature_2m.count, let temperature = hourly.temperature_2m[index] else { return nil }
            let probability = hourly.precipitation_probability.flatMap { index < $0.count ? $0[index] : nil } ?? 0
            let rain = hourly.precipitation.flatMap { index < $0.count ? $0[index] : nil } ?? 0
            return HourlyWeather(date: Date(timeIntervalSince1970: hourly.time[index]), temperature: temperature,
                                 precipitationProbability: probability, precipitation: rain)
        }
    }

    static func url(for coordinate: Coordinate) -> URL? {
        let rounded = coordinate.rounded
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", rounded.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", rounded.longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,precipitation"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "3"),
        ]
        return components?.url
    }
}

enum WeatherAdvisor {
    /// Forecast hours overlapping `interval`. Empty when there's no forecast for that time.
    static func hours(during interval: DateInterval, in forecast: [HourlyWeather]) -> [HourlyWeather] {
        forecast.filter { hour in
            let slot = DateInterval(start: hour.date, duration: 3600)
            return slot.intersection(with: interval).map { $0.duration > 0 } ?? false
        }
    }

    /// True or false when the forecast covers the interval; nil when it doesn't (never guessed).
    static func isDry(_ interval: DateInterval, forecast: [HourlyWeather]) -> Bool? {
        let covered = hours(during: interval, in: forecast)
        guard !covered.isEmpty else { return nil }
        return !covered.contains(where: \.isWet)
    }

    /// The first start (on a 15-minute grid) inside `windows` where a walk of `minutes` stays dry.
    static func firstDryStart(in windows: [OpportunityWindow], minutes: Int, forecast: [HourlyWeather],
                              notBefore: Date) -> (window: OpportunityWindow, start: Date)? {
        let length = TimeInterval(minutes * 60)
        for window in windows {
            var start = max(window.interval.start, notBefore)
            while start.addingTimeInterval(length) <= window.interval.end {
                if isDry(DateInterval(start: start, duration: length), forecast: forecast) == true {
                    return (window, start)
                }
                start = start.addingTimeInterval(15 * 60)
            }
        }
        return nil
    }

    /// "Dry, 9–14°", "Rain likely from 3 pm, 11°", "Wet this morning, drier from 1 pm". Daytime only (7am–9pm).
    static func summary(for day: DayKey, forecast: [HourlyWeather], calendar: Calendar) -> String? {
        let start = day.startDate(calendar: calendar).addingTimeInterval(7 * 3600)
        let daytime = hours(during: DateInterval(start: start, duration: 14 * 3600), in: forecast).sorted { $0.date < $1.date }
        guard !daytime.isEmpty else { return nil }
        let low = Int(daytime.map(\.temperature).min()?.rounded() ?? 0)
        let high = Int(daytime.map(\.temperature).max()?.rounded() ?? 0)
        let temperatures = low == high ? "\(high)°" : "\(low)–\(high)°"
        func time(_ date: Date) -> String {
            var style = Date.FormatStyle(date: .omitted, time: .shortened)
            style.timeZone = calendar.timeZone
            return date.formatted(style)
        }
        let wet = daytime.map(\.isWet)
        if !wet.contains(true) { return "Dry, \(temperatures)" }
        if !wet.contains(false) { return "Wet all day, \(temperatures)" }
        if let firstWet = wet.firstIndex(of: true), firstWet > 0, !wet[firstWet...].contains(false) {
            return "Rain likely from \(time(daytime[firstWet].date)), \(temperatures)"
        }
        if wet.first == true, let firstDry = wet.firstIndex(of: false), !wet[firstDry...].contains(true) {
            return "Wet early, drier from \(time(daytime[firstDry].date)), \(temperatures)"
        }
        return "Showers on and off, \(temperatures)"
    }
}

// MARK: Places and travel (L1)

struct Coordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    /// About 1 km: enough for weather, never a precise address (privacy).
    var rounded: Coordinate {
        Coordinate(latitude: (latitude * 100).rounded() / 100, longitude: (longitude * 100).rounded() / 100)
    }

    /// Great-circle distance in metres.
    func distance(to other: Coordinate) -> Double {
        let radius = 6_371_000.0
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Bolton town centre: the default weather area until the user shares a location.
    static let bolton = Coordinate(latitude: 53.58, longitude: -2.43)
}

struct SavedPlace: Codable, Hashable, Sendable {
    var name: String
    var coordinate: Coordinate
}

struct SavedPlaces: Codable, Hashable, Sendable {
    var home: SavedPlace?
    var office: SavedPlace?
    var gym: SavedPlace?
}

enum PlaceMode {
    static let radiusMetres = 300.0

    /// Home or office from where the phone is, when the user allowed location and saved those places.
    static func infer(current: Coordinate?, places: SavedPlaces) -> WorkLocation? {
        guard let current else { return nil }
        if let home = places.home, current.distance(to: home.coordinate) <= radiusMetres { return .home }
        if let office = places.office, current.distance(to: office.coordinate) <= radiusMetres { return .office }
        return nil
    }

    /// The day's mode: the user's own choice wins, then the calendar, then where the phone is.
    static func resolve(override: WorkLocation?, calendar: WorkLocation, location: WorkLocation?) -> WorkLocation {
        if let override, override != .unknown { return override }
        if calendar != .unknown { return calendar }
        return location ?? .unknown
    }
}

enum TravelSource: String, Codable, Sendable {
    /// Apple Maps journey estimate, traffic-aware where Apple has it.
    case live
    /// The user's own setting.
    case setting
}

struct TravelEstimate: Codable, Hashable, Sendable {
    var minutes: Int
    var source: TravelSource
    var updatedAt: Date
}

enum TravelPlanner {
    /// A live estimate counts for two hours; after that the setting is used.
    static let freshness: TimeInterval = 2 * 3600

    /// One-way gym travel to plan with: a fresh live estimate plus 10% and parking, rounded up to 5 minutes.
    static func gymMinutes(live: TravelEstimate?, setting: Int, now: Date) -> (minutes: Int, source: TravelSource) {
        guard let live, live.source == .live, now.timeIntervalSince(live.updatedAt) <= freshness else {
            return (setting, .setting)
        }
        let padded = Double(live.minutes) * 1.1 + 3
        return (max(5, Int((padded / 5).rounded(.up)) * 5), .live)
    }

    /// When to leave for something that starts at `start`.
    static func leaveBy(_ start: Date, travelMinutes: Int, preparationMinutes: Int = 10) -> Date {
        start.addingTimeInterval(-TimeInterval((travelMinutes + preparationMinutes) * 60))
    }
}

// MARK: Gym busyness (L3): only ever from the user's own reports

enum BusynessLevel: String, Codable, Sendable, CaseIterable {
    case quiet, normal, busy

    var score: Double {
        switch self {
        case .quiet: 0
        case .normal: 1
        case .busy: 2
        }
    }
}

struct BusynessReport: Hashable, Sendable {
    var date: Date
    var level: BusynessLevel
}

struct BusynessEstimate: Hashable, Sendable {
    var level: BusynessLevel
    var reports: Int

    /// Always says where it comes from; never presented as live occupancy.
    var label: String {
        let source = "from \(reports) of your visits"
        switch level {
        case .quiet: return "Usually quiet then (\(source))"
        case .normal: return "Usually steady then (\(source))"
        case .busy: return "Usually busy then (\(source))"
        }
    }
}

enum GymBusynessEstimator {
    static let minimumReports = 2

    /// Weekday or weekend, within an hour either side. Nil until there are enough reports.
    static func estimate(at date: Date, reports: [BusynessReport], calendar: Calendar) -> BusynessEstimate? {
        let weekend = isWeekend(date, calendar: calendar)
        let hour = calendar.component(.hour, from: date)
        let matching = reports.filter { report in
            isWeekend(report.date, calendar: calendar) == weekend && abs(calendar.component(.hour, from: report.date) - hour) <= 1
        }
        guard matching.count >= minimumReports else { return nil }
        let average = matching.map(\.level.score).reduce(0, +) / Double(matching.count)
        let level: BusynessLevel = average >= 1.5 ? .busy : average <= 0.5 ? .quiet : .normal
        return BusynessEstimate(level: level, reports: matching.count)
    }

    private static func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }
}
