import Foundation

// Phase 6: social events, drinking plans, recovery and outings (SO1–SO3, RE1). Supportive, never moralising,
// never a source of fines. No gambling suggestions anywhere.

enum SocialKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case golf, football, meal, nightOut, weekendAway, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .golf: "Golf"
        case .football: "Football"
        case .meal: "Meal out"
        case .nightOut: "Night out"
        case .weekendAway: "Weekend away"
        case .other: "Social"
        }
    }

    /// Occasions where drinking is common enough to offer a plan in advance.
    var oftenInvolvesDrinking: Bool { self != .other }
}

enum DrinkingPlan: String, Codable, Sendable, CaseIterable, Identifiable {
    case undecided, alcoholFree, lighter, moderate

    var id: String { rawValue }
    var title: String {
        switch self {
        case .undecided: "Not decided"
        case .alcoholFree: "Alcohol-free"
        case .lighter: "Lighter"
        case .moderate: "Moderate"
        }
    }

    var detail: String {
        switch self {
        case .undecided: "No plan yet. That's fine; recovery is planned as if it's a big one."
        case .alcoholFree: "Soft drinks or alcohol-free beer. Clear head tomorrow."
        case .lighter: "Two or three, with a soft drink or water in between."
        case .moderate: "A number you choose before you go. Eat first, water between rounds."
        }
    }
}

struct DetectedSocial: Hashable, Sendable {
    var eventID: String
    var title: String
    var start: Date
    var end: Date
    var kind: SocialKind
    /// From Becky's shared calendar: ask whether the user is going rather than assume.
    var needsConfirmation: Bool
    var days: Int
}

enum SocialDetector {
    private static let keywords: [(SocialKind, [String])] = [
        (.weekendAway, ["weekend away", "weekend in", "stag", "hen do", "festival", "city break"]),
        (.golf, ["golf", "driving range"]),
        (.football, ["football", "five-a-side", "5-a-side", "5 a side", "match"]),
        (.nightOut, ["drinks", "pub", "night out", "bar", "party", "birthday", "wedding", "christening", "leaving do", "beers"]),
        (.meal, ["dinner", "restaurant", "meal", "curry", "brunch", "lunch with", "tapas"]),
    ]

    static func kind(for title: String) -> SocialKind? {
        // Whole words, so "barber" isn't a bar and "matcha" isn't a match.
        for (kind, words) in keywords where CalendarClassifier.matches(title, words) { return kind }
        return nil
    }

    /// Social plans in the user's own (personal or work) calendars, plus Becky's shared ones to confirm.
    static func detect(_ events: [ClassifiedEvent], calendar: Calendar) -> [DetectedSocial] {
        events.compactMap { item in
            guard item.role != .ignored, item.kind != .workFocus, let kind = kind(for: item.event.title) else { return nil }
            let days = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: item.event.start),
                                                      to: calendar.startOfDay(for: item.event.end.addingTimeInterval(-1))).day.map { $0 + 1 } ?? 1)
            return DetectedSocial(eventID: item.event.id, title: item.event.title, start: item.event.start, end: item.event.end,
                                  kind: kind, needsConfirmation: item.role == .shared, days: days)
        }
    }
}

struct PrepStep: Hashable, Sendable, Identifiable {
    enum Action: String, Hashable, Sendable {
        /// Put a freezer meal on the plan for the day after.
        case freezerMealNextDay
        /// Mark the days after as recovery, so nothing demanding is suggested.
        case planRecovery
        /// Something to remember; nothing for the app to do.
        case reminder
    }

    var id: String { title }
    var title: String
    var action: Action
}

enum SocialPlanner {
    /// Days of recovery to plan for after the event (SO3: commonly 48–72 hours after heavy drinking).
    static func recoveryDays(plan: DrinkingPlan, eventDays: Int) -> Int {
        let base: Int
        switch plan {
        case .alcoholFree: base = 0
        case .lighter: base = 1
        case .moderate: base = 2
        case .undecided: base = 3
        }
        guard base > 0 else { return 0 }
        return min(3, base + max(0, eventDays - 1))
    }

