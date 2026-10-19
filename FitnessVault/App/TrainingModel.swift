import Foundation
import Observation
import SwiftData
import SwiftUI

/// Starts, runs and finishes gym sessions. Progression, knee rules and the programme are pure domain code;
/// this model persists what happened and tells the coach when an agreed workout is done.
@MainActor
@Observable
final class TrainingModel {
    let context: ModelContext
    let calendar: Calendar
    let now: () -> Date
    @ObservationIgnored private weak var coach: CoachModel?
    @ObservationIgnored private let restAlerts: RestAlerting

    private(set) var session: WorkoutSession? = nil
    private(set) var plan: WorkoutPlan? = nil
    private(set) var restEndsAt: Date? = nil
    private(set) var lastAdvice: String? = nil
    /// The commitment a workout is being set up for, before it starts.
    var pendingCommitmentID: UUID? = nil

    init(container: ModelContainer, coach: CoachModel?, restAlerts: RestAlerting? = nil,
         calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        context = container.mainContext
        self.coach = coach
        self.restAlerts = restAlerts ?? LocalRestAlerts()
        self.calendar = calendar
        self.now = now
        restoreActiveSession()
    }

    // MARK: State

    var isActive: Bool { session != nil }
    var currentIndex: Int { session?.currentIndex ?? 0 }
    var awaitingReady: Bool { session?.awaitingReady ?? false }
    var current: PlannedExercise? {
        guard let plan, plan.exercises.indices.contains(currentIndex) else { return nil }
        return plan.exercises[currentIndex]
    }
    var upNext: PlannedExercise? {
        guard let plan, plan.exercises.indices.contains(currentIndex + 1) else { return nil }
        return plan.exercises[currentIndex + 1]
    }
    var isLastExercise: Bool { upNext == nil }

    /// Working sets logged for the current exercise.
    var setsDone: Int {
        guard let session, let current else { return 0 }
        return logs(for: session).filter { $0.exerciseID == current.exerciseID && !$0.isWarmUp }.count
    }

    var needsWarmUp: Bool {
        guard let session, let current else { return false }
        return current.warmUpKg != nil && !session.warmUpDone && setsDone == 0
    }

    var isResting: Bool { (restEndsAt ?? .distantPast) > now() }

    // MARK: Planning

    var kneeStatus: KneeStatus { KneeRules.status(symptomLogs().map(\.entry), now: now()) }

    /// Upper or lower from the commitment's title, otherwise the opposite of the last session; A/B alternate.
    func suggestedFocus(for title: String?) -> (TrainingFocus, Int) {
        let finished = sessions().filter { !$0.isActive }
        let focus: TrainingFocus
        if let title, title.localizedCaseInsensitiveContains("lower") {
            focus = .lower
        } else if let title, title.localizedCaseInsensitiveContains("upper") {
            focus = .upper
        } else {
            focus = finished.last?.focus == .upper ? .lower : .upper
        }
        let variant = finished.filter { $0.focus == focus }.count % 2
        return (focus, variant)
    }

    func makePlan(focus: TrainingFocus, variant: Int, availableMinutes: Int, rehabFirst: Bool) -> WorkoutPlan {
        let history = records()
        let knee = kneeStatus
        var decisions: [String: ProgressionDecision] = [:]
        for exercise in ExerciseLibrary.all {
            decisions[exercise.id] = Progression.decide(exercise, history: history, knee: knee)
        }
        return ProgramGenerator.plan(ProgramInput(focus: focus, variant: variant, availableMinutes: availableMinutes,
                                                  rehabFirst: rehabFirst, knee: knee, weights: decisions))
    }

    /// Gym time left once travel and changing are taken off the agreed slot.
    func availableMinutes(for commitment: Commitment?) -> Int {
        guard let commitment, let coach else { return 60 }
        return max(30, min(75, commitment.durationMinutes - coach.coach.gymTravelMinutes * 2 - 10))
    }

