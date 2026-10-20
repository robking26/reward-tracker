import Foundation
import SwiftData

// Phase 8 entities. All new, so existing stores open with lightweight migration. Kept only on this iPhone.

/// "This suggestion was wrong", with a one-tap reason.
@Model
final class PlanFeedback {
    var id: UUID
    var day: String
    var title: String
    var kindRaw: String
    var proposedStart: Date?
    var reasonRaw: String
    var note: String?
    var at: Date

    init(day: DayKey, title: String, kind: CommitmentKind, proposedStart: Date?, reason: FeedbackReason, note: String?, at: Date) {
        id = UUID()
        self.day = day.description
        self.title = title
        kindRaw = kind.rawValue
        self.proposedStart = proposedStart
        reasonRaw = reason.rawValue
        self.note = note
        self.at = at
    }

    var reason: FeedbackReason { FeedbackReason(rawValue: reasonRaw) ?? .other }
}

/// One end-of-day answer: how useful the plan was, and how much effort the app took.
@Model
final class DayCheckIn {
    @Attribute(.unique) var day: String
    var usefulness: Int
    var effort: Int
    var note: String?
    var at: Date

    init(day: DayKey, usefulness: Usefulness, effort: Effort, note: String?, at: Date) {
        self.day = day.description
        self.usefulness = usefulness.rawValue
        self.effort = effort.rawValue
        self.note = note
        self.at = at
    }
}

/// Something the plan checker caught before it reached the user.
@Model
final class PlanAuditRecord {
    var day: String
    var title: String
    var problem: String
    var severityRaw: String
    var at: Date

    init(day: DayKey, issue: PlanIssue, at: Date) {
        self.day = day.description
        title = issue.title
        problem = issue.problem
        severityRaw = issue.severity.rawValue
        self.at = at
    }
}
