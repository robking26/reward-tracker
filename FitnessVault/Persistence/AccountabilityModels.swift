import Foundation
import SwiftData

// Phase 5 accountability entities. All new, so existing stores open with lightweight migration.

/// Append-only: every time a day's fine is set or changed, with why (A8). Never edited or deleted by the app.
@Model
final class FineLedgerEntry {
    var id: UUID
    var day: String
    var month: String
    var beforePence: Int
    var afterPence: Int
    var scorePercent: Int?
    var reason: String
    var isSimulation: Bool
    var at: Date

    init(day: DayKey, change: FineChange, scorePercent: Int?, isSimulation: Bool, at: Date) {
        id = UUID()
        self.day = day.description
        month = day.monthKey.description
        beforePence = change.before.value
        afterPence = change.after.value
        self.scorePercent = scorePercent
        reason = change.reason
        self.isSimulation = isSimulation
        self.at = at
    }

    var dayKey: DayKey? { DayKey(string: day) }
    var before: Pence { Pence(beforePence) }
    var after: Pence { Pence(afterPence) }
    var delta: Pence { after - before }
}

enum StatementStatus: String, Codable, Sendable {
    /// Closed during the trial: nothing moved.
    case simulated
    /// Closed; waiting for the user to move the money themselves.
    case awaitingManualTransfer
    /// The user said they moved it.
    case manuallyTransferred
}

/// A closed month: frozen numbers and what happens to the money (A3). One per month.
@Model
final class MonthStatement {
    @Attribute(.unique) var month: String
    var allocationPence: Int
    var finesPence: Int
    var transferablePence: Int
    var daysScored: Int
    var daysWithFines: Int
    var averageScore: Int?
    var capSavedPence: Int
    var statusRaw: String
    var idempotencyKey: String
    var closedAt: Date
    var confirmedAt: Date?

    init(summary: MonthStatementSummary, plan: TransferPlan, closedAt: Date) {
        month = summary.month.description
        allocationPence = summary.allocation.value
        finesPence = summary.fines.value
        transferablePence = summary.transferable.value
        daysScored = summary.daysScored
        daysWithFines = summary.daysWithFines
        averageScore = summary.averageScore
        capSavedPence = summary.capSaved.value
        statusRaw = (plan.mode == .simulated ? StatementStatus.simulated : .awaitingManualTransfer).rawValue
        idempotencyKey = plan.idempotencyKey
        self.closedAt = closedAt
    }

    var monthKey: MonthKey? { MonthKey(string: month) }
    var status: StatementStatus {
        get { StatementStatus(rawValue: statusRaw) ?? .simulated }
        set { statusRaw = newValue.rawValue }
    }
    var allocation: Pence { Pence(allocationPence) }
    var fines: Pence { Pence(finesPence) }
    var transferable: Pence { Pence(transferablePence) }
    var plan: TransferPlan? {
        monthKey.map { TransferPlan(month: $0, amount: transferable, mode: status == .simulated ? .simulated : .manual) }
    }
}
