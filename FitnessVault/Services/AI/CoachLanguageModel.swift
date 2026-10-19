import Foundation

/// Whether a language model can be used right now (scenario N).
enum CoachAIStatus: Equatable, Sendable {
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }

    var title: String {
        switch self {
        case .available: "On-device (Apple Intelligence)"
        case .unavailable(let reason): reason
        }
    }
}

/// The abstract AI provider (AI1). Today: Apple's on-device model. Anything that changes data goes through
/// `CoachToolbox`, which validates every argument; the model never touches the store or money directly (AI3).
@MainActor
protocol CoachLanguageModel: AnyObject {
    var status: CoachAIStatus { get }
    /// Answers one message. `context` is a compact summary built by the app; `toolbox` performs validated actions.
    func reply(to message: String, context: String, toolbox: CoachToolbox) async throws -> String
}

enum CoachAI {
    /// Apple's on-device model where the SDK and device support it; otherwise none (rule-based coach only).
    /// Nonisolated so it can be a default argument.
    static func makeDefault() -> CoachLanguageModel? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FoundationModelsCoach()
        }
        #endif
        return nil
    }

    static let instructions = """
    You are Vaultality, a personal coach for one person in the UK. Write natural British English.
    Be direct, firm, warm and brief: one to three short sentences. Ask at most one question. No speeches, no generic praise.
    Use the tools to change anything. Never say you added, moved, saved, booked or completed something unless a tool replied "OK".
    Suggestions you make with suggestCommitment only count if the user agrees, so ask.
    You cannot move money or apply fines. Don't bring up fines unless asked.
    Don't diagnose. For pain, swelling or illness, suggest rest and the physio or GP.
    Never suggest gambling. Food: no restriction, fasting or moralising. Respect foods the user never eats.
    Becky is the user's wife. Never give her tasks or judge her.
    A blank calendar slot in working hours is work time, not free time.
    If you don't know something, say so plainly.
    """
}

/// Validated actions the model may take (AI3). Each returns a short result the model reads; only successful
/// actions are recorded in `performed`, which is what the user sees as "what changed".
@MainActor
final class CoachToolbox {
    private unowned let coach: CoachModel
    private(set) var performed: [String] = []
    private(set) var suggestedReplies: [String] = []

    init(coach: CoachModel) {
        self.coach = coach
    }

