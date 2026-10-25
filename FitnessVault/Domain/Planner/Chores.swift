import Foundation

/// A job from your list: how long it roughly takes, whether it's outside, and whether it's done or booked.
struct Chore: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var minutes: Int
    var outdoor: Bool
    var createdAt: Date
    var doneAt: Date? = nil
    /// Added to your calendar for this day, so it isn't suggested again.
    var bookedOn: DayKey? = nil

    var isOpen: Bool { doneAt == nil && bookedOn == nil }
}

/// Turns a written list into chores with a time estimate, from what the words usually mean.
enum ChoreEstimator {
    private struct Rule {
        var words: [String]
        var minutes: Int
        var outdoor: Bool
    }

    // First match wins, so the more specific phrases come first.
    private static let rules: [Rule] = [
        Rule(words: ["mow", "lawn", "grass", "strim"], minutes: 45, outdoor: true),
        Rule(words: ["weed", "garden", "hedge", "prune", "plant", "borders", "leaves", "rake"], minutes: 45, outdoor: true),
        Rule(words: ["wash the car", "wash car", "car wash", "valet"], minutes: 40, outdoor: true),
        Rule(words: ["patio", "decking", "jet wash", "pressure wash", "gutters", "shed", "fence"], minutes: 60, outdoor: true),
        Rule(words: ["bins", "bin out", "recycling"], minutes: 5, outdoor: true),
        Rule(words: ["clean bathroom", "bathroom", "toilet", "shower clean", "en suite", "ensuite"], minutes: 30, outdoor: false),
        Rule(words: ["kitchen deep", "oven"], minutes: 45, outdoor: false),
        Rule(words: ["hoover", "vacuum"], minutes: 30, outdoor: false),
        Rule(words: ["mop", "floors"], minutes: 25, outdoor: false),
        Rule(words: ["iron"], minutes: 30, outdoor: false),
        Rule(words: ["change beds", "change the beds", "bedding", "sheets"], minutes: 20, outdoor: false),
        Rule(words: ["windows"], minutes: 30, outdoor: false),
        Rule(words: ["dust"], minutes: 20, outdoor: false),
        Rule(words: ["fridge", "freezer"], minutes: 20, outdoor: false),
        Rule(words: ["wardrobe", "declutter", "loft", "garage", "sort out"], minutes: 60, outdoor: false),
        Rule(words: ["washing", "laundry", "wash on", "fold"], minutes: 15, outdoor: false),
        Rule(words: ["dishes", "washing up", "dishwasher"], minutes: 15, outdoor: false),
        Rule(words: ["tidy"], minutes: 15, outdoor: false),
        Rule(words: ["email", "call", "phone", "book", "pay", "renew", "order", "post"], minutes: 10, outdoor: false),
        Rule(words: ["fix", "repair", "paint", "assemble", "flat pack", "put up", "shelf"], minutes: 60, outdoor: false),
    ]

    /// A rough time and whether it needs dry weather. "(30 min)" or "45m" in the text wins over the guess.
    static func estimate(_ title: String) -> (minutes: Int, outdoor: Bool) {
        let lowered = title.lowercased()
        let rule = rules.first { rule in rule.words.contains { lowered.contains($0) } }
        let minutes = statedMinutes(lowered) ?? rule?.minutes ?? 20
        return (minutes, rule?.outdoor ?? false)
    }

    private static func statedMinutes(_ text: String) -> Int? {
        if let match = text.range(of: #"(\d+)\s*(h|hr|hrs|hour|hours)\b"#, options: .regularExpression),
           let value = Int(text[match].filter(\.isNumber)) {
            return value * 60
        }
        if let match = text.range(of: #"(\d+)\s*(m|min|mins|minutes)\b"#, options: .regularExpression),
           let value = Int(text[match].filter(\.isNumber)) {
            return value
        }
        return nil
    }

    /// One chore per line; bullets, numbers and empty lines are ignored.
    static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let cleaned = String(line)
                .replacingOccurrences(of: #"^\s*(?:[-•*·–]|\d+[.)])\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return cleaned.isEmpty ? nil : cleaned
        }
    }
}

enum ChoreBatcher {
    /// Outdoor jobs on their own (they need the weather); indoor ones grouped, in list order, up to `maxMinutes`
    /// a batch. With batching off, everything is on its own.
    static func bundles(_ chores: [Chore], batch: Bool, maxMinutes: Int) -> [[Chore]] {
        var result: [[Chore]] = []
        var current: [Chore] = []
        var currentMinutes = 0
        for chore in chores {
            if chore.outdoor || !batch {
                result.append([chore])
                continue
            }
            if !current.isEmpty && currentMinutes + chore.minutes > maxMinutes {
                result.append(current)
                current = []
                currentMinutes = 0
            }
            current.append(chore)
            currentMinutes += chore.minutes
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