    // MARK: Running a session

    func start(_ plan: WorkoutPlan, commitment: Commitment?) {
        guard session == nil else { return }
        let created = WorkoutSession(day: DayKey(now(), calendar: calendar), plan: plan, commitmentID: commitment?.id,
                                     startedAt: now())
        context.insert(created)
        session = created
        self.plan = plan
        if let commitment, commitment.state == .approved { coach?.transition(commitment, .start, reason: "Workout started") }
        pendingCommitmentID = nil
        save()
    }

    func logWarmUp(weight: Double?, reps: Int) {
        guard let session, let current else { return }
        context.insert(SetLog(sessionID: session.id, exerciseID: current.exerciseID, setIndex: 0, isWarmUp: true,
                              weightKg: weight, reps: reps, at: now()))
        session.warmUpDone = true
        save()
    }

    /// Logs a working set and starts the rest countdown. After the last set, shows what's next and waits (W4).
    func logSet(weight: Double?, reps: Int) {
        guard let session, let current else { return }
        let index = setsDone + 1
        context.insert(SetLog(sessionID: session.id, exerciseID: current.exerciseID, setIndex: index, isWarmUp: false,
                              weightKg: weight, reps: max(0, reps), at: now()))
        let rest = current.supersetWithNext ? current.restSeconds / 2 : current.restSeconds
        if index >= current.sets {
            session.awaitingReady = true
        }
        if !(index >= current.sets && isLastExercise) {
            let ends = now().addingTimeInterval(TimeInterval(rest))
            restEndsAt = ends
            let nextName = index >= current.sets ? (upNext?.exercise?.name ?? "Next exercise") : (current.exercise?.name ?? "Next set")
            restAlerts.restStarted(until: ends, next: nextName, setLabel: index >= current.sets ? "Next exercise" : "Set \(index + 1) of \(current.sets)")
        }
        save()
    }

    func skipRest() {
        restEndsAt = nil
        restAlerts.restCancelled()
    }

    /// Moves to the next exercise once the user says they're ready.
    func ready() {
        guard let session else { return }
        session.awaitingReady = false
        session.currentIndex += 1
        session.warmUpDone = false
        skipRest()
        save()
    }

    /// Busy equipment (W4, scenario H): equivalents that aren't busy.
    func alternativesForCurrent() -> [Exercise] {
        guard let current, let exercise = current.exercise else { return [] }
        let knee = kneeStatus
        let limit: KneeLoad = knee == .settled ? .high : .low
        return exercise.alternatives.compactMap(ExerciseLibrary.exercise).filter { $0.kneeLoad <= max(limit, .low) }
    }

    func swapCurrent(to exercise: Exercise) {
        guard let session, var plan, plan.exercises.indices.contains(currentIndex) else { return }
        let decision = Progression.decide(exercise, history: records(), knee: kneeStatus)
        var item = ProgramGenerator.planned(exercise, input: ProgramInput(focus: plan.focus, variant: plan.variant,
                                                                          availableMinutes: 60, rehabFirst: plan.rehabFirst,
                                                                          knee: kneeStatus, weights: [exercise.id: decision]))
        item.isOptional = plan.exercises[currentIndex].isOptional
        plan.exercises[currentIndex] = item
        plan.notes.append("Swapped in \(exercise.name) (equipment busy).")
        apply(plan, to: session)
    }

    func doCurrentLater() {
        guard let session, let plan, setsDone == 0 else { return }
        apply(SessionAdaptation.moveLater(plan, index: currentIndex), to: session)
    }

    func move(from source: IndexSet, to destination: Int) {
        guard let session, var plan else { return }
        // Exercises already done stay where they are.
        guard (source.min() ?? 0) > currentIndex, destination > currentIndex else { return }
        plan.exercises.move(fromOffsets: source, toOffset: destination)
        apply(plan, to: session)
    }

