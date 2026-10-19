import Foundation
import SwiftData

// Vaultality 2.0 coaching entities (docs/DATA_MODEL.md). All new, so existing stores open with
// lightweight migration. Enums are stored as raw strings so unknown future values never crash.

@Model
final class Commitment {
    @Attribute(.unique) var id: UUID
    var day: String
    var title: String
    var detail: String?
    var kindRaw: String
    var stateRaw: String
    var weight: Int
    var scheduledStart: Date?
    var durationMinutes: Int
    var sourceRaw: String
    var routineID: UUID?
    var objectiveRaw: String?
    /// Why the coach suggested it (E4).
    var reason: String?
    var excuseRaw: String?
    var note: String?
    /// Set when it became missed because nobody answered (D-014), so it can be explained and corrected.
    var assumedMissed: Bool
    var createdAt: Date
    var updatedAt: Date
    var approvedAt: Date?

    init(day: DayKey, title: String, kind: CommitmentKind, state: CommitmentState = .proposed,
         weight: Int? = nil, scheduledStart: Date? = nil, durationMinutes: Int = 30,
         source: CommitmentSource = .coach, routineID: UUID? = nil, objective: Objective? = nil,
         reason: String? = nil, detail: String? = nil) {
        id = UUID()
        self.day = day.description
        self.title = title
        self.detail = detail
        kindRaw = kind.rawValue
        stateRaw = state.rawValue
        self.weight = CommitmentRules.clampedWeight(weight ?? kind.defaultWeight)
        self.scheduledStart = scheduledStart
        self.durationMinutes = durationMinutes
        sourceRaw = source.rawValue
        self.routineID = routineID
        objectiveRaw = objective?.rawValue
        self.reason = reason
        assumedMissed = false
        createdAt = .now
        updatedAt = .now
        approvedAt = state == .approved ? .now : nil
    }

    var dayKey: DayKey? { DayKey(string: day) }
    var kind: CommitmentKind { CommitmentKind(rawValue: kindRaw) ?? .other }
    var state: CommitmentState { CommitmentState(rawValue: stateRaw) ?? .pendingVerification }
    var source: CommitmentSource { CommitmentSource(rawValue: sourceRaw) ?? .coach }
    var objective: Objective? { objectiveRaw.flatMap(Objective.init(rawValue:)) }
    var excuse: ExcuseReason? { excuseRaw.flatMap(ExcuseReason.init(rawValue:)) }
    var scored: ScoredCommitment { ScoredCommitment(state: state, weight: weight) }
    var scheduledEnd: Date? { scheduledStart?.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
}

/// Append-only history of every commitment change (E4).
@Model
final class CommitmentEvent {
    var id: UUID
    var commitmentID: UUID
    var fromRaw: String
    var toRaw: String
    var reason: String?
    var actorRaw: String
    var at: Date

    init(commitmentID: UUID, from: CommitmentState, to: CommitmentState, reason: String?, actor: ChangeActor) {
        id = UUID()
        self.commitmentID = commitmentID
        fromRaw = from.rawValue
        toRaw = to.rawValue
        self.reason = reason
        actorRaw = actor.rawValue
        at = .now
    }
}

/// A pre-agreed recurring commitment (A3). Seeded routines start disabled until the user agrees.
@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRaw: String
    var weight: Int
    /// ISO weekdays: bit 0 = Monday … bit 6 = Sunday.
    var weekdayMask: Int
    var minuteOfDay: Int?
    var durationMinutes: Int
    var isEnabled: Bool
    var reason: String?
    var createdAt: Date

    init(title: String, kind: CommitmentKind, weight: Int? = nil, weekdays: Set<Int>, minuteOfDay: Int?,
         durationMinutes: Int, isEnabled: Bool = false, reason: String? = nil) {
        id = UUID()
        self.title = title
        kindRaw = kind.rawValue
        self.weight = CommitmentRules.clampedWeight(weight ?? kind.defaultWeight)
        weekdayMask = Routine.mask(weekdays)
        self.minuteOfDay = minuteOfDay
        self.durationMinutes = durationMinutes
        self.isEnabled = isEnabled
        self.reason = reason
        createdAt = .now
    }

    var kind: CommitmentKind { CommitmentKind(rawValue: kindRaw) ?? .other }

    /// ISO weekday, Monday = 1 … Sunday = 7.
    func runs(onISOWeekday weekday: Int) -> Bool {
        (1...7).contains(weekday) && weekdayMask & (1 << (weekday - 1)) != 0
    }

