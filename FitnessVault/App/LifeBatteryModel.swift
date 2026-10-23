import Foundation
import Observation

/// The year's battery: when it started, each day's step target as it stood that day, and the latest result.
@MainActor
@Observable
final class LifeBatteryModel {
    @ObservationIgnored private let defaults: UserDefaults
    let calendar: Calendar
    let now: () -> Date

    private(set) var start: DayKey
    private(set) var result: BatteryResult = .empty
    /// The Gym tab's walking target for each day, recorded on the day, so a later change never rewrites history.
    @ObservationIgnored private var stepTargets: [String: Int]

    static let startKey = "battery.start"
    static let targetsKey = "battery.stepTargets"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        let today = DayKey(now(), calendar: calendar)
        if let saved = defaults.string(forKey: Self.startKey).flatMap(DayKey.init(string:)) {
            start = saved
        } else {
            start = today
            defaults.set(today.description, forKey: Self.startKey)
        }
        stepTargets = (defaults.dictionary(forKey: Self.targetsKey) as? [String: Int]) ?? [:]
    }

    var today: DayKey { DayKey(now(), calendar: calendar) }
    /// A year from the start.
    var end: DayKey { start.adding(days: 365, calendar: calendar) }
    var daysLeft: Int { max(0, LifeBattery.daysBetween(today, end, calendar: calendar)) }
    var projection: Double? { LifeBattery.projection(result, today: today, end: end, calendar: calendar) }
    var thisWeek: Double { LifeBattery.change(result, since: DayPlanner.monday(of: today, calendar)) }

    /// Percent a week still needed to reach 100% by the end.
    var neededPerWeek: Double {
        let weeks = max(1, Double(daysLeft) / 7)
        return max(0, (100 - result.percent) / weeks)
    }

    /// Rebuilds the battery from the Gym tab's sessions and Apple Health.
    func refresh(model: AppModel, training: TrainingModel, gymPerWeek: Int) {
        // Today's walking target, saved for today.
        let recent = (0..<14).reversed().map { model.today.adding(days: -$0, calendar: calendar) }
        let target = training.stepTarget(recentSteps: recent.map { model.metrics(for: $0).steps })
        if stepTargets[today.description] != target {
            stepTargets[today.description] = target
            defaults.set(stepTargets, forKey: Self.targetsKey)
        }

        let sessions = Set(training.sessions().filter { !$0.isRehabOnly && $0.endedAt != nil }.map(\.day))
        var days: [DayKey: BatteryDay] = [:]
        var lastTarget: Int?
        var day = start
        while day <= today {
            let metrics = model.metrics(for: day)
            // A day without its own record uses the most recent target before it.
            lastTarget = stepTargets[day.description] ?? lastTarget
            days[day] = BatteryDay(gym: sessions.contains(day.description) || metrics.strengthSeconds >= 20 * 60,
                                   swim: metrics.swimmingMetres > 0, run: metrics.runningMetres > 0,
                                   steps: metrics.steps, stepTarget: lastTarget ?? target)
            day = day.adding(days: 1, calendar: calendar)
        }
        result = LifeBattery.compute(start: start, today: today, days: days, gymPerWeek: gymPerWeek, calendar: calendar)
        PlannerWidgetPublisher.publishBattery(self)
    }
}
