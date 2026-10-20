import CoreLocation
import Foundation
import MapKit

// Phase 6 services. Each has a live and a stand-in implementation so tests and previews never touch the network.

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

/// A fixed forecast for tests and previews.
struct FixedWeatherService: WeatherProviding {
    var hours: [HourlyWeather]
    func forecast(for coordinate: Coordinate) async throws -> [HourlyWeather] { hours }
}

// MARK: Location (L2: when in use, only with consent)

@MainActor
protocol LocationProviding: AnyObject {
    var isAuthorised: Bool { get }
    func requestPermission()
    func currentLocation() async -> Coordinate?
}

@MainActor
final class CoreLocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: [CheckedContinuation<Coordinate?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorised: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

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

    private func finish(_ coordinate: Coordinate?) {
        let waiting = pending
        pending = []
        waiting.forEach { $0.resume(returning: coordinate) }
    }
}

@MainActor
final class FixedLocationService: LocationProviding {
    var coordinate: Coordinate?
    var isAuthorised: Bool { coordinate != nil }
    init(_ coordinate: Coordinate?) { self.coordinate = coordinate }
    func requestPermission() {}
    func currentLocation() async -> Coordinate? { coordinate }
}

// MARK: Travel (L1)

protocol TravelProviding: Sendable {
    /// Driving minutes between two points, traffic-aware where Apple has data.
    func drivingMinutes(from: Coordinate, to: Coordinate) async throws -> Int
    /// Finds a place by name near a coordinate, e.g. "Nuffield Health Bolton".
    func search(_ query: String, near: Coordinate) async throws -> SavedPlace?
}

struct MapKitTravelService: TravelProviding {
    func drivingMinutes(from: Coordinate, to: Coordinate) async throws -> Int {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)))
        request.transportType = .automobile
        request.departureDate = .now
        let response = try await MKDirections(request: request).calculateETA()
        return max(1, Int((response.expectedTravelTime / 60).rounded(.up)))
    }

    func search(_ query: String, near: Coordinate) async throws -> SavedPlace? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude),
                                            latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        return SavedPlace(name: item.name ?? query, coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}

struct FixedTravelService: TravelProviding {
    var minutes: Int
    var place: SavedPlace?
    func drivingMinutes(from: Coordinate, to: Coordinate) async throws -> Int { minutes }
    func search(_ query: String, near: Coordinate) async throws -> SavedPlace? { place }
}