    /// Knee pain during a set (scenario D): records it, holds or reduces that lift next time, swaps the rest,
    /// and moves on from the current exercise.
    @discardableResult
    func reportKneePain(pain: Int, swelling: Bool, sharp: Bool) -> String {
        let entry = SymptomEntry(date: now(), timing: .during, pain: pain, swelling: swelling, sharp: sharp)
        context.insert(SymptomLog(date: entry.date, timing: .during, pain: pain, swelling: swelling, sharp: sharp,
                                  exerciseID: current?.exerciseID))
        let advice = KneeRules.advice(for: entry)
        lastAdvice = advice
        guard let session, let plan, let current else { save(); return advice }
        for log in logs(for: session) where log.exerciseID == current.exerciseID && !log.isWarmUp { log.pain = true }
        let severity: KneeStatus = (pain >= 6 || swelling || sharp) ? .flare : .irritable
        var adapted = SessionAdaptation.afterKneePain(plan, currentIndex: currentIndex, severity: severity)
        if setsDone == 0 {
            // Nothing done on this exercise yet: drop it, and the next exercise becomes current.
            adapted.exercises.remove(at: currentIndex)
            apply(adapted, to: session)
        } else {
            apply(adapted, to: session)
            session.awaitingReady = true
        }
        save()
        return advice
    }

    /// Extra work only when the calendar allows (W4): optional exercises from today's template not in the plan.
    func extensionOptions() -> [Exercise] {
        guard let plan else { return [] }
        if let coach, let next = coach.events.first(where: { $0.kind.blocksUser && $0.event.start > now() }),
           next.event.start.timeIntervalSince(now()) < 45 * 60 {
            return []
        }
        let inPlan = Set(plan.exercises.map(\.exerciseID))
        let candidates = ProgramGenerator.templates(plan.focus, variant: plan.variant) + ProgramGenerator.templates(plan.focus, variant: plan.variant + 1)
        var seen = Set<String>()
        return candidates.compactMap(ExerciseLibrary.exercise).filter { exercise in
            guard !inPlan.contains(exercise.id), seen.insert(exercise.id).inserted else { return false }
            return exercise.kneeLoad <= (kneeStatus == .settled ? .high : .low)
        }
    }

    func add(_ exercise: Exercise) {
        guard let session, var plan else { return }
        let decision = Progression.decide(exercise, history: records(), knee: kneeStatus)
        var item = ProgramGenerator.planned(exercise, input: ProgramInput(focus: plan.focus, variant: plan.variant,
                                                                          availableMinutes: 60, rehabFirst: plan.rehabFirst,
                                                                          knee: kneeStatus, weights: [exercise.id: decision]))
        item.isOptional = true
        plan.exercises.append(item)
        apply(plan, to: session)
    }

    struct Summary: Equatable {
        var workingSets: Int
        var exercises: Int
        var minutes: Int
        var countedAsDone: Bool
    }

    /// Ends and saves the session. Whatever was done counts; nothing is carried over as catch-up (scenario I).
    /// An agreed workout with at least one working set is marked done (D-020).
    @discardableResult
    func end() -> Summary? {
        guard let session else { return nil }
        let working = logs(for: session).filter { !$0.isWarmUp }
        session.endedAt = now()
        session.awaitingReady = false
        skipRest()
        var counted = false
        if !working.isEmpty, let id = session.commitmentID, let coach,
           let commitment = coach.allCommitments().first(where: { $0.id == id }), commitment.state.isOpen {
            counted = coach.transition(commitment, .complete, reason: "Workout logged: \(working.count) sets")
        }
        let summary = Summary(workingSets: working.count, exercises: Set(working.map(\.exerciseID)).count,
                              minutes: Int(now().timeIntervalSince(session.startedAt) / 60), countedAsDone: counted)
        self.session = nil
        plan = nil
        save()
        restAlerts.workoutEnded()
        return summary
    }

    // MARK: Walking (K1)

