import Foundation
import SwiftData

// Retired Vaultality 2.0 coaching data (commitments, coach chat, fines, social plans and the test week).
// The app no longer uses any of it. The definitions stay, with the same stored properties, so stores
// written by 2.0 still open without a migration, exactly as the retired Meal model is kept.

@Model
final class Commitment {
    @Attribute(.unique) var id: UUID = UUID()
    var day: String = ""
    var title: String = ""
    var detail: String? = nil
    var kindRaw: String = ""
    var stateRaw: String = ""
    var weight: Int = 0
    var scheduledStart: Date? = nil
    var durationMinutes: Int = 0
    var sourceRaw: String = ""
    var routineID: UUID? = nil
    var objectiveRaw: String? = nil
    var reason: String? = nil
    var excuseRaw: String? = nil
    var note: String? = nil
    var assumedMissed: Bool = false
    var createdAt: Date = .distantPast
    var updatedAt: Date = .distantPast
    var approvedAt: Date? = nil

    init() {}
}

@Model
final class CommitmentEvent {
    var id: UUID = UUID()
    var commitmentID: UUID = UUID()
    var fromRaw: String = ""
    var toRaw: String = ""
    var reason: String? = nil
    var actorRaw: String = ""
    var at: Date = .distantPast

    init() {}
}

@Model
final class Routine {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = ""
    var weight: Int = 0
    var weekdayMask: Int = 0
    var minuteOfDay: Int? = nil
    var durationMinutes: Int = 0
    var isEnabled: Bool = false
    var enabledAt: Date? = nil
    var reason: String? = nil
    var createdAt: Date = .distantPast

    init() {}
}

@Model
final class DayRecord {
    @Attribute(.unique) var day: String = ""
    var applicableWeight: Int = 0
    var completedWeight: Int = 0
    var scorePercent: Int? = nil
    var finePence: Int = 0
    var uncappedFinePence: Int = 0
    var finalisedAt: Date? = nil
    var isSimulation: Bool = false
    var explanation: String = ""

    init() {}
}

@Model
final class CoachMessage {
    var id: UUID = UUID()
    var roleRaw: String = ""
    var text: String = ""
    var createdAt: Date = .distantPast
    var quickReplies: [String] = []
    var relatedCommitmentID: UUID? = nil
    var toolSummary: String? = nil

    init() {}
}

@Model
final class MemoryRecord {
    @Attribute(.unique) var id: UUID = UUID()
    var storeRaw: String = ""
    var key: String = ""
    var value: String = ""
    var sourceRaw: String = ""
    var statusRaw: String = ""
    var confidence: Double? = nil
    var sensitivityRaw: String = ""
    var createdAt: Date = .distantPast
    var updatedAt: Date = .distantPast
    var reviewAt: Date? = nil

    init() {}
}

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var areaRaw: String = ""
    var parentID: UUID? = nil
    var dependsOn: [String] = []
    var estimatedMinutes: Int = 0
    var priority: Int = 0
    var stateRaw: String = ""
    var resumeNote: String? = nil
    var sortIndex: Int = 0
    var createdAt: Date = .distantPast
    var updatedAt: Date = .distantPast
    var completedAt: Date? = nil

    init() {}
}

@Model
final class FineLedgerEntry {
    var id: UUID = UUID()
    var day: String = ""
    var month: String = ""
    var beforePence: Int = 0
    var afterPence: Int = 0
    var scorePercent: Int? = nil
    var reason: String = ""
    var isSimulation: Bool = false
    var at: Date = .distantPast

    init() {}
}

@Model
final class MonthStatement {
    @Attribute(.unique) var month: String = ""
    var allocationPence: Int = 0
    var finesPence: Int = 0
    var transferablePence: Int = 0
    var daysScored: Int = 0
    var daysWithFines: Int = 0
    var averageScore: Int? = nil
    var capSavedPence: Int = 0
    var statusRaw: String = ""
    var idempotencyKey: String = ""
    var closedAt: Date = .distantPast
    var confirmedAt: Date? = nil

    init() {}
}

@Model
final class SocialPlan {
    @Attribute(.unique) var eventID: String = ""
    var title: String = ""
    var start: Date = .distantPast
    var end: Date = .distantPast
    var kindRaw: String = ""
    var drinkingRaw: String = ""
    var driving: Bool = false
    var days: Int = 0
    var going: Bool = false
    var preparedSteps: [String] = []
    var createdAt: Date = .distantPast

    init() {}
}

@Model
final class RecoveryPeriod {
    var id: UUID = UUID()
    var startDay: String = ""
    var days: Int = 0
    var feelingRaw: String? = nil
    var endedDay: String? = nil
    var reason: String = ""
    var createdAt: Date = .distantPast

    init() {}
}

@Model
final class GymBusynessRecord {
    var date: Date = .distantPast
    var levelRaw: String = ""

    init() {}
}

@Model
final class OutingSuggestion {
    var ideaID: String = ""
    var day: String = ""
    var accepted: Bool? = nil
    var budget: String? = nil
    var createdAt: Date = .distantPast

    init() {}
}

@Model
final class PlanFeedback {
    var id: UUID = UUID()
    var day: String = ""
    var title: String = ""
    var kindRaw: String = ""
    var proposedStart: Date? = nil
    var reasonRaw: String = ""
    var note: String? = nil
    var at: Date = .distantPast

    init() {}
}

@Model
final class DayCheckIn {
    @Attribute(.unique) var day: String = ""
    var usefulness: Int = 0
    var effort: Int = 0
    var note: String? = nil
    var at: Date = .distantPast

    init() {}
}

@Model
final class PlanAuditRecord {
    var day: String = ""
    var title: String = ""
    var problem: String = ""
    var severityRaw: String = ""
    var at: Date = .distantPast

    init() {}
}