    /// Honest, short advice for the plan. Never says heavy drinking is safe.
    static func advice(kind: SocialKind, plan: DrinkingPlan, driving: Bool, eventDays: Int) -> [String] {
        var lines: [String] = []
        if driving {
            lines.append(plan == .alcoholFree ? "You're driving, so alcohol-free is the right call."
                                              : "You're driving: no alcohol before you drive. Alcohol-free, or leave the car.")
        }
        if eventDays >= 2 && plan != .alcoholFree {
            lines.append("Drinking on several days in a row adds up, and recovery takes longer. A lighter or alcohol-free day in the middle helps.")
        }
        switch plan {
        case .lighter, .moderate:
            lines.append("Decide the number before you go, eat first, and have water between rounds.")
        case .undecided:
            lines.append("No pressure to decide. If you do, a number in advance makes it easier to stick to.")
        case .alcoholFree:
            break
        }
        if kind == .golf || kind == .football {
            lines.append("If you want an alcohol-free version, the driving range or watching at home are good alternatives.")
        }
        return lines
    }

    /// What to sort before the event (SO3: easy food, fewer chores, realistic expectations).
    static func preparation(plan: DrinkingPlan, eventDays: Int, nextDayHasWorkout: Bool) -> [PrepStep] {
        let recovery = recoveryDays(plan: plan, eventDays: eventDays)
        var steps: [PrepStep] = []
        if recovery > 0 {
            steps.append(PrepStep(title: "Easy food for the day after: a freezer meal on the plan", action: .freezerMealNextDay))
            steps.append(PrepStep(title: "Keep the next \(recovery == 1 ? "day" : "\(recovery) days") gentle: no demanding suggestions",
                                  action: .planRecovery))
            if nextDayHasWorkout {
                steps.append(PrepStep(title: "Move the next day's gym session later in the week", action: .reminder))
            }
        }
        steps.append(PrepStep(title: "Water by the bed and the phone charged", action: .reminder))
        steps.append(PrepStep(title: "Know how you're getting home", action: .reminder))
        return steps
    }
}

// MARK: Recovery (SO3)

enum RecoveryFeeling: String, Codable, Sendable, CaseIterable, Identifiable {
    case rough, gettingThere, normal

    var id: String { rawValue }
    var title: String {
        switch self {
        case .rough: "Rough"
        case .gettingThere: "Getting there"
        case .normal: "Back to normal"
        }
    }
}

/// What the recommendation engine needs to know about recovery today.
enum RecoveryStatus: Hashable, Sendable {
    case clear
    case recovering(RecoveryFeeling)
    /// The first day back: one manageable thing, and an easy gym session (SO3).
    case restarting
}

struct RecoveryWindow: Hashable, Sendable {
    var start: DayKey
    var days: Int
    var feeling: RecoveryFeeling?
    var endedOn: DayKey?

    func status(on day: DayKey, calendar: Calendar) -> RecoveryStatus {
        let end = endedOn ?? start.adding(days: days, calendar: calendar)
        if day >= start && day < end && feeling != .normal { return .recovering(feeling ?? .rough) }
        if day == end { return .restarting }
        return .clear
    }
}

enum RecoveryPlanner {
    static func guidance(_ feeling: RecoveryFeeling) -> [String] {
        var lines = ["Water little and often.", "Normal meals at normal times. No skipping, no making up for anything."]
        switch feeling {
        case .rough:
            lines.append("Rest. No gym today; it'll still be there.")
        case .gettingThere:
            lines.append("A short, easy walk if you feel up to it. Nothing more.")
        case .normal:
            break
        }
        lines.append("Protect tonight's sleep: usual bedtime.")
        return lines
    }
}

// MARK: Outings with Becky (RE1)

struct OutingIdea: Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var question: String
    var outdoor: Bool
    var paid: Bool
}

enum OutingPlanner {
    static let evening: [OutingIdea] = [
        OutingIdea(id: "badminton", title: "Badminton", question: "You're both free tonight. Fancy badminton?", outdoor: false, paid: true),
        OutingIdea(id: "cinema", title: "Cinema", question: "Nothing on tonight for either of you. Cinema?", outdoor: false, paid: true),
        OutingIdea(id: "evening-walk", title: "Walk together", question: "You're both free and it's dry. A walk after dinner?", outdoor: true, paid: false),
        OutingIdea(id: "climbing", title: "Climbing wall", question: "Free evening for both of you. Try the climbing wall?", outdoor: false, paid: true),
        OutingIdea(id: "bowling", title: "Bowling", question: "You're both free tonight. Bowling?", outdoor: false, paid: true),
        OutingIdea(id: "cook-together", title: "Cook something new together", question: "Quiet night for both of you. Cook something new together?", outdoor: false, paid: false),
        OutingIdea(id: "driving-range", title: "Driving range", question: "Both free tonight. Driving range together?", outdoor: true, paid: true),
    ]

