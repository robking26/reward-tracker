import EventKit
import Foundation
import Observation
import SwiftData
import WidgetKit

/// Owns everything coaching: today's commitments, routines, reconciliation, the consolidated calendar,
/// the conversation and memory. Shares the SwiftData store with `AppModel`. Every change to a
/// commitment goes through `CommitmentRules` and is logged (E4).
@MainActor
@Observable
final class CoachModel {
    let settingsStore: SettingsStore
    let calendar: Calendar
    let now: () -> Date
    let context: ModelContext
    private let container: ModelContainer
    private let liveCalendar: CalendarProviding
    private let demoCalendar: CalendarProviding
    let defaults: UserDefaults
    let reminders: ReminderScheduling
    /// Apple's on-device model when available; nil means the rule-based coach only (scenario N).
    let languageModel: CoachLanguageModel?
    @ObservationIgnored private var calendarObserver: NSObjectProtocol? = nil
    @ObservationIgnored private var lastWidgetSnapshot: CoachWidgetSnapshot? = nil
    /// The last reminder plan sent to iOS, so unchanged plans aren't rescheduled.
    @ObservationIgnored var lastReminderSignature: String? = nil
    /// Step-by-step start in progress (C3).
    var launch: LaunchState? = nil
    /// True while the on-device model is writing a reply.
    var isThinking = false
    /// The reply being written by the model, so tests (and callers) can wait for it.
    @ObservationIgnored var pendingReply: Task<Void, Never>? = nil

    // MARK: Derived state (read by views)

    private(set) var today: DayKey
    /// Today's commitments, in the order they're shown.
    private(set) var commitments: [Commitment] = []
    /// Earlier commitments waiting for "did you do this?" (D-014).
    private(set) var needsVerification: [Commitment] = []
    private(set) var events: [ClassifiedEvent] = []
    private(set) var windows: [OpportunityWindow] = []
    private(set) var projection: DayProjection
    private(set) var monthFines: Pence = .zero
    private(set) var messages: [CoachMessage] = []
    private(set) var calendarAccess: CalendarAccess = .notDetermined
    private(set) var availableCalendars: [CalendarInfo] = []
    private(set) var workLocation: WorkLocation = .unknown
    private(set) var isOnLeave = false
    private(set) var lastError: String? = nil
    /// A commitment or task waiting for a "where have you got to?" note (C4).
    var awaitingResumeNote: UUID? = nil

    var settings: AppSettings { settingsStore.settings }
    var coach: CoachSettings { settings.coach }
    var calendarProvider: CalendarProviding { settings.demoMode ? demoCalendar : liveCalendar }

    /// Calendar roles in use; demo calendars are labelled automatically.
    var calendarRoles: [String: CalendarRole] {
        settings.demoMode ? coach.calendarRoles.merging(DemoCalendarService.roles) { saved, _ in saved } : coach.calendarRoles
    }

    /// True when calendar access is granted but no calendar is labelled Work (scenario M).
    var hasNoWorkCalendar: Bool {
        calendarAccess == .granted && !calendarRoles.values.contains(.work)
    }

    init(container: ModelContainer,
         settingsStore: SettingsStore,
         liveCalendar: CalendarProviding? = nil,
         demoCalendar: CalendarProviding? = nil,
         defaults: UserDefaults = .standard,
         reminders: ReminderScheduling? = nil,
         languageModel: CoachLanguageModel? = CoachAI.makeDefault(),
         calendar: Calendar = .current,
         now: @escaping () -> Date = { .now }) {
        self.container = container
        context = container.mainContext
        self.settingsStore = settingsStore
        self.liveCalendar = liveCalendar ?? EventKitCalendarService()
        self.demoCalendar = demoCalendar ?? DemoCalendarService(calendar: calendar)
        self.defaults = defaults
        self.reminders = reminders ?? LocalReminderScheduler()
        self.languageModel = languageModel
        self.calendar = calendar
        self.now = now
        let today = DayKey(now(), calendar: calendar)
        self.today = today
        projection = DayProjection(score: DayScore([]), schedule: settingsStore.settings.coach.fineSchedule,
                                   monthToDateFines: .zero, allocation: settingsStore.settings.monthlyAllocation)
    }

    // MARK: Lifecycle

