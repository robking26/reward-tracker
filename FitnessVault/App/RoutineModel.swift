import Foundation
import Observation
import SwiftData

/// Morning and night routines: what's due now, ticking items off, home or away, reminders, and whether a missed
/// home routine halves a day's earnings.
@MainActor
@Observable
final class RoutineModel {
    @ObservationIgnored private let container: ModelContainer
    let context: ModelContext
    let calendar: Calendar
    let now: () -> Date
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let reminders: ReminderScheduling

    private(set) var setup: RoutineSetup
    /// Bumped whenever a record changes, so views and earnings refresh.
    private(set) var revision = 0
    /// Called when something that can change earnings happens (a routine finished, missed, or moved away).
    @ObservationIgnored var onChange: (() -> Void)?

    static let setupKey = "routines.setup"

    init(container: ModelContainer, reminders: ReminderScheduling? = nil, defaults: UserDefaults = .standard,
         calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        self.container = container
        context = container.mainContext
        self.reminders = reminders ?? LocalReminderScheduler(prefix: "routine.")
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        setup = defaults.data(forKey: Self.setupKey).flatMap { try? JSONDecoder().decode(RoutineSetup.self, from: $0) }
            ?? RoutineSetup()
    }

    var today: DayKey { DayKey(now(), calendar: calendar) }
    var isSetUp: Bool { setup.isSetUp }

    // MARK: Records

    func record(_ part: RoutinePart, on day: DayKey) -> RoutineRecord? {
        log(part, on: day)?.record
    }

    private func log(_ part: RoutinePart, on day: DayKey) -> RoutineLog? {
        let id = RoutineLog.id(day: day, part: part)
        var descriptor = FetchDescriptor<RoutineLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func ensureLog(_ part: RoutinePart, on day: DayKey) -> RoutineLog {
        if let existing = log(part, on: day) { return existing }
        let created = RoutineLog(day: day, part: part)
        context.insert(created)
        return created
    }

    func place(_ part: RoutinePart, on day: DayKey) -> RoutinePlace { record(part, on: day)?.place ?? .home }

    func key(_ part: RoutinePart, on day: DayKey) -> RoutineKey {
        RoutineRules.key(part, on: day, place: place(part, on: day), calendar: calendar)
    }

    func items(_ part: RoutinePart, on day: DayKey) -> [RoutineItem] { setup.items(key(part, on: day)) }

    func window(_ part: RoutinePart, on day: DayKey) -> DateInterval {
        RoutineRules.window(key(part, on: day), on: day, setup: setup, calendar: calendar)
    }

    func status(_ part: RoutinePart, on day: DayKey) -> RoutineStatus {
        _ = revision
        return RoutineRules.status(part, on: day, record: record(part, on: day), setup: setup, now: now(), calendar: calendar)
    }

    /// The routine to show now: this morning's until it closes, then tonight's.
    var currentPart: RoutinePart {
        guard isSetUp else { return .morning }
        return now() <= window(.morning, on: today).end ? .morning : .evening
    }

    /// Whether the time to finish has passed, after which nothing about that routine can change.
    func isClosed(_ part: RoutinePart, on day: DayKey) -> Bool { now() > window(part, on: day).end }

    func toggle(_ item: RoutineItem, part: RoutinePart, on day: DayKey) {
        guard !isClosed(part, on: day) else { return }
        let log = ensureLog(part, on: day)
        guard let record = log.record else { return }
        let next = RoutineRules.toggle(item.id, in: record, items: items(part, on: day), at: now())
        log.tickedIDs = Array(next.ticked).sorted()
        log.completedAt = next.completedAt
        log.updatedAt = now()
        changed()
    }

    /// Home or away for one routine, until its time to finish. Away routines don't cost anything.
    func setPlace(_ place: RoutinePlace, part: RoutinePart, on day: DayKey) {
        guard !isClosed(part, on: day) else { return }
        let log = ensureLog(part, on: day)
        guard log.placeRaw != place.rawValue else { return }
        log.placeRaw = place.rawValue
        // A different version has different items, so the finish time is worked out again.
        if let record = log.record {
            let items = setup.items(RoutineRules.key(part, on: day, place: place, calendar: calendar))
            log.completedAt = RoutineRules.isComplete(record, items: items) ? now() : nil
        }
        log.updatedAt = now()
        changed()
    }

    // MARK: Earnings

    /// True when a home routine on `day` was missed, so that day keeps half its earnings.
    func isPenalised(_ day: DayKey) -> Bool {
        var records: [RoutinePart: RoutineRecord] = [:]
        for part in RoutinePart.allCases { records[part] = record(part, on: day) }
        return RoutineRules.isPenalised(day, records: records, setup: setup, now: now(), calendar: calendar)
    }

    // MARK: Setup

    /// Saves the questionnaire. The first time, penalties start tomorrow so today can't be missed retrospectively.
    func save(_ items: [String: [RoutineItem]], times: [String: RoutineTimes]) {
        var next = setup
        next.items = items
        next.times = times
        if next.penaltyFrom == nil { next.penaltyFrom = today.adding(days: 1, calendar: calendar) }
        setup = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.setupKey) }
        changed()
    }

    private func changed() {
        try? context.save()
        revision += 1
        scheduleReminders()
        onChange?()
    }

    // MARK: Reminders

    /// A nudge when each routine opens, and a warning 30 minutes before a home routine closes, for the next three days.
    func scheduleReminders() {
        guard isSetUp else {
            reminders.replace(with: [])
            return
        }
        var plan: [PlannedNotification] = []
        for offset in 0..<3 {
            let day = today.adding(days: offset, calendar: calendar)
            for part in RoutinePart.allCases {
                let status = self.status(part, on: day)
                guard status == .upcoming || status == .open || status == .awayOpen else { continue }
                let window = self.window(part, on: day)
                let count = items(part, on: day).count
                if window.start > now() {
                    plan.append(PlannedNotification(id: "routine.\(day).\(part.rawValue).start", date: window.start,
                                                    body: "\(part.title): \(count) things \(part.purpose.lowercased()).",
                                                    isDiscreet: false))
                }
                let warning = window.end.addingTimeInterval(-30 * 60)
                if place(part, on: day) == .home, warning > now() {
                    plan.append(PlannedNotification(id: "routine.\(day).\(part.rawValue).warn", date: warning,
                                                    body: "30 minutes left on your \(part.title.lowercased()). Unfinished, today keeps half its earnings.",
                                                    isDiscreet: false))
                }
            }
        }
        reminders.replace(with: plan)
    }
}
