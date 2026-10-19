import Foundation
import SwiftData

/// Phase 5: the fine ledger, month close and statements, the simulated transfer and the trial review.
/// No code here talks to a bank. A live month only produces an instruction the user carries out themselves (D-030).
extension CoachModel {
    // MARK: Months

    func isClosed(_ month: MonthKey) -> Bool {
        statement(for: month) != nil
    }

    func statement(for month: MonthKey) -> MonthStatement? {
        let key = month.description
        return try? context.fetch(FetchDescriptor<MonthStatement>(predicate: #Predicate { $0.month == key })).first
    }

    func statements() -> [MonthStatement] {
        ((try? context.fetch(FetchDescriptor<MonthStatement>())) ?? []).sorted { $0.month > $1.month }
    }

    /// Months that have any scored day, newest first, including this one.
    func accountabilityMonths() -> [MonthKey] {
        let records = (try? context.fetch(FetchDescriptor<DayRecord>())) ?? []
        var months = Set(records.compactMap { $0.dayKey?.monthKey })
        months.insert(today.monthKey)
        return months.sorted(by: >)
    }

    func scoredDays(in month: MonthKey) -> [ScoredDay] {
        dayRecords(in: month).compactMap { record in
            guard record.finalisedAt != nil, let day = record.dayKey else { return nil }
            return ScoredDay(day: day, scorePercent: record.scorePercent, fine: record.fine, uncappedFine: Pence(record.uncappedFinePence))
        }
    }

    /// The month so far, or its frozen numbers once closed.
    func monthSummary(_ month: MonthKey) -> MonthStatementSummary {
        MonthStatementSummary(month: month, days: scoredDays(in: month), allocation: settings.monthlyAllocation,
                              schedule: coach.fineSchedule)
    }

    /// Closes every earlier month whose verification window has passed (D-029). Idempotent: one statement per month.
    func closeMonthsIfDue() {
        let records = (try? context.fetch(FetchDescriptor<DayRecord>())) ?? []
        let months = Set(records.compactMap { $0.dayKey?.monthKey }).filter { $0 < today.monthKey }
        for month in months.sorted() where !isClosed(month) && MonthCloseRule.canClose(month, today: today) {
            recomputeDayRecords(for: month)
            let summary = monthSummary(month)
            let plan = TransferPlan(month: month, amount: summary.transferable, mode: coach.finesAreSimulated ? .simulated : .manual)
            context.insert(MonthStatement(summary: summary, plan: plan, closedAt: now()))
            let mode = coach.finesAreSimulated ? "simulated, nothing moved" : "waiting for you to move it"
            context.insert(AuditEvent(kind: "month.closed",
                                      message: "\(month) closed: \(summary.fines.formatted()) fines, \(summary.transferable.formatted()) to transfer (\(mode)).",
                                      relatedID: plan.idempotencyKey))
        }
        save()
    }

    /// The user says they moved the money themselves. Only for a live month; recorded once.
    @discardableResult
    func confirmManualTransfer(_ statement: MonthStatement) -> Bool {
        guard statement.status == .awaitingManualTransfer else { return false }
        statement.status = .manuallyTransferred
        statement.confirmedAt = now()
        context.insert(AuditEvent(kind: "month.transfer.confirmed",
                                  message: "You confirmed moving \(statement.transferable.formatted()) from Starling to Monzo for \(statement.month).",
                                  relatedID: statement.idempotencyKey))
        save()
        reload()
        return true
    }

    // MARK: Ledger and audit (A8)

    func fineLedger(in month: MonthKey) -> [FineLedgerEntry] {
        let key = month.description
        return ((try? context.fetch(FetchDescriptor<FineLedgerEntry>(predicate: #Predicate { $0.month == key }))) ?? [])
            .sorted { $0.at > $1.at }
    }

    func accountabilityAudit() -> [AuditEvent] {
        ((try? context.fetch(FetchDescriptor<AuditEvent>())) ?? [])
            .filter { $0.kind.hasPrefix("month.") || $0.kind.hasPrefix("fines.") }
            .sorted { $0.date > $1.date }
    }

    // MARK: Trial review (A7)

    func trialReview() -> TrialReview {
        let days = accountabilityMonths().flatMap { scoredDays(in: $0) }
        let todayKey = today.description
        let outcomes = allCommitments().filter { $0.day < todayKey && $0.state.isApplicable }
            .map { TrialReview.Outcome(kind: $0.kind, state: $0.state, assumedMissed: $0.assumedMissed) }
        let excused = allCommitments().filter { $0.day < todayKey && $0.state == .excused }
            .map { TrialReview.Outcome(kind: $0.kind, state: $0.state, assumedMissed: false) }
        return TrialReview(days: days, outcomes: outcomes + excused, schedule: coach.fineSchedule)
    }

    /// After the review, fines can count for real with transfers made by hand; or go back to the trial.
    /// Never enables automatic payments (D-030).
    func setFinesLive(_ live: Bool) {
        guard live != !coach.finesAreSimulated else { return }
        settingsStore.settings.coach.finesAreSimulated = !live
        context.insert(AuditEvent(kind: "fines.mode",
                                  message: live ? "Fines switched to live after the trial review. Transfers are made by you, by hand."
                                                : "Fines switched back to the trial. Nothing real happens.",
                                  relatedID: nil))
        save()
        reload()
    }
}