    var weekdays: Set<Int> { Set((1...7).filter(runs(onISOWeekday:))) }

    static func mask(_ weekdays: Set<Int>) -> Int {
        weekdays.filter { (1...7).contains($0) }.reduce(0) { $0 | (1 << ($1 - 1)) }
    }
}

/// The reconciled result of one day (A4–A6).
@Model
final class DayRecord {
    @Attribute(.unique) var day: String
    var applicableWeight: Int
    var completedWeight: Int
    var scorePercent: Int?
    var finePence: Int
    var uncappedFinePence: Int
    var finalisedAt: Date?
    var isSimulation: Bool
    var explanation: String

    init(day: DayKey, isSimulation: Bool) {
        self.day = day.description
        applicableWeight = 0
        completedWeight = 0
        finePence = 0
        uncappedFinePence = 0
        self.isSimulation = isSimulation
        explanation = ""
    }

    var dayKey: DayKey? { DayKey(string: day) }
    var fine: Pence { Pence(finePence) }
}

/// One item in the coach conversation (N3). Voice and text share this history (V1).
@Model
final class CoachMessage {
    var id: UUID
    var roleRaw: String
    var text: String
    var createdAt: Date
    var quickReplies: [String]
    var relatedCommitmentID: UUID?
    /// What the app actually did, shown under the message, e.g. "Added to your list: Clean the attic".
    var toolSummary: String?

    init(role: MessageRole, text: String, quickReplies: [String] = [], relatedCommitmentID: UUID? = nil,
         toolSummary: String? = nil) {
        id = UUID()
        roleRaw = role.rawValue
        self.text = text
        createdAt = .now
        self.quickReplies = quickReplies
        self.relatedCommitmentID = relatedCommitmentID
        self.toolSummary = toolSummary
    }

    var role: MessageRole { MessageRole(rawValue: roleRaw) ?? .system }
}

/// A structured memory (M1–M4).
@Model
final class MemoryRecord {
    @Attribute(.unique) var id: UUID
    var storeRaw: String
    var key: String
    var value: String
    var sourceRaw: String
    var statusRaw: String
    var confidence: Double?
    var sensitivityRaw: String
    var createdAt: Date
    var updatedAt: Date
    var reviewAt: Date?

    init(store: MemoryStore, key: String, value: String, source: MemorySource,
         sensitivity: Sensitivity = .general, confidence: Double? = nil, reviewAt: Date? = nil) {
        id = UUID()
        storeRaw = store.rawValue
        self.key = key
        self.value = value
        sourceRaw = source.rawValue
        statusRaw = MemoryRules.initialStatus(for: source).rawValue
        self.confidence = confidence
        sensitivityRaw = sensitivity.rawValue
        createdAt = .now
        updatedAt = .now
        self.reviewAt = reviewAt
    }

    var store: MemoryStore { MemoryStore(rawValue: storeRaw) ?? .profile }
    var source: MemorySource { MemorySource(rawValue: sourceRaw) ?? .system }
    var status: MemoryStatus { MemoryStatus(rawValue: statusRaw) ?? .hypothesis }
    var sensitivity: Sensitivity { Sensitivity(rawValue: sensitivityRaw) ?? .general }
}

/// A backlog task with optional parent and dependencies (H1–H3).
@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var areaRaw: String
    var parentID: UUID?
    var dependsOn: [String]
    var estimatedMinutes: Int
    var priority: Int
    var stateRaw: String
    var resumeNote: String?
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(title: String, area: TaskArea, parentID: UUID? = nil, dependsOn: [UUID] = [], estimatedMinutes: Int = 15,
         priority: Int = 3, sortIndex: Int = 0) {
        id = UUID()
        self.title = title
        areaRaw = area.rawValue
        self.parentID = parentID
        self.dependsOn = dependsOn.map(\.uuidString)
        self.estimatedMinutes = estimatedMinutes
        self.priority = min(5, max(1, priority))
        stateRaw = TaskState.open.rawValue
        self.sortIndex = sortIndex
        createdAt = .now
        updatedAt = .now
    }

    var area: TaskArea { TaskArea(rawValue: areaRaw) ?? .personal }
    var state: TaskState {
        get { TaskState(rawValue: stateRaw) ?? .open }
        set {
            stateRaw = newValue.rawValue
            updatedAt = .now
            completedAt = newValue == .done ? .now : nil
        }
    }
}
