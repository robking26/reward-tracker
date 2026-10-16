import Foundation

/// Generates plausible, deterministic activity for previews and demo mode.
/// Demo mode always pairs this with the mock bank, so fabricated activity can never move real money.
final class MockHealthService: HealthDataProviding, @unchecked Sendable {
    private let calendar: Calendar
    private let now: () -> Date

    init(calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        self.calendar = calendar
        self.now = now
    }

    func access() async -> HealthAccess { .requested }
    func requestAccess() async throws {}

    func readings(from start: DayKey, through end: DayKey) async throws -> [DayKey: HealthDayReading] {
        try await Task.sleep(for: .milliseconds(400))
        var result: [DayKey: HealthDayReading] = [:]
        let today = DayKey(now(), calendar: calendar)
        var day = start
        while day <= end {
            result[day] = Self.reading(for: day, partial: day == today)
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }

    static func reading(for day: DayKey, partial: Bool) -> HealthDayReading {
        var seed = UInt64(day.year * 10_000 + day.month * 100 + day.day) &* 6_364_136_223_846_793_005 &+ 1
        func next(_ range: ClosedRange<Int>) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return range.lowerBound + Int((seed >> 33) % UInt64(range.count))
        }
        let scale = partial ? 0.6 : 1
        let lifts = next(0...9) < 4
        let swims = next(0...9) < 2
        return HealthDayReading(
            day: day,
            steps: Int(Double(next(5_000...15_000)) * scale),
            swimmingMetres: swims ? next(800...1_600) : 0,
            strengthSeconds: lifts ? next(35...60) * 60 : 0,
            strengthWorkoutIDs: lifts ? ["demo-\(day)"] : [],
            exerciseSeconds: Int(Double(next(15...70) * 60) * scale),
            activeKilocalories: Int(Double(next(300...800)) * scale),
            flightsClimbed: next(2...18))
    }

    func activityRings(on day: DayKey) async throws -> ActivityRingsSnapshot? {
        let reading = Self.reading(for: day, partial: day == DayKey(now(), calendar: calendar))
        return ActivityRingsSnapshot(
            move: RingProgress(value: Double(reading.activeKilocalories), goal: 600),
            exercise: RingProgress(value: Double(reading.exerciseSeconds / 60), goal: 30),
            stand: RingProgress(value: Double(min(12, reading.flightsClimbed)), goal: 12),
            moveUnit: "kcal")
    }

    func startObservingChanges(_ onChange: @escaping @Sendable () async -> Void) {}
}
