import Foundation

/// A local notification the app intends to schedule. Pure data, so the plan is unit tested.
struct PlannedNotification: Hashable, Sendable {
    var id: String
    var date: Date
    var body: String
    /// In the office: no sound, delivered quietly (S2).
    var isDiscreet: Bool
}

/// The minimum about a commitment needed to remind about it.
struct NotifiableCommitment: Hashable, Sendable {
    var id: UUID
    var title: String
    var kind: CommitmentKind
    var start: Date
    var state: CommitmentState
}

/// Contextual reminders with firmness that rises only for agreed, actionable commitments (NO1–NO2).
/// Never during meetings, focus blocks, quiet hours or sleep, and never more than three per commitment.
enum NotificationPlanner {
    static let prefix = "commitment."
    /// iOS allows 64 pending; leave room for others.
    static let maximum = 40

    /// Minutes before the start for the first nudge.
    static func lead(_ kind: CommitmentKind) -> Int {
        switch kind {
        case .workout, .swim: 15
        default: 5
        }
    }

    /// Minutes after the start when it's realistically too late.
    static func grace(_ kind: CommitmentKind) -> Int {
        switch kind {
        case .workout, .swim: 30
        case .walk: 20
        case .household, .rehab, .selfCare: 30
        default: 20
        }
    }

    static func plan(_ commitments: [NotifiableCommitment], blocks: [BusyBlock], now: Date,
                     quietFrom bedtime: Date, quietUntil wake: Date, office: Bool) -> [PlannedNotification] {
        let protected = blocks.filter { [.workMeeting, .workFocus, .personal].contains($0.kind) }.map(\.interval)
        var result: [PlannedNotification] = []
        for item in commitments where item.state == .approved {
            let candidates: [(Int, Date, String)] = [
                (1, item.start.addingTimeInterval(-TimeInterval(lead(item.kind) * 60)), first(item)),
                (2, item.start.addingTimeInterval(TimeInterval((grace(item.kind) - 15) * 60)), "You've got 15 minutes before \(lower(item)) gets difficult. Let's get moving."),
                (3, item.start.addingTimeInterval(TimeInterval(grace(item.kind) * 60)), "You're about to miss \(lower(item)) you agreed to. Is there a genuine blocker, or are we going?"),
            ]
            var lastDate: Date?
            for (level, date, body) in candidates {
                // Skip a follow-up that would land on or before the previous one (short grace periods).
                if let lastDate, date <= lastDate { continue }
                guard date > now, date >= wake, date < bedtime else { continue }
                guard !protected.contains(where: { $0.contains(date) && $0.end != date }) else { continue }
                result.append(PlannedNotification(id: "\(prefix)\(item.id.uuidString).\(level)", date: date, body: body,
                                                  isDiscreet: office))
                lastDate = date
            }
        }
        return Array(result.sorted { $0.date < $1.date }.prefix(maximum))
    }

    private static func first(_ item: NotifiableCommitment) -> String {
        switch item.kind {
        case .walk: "Five minutes until your walk. Finish what you're doing."
        case .workout: "Your gym window starts soon. Kit ready?"
        case .swim: "Swim soon. Bag packed?"
        case .rehab: "Exercises in five minutes."
        case .selfCare: "Wind-down in five minutes. Phone down soon."
        default: "\(item.title) in five minutes."
        }
    }

    /// "the walk", "the workout", or "<title>" for everything else.
    private static func lower(_ item: NotifiableCommitment) -> String {
        switch item.kind {
        case .walk: "the walk"
        case .workout: "the workout"
        case .swim: "the swim"
        case .rehab: "your exercises"
        case .selfCare: "your wind-down"
        default: item.title.lowercased()
        }
    }
}

// MARK: - Memory retrieval (M1, AI context)

/// A memory reduced to what retrieval needs.
struct MemoryItem: Hashable, Sendable {
    var store: MemoryStore
    var key: String
    var value: String
    var status: MemoryStatus
}

/// Picks the few memories relevant to a message, so the on-device model gets a small, focused context
/// instead of everything the coach knows.
enum MemoryRetriever {
    static func relevant(_ items: [MemoryItem], to message: String, limit: Int = 6) -> [MemoryItem] {
        let words = stems(message)
        let scored: [(MemoryItem, Int, Int)] = items.enumerated().compactMap { index, item in
            guard item.status != .superseded else { return nil }
            let overlap = words.intersection(stems(item.key + " " + item.value)).count
            let keyHit = words.intersection(stems(item.key)).isEmpty ? 0 : 2
            let score = overlap + keyHit
            return score > 0 ? (item, score, index) : nil
        }
        return scored.sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }.prefix(limit).map { $0.0 }
    }

    /// Lowercased word stems of three letters or more (first five characters), ignoring common words.
    static func stems(_ text: String) -> Set<String> {
        let stop: Set<String> = ["the", "and", "for", "you", "are", "can", "not", "but", "was", "its", "our", "get",
                                 "has", "had", "how", "who", "why", "any", "all", "out", "too", "now", "yes",
                                 "that", "this", "with", "have", "what", "when", "your", "from", "will", "just",
                                 "about", "there", "they", "them", "then", "than", "into", "some", "more", "much"]
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        return Set(words.filter { $0.count >= 3 && !stop.contains($0) }.map { String($0.prefix(5)) })
    }
}