    /// Today's step target: from the real baseline, reviewed at most once a week, and only raised when the knee
    /// is settled. `recentSteps` is oldest first and includes today, which is left out as it isn't finished.
    func stepTarget(recentSteps: [Int]) -> Int {
        guard let store = coach?.settingsStore else { return WalkingTargets.startingAim }
        let today = DayKey(now(), calendar: calendar)
        let history = Array(recentSteps.dropLast())
        let current = store.settings.coach.stepTarget
        if let current, let reviewed = store.settings.coach.stepTargetReviewed,
           reviewed.adding(days: 7, calendar: calendar) > today {
            return current
        }
        guard let baseline = WalkingTargets.baseline(history) else { return current ?? WalkingTargets.startingAim }
        let next = WalkingTargets.target(baseline: baseline, previous: current, lastWeek: Array(history.suffix(7)), knee: kneeStatus)
        store.settings.coach.stepTarget = next
        store.settings.coach.stepTargetReviewed = today
        return next
    }

    // MARK: Knee check-ins (R3)

    /// The morning after a lower-body session or rehab, until it's been answered.
    var needsNextDayKneeCheck: Bool {
        let today = DayKey(now(), calendar: calendar)
        let yesterday = today.adding(days: -1, calendar: calendar).description
        let trainedLegs = sessions().contains { $0.day == yesterday && $0.endedAt != nil && $0.focus == .lower }
            || (coach?.allCommitments().contains { $0.day == yesterday && $0.kind == .rehab && $0.state == .completed } ?? false)
        guard trainedLegs else { return false }
        return !symptomLogs().contains { $0.timing == .nextDay && DayKey($0.date, calendar: calendar) == today }
    }

    @discardableResult
    func logSymptom(timing: SymptomTiming, pain: Int, swelling: Bool, sharp: Bool, note: String? = nil) -> String {
        let log = SymptomLog(date: now(), timing: timing, pain: pain, swelling: swelling, sharp: sharp, note: note)
        context.insert(log)
        save()
        let advice = KneeRules.advice(for: log.entry)
        lastAdvice = advice
        return advice
    }

    // MARK: Store

    func sessions() -> [WorkoutSession] {
        (try? context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
    }

    func logs(for session: WorkoutSession) -> [SetLog] {
        let id = session.id
        return (try? context.fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.sessionID == id },
                                                         sortBy: [SortDescriptor(\.loggedAt)]))) ?? []
    }

    func allLogs() -> [SetLog] {
        (try? context.fetch(FetchDescriptor<SetLog>(sortBy: [SortDescriptor(\.loggedAt)]))) ?? []
    }

    func symptomLogs() -> [SymptomLog] {
        (try? context.fetch(FetchDescriptor<SymptomLog>(sortBy: [SortDescriptor(\.date)]))) ?? []
    }

    /// Per-session, per-exercise records for progression.
    func records() -> [ExerciseRecord] {
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions().map { ($0.id, $0) })
        let grouped = Dictionary(grouping: allLogs().filter { !$0.isWarmUp }) { "\($0.sessionID.uuidString)|\($0.exerciseID)" }
        return grouped.values.compactMap { logs -> ExerciseRecord? in
            guard let first = logs.first, let session = sessionsByID[first.sessionID] else { return nil }
            let sorted = logs.sorted { $0.setIndex < $1.setIndex }
            return ExerciseRecord(date: session.startedAt, exerciseID: first.exerciseID,
                                  sets: sorted.map { LoggedSet(weightKg: $0.weightKg, reps: $0.reps) },
                                  pain: logs.contains(where: \.pain))
        }
        .sorted { $0.date < $1.date }
    }

    private func apply(_ updated: WorkoutPlan, to session: WorkoutSession) {
        session.plan = updated
        plan = updated
        save()
    }

    private func restoreActiveSession() {
        guard let active = sessions().last(where: \.isActive) else { return }
        session = active
        plan = active.plan
    }

    private func save() {
        try? context.save()
    }
}