    func start() async {
        seedIfNeeded()
        observeCalendarChanges()
        await refresh()
    }

    /// Rolls the day forward, settles earlier days, creates today's routine commitments and re-reads the calendar.
    func refresh() async {
        today = DayKey(now(), calendar: calendar)
        reconcilePastDays()
        ensureRoutineCommitments(for: today)
        refreshCalendar()
        save()
        reload()
        replanForCalendarChanges()
    }

    private func observeCalendarChanges() {
        guard calendarObserver == nil else { return }
        // Only fires while the app is running; otherwise the calendar is re-read on foreground (S4).
        calendarObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil,
                                                                  queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCalendar()
                self?.reload()
                self?.replanForCalendarChanges()
            }
        }
    }

    // MARK: Calendar

    func requestCalendarAccess() async {
        calendarAccess = await calendarProvider.requestAccess()
        refreshCalendar()
        reload()
    }

    func setRole(_ role: CalendarRole?, for calendarID: String) {
        settingsStore.settings.coach.calendarRoles[calendarID] = role
        refreshCalendar()
        reload()
    }

    func refreshCalendar() {
        calendarAccess = calendarProvider.access
        availableCalendars = calendarProvider.calendars()
        events = classifiedEvents(on: today)
        workLocation = CalendarClassifier.workLocation(from: events)
        isOnLeave = CalendarClassifier.isOnLeave(events)
    }

    func classifiedEvents(on day: DayKey) -> [ClassifiedEvent] {
        let raw = calendarProvider.events(from: day.startDate(calendar: calendar), to: day.endDate(calendar: calendar))
        return CalendarClassifier.classify(raw, roles: calendarRoles)
    }

    var isWorkdayToday: Bool { coach.isWorkday(today, calendar: calendar) && !isOnLeave }

    /// Calendar blocks plus agreed commitments with a time, for the availability engine.
    func busyBlocks(on day: DayKey, events: [ClassifiedEvent], commitments: [Commitment]) -> [BusyBlock] {
        let own = commitments.compactMap { item -> BusyBlock? in
            guard item.state.isOpen, let start = item.scheduledStart, let end = item.scheduledEnd, end > start else { return nil }
            return BusyBlock(interval: DateInterval(start: start, end: end), kind: .coachCommitment, title: item.title)
        }
        return CalendarClassifier.blocks(from: events) + own
    }

    // MARK: Commitments

    /// The one thing to do now (N2): in progress first, then anything due or overdue, then anything with no time.
    var currentAction: Commitment? {
        let open = commitments.filter { $0.state == .approved || $0.state == .inProgress }
        if let active = open.first(where: { $0.state == .inProgress }) { return active }
        let soon = now().addingTimeInterval(30 * 60)
        if let due = open.filter({ ($0.scheduledStart ?? .distantFuture) <= soon })
            .min(by: { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }) {
            return due
        }
        return open.first { $0.scheduledStart == nil }
    }

    /// The next agreed commitment with a time after the current action.
    var nextCommitment: Commitment? {
        let current = currentAction?.id
        return commitments
            .filter { $0.state == .approved && $0.id != current && ($0.scheduledStart ?? .distantPast) > now() }
            .min { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }
    }

    /// Other agreed commitments still due today, at most three (N2).
    var essentialsDue: [Commitment] {
        let excluded = Set([currentAction?.id, nextCommitment?.id].compactMap { $0 })
        return Array(commitments.filter { $0.state.isOpen && !excluded.contains($0.id) }.prefix(3))
    }

    var proposals: [Commitment] { commitments.filter { $0.state == .proposed } }

    /// The next timed calendar event that hasn't finished.
    var upcomingEvent: ClassifiedEvent? {
        events.first { !$0.event.isAllDay && $0.event.end > now() && $0.kind != .allDayInfo }
    }

    /// The next stretch of time worth using, outside protected work time.
    var nextOpportunity: OpportunityWindow? {
        windows.first { $0.kind != .workGap && $0.minutes >= 15 }
    }

    @discardableResult
    func propose(_ title: String, kind: CommitmentKind, start: Date? = nil, durationMinutes: Int = 30,
                 weight: Int? = nil, objective: Objective? = nil, reason: String? = nil) -> Commitment {
        let item = Commitment(day: start.map { DayKey($0, calendar: calendar) } ?? today, title: title, kind: kind,
                              state: .proposed, weight: weight, scheduledStart: start, durationMinutes: durationMinutes,
                              source: .coach, objective: objective, reason: reason)
        context.insert(item)
        save()
        reload()
        return item
    }

    /// Something the user commits to themselves. Agreed immediately, so it counts.
    @discardableResult
    func addCommitment(_ title: String, kind: CommitmentKind, start: Date?, durationMinutes: Int, weight: Int? = nil) -> Commitment {
        let item = Commitment(day: start.map { DayKey($0, calendar: calendar) } ?? today, title: title, kind: kind,
                              state: .approved, weight: weight, scheduledStart: start, durationMinutes: durationMinutes,
                              source: .user)
        context.insert(item)
        context.insert(CommitmentEvent(commitmentID: item.id, from: .proposed, to: .approved, reason: "Added by you", actor: .user))
        save()
        reload()
        return item
    }

    /// Applies one action through the state machine and records why (E4).
    @discardableResult
    func transition(_ item: Commitment, _ action: CommitmentAction, actor: ChangeActor = .user, reason: String? = nil) -> Bool {
        let from = item.state
        do {
            let to = try CommitmentRules.apply(action, to: from)
            item.stateRaw = to.rawValue
            item.updatedAt = now()
            switch action {
            case .approve: item.approvedAt = now()
            case .excuse(let excuse), .rescheduleToAnotherDay(let excuse): item.excuseRaw = excuse.rawValue
            case .verificationExpired: item.assumedMissed = true
            case .correct: item.assumedMissed = false
            default: break
            }
            context.insert(CommitmentEvent(commitmentID: item.id, from: from, to: to, reason: reason ?? describe(action), actor: actor))
            lastError = nil
            if let day = item.dayKey, day < today { recomputeDayRecords(for: day.monthKey) }
            save()
            reload()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Moves a commitment to `start`. Same day is free; another day needs a legitimate reason (D-013).
    @discardableResult
    func reschedule(_ item: Commitment, to start: Date, reason: ExcuseReason? = nil) -> Commitment? {
        let newDay = DayKey(start, calendar: calendar)
        let action: CommitmentAction
        if newDay.description == item.day {
            action = .rescheduleLaterToday
        } else if let reason {
            action = .rescheduleToAnotherDay(reason)
        } else {
            lastError = "Moving this to another day needs a reason."
            return nil
        }
        guard start < newDay.startDate(calendar: calendar).addingTimeInterval(TimeInterval(coach.bedtimeMinute * 60)) else {
            lastError = "That's after your bedtime."
            return nil
        }
        let copy = Commitment(day: newDay, title: item.title, kind: item.kind, state: .approved, weight: item.weight,
                              scheduledStart: start, durationMinutes: item.durationMinutes, source: item.source,
                              routineID: nil, objective: item.objective,
                              reason: "Moved from \(item.scheduledStart?.formatted(date: .omitted, time: .shortened) ?? "earlier")",
                              detail: item.detail)
        guard transition(item, action, reason: "Moved to \(start.formatted(date: .abbreviated, time: .shortened))") else { return nil }
        context.insert(copy)
        context.insert(CommitmentEvent(commitmentID: copy.id, from: .proposed, to: .approved,
                                       reason: "Moved from another time", actor: .user))
        save()
        reload()
        return copy
    }

    func history(for item: Commitment) -> [CommitmentEvent] {
        let id = item.id
        return (try? context.fetch(FetchDescriptor<CommitmentEvent>(predicate: #Predicate { $0.commitmentID == id },
                                                                   sortBy: [SortDescriptor(\.at)]))) ?? []
    }

    // MARK: Routines

    func routines() -> [Routine] {
        (try? context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    /// Agreeing to a routine creates today's commitment only if its time hasn't passed, so enabling one late
    /// in the day can never create a miss.
    func setRoutine(_ routine: Routine, enabled: Bool) {
        routine.isEnabled = enabled
        routine.enabledAt = enabled ? now() : nil
        if enabled { ensureRoutineCommitments(for: today, onlyUpcoming: true) }
        save()
        reload()
    }

    /// Creates each enabled routine's commitment for `day` once.
    func ensureRoutineCommitments(for day: DayKey, onlyUpcoming: Bool = false) {
        let weekday = isoWeekday(day)
        let existing = Set(commitments(on: day).compactMap(\.routineID))
        for routine in routines() where routine.isEnabled && routine.runs(onISOWeekday: weekday) && !existing.contains(routine.id) {
            if let enabledAt = routine.enabledAt, DayKey(enabledAt, calendar: calendar) > day { continue }
            let start = routine.minuteOfDay.map { day.startDate(calendar: calendar).addingTimeInterval(TimeInterval($0 * 60)) }
            if onlyUpcoming, let start, start < now() { continue }
            let item = Commitment(day: day, title: routine.title, kind: routine.kind, state: .approved, weight: routine.weight,
                                  scheduledStart: start, durationMinutes: routine.durationMinutes, source: .routine,
                                  routineID: routine.id, reason: routine.reason)
            context.insert(item)
            context.insert(CommitmentEvent(commitmentID: item.id, from: .proposed, to: .approved,
                                           reason: "Pre-agreed routine", actor: .system))
        }
    }

    // MARK: Reconciliation (A4, D-014)

    /// Closes earlier days: open → pending verification; unanswered by the end of the next day → missed (assumed);
    /// stale suggestions are cancelled; then each finished day gets its score and (simulated) fine.
    func reconcilePastDays() {
        // Routines count every agreed day, even if the app wasn't opened (no loophole), but only for the last week.
        for offset in (1...7).reversed() {
            ensureRoutineCommitments(for: today.adding(days: -offset, calendar: calendar))
        }
        let todayKey = today.description
        let yesterday = today.adding(days: -1, calendar: calendar)
        let past = allCommitments().filter { $0.day < todayKey }
        var months = Set<MonthKey>()
        for item in past {
            guard let day = item.dayKey else { continue }
            switch item.state {
            case .proposed:
                apply(.cancel, to: item, reason: "Suggestion expired")
            case .approved, .inProgress:
                apply(.dayEnded, to: item, reason: "The day ended before this was marked done")
                if day < yesterday { apply(.verificationExpired, to: item, reason: "No answer by the end of the next day") }
            case .pendingVerification where day < yesterday:
                apply(.verificationExpired, to: item, reason: "No answer by the end of the next day")
            default:
                continue
            }
            months.insert(day.monthKey)
        }
        months.insert(today.monthKey)
        for month in months { recomputeDayRecords(for: month) }
    }

    /// System transitions during reconciliation; no reload per item.
    private func apply(_ action: CommitmentAction, to item: Commitment, reason: String) {
        let from = item.state
        guard let to = try? CommitmentRules.apply(action, to: from) else { return }
        item.stateRaw = to.rawValue
        item.updatedAt = now()
        if action == .verificationExpired { item.assumedMissed = true }
        context.insert(CommitmentEvent(commitmentID: item.id, from: from, to: to, reason: reason, actor: .system))
    }

    /// Recalculates every finished day of `month` in date order, so the monthly cap applies in sequence.
    func recomputeDayRecords(for month: MonthKey) {
        let prefix = month.description
        let all = allCommitments().filter { $0.day.hasPrefix(prefix) }
        let byDay = Dictionary(grouping: all, by: \.day)
        var monthToDate = Pence.zero
        for dayString in byDay.keys.sorted() {
            guard let day = DayKey(string: dayString), day < today, let items = byDay[dayString] else { continue }
            let record = dayRecord(day) ?? {
                let created = DayRecord(day: day, isSimulation: coach.finesAreSimulated)
                context.insert(created)
                return created
            }()
            let score = DayScore(items.map(\.scored))
            record.applicableWeight = score.applicableWeight
            record.completedWeight = score.completedWeight
            if !score.isSettled {
                record.scorePercent = score.confirmedPercent
                record.finePence = 0
                record.uncappedFinePence = 0
                record.finalisedAt = nil
                record.explanation = "Waiting for you to confirm what got done."
                continue
            }
            let outcome = DayReconciliation.finalise(items.map(\.scored), schedule: coach.fineSchedule,
                                                     monthToDateFines: monthToDate, allocation: settings.monthlyAllocation)
            record.scorePercent = outcome.scorePercent
            record.finePence = outcome.fine.value
            record.uncappedFinePence = outcome.uncappedFine.value
            record.explanation = outcome.explanation
            record.isSimulation = coach.finesAreSimulated
            if record.finalisedAt == nil { record.finalisedAt = now() }
            monthToDate = monthToDate + outcome.fine
        }
    }

    func dayRecord(_ day: DayKey) -> DayRecord? {
        let key = day.description
        return try? context.fetch(FetchDescriptor<DayRecord>(predicate: #Predicate { $0.day == key })).first
    }

    func dayRecords(in month: MonthKey) -> [DayRecord] {
        let prefix = month.description
        return ((try? context.fetch(FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.day)]))) ?? [])
            .filter { $0.day.hasPrefix(prefix) }
    }

    // MARK: Reload

    func allCommitments() -> [Commitment] {
        (try? context.fetch(FetchDescriptor<Commitment>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func commitments(on day: DayKey) -> [Commitment] {
        let key = day.description
        return (try? context.fetch(FetchDescriptor<Commitment>(predicate: #Predicate { $0.day == key }))) ?? []
    }

    func reload() {
        let items = commitments(on: today)
        commitments = items.sorted { lhs, rhs in
            let l = lhs.scheduledStart ?? .distantFuture, r = rhs.scheduledStart ?? .distantFuture
            return l == r ? lhs.createdAt < rhs.createdAt : l < r
        }
        let todayKey = today.description
        needsVerification = allCommitments()
            .filter { $0.day < todayKey && $0.state == .pendingVerification }
            .sorted { $0.day < $1.day }

        monthFines = dayRecords(in: today.monthKey).filter { $0.finalisedAt != nil }.sum(\.fine)
        projection = DayProjection(score: DayScore(commitments.map(\.scored)), schedule: coach.fineSchedule,
                                   monthToDateFines: monthFines, allocation: settings.monthlyAllocation)
        windows = Availability.windows(on: today, shape: coach.shape(isWorkday: isWorkdayToday),
                                       blocks: busyBlocks(on: today, events: events, commitments: commitments),
                                       notBefore: now(), calendar: calendar)
        messages = (try? context.fetch(FetchDescriptor<CoachMessage>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        publishWidgetSnapshot()
        scheduleReminders()
    }

    /// Commitment kinds that are kept off the Lock Screen by name (WG1).
    static let sensitiveKinds: Set<CommitmentKind> = [.rehab]

    /// Shares the next action and today's count with the widget, refreshing it only when something changed.
    private func publishWidgetSnapshot() {
        let current = currentAction
        let applicable = commitments.filter { $0.state.isApplicable }
        let snapshot = CoachWidgetSnapshot(
            day: today.description,
            nextTitle: current?.title,
            nextSymbol: current?.kind.symbol,
            nextStart: current?.scheduledStart,
            nextIsSensitive: current.map { Self.sensitiveKinds.contains($0.kind) } ?? false,
            nextInProgress: current?.state == .inProgress,
            stillDue: essentialsDue.filter { !Self.sensitiveKinds.contains($0.kind) }.map(\.title),
            done: applicable.filter { $0.state == .completed }.count,
            total: applicable.count,
            updatedAt: now())
        if let lastWidgetSnapshot, lastWidgetSnapshot.hasSameContent(as: snapshot) { return }
        CoachWidgetStore.save(snapshot)
        lastWidgetSnapshot = snapshot
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
    }

    func save() {
        do { try context.save() } catch { lastError = "Couldn't save: \(error.localizedDescription)" }
    }

    // MARK: Helpers

    func isoWeekday(_ day: DayKey) -> Int {
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        return weekday == 1 ? 7 : weekday - 1
    }

    private func describe(_ action: CommitmentAction) -> String {
        switch action {
        case .approve: "Agreed"
        case .cancel: "Cancelled before agreeing"
        case .start: "Started"
        case .complete: "Done"
        case .rescheduleLaterToday: "Moved to later today"
        case .rescheduleToAnotherDay(let reason): "Moved to another day: \(reason.title)"
        case .excuse(let reason): "Excused: \(reason.title)"
        case .dayEnded: "Day ended"
        case .verificationExpired: "No answer"
        case .markMissed: "Missed"
        case .correct(let to): "Corrected to \(to.title.lowercased())"
        }
    }
}
