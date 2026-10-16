import Foundation
import HealthKit

/// Live Apple Health access.
///
/// - Totals use `HKStatisticsCollectionQuery` cumulative sums, which de-duplicate overlapping
///   iPhone and Apple Watch samples the same way the Health app does.
/// - Exercise uses Apple's own Exercise minutes (`appleExerciseTime`). Heart rate is never used as a proxy.
/// - Strength uses only real workout records of strength-training types, de-duplicated by workout UUID.
///   A workout counts towards the day it started.
/// - The app only reads from Health; it never writes.
final class HealthKitService: HealthDataProviding, @unchecked Sendable {
    private let store = HKHealthStore()
    private let calendar: Calendar

    static let strengthWorkoutTypes: Set<HKWorkoutActivityType> = [.traditionalStrengthTraining, .functionalStrengthTraining]

    private let cumulativeTypes: [(HKQuantityTypeIdentifier, HKUnit)] = [
        (.stepCount, .count()),
        (.distanceSwimming, .meter()),
        (.appleExerciseTime, .second()),
        (.activeEnergyBurned, .kilocalorie()),
        (.flightsClimbed, .count()),
    ]

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>(cumulativeTypes.map { HKQuantityType($0.0) as HKObjectType })
        types.insert(HKObjectType.workoutType())
        types.insert(HKObjectType.activitySummaryType())
        return types
    }

    /// Read-only: the app never writes to Apple Health.
    private var shareTypes: Set<HKSampleType> { [] }

    func access() async -> HealthAccess {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        guard let status = try? await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes) else {
            return .notDetermined
        }
        return status == .unnecessary ? .requested : .notDetermined
    }

    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func readings(from start: DayKey, through end: DayKey) async throws -> [DayKey: HealthDayReading] {
        let startDate = start.startDate(calendar: calendar)
        let endDate = end.endDate(calendar: calendar)

        var result: [DayKey: HealthDayReading] = [:]
        var day = start
        while day <= end {
            result[day] = HealthDayReading(day: day)
            day = day.adding(days: 1, calendar: calendar)
        }

        for (identifier, unit) in cumulativeTypes {
            let sums = try await dailySums(identifier, unit: unit, from: startDate, to: endDate)
            for (key, value) in sums where result[key] != nil {
                let whole = Int(value.rounded(.down))
                switch identifier {
                case .stepCount: result[key]?.steps = whole
                case .distanceSwimming: result[key]?.swimmingMetres = whole
                case .appleExerciseTime: result[key]?.exerciseSeconds = whole
                case .activeEnergyBurned: result[key]?.activeKilocalories = whole
                case .flightsClimbed: result[key]?.flightsClimbed = whole
                default: break
                }
            }
        }

        for workout in try await strengthWorkouts(from: startDate, to: endDate) {
            let key = DayKey(workout.startDate, calendar: calendar)
            guard var reading = result[key] else { continue }
            let id = workout.uuid.uuidString
            guard !reading.strengthWorkoutIDs.contains(id) else { continue }
            reading.strengthWorkoutIDs.append(id)
            reading.strengthSeconds += Int(workout.duration.rounded(.down))
            result[key] = reading
        }
        return result
    }

    private func dailySums(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> [DayKey: Double] {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let calendar = calendar
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum,
                anchorDate: calendar.startOfDay(for: start), intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    if let hkError = error as? HKError, hkError.code == .errorNoData {
                        continuation.resume(returning: [:])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                var sums: [DayKey: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let quantity = statistics.sumQuantity() {
                        sums[DayKey(statistics.startDate, calendar: calendar)] = quantity.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: sums)
            }
            store.execute(query)
        }
    }

    private func strengthWorkouts(from start: Date, to end: Date) async throws -> [HKWorkout] {
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let typePredicates = Self.strengthWorkoutTypes.map { HKQuery.predicateForWorkouts(with: $0) }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            datePredicate, NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates),
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store)
    }

    func activityRings(on day: DayKey) async throws -> ActivityRingsSnapshot? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        var components = calendar.dateComponents([.era, .year, .month, .day], from: day.startDate(calendar: calendar))
        components.calendar = calendar
        let predicate = HKQuery.predicateForActivitySummary(with: components)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error {
                    if let hkError = error as? HKError, hkError.code == .errorNoData {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let summary = summaries?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Self.rings(from: summary))
            }
            store.execute(query)
        }
    }

    private static func rings(from summary: HKActivitySummary) -> ActivityRingsSnapshot {
        let moveIsTime = summary.activityMoveMode == .appleMoveTime
        let move = moveIsTime
            ? RingProgress(value: summary.appleMoveTime.doubleValue(for: .minute()),
                           goal: summary.appleMoveTimeGoal.doubleValue(for: .minute()))
            : RingProgress(value: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                           goal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()))
        return ActivityRingsSnapshot(
            move: move,
            exercise: RingProgress(value: summary.appleExerciseTime.doubleValue(for: .minute()),
                                   goal: summary.appleExerciseTimeGoal.doubleValue(for: .minute())),
            stand: RingProgress(value: summary.appleStandHours.doubleValue(for: .count()),
                                goal: summary.appleStandHoursGoal.doubleValue(for: .count())),
            moveUnit: moveIsTime ? "min" : "kcal")
    }

    func startObservingChanges(_ onChange: @escaping @Sendable () async -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var types: [HKSampleType] = cumulativeTypes.map { HKQuantityType($0.0) as HKSampleType }
        types.append(HKObjectType.workoutType())
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task {
                    await onChange()
                    completion()
                }
            }
            store.execute(query)
            // Best effort: iOS decides when, and whether, background updates are delivered.
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }
}
