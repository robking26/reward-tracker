import Foundation

// Phase 8: real-world validation. A safety net that checks each morning's plan before it's shown, the user's own
// verdicts on suggestions and days, and a plain report to share. Nothing here affects scores or fines.

/// Why a suggestion was wrong, in the user's words (one tap).
enum FeedbackReason: String, Codable, Sendable, CaseIterable, Identifiable {
    case wrongTime, tooMuch, alreadyPlanned, notForMe, weatherOrTravel, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .wrongTime: "Wrong time"
        case .tooMuch: "Too much for today"
        case .alreadyPlanned: "Already had plans"
        case .notForMe: "Not something I'd do"
        case .weatherOrTravel: "Weather or travel was wrong"
        case .other: "Something else"
        }
    }
}

/// A problem found in a plan before it reached the user.
struct PlanIssue: Hashable, Sendable {
    enum Severity: String, Codable, Sendable {
        /// The suggestion is removed: it could never be right (a clash, or while asleep).
        case blocking
        /// Shown, but recorded for review.
        case warning
    }

    var title: String
    var problem: String
    var severity: Severity
}

/// Independent checks on the morning plan. Written separately from the engine so the engine can't mark its own
/// homework: if these ever fire, a recommendation rule is wrong and needs fixing (Phase 8).
enum PlanAuditor {
    /// More than this many suggestions in one morning is too much to take in (design bar §31).
    static let maximumSuggestions = 5

    static func audit(_ plan: [Recommendation], events: [ClassifiedEvent], settings: CoachSettings, day: DayKey,
                      calendar: Calendar, forecast: [HourlyWeather], recovering: Bool) -> [PlanIssue] {
        var issues: [PlanIssue] = []
        let wake = day.date(atMinute: settings.wakeMinute, calendar: calendar)
        let bedtime = day.date(atMinute: settings.bedtimeMinute, calendar: calendar)
        let blocking = events.filter { $0.kind.blocksUser && !$0.event.isAllDay && $0.event.end > $0.event.start }
        for item in plan {
            guard let start = item.start else { continue }
            let interval = DateInterval(start: start, duration: TimeInterval(max(1, item.durationMinutes) * 60))
            if start < wake || interval.end > bedtime {
                issues.append(PlanIssue(title: item.title, problem: "Outside waking hours", severity: .blocking))
            }
            if let clash = blocking.first(where: { event in
                DateInterval(start: event.event.start, end: event.event.end).intersection(with: interval).map { $0.duration > 0 } ?? false
            }) {
                issues.append(PlanIssue(title: item.title, problem: "Clashes with \(clash.kind.label.lowercased())", severity: .blocking))
            }
            if item.kind == .walk, WeatherAdvisor.isDry(interval, forecast: forecast) == false {
                issues.append(PlanIssue(title: item.title, problem: "Rain is forecast then", severity: .warning))
            }
            if recovering, item.kind == .workout || item.kind == .swim {
                issues.append(PlanIssue(title: item.title, problem: "Suggested on a recovery day", severity: .blocking))
            }
            if item.kind == .workout, item.durationMinutes < 60 + 10 + 2 * 5, !item.title.hasPrefix("Easy") {
                issues.append(PlanIssue(title: item.title, problem: "Not enough time for the full trip", severity: .warning))
            }
        }
        let kinds = plan.map(\.kind)
        if Set(kinds).count < kinds.count {
            issues.append(PlanIssue(title: "Morning plan", problem: "The same kind of thing suggested twice", severity: .warning))
        }
        if plan.count > maximumSuggestions {
            issues.append(PlanIssue(title: "Morning plan", problem: "\(plan.count) suggestions is too many at once", severity: .warning))
        }
        return issues
    }

    /// The plan with anything that could never be right taken out.
    static func filtered(_ plan: [Recommendation], issues: [PlanIssue]) -> [Recommendation] {
        let blocked = Set(issues.filter { $0.severity == .blocking }.map(\.title))
        return plan.filter { !blocked.contains($0.title) }
    }
}

/// The user's end-of-day verdict (Phase 8: usefulness and cognitive burden).
enum Usefulness: Int, Codable, Sendable, CaseIterable, Identifiable {
    case notReally = 1, somewhat, very

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .notReally: "Not really"
        case .somewhat: "Somewhat"
        case .very: "Very"
        }
    }
}

enum Effort: Int, Codable, Sendable, CaseIterable, Identifiable {
    case light = 1, fine, tooMuch

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .light: "Light"
        case .fine: "OK"
        case .tooMuch: "Too much"
        }
    }
}

/// Everything the test week report needs, already gathered.
struct ValidationInput: Sendable {
    struct Suggestion: Hashable, Sendable {
        var kind: CommitmentKind
        var agreed: Bool
        var declined: Bool
    }

    struct Outcome: Hashable, Sendable {
        var state: CommitmentState
        var assumedMissed: Bool
    }

    struct CheckIn: Hashable, Sendable {
        var usefulness: Usefulness
        var effort: Effort
        var note: String?
    }

