import Foundation

/// One day of activity as read from Apple Health.
struct HealthDayReading: Hashable, Sendable {
    var day: DayKey
    var steps = 0
    var swimmingMetres = 0
    var strengthSeconds = 0
    var strengthWorkoutIDs: [String] = []
    var exerciseSeconds = 0
    var activeKilocalories = 0
    var flightsClimbed = 0
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
    /// Saves a confirmed meal as a food correlation. Returns false if permission was declined.
    func saveMeal(id: UUID, estimate: NutritionEstimate, date: Date) async throws -> Bool
    func deleteMeal(id: UUID) async throws
    /// Calls `onChange` when Health data changes, including in the background where iOS allows it.
    func startObservingChanges(_ onChange: @escaping @Sendable () async -> Void)
}
