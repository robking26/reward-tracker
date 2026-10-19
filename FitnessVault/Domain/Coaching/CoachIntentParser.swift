import Foundation

/// What the user asked the coach to do. The deterministic parser recognises the core commands so the
/// coach still works with no language model at all (AI3, scenario N).
enum CoachIntent: Equatable, Sendable {
    case whatsNext
    case ready
    case done
    case start
    case notNow
    case blocked
    case park
    case back
    case bored
    case dontFancy
    case unavoidable
    case moveLater(minutes: Int)
    case moveToEvening
    case yes
    case nextStep
    case imIn
    case no
    case unwell(ExcuseReason)
    case addTask(String)
    case ranOut(String)
    /// "We've got three portions of curry left": a conversational inventory correction (I4).
    case haveLeft(portions: Int?, item: String)
    case addToShopping(String)
    case whatsForDinner
    case forgotDefrost
    case defrosted
    case dinnerNotReady
    case unknown(String)
}

enum CoachIntentParser {
    static func parse(_ raw: String) -> CoachIntent {
        let text = normalise(raw)
        guard !text.isEmpty else { return .unknown(raw) }

        // Commands that carry content come first, so "add done laundry" isn't read as "done".
        if let item = capture(text, prefixes: ["put ", "add ", "can you add "],
                              suffixes: [" on the shopping list", " on my shopping list", " to the shopping list", " to my shopping list",
                                         " to the shopping", " to shopping", " on the shopping"]) {
            return .addToShopping(item)
        }
        if text.hasPrefix("we need "), !text.hasPrefix("we need to "), let item = capture(text, prefixes: ["we need "], suffixes: []) {
            return .addToShopping(item)
        }
        if contains(text, ["forgot to defrost", "forgot to take", "didn't defrost", "didnt defrost", "not defrosted", "isn't defrosted",
                           "isnt defrosted", "still frozen"]) {
            return .forgotDefrost
        }
        if matches(text, ["it's defrosted", "its defrosted", "it's defrosting", "its defrosting", "moved it to the fridge",
                          "it's in the fridge", "its in the fridge", "defrosted"]) {
            return .defrosted
        }
        if contains(text, ["nothing for dinner", "nothing in for dinner", "nothing in for tea", "nothing for tea", "no dinner",
                           "dinner isn't ready", "dinner isnt ready", "haven't got anything for dinner", "havent got anything for dinner",
                           "don't have the ingredients", "dont have the ingredients", "missing ingredients", "can't be bothered to cook",
                           "cant be bothered to cook"]) {
            return .dinnerNotReady
        }
        if matches(text, ["what's for dinner", "whats for dinner", "what's for tea", "whats for tea", "what are we having for dinner",
                          "what are we having tonight", "what's for dinner tonight", "dinner tonight"]) {
            return .whatsForDinner
        }
        if let groups = RegexHelper.firstMatch(#"^(?:we've got|we have got|we've|we have|there's|there are|there is|got) (\w+) (?:portions?|bags?|tubs?|packs?|tins?|boxes?) of (.+?)(?: left)?(?: in the freezer)?$"#, in: text),
           groups.count == 2, let count = number(groups[0]) {
            return .haveLeft(portions: count, item: groups[1])
        }
        if let item = capture(text, prefixes: ["we've got ", "we have got ", "we have ", "we've still got ", "there's still "], suffixes: []),
           FoodCatalogue.match(item) != nil {
            return .haveLeft(portions: nil, item: item.replacingOccurrences(of: " left", with: ""))
        }
        if let task = capture(text, prefixes: ["put ", "add ", "remind me to ", "i need to ", "can you add "],
                              suffixes: [" on my list", " on the list", " to my list", " to the list", " to my to do list"]) {
            return .addTask(task)
        }
        if let task = capture(text, prefixes: ["remind me to ", "add a task to ", "new task "], suffixes: []) {
            return .addTask(task)
        }
        if let item = capture(text, prefixes: ["we've run out of ", "we have run out of ", "we've ran out of ", "run out of ",
                                               "we're out of ", "we are out of ", "out of ", "i used the last ", "we used the last "],
                              suffixes: []) {
            return .ranOut(item)
        }

        if matches(text, ["my knee hurts", "knee pain", "knee is sore", "knee's sore", "my knee", "knee hurts", "injured", "pain in my knee"]) {
            return .unwell(.injurySymptoms)
        }
        if matches(text, ["i'm ill", "im ill", "i'm sick", "im sick", "feel ill", "feeling ill", "feel sick", "feeling sick",
                          "i've got a cold", "ive got a cold", "i have a cold", "got covid", "migraine", "temperature"]) {
            return .unwell(.illness)
        }
        if matches(text, ["exhausted", "wiped out", "need to rest", "need rest", "knackered", "shattered"]) {
            return .unwell(.restOrRecovery)
        }

        if matches(text, ["something unavoidable came up", "something came up", "a meeting came up", "meeting came up",
                          "can't make it", "cant make it", "it's out of my control", "its out of my control", "outside my control"]) {
            return .unavoidable
        }
        if matches(text, ["in an hour", "in 1 hour", "an hour later"]) { return .moveLater(minutes: 60) }
        if matches(text, ["in half an hour", "in 30 minutes", "in 30 mins"]) { return .moveLater(minutes: 30) }
        if matches(text, ["in 15 minutes", "in 15 mins", "in a bit"]) { return .moveLater(minutes: 15) }
        if matches(text, ["this evening", "tonight", "after work"]) { return .moveToEvening }
        if matches(text, ["next step", "then what", "and then", "what's the next step", "whats the next step"]) {
            return .nextStep
        }
        if matches(text, ["i'm in", "im in", "i'm going", "im going", "on my way", "i've started", "ive started", "i'm on my way"]) {
            return .imIn
        }
        if matches(text, ["yes", "yeah", "yep", "ok", "okay", "sure", "go on", "deal", "sounds good", "let's do it", "lets do it"]) {
            return .yes
        }
        if matches(text, ["no", "nope", "no thanks", "not today"]) { return .no }

        if matches(text, ["what's next", "whats next", "what next", "what now", "what should i do", "what do i do", "next"]) {
            return .whatsNext
        }
        if matches(text, ["i'm ready", "im ready", "ready", "i am ready"]) { return .ready }
        if matches(text, ["i'm back", "im back", "back", "i am back", "back now"]) { return .back }
        if matches(text, ["park this", "park it", "park that", "pause this", "pause", "stop here"]) { return .park }
        if matches(text, ["not now", "later", "not yet", "maybe later"]) { return .notNow }
        if matches(text, ["something's blocking me", "somethings blocking me", "something is blocking me", "i'm blocked",
                          "im blocked", "blocked", "i'm stuck", "im stuck", "stuck"]) {
            return .blocked
        }
        if matches(text, ["i'm bored", "im bored", "bored", "nothing to do"]) { return .bored }
        if matches(text, ["i don't fancy", "i dont fancy", "don't fancy", "dont fancy", "don't feel like", "dont feel like",
                          "can't be bothered", "cant be bothered", "skip it", "skip the gym", "i don't want to", "i dont want to"]) {
            return .dontFancy
        }
        if matches(text, ["done", "i'm done", "im done", "finished", "did it", "all done", "completed", "that's done", "thats done"]) {
            return .done
        }
        if matches(text, ["start", "starting", "let's go", "lets go", "going now", "on it", "starting now"]) {
            return .start
        }
        return .unknown(raw)
    }

    /// "three" → 3, "3" → 3.
    static func number(_ word: String) -> Int? {
        if let value = Int(word) { return value }
        let words = ["no": 0, "none": 0, "one": 1, "a": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                     "eight": 8, "nine": 9, "ten": 10, "a couple": 2, "couple": 2]
        return words[word]
    }

    /// The phrase appears anywhere in the message.
    private static func contains(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    /// Lowercased, curly apostrophes straightened, trailing punctuation and spaces removed.
    static func normalise(_ raw: String) -> String {
        var text = raw.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ".!?,".contains(last) { text.removeLast() }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Whole message equals a phrase, or starts with it followed by a space or comma.
    private static func matches(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { phrase in
            text == phrase || text.hasPrefix(phrase + " ") || text.hasPrefix(phrase + ",")
        }
    }

    /// The text between a prefix and an optional suffix, e.g. "put cleaning the attic on my list" → "cleaning the attic".
    /// When `suffixes` isn't empty, one of them must be present.
    private static func capture(_ text: String, prefixes: [String], suffixes: [String]) -> String? {
        for prefix in prefixes where text.hasPrefix(prefix) {
            var body = String(text.dropFirst(prefix.count))
            if !suffixes.isEmpty {
                guard let suffix = suffixes.first(where: { body.hasSuffix($0) }) else { continue }
                body = String(body.dropLast(suffix.count))
            }
            let trimmed = body.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
