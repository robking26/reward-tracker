import Foundation

// MARK: - Knee status (R3)

enum SymptomTiming: String, Codable, CaseIterable, Sendable {
    case during, nextDay, general

    var title: String {
        switch self {
        case .during: "During activity"
        case .nextDay: "The next morning"
        case .general: "Today"
        }
    }
}

struct SymptomEntry: Hashable, Sendable {
    var date: Date
    var timing: SymptomTiming
    /// 0 (none) to 10 (worst).
    var pain: Int
    var swelling: Bool
    var sharp: Bool
}

enum KneeStatus: String, Codable, Sendable {
    /// Train as planned.
    case settled
    /// Hold lower-body progression and swap high knee-load lifts.
    case irritable
    /// Rehab and upper body only; recommend professional care.
    case flare

    var title: String {
        switch self {
        case .settled: "Settled"
        case .irritable: "Irritable"
        case .flare: "Flared up"
        }
    }
}

enum KneeRules {
    /// The last 72 hours decide the status. Sharp pain or swelling always counts as a flare.
    static func status(_ entries: [SymptomEntry], now: Date) -> KneeStatus {
        let recent = entries.filter { $0.date <= now && now.timeIntervalSince($0.date) <= 72 * 3_600 }
        if recent.contains(where: { $0.pain >= 6 || $0.swelling || $0.sharp }) { return .flare }
        if recent.contains(where: { $0.pain >= 3 }) { return .irritable }
        // Delayed pain matters (O-B): worse the next morning than during the session.
        let sorted = recent.sorted { $0.date < $1.date }
        for (index, entry) in sorted.enumerated() where entry.timing == .nextDay && index > 0 {
            if entry.pain >= sorted[index - 1].pain + 2 { return .irritable }
        }
        return .settled
    }

    /// Advice for one report. Concerning symptoms always point to professional care; never a diagnosis.
    static func advice(for entry: SymptomEntry) -> String {
        if entry.sharp || entry.swelling || entry.pain >= 6 {
            return "Stop anything that provokes it and rest it today. Sharp pain or swelling needs your physio or GP, especially after the last reinjury. Don't push through it."
        }
        if entry.pain >= 3 {
            return "Ease off: lower-body loads stay where they are and the heavy knee work is swapped for gentler options until it settles. Keep doing the rehab that doesn't hurt."
        }
        return entry.timing == .nextDay ? "Good. Normal plan today." : "Fine to carry on. Tell me if it changes."
    }
}

// MARK: - Session plan

struct PlannedExercise: Hashable, Sendable, Identifiable, Codable {
    var exerciseID: String
    var sets: Int
    var targetReps: Int
    var weightKg: Double?
    var warmUpKg: Double?
    var restSeconds: Int
    /// First time, or a new starting estimate: confirm it feels right before trusting it (W3).
    var isValidation: Bool
    var isRehab: Bool
    var isOptional: Bool
    /// Done back to back with the next exercise to save time.
    var supersetWithNext: Bool = false
    var note: String?

    var id: String { exerciseID }
    var exercise: Exercise? { ExerciseLibrary.exercise(exerciseID) }
}

struct WorkoutPlan: Hashable, Sendable, Codable {
    var focus: TrainingFocus
    /// 0 = A, 1 = B: alternates within a focus so the two weekly sessions differ.
    var variant: Int
    var exercises: [PlannedExercise]
    var rehabFirst: Bool
    var estimatedMinutes: Int
    var notes: [String]

    var title: String { "\(focus.title) \(variant == 0 ? "A" : "B")" }
}

struct ProgramInput: Sendable {
    var focus: TrainingFocus
    var variant: Int
    /// Time in the gym, excluding travel and changing.
    var availableMinutes: Int
    var rehabFirst: Bool
    var knee: KneeStatus
    /// Working weight decided by progression, per exercise.
    var weights: [String: ProgressionDecision]
}

enum ProgramGenerator {
    static let warmUpMinutes = 8

    static func templates(_ focus: TrainingFocus, variant: Int) -> [String] {
        switch (focus, variant % 2) {
        case (.upper, 0): ["inclineDBBench", "barbellRow", "seatedDBShoulderPress", "ezBarCurl", "tricepsMachine", "lateralRaise"]
        case (.upper, _): ["flatDBBench", "latPulldown", "seatedDBShoulderPress", "hammerCurl", "skullCrusher", "trapMachine"]
        case (.lower, 0): ["barbellSquat", "singleLegPress", "cleanAndPress", "plank"]
        case (.lower, _): ["deadlift", "singleLegPress", "cleanAndPress", "cableCrunch"]
        }
    }

