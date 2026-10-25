import Foundation

// MARK: Places

struct Coordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    /// About 1 km: enough for a forecast, never a precise address.
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

    /// Bolton town centre: the forecast area until you share a location or save home.
    static let bolton = Coordinate(latitude: 53.58, longitude: -2.43)
}

struct SavedPlace: Codable, Hashable, Sendable {
    var name: String
    var coordinate: Coordinate
}

/// The places the planner drives between. `current` is wherever the phone is right now.
enum PlaceID: String, Codable, CaseIterable, Sendable, Identifiable {
    case home, office, gym, pool, pool2, pool3, aldi, current

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .office: "Office"
        case .gym: "Gym"
        case .pool: "Pool"
        case .pool2: "Pool 2"
        case .pool3: "Pool 3"
        case .aldi: "Aldi"
        case .current: "Where you are"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .office: "building.2.fill"
        case .gym: "dumbbell.fill"
        case .pool, .pool2, .pool3: "figure.pool.swim"
        case .aldi: "cart.fill"
        case .current: "location.fill"
        }
    }

    /// What to search Apple Maps for when picking this place.
    var searchHint: String {
        switch self {
        case .home, .office, .current: "Address or postcode"
        case .gym: "Your gym"
        case .pool, .pool2, .pool3: "Swimming pool"
        case .aldi: "Aldi"
        }
    }

    static let saveable: [PlaceID] = [.home, .office, .gym, .pool, .pool2, .pool3, .aldi]
    static let pools: [PlaceID] = [.pool, .pool2, .pool3]
}

struct PlannerPlaces: Codable, Hashable, Sendable {
    var home: SavedPlace?
    var office: SavedPlace?
    var gym: SavedPlace?
    var pool: SavedPlace?
    var pool2: SavedPlace?
    var pool3: SavedPlace?
    var aldi: SavedPlace?

    /// The pools you've saved.
    var pools: [PlaceID] { PlaceID.pools.filter { self[$0] != nil } }

    /// Two saved places that are really one, like a gym with a pool: within 150 m, or the same name.
    func isSamePlace(_ a: PlaceID, _ b: PlaceID) -> Bool {
        guard let first = self[a], let second = self[b] else { return false }
        return first.name.caseInsensitiveCompare(second.name) == .orderedSame
            || first.coordinate.distance(to: second.coordinate) < 150
    }

    subscript(id: PlaceID) -> SavedPlace? {
        get {
            switch id {
            case .home: home
            case .office: office
            case .gym: gym
            case .pool: pool
            case .pool2: pool2
            case .pool3: pool3
            case .aldi: aldi
            case .current: nil
            }
        }
        set {
            switch id {
            case .home: home = newValue
            case .office: office = newValue
            case .gym: gym = newValue
            case .pool: pool = newValue
            case .pool2: pool2 = newValue
            case .pool3: pool3 = newValue
            case .aldi: aldi = newValue
            case .current: break
            }
        }
    }
}

/// Driving minutes between places, from Apple Maps. Missing pairs fall back to a setting and are marked as estimates.
struct TravelTable: Hashable, Sendable {
    var minutes: [String: Int] = [:]

    static func key(_ from: PlaceID, _ to: PlaceID) -> String { "\(from.rawValue)>\(to.rawValue)" }

    func minutes(from: PlaceID, to: PlaceID) -> Int? {
        if from == to { return 0 }
        return minutes[Self.key(from, to)] ?? minutes[Self.key(to, from)]
    }

    mutating func set(_ value: Int, from: PlaceID, to: PlaceID) {
        minutes[Self.key(from, to)] = value
    }

    /// One-way minutes to plan with: the drive plus 10% and parking, rounded up to 5 minutes.
    static func padded(_ drive: Int) -> Int {
        let value = Double(drive) * 1.1 + 3
        return max(5, Int((value / 5).rounded(.up)) * 5)
    }
}

// MARK: Weather

struct HourlyWeather: Codable, Hashable, Sendable {
    var date: Date
    var temperature: Double
    /// 0–100.
    var precipitationProbability: Int
    /// Millimetres in the hour.
    var precipitation: Double
    var isDaylight: Bool = true

    /// Rain you'd rather not walk or run in.
    var isWet: Bool { precipitationProbability >= 50 || precipitation >= 0.3 }
}