    static let weekendAway = OutingIdea(id: "lakes", title: "A night in the Lakes", question: "", outdoor: true, paid: true)

    /// Budget options asked at the moment of suggestion, never from the bank (RE1).
    static let budgetReplies = ["Under £20", "£20–£60", "Treat ourselves"]

    /// Tonight's idea when both are free from 6pm, at most every few days, avoiding recent repeats and wet outdoor ideas.
    static func tonight(day: DayKey, userFreeEvening: Bool, beckyFreeEvening: Bool, eveningIsDry: Bool?,
                        recentIDs: [String], daysSinceLastIdea: Int?, recovering: Bool, calendar: Calendar) -> OutingIdea? {
        guard userFreeEvening, beckyFreeEvening, !recovering else { return nil }
        if let since = daysSinceLastIdea, since < 3 { return nil }
        let candidates = evening.filter { idea in
            !recentIDs.suffix(3).contains(idea.id) && (!idea.outdoor || eveningIsDry == true)
        }
        guard !candidates.isEmpty else { return nil }
        let ordinal = calendar.ordinality(of: .day, in: .era, for: day.startDate(calendar: calendar)) ?? 0
        return candidates[ordinal % candidates.count]
    }

    /// The first Saturday at least two weeks ahead (within eight weeks) with nothing in anyone's calendar
    /// on the Saturday or Sunday. `busyDays` holds every day with an event in any calendar, Becky's included.
    static func freeWeekend(from day: DayKey, busyDays: Set<DayKey>, calendar: Calendar) -> DayKey? {
        for offset in 14...56 {
            let candidate = day.adding(days: offset, calendar: calendar)
            guard calendar.component(.weekday, from: candidate.startDate(calendar: calendar)) == 7 else { continue }
            let sunday = candidate.adding(days: 1, calendar: calendar)
            if !busyDays.contains(candidate) && !busyDays.contains(sunday) { return candidate }
        }
        return nil
    }
}

// MARK: Eating out (SO1)

struct MenuPick: Hashable, Sendable {
    var dish: String
    var reason: String
}

/// Picks from a menu the user photographed or pasted. Protein-forward, exclusions skipped, never a lecture.
enum MenuAdvisor {
    private static let proteins = ["chicken", "steak", "beef", "fish", "salmon", "cod", "haddock", "seabass", "sea bass", "prawn",
                                   "tuna", "turkey", "lamb", "pork", "gammon", "egg", "halloumi", "chilli con carne", "fajita", "kebab"]
    private static let methods = ["grilled", "roast", "baked", "chargrilled", "flame", "skewer"]
    private static let skip = ["dessert", "desserts", "starters", "mains", "sides", "drinks", "menu", "allergens", "vat",
                               "service charge", "please", "ask", "wine", "beer", "lager", "gin"]

    static func picks(from text: String, limit: Int = 3) -> [MenuPick] {
        var seen = Set<String>()
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                let lower = line.lowercased()
                return line.count >= 4 && line.count <= 90 && line.contains(where: \.isLetter)
                    && !skip.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") })
            }
        var scored: [(Int, MenuPick)] = []
        for line in lines {
            let lower = line.lowercased()
            guard FoodExclusions.excluded(lower) == nil else { continue }
            guard let protein = proteins.first(where: { lower.contains($0) }) else { continue }
            let dish = line.replacingOccurrences(of: #"\s*£?\d+([.,]\d{2})?\s*$"#, with: "", options: .regularExpression)
            guard seen.insert(dish.lowercased()).inserted else { continue }
            var score = 3
            var reason = "Good protein (\(protein))"
            if let method = methods.first(where: { lower.contains($0) }) {
                score += 1
                reason += ", \(method)"
            }
            scored.append((score, MenuPick(dish: dish, reason: reason)))
        }
        let ordered = scored.enumerated().sorted { left, right in
            left.element.0 != right.element.0 ? left.element.0 > right.element.0 : left.offset < right.offset
        }
        return ordered.prefix(limit).map { $0.element.1 }
    }

    static let footnote = "Picked for protein and what you like. Nutrition isn't known for this menu, so treat it as a rough guide, and enjoy the meal."
}