    /// Rehab block: 10–15 minutes on lower days, brief on upper days (R2).
    static func rehabBlock(_ focus: TrainingFocus) -> [String] {
        focus == .lower
            ? ["gluteBridge", "sideLyingAbduction", "bandedLateralWalk", "stepDown", "singleLegBalance"]
            : ["gluteBridge", "singleLegBalance"]
    }

    static func plan(_ input: ProgramInput) -> WorkoutPlan {
        var notes: [String] = []
        var main: [PlannedExercise] = []

        for id in templates(input.focus, variant: input.variant) {
            guard var exercise = ExerciseLibrary.exercise(id) else { continue }
            // An irritable or flared knee swaps the heavier knee work for gentler alternatives (R3).
            let limit: KneeLoad = input.knee == .settled ? .high : (input.knee == .irritable ? .low : .none)
            if exercise.kneeLoad > limit {
                guard let swap = exercise.alternatives.compactMap(ExerciseLibrary.exercise).first(where: { $0.kneeLoad <= limit }) else {
                    notes.append("\(exercise.name) left out while the knee settles.")
                    continue
                }
                notes.append("\(exercise.name) swapped for \(swap.name) while the knee settles.")
                exercise = swap
            }
            main.append(planned(exercise, input: input))
        }

        if input.knee == .flare && input.focus == .lower {
            main = []
            notes.append("Knee flared up: rehab only today, and only what doesn't hurt. Book your physio if it's not settling.")
        }

        let rehab = rehabBlock(input.focus).compactMap(ExerciseLibrary.exercise).map { planned($0, input: input) }

        // Fit the time: drop optional work first, then superset accessories. Rehab and main lifts stay (W4).
        var chosen = main
        func total(_ list: [PlannedExercise]) -> Int { warmUpMinutes + minutes(list) + minutes(rehab) }
        while total(chosen) > input.availableMinutes, let index = chosen.lastIndex(where: { $0.isOptional }) {
            notes.append("\(chosen[index].exercise?.name ?? "An extra") dropped to fit the time.")
            chosen.remove(at: index)
        }
        if total(chosen) > input.availableMinutes {
            let accessories = chosen.indices.filter { chosen[$0].exercise?.role == .accessory }
            for pair in stride(from: 0, to: accessories.count - 1, by: 2) {
                chosen[accessories[pair]].supersetWithNext = true
            }
            if accessories.count >= 2 { notes.append("Accessories paired as supersets to save time.") }
        }

        let ordered = input.rehabFirst ? rehab + chosen : chosen + rehab
        return WorkoutPlan(focus: input.focus, variant: input.variant % 2, exercises: ordered, rehabFirst: input.rehabFirst,
                           estimatedMinutes: total(chosen), notes: notes)
    }

    static func planned(_ exercise: Exercise, input: ProgramInput) -> PlannedExercise {
        let decision = input.weights[exercise.id] ?? .start(exercise.startingKg)
        var note = decision.reason
        if exercise.startingKg == nil && exercise.usesWeight && decision.weight == nil {
            note = "Find a weight you can lift for \(exercise.targetReps) with good form."
        }
        return PlannedExercise(exerciseID: exercise.id, sets: exercise.sets, targetReps: exercise.targetReps,
                               weightKg: decision.weight, warmUpKg: exercise.warmUpKg, restSeconds: exercise.restSeconds,
                               isValidation: decision.isValidation, isRehab: exercise.role == .rehab,
                               isOptional: exercise.role == .accessory || exercise.role == .core, note: note)
    }

    /// Rough time per exercise: a warm-up set, working sets with rest, and moving between stations.
    static func minutes(_ list: [PlannedExercise]) -> Int {
        let seconds = list.reduce(0) { sum, item in
            // Rehab moves are short and done back to back: about 12 minutes on lower days, 5 on upper days (R2).
            if item.isRehab { return sum + 150 }
            let work = 45
            let warm = item.warmUpKg != nil ? 90 : 0
            let rest = item.supersetWithNext ? item.restSeconds / 2 : item.restSeconds
            return sum + warm + item.sets * (work + rest) + 60
        }
        return Int((Double(seconds) / 60).rounded(.up))
    }
}