/// Parses Open-Meteo's hourly forecast requested with `timeformat=unixtime`. Free, no key, no account.
enum OpenMeteoParser {
    private struct Response: Decodable {
        struct Hourly: Decodable {
            var time: [Double]
            var temperature_2m: [Double?]
            var precipitation_probability: [Int?]?
            var precipitation: [Double?]?
            var is_day: [Int?]?
        }
        var hourly: Hourly
    }

    static func parse(_ data: Data) throws -> [HourlyWeather] {
        let hourly = try JSONDecoder().decode(Response.self, from: data).hourly
        return hourly.time.indices.compactMap { index -> HourlyWeather? in
            guard index < hourly.temperature_2m.count, let temperature = hourly.temperature_2m[index] else { return nil }
            let probability = value(hourly.precipitation_probability, index) ?? 0
            let rain = value(hourly.precipitation, index) ?? 0
            let day = value(hourly.is_day, index) ?? 1
            return HourlyWeather(date: Date(timeIntervalSince1970: hourly.time[index]), temperature: temperature,
                                 precipitationProbability: probability, precipitation: rain, isDaylight: day == 1)
        }
    }

    private static func value<T>(_ list: [T?]?, _ index: Int) -> T? {
        guard let list, index < list.count else { return nil }
        return list[index]
    }

    static func url(for coordinate: Coordinate) -> URL? {
        let rounded = coordinate.rounded
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", rounded.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", rounded.longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,precipitation,is_day"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "7"),
        ]
        return components?.url
    }
}

enum WeatherAdvisor {
    /// Forecast hours overlapping `interval`.
    static func hours(during interval: DateInterval, in forecast: [HourlyWeather]) -> [HourlyWeather] {
        forecast.filter { hour in
            let slot = DateInterval(start: hour.date, duration: 3600)
            return (slot.intersection(with: interval)?.duration ?? 0) > 0
        }
    }

    /// True when the forecast covers the interval and it's dry and light throughout; nil when there's no forecast.
    static func isGoodOutside(_ interval: DateInterval, forecast: [HourlyWeather]) -> Bool? {
        let covered = hours(during: interval, in: forecast)
        guard !covered.isEmpty else { return nil }
        return covered.allSatisfy { !$0.isWet && $0.isDaylight }
    }

    /// "Dry, 9–14°", "Rain likely from 3 pm, 11°", "Wet early, drier from 1 pm, 10°". Daytime only (7 am–9 pm).
    static func summary(for day: DayKey, forecast: [HourlyWeather], calendar: Calendar) -> String? {
        let daytime = DateInterval(start: day.date(atMinute: 7 * 60, calendar: calendar),
                                   end: day.date(atMinute: 21 * 60, calendar: calendar))
        let slots = hours(during: daytime, in: forecast).sorted { $0.date < $1.date }
        guard !slots.isEmpty else { return nil }
        let low = Int(slots.map(\.temperature).min()?.rounded() ?? 0)
        let high = Int(slots.map(\.temperature).max()?.rounded() ?? 0)
        let temperatures = low == high ? "\(high)°" : "\(low)–\(high)°"
        let wet = slots.map(\.isWet)
        if !wet.contains(true) { return "Dry, \(temperatures)" }
        if !wet.contains(false) { return "Wet all day, \(temperatures)" }
        if let firstWet = wet.firstIndex(of: true), firstWet > 0, !wet[firstWet...].contains(false) {
            return "Rain likely from \(PlannerFormat.time(slots[firstWet].date, calendar)), \(temperatures)"
        }
        if wet.first == true, let firstDry = wet.firstIndex(of: false), !wet[firstDry...].contains(true) {
            return "Wet early, drier from \(PlannerFormat.time(slots[firstDry].date, calendar)), \(temperatures)"
        }
        return "Showers on and off, \(temperatures)"
    }

    static func symbol(for summary: String?) -> String {
        guard let summary else { return "cloud" }
        if summary.hasPrefix("Dry") { return "sun.max.fill" }
        if summary.hasPrefix("Wet all") { return "cloud.rain.fill" }
        return "cloud.sun.rain.fill"
    }
}

enum PlannerFormat {
    static func time(_ date: Date, _ calendar: Calendar) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    static func range(_ start: Date, _ end: Date, _ calendar: Calendar) -> String {
        "\(time(start, calendar))–\(time(end, calendar))"
    }

    static func minutes(_ value: Int) -> String {
        if value < 60 { return "\(value) min" }
        let hours = value / 60, rest = value % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
