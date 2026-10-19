import Foundation

/// What kind of action a commitment is. Drives icons, default weights and which objective it serves.
enum CommitmentKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case workout, walk, swim, rehab, household, meal, selfCare, work, social, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workout: "Workout"
        case .walk: "Walk"
        case .swim: "Swim"
        case .rehab: "Knee rehab"
        case .household: "Household"
        case .meal: "Meal"
        case .selfCare: "Self-care"
        case .work: "Work"
        case .social: "Social"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .workout: "dumbbell.fill"
        case .walk: "figure.walk"
        case .swim: "figure.pool.swim"
        case .rehab: "figure.strengthtraining.functional"
        case .household: "house"
        case .meal: "fork.knife"
        case .selfCare: "moon.stars"
        case .work: "laptopcomputer"
        case .social: "person.2"
        case .other: "checkmark.circle"
        }
    }

    /// Default weight (D-012). 1 is light, 5 is major.
    var defaultWeight: Int {
        switch self {
        case .workout: 4
        case .rehab: 3
        case .swim: 3
        case .walk, .selfCare, .meal: 2
        case .household, .work, .social, .other: 1
        }
    }
}

/// Explicit lifecycle of a commitment (A4). "Due later" is a label for an approved commitment
/// whose start is still ahead, not a separate state.
enum CommitmentState: String, Codable, CaseIterable, Sendable {
    case proposed
    case approved
    case inProgress
    case completed
    case missed
    case excused
    case rescheduled
    case cancelled
    case pendingVerification

    /// Counted in the day's score denominator.
    var isApplicable: Bool {
        switch self {
        case .approved, .inProgress, .completed, .missed, .pendingVerification: true
        case .proposed, .excused, .rescheduled, .cancelled: false
        }
    }

    /// Still to be done, so it can still raise the day's score.
    var isOpen: Bool {
        self == .approved || self == .inProgress || self == .pendingVerification
    }

    var title: String {
        switch self {
        case .proposed: "Suggested"
        case .approved: "Agreed"
        case .inProgress: "In progress"
        case .completed: "Done"
        case .missed: "Missed"
        case .excused: "Excused"
        case .rescheduled: "Moved"
        case .cancelled: "Cancelled"
        case .pendingVerification: "Did you do this?"
        }
    }
}

/// Legitimate reasons a commitment doesn't count against the day (A6, D-013).
/// Deliberately has no "didn't fancy it" option: avoidance is coached, not excused.
enum ExcuseReason: String, Codable, CaseIterable, Sendable, Identifiable {
    case illness
    case injurySymptoms
    case restOrRecovery
    case sleep
    case calendarConflict
    case outsideControl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .illness: "I'm ill"
        case .injurySymptoms: "Injury or knee symptoms"
        case .restOrRecovery: "Needed rest or recovery"
        case .sleep: "Sleep comes first"
        case .calendarConflict: "Something unavoidable came up"
        case .outsideControl: "Outside my control"
        }
    }
}

enum CommitmentSource: String, Codable, Sendable {
    case routine, coach, user
}

/// Who changed a commitment, for the history log.
enum ChangeActor: String, Codable, Sendable {
    case user, coach, system
}

/// The long-term objectives a commitment can serve (O-A … O-D).
enum Objective: String, Codable, CaseIterable, Sendable {
    case health, knee, homeMove, lifestyle, household

    var title: String {
        switch self {
        case .health: "Health and body composition"
        case .knee: "Knee rehab and five-a-side"
        case .homeMove: "Home move"
        case .lifestyle: "Lifestyle and presence"
        case .household: "Household"
        }
    }
}

/// The actions a user, the coach or the system can take on a commitment.
enum CommitmentAction: Equatable, Sendable {
    case approve
    case cancel
    case start
    case complete
    /// Same day, later time. Never needs a reason.
    case rescheduleLaterToday
    /// Another day. Needs a legitimate reason.
    case rescheduleToAnotherDay(ExcuseReason)
    case excuse(ExcuseReason)
    /// The day ended with the commitment still open.
    case dayEnded
    /// Nobody answered by the end of the following day (D-014).
    case verificationExpired
    case markMissed
    /// The user corrects the record, e.g. "I was actually at the gym".
    case correct(to: CommitmentState)
}

enum CommitmentRuleError: Error, Equatable, LocalizedError {
    case notAllowed(from: CommitmentState, action: String)
    case monthClosed
    case weightFrozen

    var errorDescription: String? {
        switch self {
        case .notAllowed(let from, let action): "Can't \(action) a commitment that is \(from.title.lowercased())."
        case .monthClosed: "That month has been closed, so its record can't change."
        case .weightFrozen: "A commitment's weight is fixed once it's agreed."
        }
    }
}

/// The commitment state machine. Pure, so every rule is unit tested.
enum CommitmentRules {
    /// The state after applying `action`, or an error when the action isn't allowed.
    static func apply(_ action: CommitmentAction, to state: CommitmentState, monthClosed: Bool = false) throws -> CommitmentState {
        if monthClosed { throw CommitmentRuleError.monthClosed }
        switch (state, action) {
        case (.proposed, .approve): return .approved
        case (.proposed, .cancel): return .cancelled

        case (.approved, .start): return .inProgress
        case (.approved, .complete), (.inProgress, .complete), (.pendingVerification, .complete): return .completed
        case (.approved, .rescheduleLaterToday), (.inProgress, .rescheduleLaterToday): return .rescheduled
        case (.approved, .rescheduleToAnotherDay), (.inProgress, .rescheduleToAnotherDay): return .rescheduled
        case (.approved, .excuse), (.inProgress, .excuse), (.pendingVerification, .excuse): return .excused
        case (.approved, .dayEnded), (.inProgress, .dayEnded): return .pendingVerification
        case (.approved, .markMissed), (.inProgress, .markMissed), (.pendingVerification, .markMissed): return .missed
        case (.pendingVerification, .verificationExpired): return .missed

        // Corrections (E4): plausible user corrections override what the app assumed.
        case (.missed, .correct(let target)) where [.completed, .excused].contains(target): return target
        case (.completed, .correct(.missed)): return .missed
        case (.excused, .correct(let target)) where [.completed, .missed].contains(target): return target

        default:
            throw CommitmentRuleError.notAllowed(from: state, action: describe(action))
        }
    }

    static func canApply(_ action: CommitmentAction, to state: CommitmentState) -> Bool {
        (try? apply(action, to: state)) != nil
    }

    /// Weight can only be set while the commitment is still a suggestion (D-012).
    static func canChangeWeight(in state: CommitmentState) -> Bool { state == .proposed }

    /// Weight clamped to the 1–5 scale.
    static func clampedWeight(_ weight: Int) -> Int { min(5, max(1, weight)) }

    private static func describe(_ action: CommitmentAction) -> String {
        switch action {
        case .approve: "agree to"
        case .cancel: "cancel"
        case .start: "start"
        case .complete: "complete"
        case .rescheduleLaterToday, .rescheduleToAnotherDay: "move"
        case .excuse: "excuse"
        case .dayEnded: "close"
        case .verificationExpired: "expire"
        case .markMissed: "mark as missed"
        case .correct: "correct"
        }
    }
}
