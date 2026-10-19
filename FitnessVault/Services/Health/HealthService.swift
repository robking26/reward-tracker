import Foundation

/// One day of activity as read from Apple Health.
struct HealthDayReading: Hashable, Sendable {
    var day: DayKey
    var steps = 0
    var swimmingMetres = 0
    /// Distance recorded in running workouts.
    var runningMetres = 0
    var strengthSeconds = 0
    var strengthWorkoutIDs: [String] = []
    var exerciseSeconds = 0
    var activeKilocalories = 0
    var flightsClimbed = 0
}

/// A body measurement from Apple Health (smart scales or manual entries). Trends, not truths (O-A).
struct BodySample: Hashable, Sendable {
    var date: Date
    var kilograms: Double?
    var bodyFatPercent: Double?
}

/// A swimming workout recorded by the Apple Watch (SW1).
struct SwimSample: Hashable, Sendable {
    var date: Date
    var minutes: Int
    var metres: Int
}

enum HealthAccess: Equatable, Sendable {
    /// HealthKit isn't available on this device.
    case unavailable
    /// The permission sheet hasn't been shown yet.
    case notDetermined
    /// The sheet has been shown. iOS deliberately hides whether reading was allowed,
    /// so missing data may mean access was declined.
    case requested
}

protocol HealthDataProviding: AnyObject, Sendable {
    func access() async -> HealthAccess
    func requestAccess() async throws
    /// Cumulative totals per local calendar day, inclusive of both ends.
    func readings(from start: DayKey, through end: DayKey) async throws -> [DayKey: HealthDayReading]
    /// Today's Move, Exercise and Stand rings, or nil when Apple Health has no summary for the day.
    func activityRings(on day: DayKey) async throws -> ActivityRingsSnapshot?
    /// Calls `onChange` when Health data changes, including in the background where iOS allows it.
    func startObservingChanges(_ onChange: @escaping @Sendable () async -> Void)
    /// Body weight and body-fat readings since `start`, oldest first.
    func bodySamples(since start: Date) async throws -> [BodySample]
    /// Swimming workouts since `start`, oldest first.
    func swims(since start: Date) async throws -> [SwimSample]
}