    struct Feedback: Hashable, Sendable {
        var title: String
        var reason: FeedbackReason
        var note: String?
    }

    var from: DayKey
    var to: DayKey
    var suggestions: [Suggestion]
    var outcomes: [Outcome]
    var checkIns: [CheckIn]
    var feedback: [Feedback]
    var issues: [String]
    var messagesSent: Int
    var unknownMessages: Int
}

struct ReasonCount: Hashable, Sendable {
    var reason: FeedbackReason
    var count: Int
}

struct ValidationSummary: Sendable {
    var days: Int
    var suggested: Int
    var agreed: Int
    var declined: Int
    var flaggedWrong: Int
    var reasons: [ReasonCount]
    var done: Int
    var missed: Int
    var assumedMissed: Int
    var excused: Int
    var checkIns: Int
    var averageUsefulness: Double?
    var tooMuchDays: Int
    var issues: [String]
    var unknownMessages: Int
    var messagesSent: Int

    init(_ input: ValidationInput, calendar: Calendar) {
        days = max(1, MealPlanner.daysBetween(input.from, input.to) + 1)
        suggested = input.suggestions.count
        agreed = input.suggestions.filter(\.agreed).count
        declined = input.suggestions.filter(\.declined).count
        flaggedWrong = input.feedback.count
        let grouped = Dictionary(grouping: input.feedback, by: \.reason)
        reasons = FeedbackReason.allCases.compactMap { reason in grouped[reason].map { ReasonCount(reason: reason, count: $0.count) } }
            .sorted { $0.count > $1.count }
        done = input.outcomes.filter { $0.state == .completed }.count
        let missedOutcomes = input.outcomes.filter { $0.state == .missed }
        missed = missedOutcomes.count
        assumedMissed = missedOutcomes.filter(\.assumedMissed).count
        excused = input.outcomes.filter { $0.state == .excused }.count
        checkIns = input.checkIns.count
        averageUsefulness = input.checkIns.isEmpty ? nil
            : Double(input.checkIns.map(\.usefulness.rawValue).reduce(0, +)) / Double(input.checkIns.count)
        tooMuchDays = input.checkIns.filter { $0.effort == .tooMuch }.count
        issues = input.issues
        unknownMessages = input.unknownMessages
        messagesSent = input.messagesSent
    }

    /// What most needs fixing, worst first. Wrong recommendations come before anything else (Phase 8).
    var priorities: [String] {
        var list: [String] = []
        if !issues.isEmpty { list.append("The plan checker found \(issues.count) problem\(issues.count == 1 ? "" : "s") in morning plans.") }
        if let top = reasons.first, top.count >= 2 { list.append("Suggestions were often wrong: \(top.reason.title.lowercased()) (\(top.count)).") }
        if suggested >= 5, agreed * 2 < suggested { list.append("Fewer than half the suggestions were agreed.") }
        if tooMuchDays >= 2 { list.append("\(tooMuchDays) days felt like too much effort.") }
        if missed > 0, assumedMissed * 2 >= missed { list.append("Most misses were unanswered rather than missed.") }
        if messagesSent >= 5, unknownMessages * 4 >= messagesSent { list.append("The coach didn't understand \(unknownMessages) of \(messagesSent) messages.") }
        return list
    }

    /// A plain-text report to share. No calendar event titles, health figures or money.
    func report(feedback: [ValidationInput.Feedback], notes: [String]) -> String {
        var lines = ["Vaultality test report (\(days) day\(days == 1 ? "" : "s"))", ""]
        lines.append("Suggestions: \(suggested) offered, \(agreed) agreed, \(declined) declined, \(flaggedWrong) marked wrong")
        for item in reasons { lines.append("  - \(item.reason.title): \(item.count)") }
        lines.append("Commitments: \(done) done, \(missed) missed (\(assumedMissed) unanswered), \(excused) excused")
        if let average = averageUsefulness {
            lines.append("Daily check-ins: \(checkIns), usefulness \(String(format: "%.1f", average)) of 3, \(tooMuchDays) too-much days")
        } else {
            lines.append("Daily check-ins: none yet")
        }
        lines.append("Coach messages: \(messagesSent) sent, \(unknownMessages) not understood")
        if !issues.isEmpty {
            lines.append("")
            lines.append("Plan checker:")
            issues.forEach { lines.append("  - \($0)") }
        }
        let flagged = feedback.filter { $0.note?.isEmpty == false || $0.reason == .other }
        if !flagged.isEmpty || !notes.isEmpty {
            lines.append("")
            lines.append("Your notes:")
            flagged.forEach { lines.append("  - \($0.title): \($0.reason.title)\($0.note.map { ": \($0)" } ?? "")") }
            notes.forEach { lines.append("  - \($0)") }
        }
        if !priorities.isEmpty {
            lines.append("")
            lines.append("Fix first:")
            priorities.forEach { lines.append("  - \($0)") }
        }
        return lines.joined(separator: "\n")
    }
}
