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
    /// What the calendar and location say about a day: leave, the first event, out at 8:30 pm. Set by the Day tab.
    @ObservationIgnored var dayInfo: ((DayKey) -> RoutineDayInfo)?

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

    /// True when tonight was switched to away because you weren't home by 8:30 pm.
    func isAutoAway(_ part: RoutinePart, on day: DayKey) -> Bool { log(part, on: day)?.autoAway ?? false }

    func key(_ part: RoutinePart, on day: DayKey) -> RoutineKey {
        RoutineRules.key(for: record(part, on: day), part: part, on: day, calendar: calendar)
    }

    func items(_ part: RoutinePart, on day: DayKey) -> [RoutineItem] { setup.items(key(part, on: day)) }

    func window(_ part: RoutinePart, on day: DayKey) -> DateInterval {
        if let saved = record(part, on: day)?.window { return saved }
        return RoutineRules.window(key(part, on: day), on: day, setup: setup, calendar: calendar)
    }

    /// Ticks needed to count as done.
    func required(_ part: RoutinePart, on day: DayKey) -> Int {
        RoutineRules.required(items(part, on: day).count, share: setup.share)
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
        let next = RoutineRules.toggle(item.id, in: record, items: items(part, on: day), share: setup.share, at: now())
        log.tickedIDs = Array(next.ticked).sorted()
        log.completedAt = next.completedAt
        log.updatedAt = now()
        changed()
    }

    /// Ticks an item if it isn't already, e.g. once its journal entry is written.
    func tick(_ item: RoutineItem, part: RoutinePart, on day: DayKey) {
        guard !(record(part, on: day)?.ticked.contains(item.id) ?? false) else { return }
        toggle(item, part: part, on: day)
    }

    /// Home or away for one routine, until its time to finish. Away routines don't cost anything.
    func setPlace(_ place: RoutinePlace, part: RoutinePart, on day: DayKey) {
        guard !isClosed(part, on: day) else { return }
        let log = ensureLog(part, on: day)
        log.placeSetByUser = true
        log.autoAway = false
        apply(place, to: log, part: part, on: day)
        changed()
    }

    private func apply(_ place: RoutinePlace, to log: RoutineLog, part: RoutinePart, on day: DayKey) {
        log.placeRaw = place.rawValue
        // A different version has different items and times, so both are worked out again.
        schedule(log, part: part, on: day, info: dayInfo?(day) ?? RoutineDayInfo())
        if let record = log.record {
            let items = setup.items(RoutineRules.key(for: record, part: part, on: day, calendar: calendar))
            log.completedAt = RoutineRules.isComplete(record, items: items, share: setup.share) ? now() : nil
        }
        log.updatedAt = now()
    }

    private func schedule(_ log: RoutineLog, part: RoutinePart, on day: DayKey, info: RoutineDayInfo) {
        let place = RoutinePlace(rawValue: log.placeRaw) ?? .home
        let days = RoutineRules.days(for: part, on: day, place: place, info: info, calendar: calendar)
        let key = RoutineKey(part: part, days: days, place: place)
        let window = RoutineRules.window(key, on: day, setup: setup, firstEvent: info.firstEvent, calendar: calendar)
        log.daysRaw = days.rawValue
        log.windowStart = window.start
        log.windowEnd = window.end
    }

    /// Saves today's and tomorrow's versions and times while they're still open: a leave day, an early first event,
    /// and tonight counting as away if you're not home by 8:30 pm. Once a routine closes it never changes.
    func refreshSchedule() {
        guard isSetUp, let dayInfo else { return }
        var changes = false
        for day in [today, today.adding(days: 1, calendar: calendar)] {
            let info = dayInfo(day)
            for part in RoutinePart.allCases where !isClosed(part, on: day) {
                let log = ensureLog(part, on: day)
                let before = [log.daysRaw, log.windowStart?.description, log.windowEnd?.description, log.placeRaw]
                let userChose = log.placeSetByUser ?? false
                if part == .evening && info.outAtHalfEight && !userChose && log.placeRaw == RoutinePlace.home.rawValue {
                    log.autoAway = true
                    apply(.away, to: log, part: part, on: day)
                } else {
                    schedule(log, part: part, on: day, info: info)
                }
                let after = [log.daysRaw, log.windowStart?.description, log.windowEnd?.description, log.placeRaw]
                if before != after { changes = true }
            }
        }
        if changes { changed() }
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
    func save(_ items: [String: [RoutineItem]], times: [String: RoutineTimes], share: Double = 0.8) {
        var next = setup
        next.items = items
        next.times = times
        next.completionShare = share
        if next.penaltyFrom == nil { next.penaltyFrom = today.adding(days: 1, calendar: calendar) }
        setup = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.setupKey) }
        refreshSchedule()
        changed()
    }

    private func changed() {
        try? context.save()
        revision += 1
        scheduleReminders()
        onChange?()
    }

    // MARK: Reminders

    /// A nudge when each routine opens, a warning 30 minutes before a home routine closes, and an 8:30 pm check-in
    /// on home nights, for the next three days.
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
                if setup.times(key(part, on: day)).isAdHoc { continue }
                let window = self.window(part, on: day)
                let count = items(part, on: day).count
                if window.start > now() {
                    plan.append(PlannedNotification(id: "routine.\(day).\(part.rawValue).start", date: window.start,
                                                    body: "\(part.title): \(count) things \(part.purpose.lowercased()).",
                                                    isDiscreet: false))
                }
                guard place(part, on: day) == .home else { continue }
                let warning = window.end.addingTimeInterval(-30 * 60)
                if warning > now() {
                    plan.append(PlannedNotification(id: "routine.\(day).\(part.rawValue).warn", date: warning,
                                                    body: "30 minutes left on your \(part.title.lowercased()). Unfinished, today keeps half its earnings.",
                                                    isDiscreet: false))
                }
                let checkIn = day.date(atMinute: RoutineRules.homeByMinute, calendar: calendar)
                if part == .evening, checkIn > now(), checkIn < window.end {
                    plan.append(PlannedNotification(id: "routine.\(day).evening.out", date: checkIn,
                                                    body: "Not home yet? Open Vaultality so tonight counts as away.",
                                                    isDiscreet: true))
                }
            }
        }
        reminders.replace(with: plan)
    }
}