// MARK: - Progression (W2)

struct LoggedSet: Hashable, Sendable, Codable {
    var weightKg: Double?
    var reps: Int
}

/// What happened to one exercise in one session.
struct ExerciseRecord: Hashable, Sendable {
    var date: Date
    var exerciseID: String
    var sets: [LoggedSet]
    var pain: Bool = false
    var techniqueConcern: Bool = false

    var topWeight: Double? { sets.compactMap(\.weightKg).max() }
}

enum ProgressionDecision: Hashable, Sendable, Codable {
    case start(Double?)
    case increase(to: Double)
    case hold(at: Double?, reason: String)
    case reduce(to: Double, reason: String)

    var weight: Double? {
        switch self {
        case .start(let kg): kg
        case .increase(let kg): kg
        case .hold(let kg, _): kg
        case .reduce(let kg, _): kg
        }
    }

    var isValidation: Bool {
        if case .start = self { return true }
        return false
    }

    var reason: String? {
        switch self {
        case .start(let kg): kg.map { "Starting estimate \(WeightFormat.text($0)). Check it feels right." }
        case .increase(let kg): "Up to \(WeightFormat.text(kg)): three sessions on target."
        case .hold(_, let reason): reason
        case .reduce(_, let reason): reason
        }
    }
}

enum Progression {
    /// Up one increment only after the target was hit in three consecutive sessions at the same weight.
    /// Never because time has passed. Pain or technique concerns hold or reduce.
    static func decide(_ exercise: Exercise, history: [ExerciseRecord], knee: KneeStatus) -> ProgressionDecision {
        let records = history.filter { $0.exerciseID == exercise.id }.sorted { $0.date < $1.date }
        guard let last = records.last else { return .start(exercise.startingKg) }
        guard exercise.usesWeight, let current = last.topWeight else {
            return .hold(at: nil, reason: "Same as last time; quality over load.")
        }

        if last.pain {
            let lower = max(exercise.warmUpKg ?? 0, current - exercise.incrementKg)
            return .reduce(to: lower, reason: "It hurt last time, so one step lighter.")
        }
        if exercise.kneeLoad >= .moderate && knee != .settled {
            return .hold(at: current, reason: "Holding while the knee settles.")
        }
        if last.techniqueConcern {
            return .hold(at: current, reason: "Holding until the form feels solid.")
        }

        let atWeight = Array(records.reversed().prefix { $0.topWeight == current })
        let hits = atWeight.prefix(3).filter { hitTarget($0, exercise) }.count
        if atWeight.count >= 3 && hits == 3 {
            return .increase(to: current + exercise.incrementKg)
        }
        let misses = atWeight.prefix(2).filter { missedMinimum($0, exercise) }.count
        if atWeight.count >= 2 && misses == 2 {
            let lower = max(exercise.warmUpKg ?? 0, current - exercise.incrementKg)
            return .reduce(to: lower, reason: "Under \(exercise.minReps) reps twice, so one step lighter.")
        }
        let streak = atWeight.prefix { hitTarget($0, exercise) }.count
        return .hold(at: current, reason: "\(streak) of 3 sessions on target at this weight.")
    }

    static func hitTarget(_ record: ExerciseRecord, _ exercise: Exercise) -> Bool {
        let working = record.sets.prefix(exercise.sets)
        return working.count >= exercise.sets && working.allSatisfy { $0.reps >= exercise.targetReps }
    }

    static func missedMinimum(_ record: ExerciseRecord, _ exercise: Exercise) -> Bool {
        record.sets.prefix(exercise.sets).contains { $0.reps < exercise.minReps }
    }
}

enum WeightFormat {
    static func text(_ kg: Double, perSide: Bool = false) -> String {
        let number = kg.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(kg)) : String(format: "%.1f", kg)
        return "\(number) kg\(perSide ? " each" : "")"
    }
}

// MARK: - Mid-session adaptation (scenario D)

