import Foundation
import SwiftData

/// Phase 8: the test week. Feedback on suggestions, the end-of-day check-in and the shareable report.
extension CoachModel {
    /// Declines a suggestion and records why it was wrong.
    func flagWrong(_ item: Commitment, reason: FeedbackReason, note: String? = nil) {
        context.insert(PlanFeedback(day: today, title: item.title, kind: item.kind, proposedStart: item.scheduledStart,
                                    reason: reason, note: note, at: now()))
        if item.state == .proposed {
            transition(item, .cancel, reason: "Not right: \(reason.title.lowercased())")
        } else {
            save()
        }
    }

    /// The day's check-in, from 7pm until bedtime, once.
    var shouldAskForCheckIn: Bool {
        guard calendar.component(.hour, from: now()) >= 19, now() < today.date(atMinute: coach.bedtimeMinute, calendar: calendar) else {
            return false
        }
        return checkIn(on: today) == nil && defaults.string(forKey: Self.checkInSkippedKey) != today.description
    }

    static let checkInSkippedKey = "validation.checkin.skipped"

    func checkIn(on day: DayKey) -> DayCheckIn? {
        let key = day.description
        return try? context.fetch(FetchDescriptor<DayCheckIn>(predicate: #Predicate { $0.day == key })).first
    }

    func saveCheckIn(usefulness: Usefulness, effort: Effort, note: String?) {
        if let existing = checkIn(on: today) {
            existing.usefulness = usefulness.rawValue
            existing.effort = effort.rawValue
            existing.note = note
        } else {
            context.insert(DayCheckIn(day: today, usefulness: usefulness, effort: effort, note: note, at: now()))
        }
        save()
        reload()
    }

    func skipCheckIn() {
        defaults.set(today.description, forKey: Self.checkInSkippedKey)
        reload()
    }

    /// The test so far, from the project start (or `from`) to today.
    func validationInput(from start: DayKey = RecommendationEngine.projectStart) -> ValidationInput {
        let first = start.description
        let all = allCommitments().filter { $0.day >= first }
        let suggestions = all.filter { $0.source == .coach }.map { item in
            ValidationInput.Suggestion(kind: item.kind, agreed: item.approvedAt != nil,
                                       declined: item.state == .cancelled && item.approvedAt == nil)
        }
        let todayKey = today.description
        let outcomes = all.filter { $0.day < todayKey && $0.state != .proposed }
            .map { ValidationInput.Outcome(state: $0.state, assumedMissed: $0.assumedMissed) }
        let records = ((try? context.fetch(FetchDescriptor<DayCheckIn>())) ?? []).filter { $0.day >= first }
        let checkIns = records.compactMap { record -> ValidationInput.CheckIn? in
            guard let usefulness = Usefulness(rawValue: record.usefulness), let effort = Effort(rawValue: record.effort) else { return nil }
            return ValidationInput.CheckIn(usefulness: usefulness, effort: effort, note: record.note)
        }
        let feedback = ((try? context.fetch(FetchDescriptor<PlanFeedback>())) ?? []).filter { $0.day >= first }
            .sorted { $0.at < $1.at }
            .map { ValidationInput.Feedback(title: $0.title, reason: $0.reason, note: $0.note) }
        let issues = ((try? context.fetch(FetchDescriptor<PlanAuditRecord>())) ?? []).filter { $0.day >= first }
            .sorted { $0.at < $1.at }
            .map { "\($0.day): \($0.title): \($0.problem)" }
        let sent = messages.filter { $0.role == .user }
        let unknown = sent.filter { message in
            if case .unknown = CoachIntentParser.parse(message.text) { return true }
            return false
        }
        return ValidationInput(from: start, to: today, suggestions: suggestions, outcomes: outcomes, checkIns: checkIns,
                               feedback: feedback, issues: issues, messagesSent: sent.count, unknownMessages: unknown.count)
    }

    func validationReport() -> String {
        let input = validationInput()
        let notes = ((try? context.fetch(FetchDescriptor<DayCheckIn>())) ?? [])
            .sorted { $0.day < $1.day }
            .compactMap { record in record.note.flatMap { $0.isEmpty ? nil : "\(record.day): \($0)" } }
        return ValidationSummary(input, calendar: calendar).report(feedback: input.feedback, notes: notes)
    }
}
