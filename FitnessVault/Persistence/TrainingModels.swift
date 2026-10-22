import Foundation
import SwiftData

// Phase 3 training entities. All new, so existing stores open with lightweight migration.

/// One gym session. The plan is stored as it currently stands, including any mid-session changes.
@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var day: String
    var focusRaw: String
    var variant: Int
    var planData: Data
    var startedAt: Date
    var endedAt: Date?
    var commitmentID: UUID?
    var currentIndex: Int
    /// Finished the last set of an exercise; waiting for "Ready" before the next (W4).
    var awaitingReady: Bool
    var warmUpDone: Bool

    init(day: DayKey, plan: WorkoutPlan, commitmentID: UUID?, startedAt: Date) {
        id = UUID()
        self.day = day.description
        focusRaw = plan.focus.rawValue
        variant = plan.variant
        planData = (try? JSONEncoder().encode(plan)) ?? Data()
        self.startedAt = startedAt
        self.commitmentID = commitmentID
        currentIndex = 0
        awaitingReady = false
        warmUpDone = false
    }

    var focus: TrainingFocus { TrainingFocus(rawValue: focusRaw) ?? .push }
    var isActive: Bool { endedAt == nil }
    /// A knee rehab session on its own: it doesn't move the push, pull, legs rotation on.
    var isRehabOnly: Bool { plan?.rehabOnly == true }

    var plan: WorkoutPlan? {
        get { try? JSONDecoder().decode(WorkoutPlan.self, from: planData) }
        set { planData = (newValue.flatMap { try? JSONEncoder().encode($0) }) ?? planData }
    }
}

/// One logged set: what was actually lifted, entered on the iPhone (W4).
@Model
final class SetLog {
    var id: UUID
    var sessionID: UUID
    var exerciseID: String
    var setIndex: Int
    var isWarmUp: Bool
    var weightKg: Double?
    var reps: Int
    var pain: Bool
    var loggedAt: Date

    init(sessionID: UUID, exerciseID: String, setIndex: Int, isWarmUp: Bool, weightKg: Double?, reps: Int, at date: Date) {
        id = UUID()
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.setIndex = setIndex
        self.isWarmUp = isWarmUp
        self.weightKg = weightKg
        self.reps = reps
        pain = false
        loggedAt = date
    }
}

/// A knee check-in (R3): during activity, the next morning, or any time.
@Model
final class SymptomLog {
    var id: UUID
    var date: Date
    var timingRaw: String
    var pain: Int
    var swelling: Bool
    var sharp: Bool
    var exerciseID: String?
    var note: String?

    init(date: Date, timing: SymptomTiming, pain: Int, swelling: Bool, sharp: Bool, exerciseID: String? = nil, note: String? = nil) {
        id = UUID()
        self.date = date
        timingRaw = timing.rawValue
        self.pain = min(10, max(0, pain))
        self.swelling = swelling
        self.sharp = sharp
        self.exerciseID = exerciseID
        self.note = note
    }

    var timing: SymptomTiming { SymptomTiming(rawValue: timingRaw) ?? .general }
    var entry: SymptomEntry { SymptomEntry(date: date, timing: timing, pain: pain, swelling: swelling, sharp: sharp) }
}