    func addTask(title: String, minutes: Int) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...120).contains(clean.count) else { return "Not done: the title must be 2 to 120 characters." }
        guard (5...480).contains(minutes) else { return "Not done: minutes must be between 5 and 480." }
        let titled = clean.prefix(1).uppercased() + clean.dropFirst()
        let area = SeedProfile.area(forTask: titled)
        let task = TaskItem(title: titled, area: area, estimatedMinutes: minutes,
                            sortIndex: (coach.allTasks().map(\.sortIndex).max() ?? 0) + 1)
        coach.context.insert(task)
        coach.save()
        performed.append("Added to your list: \(titled)")
        return "OK: added '\(titled)' to the \(area.title.lowercased()) list."
    }

    /// Creates a *proposed* commitment. It only counts if the user agrees.
    func suggestCommitment(title: String, kind: String, startTime: String, minutes: Int) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(clean.count) else { return "Not done: the title must be 2 to 80 characters." }
        guard (5...240).contains(minutes) else { return "Not done: minutes must be between 5 and 240." }
        let commitmentKind = CommitmentKind(rawValue: kind) ?? .other
        var start: Date?
        if !startTime.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let parsed = ToolParsing.time(startTime, on: coach.today, calendar: coach.calendar) else {
                return "Not done: startTime must be HH:mm, e.g. 17:30."
            }
            guard parsed > coach.now() else { return "Not done: that time has already passed." }
            let bedtime = coach.today.startDate(calendar: coach.calendar).addingTimeInterval(TimeInterval(coach.coach.bedtimeMinute * 60))
            guard parsed.addingTimeInterval(TimeInterval(minutes * 60)) <= bedtime else { return "Not done: that runs past bedtime." }
            let interval = DateInterval(start: parsed, duration: TimeInterval(minutes * 60))
            if let clash = coach.events.first(where: { $0.kind.blocksUser && DateInterval(start: $0.event.start, end: max($0.event.start, $0.event.end)).intersection(with: interval).map { $0.duration > 0 } ?? false }) {
                return "Not done: it clashes with \(clash.event.title) (\(clash.kind.label.lowercased()))."
            }
            start = parsed
        }
        let item = coach.propose(clean, kind: commitmentKind, start: start, durationMinutes: minutes, reason: "Suggested in conversation.")
        item.detail = "\(clean)\(start.map { " at \(coach.time($0))" } ?? "")?"
        performed.append("Suggested: \(clean)\(start.map { " at \(coach.time($0))" } ?? "")")
        suggestedReplies = ["Yes", "No thanks"]
        return "OK: suggested. It only counts if the user says yes, so ask them."
    }

    /// Acts on the current commitment for the user. Excuses only for legitimate reasons (A6, D-013).
    func updateCurrent(action: String, reason: String) -> String {
        guard let current = coach.currentAction else { return "Not done: nothing is agreed right now." }
        switch action {
        case "done":
            guard coach.transition(current, .complete) else { return "Not done: \(coach.lastError ?? "not allowed")." }
            performed.append("Marked done: \(current.title)")
            return "OK: \(current.title) is done."
        case "start":
            guard coach.transition(current, .start) else { return "Not done: \(coach.lastError ?? "not allowed")." }
            performed.append("Started: \(current.title)")
            return "OK: started \(current.title)."
        case "excuse":
            guard let excuse = ToolParsing.excuse(reason) else {
                return "Not done: excuses are only for illness, injury, rest, sleep, an unavoidable clash or something outside their control. Not fancying it isn't one."
            }
            guard coach.transition(current, .excuse(excuse), reason: excuse.title) else { return "Not done: \(coach.lastError ?? "not allowed")." }
            performed.append("Excused: \(current.title) (\(excuse.title))")
            return "OK: \(current.title) won't count against today."
        default:
            return "Not done: action must be done, start or excuse."
        }
    }

    /// Remembers something. A guess is stored as a hypothesis, never as fact (M3).
    func remember(topic: String, fact: String, userSaidIt: Bool) -> String {
        let key = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...60).contains(key.count), (2...300).contains(value.count) else {
            return "Not done: topic must be 2 to 60 characters and the fact 2 to 300."
        }
        coach.remember(value, key: key.prefix(1).uppercased() + key.dropFirst(), in: .preference,
                       source: userSaidIt ? .userStated : .inferred)
        performed.append(userSaidIt ? "Remembered: \(key)" : "Noted as a guess: \(key)")
        return "OK: remembered."
    }

    func freeTime(minutes: Int) -> String {
        let fits = coach.windows.filter { $0.kind != .workGap && $0.minutes >= max(5, minutes) }
        guard !fits.isEmpty else { return "No free stretch of \(minutes) minutes left today outside work." }
        return fits.prefix(4).map { "\(coach.time($0.interval.start))–\(coach.time($0.interval.end))\($0.kind == .lunch ? " (lunch)" : "")" }
            .joined(separator: ", ")
    }

    func listTasks() -> String {
        let tasks = coach.opportunityTasks(minutes: 480)
        guard !tasks.isEmpty else { return "The list is empty." }
        return tasks.map { "\($0.title) (\($0.estimatedMinutes) min)" }.joined(separator: "; ")
    }
}

/// Parsing helpers for tool arguments. Pure, so they're unit tested.
enum ToolParsing {
    /// "17:30", "5:30pm", "9am" → that time on `day`.
    static func time(_ text: String, on day: DayKey, calendar: Calendar) -> Date? {
        let lowered = text.lowercased().replacingOccurrences(of: " ", with: "")
        let isPM = lowered.hasSuffix("pm"), isAM = lowered.hasSuffix("am")
        let digits = (isPM || isAM) ? String(lowered.dropLast(2)) : lowered
        let parts = digits.split(separator: ":").map(String.init)
        guard let hourValue = parts.first.flatMap({ Int($0) }) else { return nil }
        let minute = parts.count > 1 ? Int(parts[1]) ?? -1 : 0
        var hour = hourValue
        if isPM && hour < 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        guard (0...23).contains(hour), (0...59).contains(minute), parts.count <= 2 else { return nil }
        return day.startDate(calendar: calendar).addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    static func excuse(_ text: String) -> ExcuseReason? {
        let lowered = text.lowercased()
        if lowered.range(of: "\\b(ill|illness|unwell)\\b", options: .regularExpression) != nil || lowered.contains("sick") {
            return .illness
        }
        if lowered.contains("injur") || lowered.contains("knee") || lowered.contains("pain") { return .injurySymptoms }
        if lowered.contains("rest") || lowered.contains("recover") || lowered.contains("exhaust") { return .restOrRecovery }
        if lowered.contains("sleep") { return .sleep }
        if lowered.contains("clash") || lowered.contains("conflict") || lowered.contains("meeting") || lowered.contains("unavoidable") {
            return .calendarConflict
        }
        if lowered.contains("outside") || lowered.contains("control") { return .outsideControl }
        return nil
    }
}

/// Catches a reply that claims a change when no tool made one, so the user is never told something
/// was saved when it wasn't (N3).
enum ClaimGuard {
    static func claimsAChange(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let claims = ["i've added", "i have added", "i've saved", "i have saved", "i've booked", "i've scheduled",
                      "i have scheduled", "i've moved", "i have moved", "i've marked", "i've put", "added it",
                      "added that", "i've set", "i've updated", "i've cancelled", "i've removed", "i've noted", "noted that"]
        return claims.contains { lowered.contains($0) }
    }
}