enum SessionAdaptation {
    /// Knee pain during a set: the current exercise stops, remaining knee-loading work is swapped for gentler
    /// options or dropped, and anything that's already done stays done (scenario I).
    static func afterKneePain(_ plan: WorkoutPlan, currentIndex: Int, severity: KneeStatus) -> WorkoutPlan {
        var result = plan
        let limit: KneeLoad = severity == .flare ? .none : .low
        var remaining: [PlannedExercise] = []
        for item in plan.exercises.dropFirst(currentIndex + 1) {
            guard let exercise = item.exercise else { continue }
            if exercise.kneeLoad <= limit {
                remaining.append(item)
            } else if let swap = exercise.alternatives.compactMap(ExerciseLibrary.exercise).first(where: { $0.kneeLoad <= limit }) {
                var replaced = item
                replaced.exerciseID = swap.id
                replaced.weightKg = nil
                replaced.warmUpKg = nil
                replaced.isValidation = true
                replaced.note = "Swapped for your knee. Find an easy weight."
                remaining.append(replaced)
            }
        }
        result.exercises = Array(plan.exercises.prefix(currentIndex + 1)) + remaining
        result.notes.append(severity == .flare
                            ? "Stopped the knee-loading work. Rest it, and see your physio if it's sharp, swollen or worse tomorrow."
                            : "Knee-loading work swapped for gentler options.")
        return result
    }

    /// Busy equipment: the best equivalent that isn't also busy (W4, scenario H).
    static func alternative(for exerciseID: String, busy: Set<String>, knee: KneeStatus) -> Exercise? {
        guard let exercise = ExerciseLibrary.exercise(exerciseID) else { return nil }
        let limit: KneeLoad = knee == .settled ? .high : .low
        return exercise.alternatives.compactMap(ExerciseLibrary.exercise)
            .first { !busy.contains($0.id) && $0.kneeLoad <= max(limit, exercise.kneeLoad == .none ? .none : .low) }
    }

    /// Moves an exercise to later in the session (do it when the machine's free).
    static func moveLater(_ plan: WorkoutPlan, index: Int) -> WorkoutPlan {
        guard plan.exercises.indices.contains(index), index < plan.exercises.count - 1 else { return plan }
        var result = plan
        let item = result.exercises.remove(at: index)
        result.exercises.insert(item, at: index + 1)
        return result
    }
}

// MARK: - Walking (K1)

enum WalkingTargets {
    static let ceiling = 12_500
    static let startingAim = 7_000

    /// Median of the recorded days (zero days are ignored: usually the watch was off).
    static func baseline(_ steps: [Int]) -> Int? {
        let days = steps.filter { $0 > 0 }.sorted()
        guard !days.isEmpty else { return nil }
        return days[days.count / 2]
    }

    /// Gradual: start from the real baseline, step up 500 a week only when the knee is settled and the target was
    /// met on 5 of the last 7 days.
    static func target(baseline: Int, previous: Int?, lastWeek: [Int], knee: KneeStatus) -> Int {
        guard let previous else {
            let start = baseline >= startingAim ? baseline : min(startingAim, baseline + 1_000)
            return min(ceiling, roundUp(start))
        }
        switch knee {
        case .flare: return max(roundUp(baseline), previous - 1_000)
        case .irritable: return previous
        case .settled:
            let met = lastWeek.suffix(7).filter { $0 >= previous }.count
            return met >= 5 ? min(ceiling, previous + 500) : previous
        }
    }

    static func roundUp(_ value: Int) -> Int { ((value + 249) / 250) * 250 }
}

// MARK: - Swimming (SW2)

struct SwimRecord: Hashable, Sendable {
    var date: Date
    var minutes: Int
    var metres: Int
}

enum SwimPlan {
    /// Low pressure: +5 minutes after two comfortable swims at the current length, up to 60 minutes.
    /// Simple sets come in once 40 minutes feels normal.
    static func next(_ history: [SwimRecord]) -> (minutes: Int, note: String) {
        let recent = history.sorted { $0.date < $1.date }.suffix(4)
        guard let last = recent.last else { return (20, "Get in and swim. Rest whenever you need to.") }
        let current = max(20, (last.minutes / 5) * 5)
        let comfortable = recent.suffix(2).filter { $0.minutes >= current }.count == 2
        let next = min(60, comfortable ? current + 5 : current)
        let note = next >= 40
            ? "Try a simple set: 4 × 100 m steady, 30 seconds rest, then swim easy."
            : "Swim easy, rest as needed. Aim for \(next) minutes."
        return (next, note)
    }
}
