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
        let runs = next(0...9) < 3
        return HealthDayReading(
            day: day,
            steps: Int(Double(next(5_000...15_000)) * scale),
            swimmingMetres: swims ? next(800...1_600) : 0,
            runningMetres: runs ? next(3_000...8_000) : 0,
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

    func bodySamples(since start: Date) async throws -> [BodySample] {
        // A gentle downward trend from 95.3 kg and 30% body fat, with day-to-day noise.
        var samples: [BodySample] = []
        var day = DayKey(start, calendar: calendar)
        let today = DayKey(now(), calendar: calendar)
        var index = 0
        while day <= today {
            let noise = Double((index * 37) % 9 - 4) / 10
            samples.append(BodySample(date: day.startDate(calendar: calendar).addingTimeInterval(6 * 3_600),
                                      kilograms: 95.3 - Double(index) * 0.05 + noise,
                                      bodyFatPercent: index % 7 == 0 ? 30 - Double(index) * 0.03 : nil))
            day = day.adding(days: 1, calendar: calendar)
            index += 1
        }
        return samples
    }

    func swims(since start: Date) async throws -> [SwimSample] {
        var result: [SwimSample] = []
        var day = DayKey(start, calendar: calendar)
        let today = DayKey(now(), calendar: calendar)
        while day <= today {
            let reading = Self.reading(for: day, partial: false)
            if reading.swimmingMetres > 0 {
                result.append(SwimSample(date: day.startDate(calendar: calendar).addingTimeInterval(18 * 3_600),
                                         minutes: reading.swimmingMetres / 40, metres: reading.swimmingMetres))
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }

    func startObservingChanges(_ onChange: @escaping @Sendable () async -> Void) {}
}
