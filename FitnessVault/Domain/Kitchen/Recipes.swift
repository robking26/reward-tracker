import Foundation

/// One ingredient line of a recipe, with the amount converted to grams, millilitres or items where it was readable.
struct RecipeIngredient: Codable, Sendable, Hashable, Identifiable {
    var id: String { original }
    var name: String
    var amount: Double?
    var unit: KitchenUnit?
    var foodID: String?
    var original: String

    var food: FoodItem? { foodID.flatMap { FoodCatalogue.byID[$0] } }

    /// Grams (or millilitres) for nutrition, when they can be worked out.
    var grams: Double? {
        guard let amount else { return nil }
        switch unit {
        case .grams, .millilitres: return amount
        case .items, .none: return food?.gramsPerItem.map { $0 * amount }
        }
    }

    var amountText: String {
        guard let amount else { return "" }
        let number = amount.rounded() == amount ? String(Int(amount)) : String(format: "%.1f", amount)
        switch unit {
        case .grams, .millilitres: return number + (unit?.symbol ?? "")
        case .items, .none: return number + " ×"
        }
    }

    func scaled(_ factor: Double) -> RecipeIngredient {
        var copy = self
        copy.amount = amount.map { $0 * factor }
        return copy
    }
}

/// How sure an estimate is (F7). Every nutrition figure is an estimate; this says how rough.
enum EstimateConfidence: String, Codable, Sendable, Comparable {
    case rough, fair, good, confirmed

    var title: String {
        switch self {
        case .rough: "rough estimate"
        case .fair: "estimate"
        case .good: "close estimate"
        case .confirmed: "your figures"
        }
    }

    private var order: Int { [.rough, .fair, .good, .confirmed].firstIndex(of: self) ?? 0 }
    static func < (lhs: EstimateConfidence, rhs: EstimateConfidence) -> Bool { lhs.order < rhs.order }
}

struct NutritionEstimate: Sendable, Hashable {
    var perPortion: Macros
    var confidence: EstimateConfidence
    /// Ingredients that couldn't be counted, so the user can see why it's rough.
    var unmatched: [String]

    var summary: String {
        "≈ \(Int(perPortion.kcal.rounded())) kcal · \(Int(perPortion.protein.rounded())) g protein (\(confidence.title))"
    }
}

enum NutritionEstimator {
    static func estimate(_ ingredients: [RecipeIngredient], servings: Int) -> NutritionEstimate {
        var total = Macros.zero
        var counted = 0
        var countable = 0
        var unmatched: [String] = []
        for ingredient in ingredients {
            let food = ingredient.food
            // Seasoning without an amount adds almost nothing; don't let it drag the confidence down.
            if let food, food.isStaple, ingredient.amount == nil { continue }
            countable += 1
            guard let food, let per100 = food.per100, let grams = ingredient.grams else {
                unmatched.append(ingredient.name)
                continue
            }
            total = total + per100.scaled(grams / 100)
            counted += 1
        }
        let coverage = countable == 0 ? 0 : Double(counted) / Double(countable)
        let confidence: EstimateConfidence = coverage >= 0.999 ? .good : coverage >= 0.75 ? .fair : .rough
        return NutritionEstimate(perPortion: total.scaled(1 / Double(max(1, servings))), confidence: confidence, unmatched: unmatched)
    }
}

/// Hand-washing time from the kit a recipe uses (F4: no dishwasher, 5–10 minutes at most).
enum WashUpEstimator {
    private static let vessels: [(String, Int)] = [
        ("food processor", 4), ("slow cooker", 4), ("roasting tin", 4), ("casserole", 4), ("air fryer", 3),
        ("baking tray", 3), ("frying pan", 3), ("saucepan", 3), ("blender", 3), ("tray", 3), ("wok", 3),
        ("pan", 3), ("pot", 3), ("grater", 2), ("colander", 1), ("sieve", 1), ("bowl", 1),
    ]
    private static let cookware: Set<String> = ["slow cooker", "roasting tin", "casserole", "air fryer", "baking tray", "frying pan",
                                                "saucepan", "tray", "wok", "pan", "pot"]

    /// Minutes of washing up and how many pans, pots or trays are used.
    static func estimate(_ text: String) -> (minutes: Int, cookware: Int) {
        var remaining = " " + text.lowercased() + " "
        var minutes = 2 // chopping board, knife, two plates
        var count = 0
        for (word, cost) in vessels where remaining.contains(word) {
            minutes += cost
            if cookware.contains(word) { count += 1 }
            remaining = remaining.replacingOccurrences(of: word, with: " ")
        }
        return (max(3, minutes), count)
    }
}

/// A recipe as read from a photo, screenshot, PDF or typed text, for the user to check before saving (F7).
struct RecipeDraft: Sendable, Hashable {
    var title: String
    var servings: Int
    var servingsWasRead: Bool
    var ingredients: [RecipeIngredient]
    var steps: [String]
    var prepMinutes: Int?
    var cookMinutes: Int?
    var washUpMinutes: Int
    var cookware: Int
    var excluded: [String]
    var nutrition: NutritionEstimate

    var isOnePan: Bool { cookware <= 1 }
    var usesSlowCooker: Bool { (steps.joined(separator: " ") + title).lowercased().contains("slow cooker") }
    var usesAirFryer: Bool { (steps.joined(separator: " ") + title).lowercased().contains("air fryer") }
}

enum IngredientParser {
    private static let fractions: [String: String] = ["½": " 0.5", "¼": " 0.25", "¾": " 0.75", "⅓": " 0.33", "⅔": " 0.67"]
    /// Unit word → (unit, multiplier to grams/ml/items).
    private static let units: [String: (KitchenUnit, Double)] = [
        "g": (.grams, 1), "gram": (.grams, 1), "grams": (.grams, 1), "kg": (.grams, 1000), "kilo": (.grams, 1000),
        "ml": (.millilitres, 1), "l": (.millilitres, 1000), "litre": (.millilitres, 1000), "litres": (.millilitres, 1000),
        "tbsp": (.millilitres, 15), "tablespoon": (.millilitres, 15), "tablespoons": (.millilitres, 15),
        "tsp": (.millilitres, 5), "teaspoon": (.millilitres, 5), "teaspoons": (.millilitres, 5),
        "tin": (.items, 1), "tins": (.items, 1), "can": (.items, 1), "cans": (.items, 1), "pack": (.items, 1),
        "packs": (.items, 1), "jar": (.items, 1), "pouch": (.items, 1), "clove": (.items, 1), "cloves": (.items, 1),
        "handful": (.grams, 30), "handfuls": (.grams, 30), "oz": (.grams, 28),
    ]
    private static let filler: Set<String> = ["of", "x", "a", "an", "large", "small", "medium", "fresh", "approx", "about"]

    static func parse(_ line: String) -> RecipeIngredient {
        let original = line.trimmingCharacters(in: .whitespaces)
        var text = original.lowercased()
        for (symbol, value) in fractions { text = text.replacingOccurrences(of: symbol, with: value) }
        // Drop bullets and anything after a comma ("2 onions, finely chopped").
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "-•*·– "))
        if let comma = text.firstIndex(of: ",") { text = String(text[..<comma]) }
        text = spaceNumbers(text.replacingOccurrences(of: "(", with: " ").replacingOccurrences(of: ")", with: " "))
        var tokens = text.split(separator: " ").map(String.init)

        var amount: Double?
        var unit: KitchenUnit?
        if let first = tokens.first, let value = number(first) {
            amount = value
            tokens.removeFirst()
            // "1 x 400 g tin": multiply by the inner amount.
            if tokens.first == "x", tokens.count > 1, let inner = number(tokens[1]) {
                tokens.removeFirst(2)
                amount = value * inner
            }
            if let word = tokens.first, let match = units[word] {
                let kind = match.0, factor = match.1
                tokens.removeFirst()
                unit = kind
                amount = (amount ?? 1) * factor
                // "1 tin (400 g)" style: the explicit weight wins.
                if kind == .items, tokens.count > 1, let inner = number(tokens[0]), let innerMatch = units[tokens[1]],
                   innerMatch.0 != .items {
                    tokens.removeFirst(2)
                    unit = innerMatch.0
                    amount = (amount ?? 1) * inner * innerMatch.1
                }
            } else {
                unit = .items
            }
        }
        let name = tokens.filter { !filler.contains($0) }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let food = FoodCatalogue.match(name.isEmpty ? original : name)
        // A spoon of something solid in a catalogue measured in items stays in millilitres; that's close enough.
        return RecipeIngredient(name: name.isEmpty ? original : name, amount: amount, unit: unit, foodID: food?.id, original: original)
    }

    static func number(_ token: String) -> Double? {
        if let value = Double(token) { return value }
        let parts = token.split(separator: "/")
        if parts.count == 2, let top = Double(parts[0]), let bottom = Double(parts[1]), bottom != 0 { return top / bottom }
        // "2-3" → 2
        let range = token.split(separator: "-")
        if range.count == 2, let low = Double(range[0]) { return low }
        return nil
    }

    /// "200g" → "200 g", "1x400g" → "1 x 400 g".
    private static func spaceNumbers(_ text: String) -> String {
        var result = ""
        var previous: Character?
        for character in text {
            if let previous {
                let digitToLetter = (previous.isNumber || previous == ".") && character.isLetter
                let letterToDigit = previous == "x" && character.isNumber
                if digitToLetter || letterToDigit { result.append(" ") }
            }
            result.append(character)
            previous = character
        }
        return result
    }
}

enum RecipeParser {
    private static let ingredientHeaders = ["ingredients", "you will need", "you'll need", "what you need", "shopping list"]
    private static let methodHeaders = ["method", "instructions", "directions", "steps", "how to make it", "how to make", "preparation"]

    static func parse(_ text: String) -> RecipeDraft {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let lowerAll = text.lowercased()

        var title: String?
        var ingredients: [RecipeIngredient] = []
        var steps: [String] = []
        enum Section { case none, ingredients, method }
        var section = Section.none

        for line in lines {
            let lower = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            if ingredientHeaders.contains(lower) { section = .ingredients; continue }
            if methodHeaders.contains(lower) { section = .method; continue }
            if isMetadata(lower) { continue }
            if title == nil, section == .none, line.count <= 70, !startsWithNumber(line) {
                title = line
                continue
            }
            switch section {
            case .ingredients:
                if line.count > 90 || (looksLikeStep(line) && !startsWithNumber(line)) {
                    steps.append(cleanStep(line))
                } else {
                    ingredients.append(IngredientParser.parse(line))
                }
            case .method:
                steps.append(cleanStep(line))
            case .none:
                if looksLikeIngredient(line) {
                    ingredients.append(IngredientParser.parse(line))
                } else if line.count > 20 {
                    steps.append(cleanStep(line))
                }
            }
        }

        let servingsRead = firstNumber(in: lowerAll, patterns: [#"(?:serves|servings|portions|makes)\s*:?\s*(\d+)"#,
                                                                #"(\d+)\s*(?:servings|portions|people)"#])
        let servings = min(12, max(1, servingsRead ?? 2))
        let prep = minutes(in: lowerAll, label: #"prep(?:aration)?(?:\s*time)?"#)
        let cook = minutes(in: lowerAll, label: #"cook(?:ing)?(?:\s*time)?"#)
        let washUp = WashUpEstimator.estimate(steps.joined(separator: " "))
        let everything = ([title ?? ""] + ingredients.map(\.original)).joined(separator: " ")
        let excluded = FoodExclusions.words.filter { everything.lowercased().contains($0) }

        return RecipeDraft(title: title ?? "Imported recipe", servings: servings, servingsWasRead: servingsRead != nil,
                           ingredients: ingredients, steps: steps, prepMinutes: prep, cookMinutes: cook,
                           washUpMinutes: washUp.minutes, cookware: washUp.cookware, excluded: excluded,
                           nutrition: NutritionEstimator.estimate(ingredients, servings: servings))
    }

    private static func isMetadata(_ lower: String) -> Bool {
        ["serves", "servings", "prep time", "cook time", "cooking time", "preparation time", "total time", "makes "]
            .contains { lower.hasPrefix($0) }
    }

    private static func startsWithNumber(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return first.isNumber || "½¼¾⅓⅔".contains(first)
    }

    private static func looksLikeStep(_ line: String) -> Bool {
        let lower = line.lowercased()
        let verbs = ["heat ", "add ", "cook ", "preheat", "stir ", "place ", "bake ", "serve", "mix ", "fry ", "put ", "season ",
                     "bring ", "simmer", "roast ", "remove ", "chop ", "slice ", "pour ", "leave "]
        return line.count > 30 && verbs.contains { lower.hasPrefix($0) || lower.contains(". " + $0) }
    }

    private static func looksLikeIngredient(_ line: String) -> Bool {
        if line.count > 70 { return false }
        if startsWithNumber(line) {
            // "1. Heat the oven" is a numbered step, not an ingredient.
            let afterNumber = line.drop { $0.isNumber || $0 == " " }
            if afterNumber.hasPrefix(". ") || afterNumber.hasPrefix(")") { return false }
            return true
        }
        return line.count <= 40 && FoodCatalogue.match(line) != nil && !looksLikeStep(line)
    }

    private static func cleanStep(_ line: String) -> String {
        var text = line
        if text.lowercased().hasPrefix("step ") { text = String(text.dropFirst(5)) }
        let trimmed = text.drop { $0.isNumber || $0 == "." || $0 == ")" || $0 == ":" || $0 == " " }
        return trimmed.isEmpty ? line : String(trimmed)
    }

    private static func minutes(in text: String, label: String) -> Int? {
        let pattern = label + #"\s*:?\s*(\d+)\s*(min|mins|minutes|hr|hrs|hour|hours)"#
        guard let groups = RegexHelper.firstMatch(pattern, in: text), groups.count >= 2, let value = Int(groups[0]) else { return nil }
        return groups[1].hasPrefix("h") ? value * 60 : value
    }

    private static func firstNumber(in text: String, patterns: [String]) -> Int? {
        for pattern in patterns {
            if let groups = RegexHelper.firstMatch(pattern, in: text), let first = groups.first, let value = Int(first) { return value }
        }
        return nil
    }
}

enum RegexHelper {
    /// The capture groups of the first match, or nil.
    static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for index in 1..<max(1, match.numberOfRanges) {
            if let groupRange = Range(match.range(at: index), in: text) {
                groups.append(String(text[groupRange]))
            } else {
                groups.append("")
            }
        }
        return groups
    }
}

/// Macro improvements that keep the dish recognisably the same (F7). Anything that changes the flavour is marked
/// so the app asks before applying it.
struct MacroTweak: Sendable, Hashable, Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var changesFlavour: Bool
    var replaceFoodID: String?
    var withFoodID: String?
    /// Multiplies the amount of `replaceFoodID` (e.g. a third less cheese).
    var amountFactor: Double
}

enum MacroTweaks {
    static func suggest(_ ingredients: [RecipeIngredient], servings: Int) -> [MacroTweak] {
        var tweaks: [MacroTweak] = []
        let ids = Set(ingredients.compactMap(\.foodID))
        if ids.contains("beef-mince") {
            tweaks.append(MacroTweak(title: "Use 5% beef mince", detail: "Same dish, noticeably less fat. Brown it well for flavour.",
                                     changesFlavour: false, replaceFoodID: "beef-mince", withFoodID: "beef-mince-5", amountFactor: 1))
        }
        if let oil = ingredients.first(where: { $0.foodID == "olive-oil" }), let ml = oil.amount, ml / Double(max(1, servings)) > 8 {
            tweaks.append(MacroTweak(title: "Measure the oil", detail: "One tablespoon plus spray oil is plenty; the taste doesn't change.",
                                     changesFlavour: false, replaceFoodID: "olive-oil", withFoodID: nil, amountFactor: 15 / ml))
        }
        if ids.contains("cheddar") {
            tweaks.append(MacroTweak(title: "A third less mature cheddar", detail: "Strong cheese keeps the flavour with less of it.",
                                     changesFlavour: false, replaceFoodID: "cheddar", withFoodID: nil, amountFactor: 0.67))
        }
        if ids.contains("cream") {
            tweaks.append(MacroTweak(title: "Light crème fraîche instead of cream", detail: "Slightly tangier. Only if you're happy with that.",
                                     changesFlavour: true, replaceFoodID: "cream", withFoodID: "creme-fraiche", amountFactor: 1))
        }
        if ids.contains("pork-mince") {
            tweaks.append(MacroTweak(title: "Turkey mince instead of pork mince", detail: "Leaner, but milder. Your call.",
                                     changesFlavour: true, replaceFoodID: "pork-mince", withFoodID: "turkey-mince", amountFactor: 1))
        }
        let estimate = NutritionEstimator.estimate(ingredients, servings: servings)
        if estimate.perPortion.protein < 30, let protein = ingredients.first(where: { ["chicken-breast", "turkey-mince", "chicken-thigh"].contains($0.foodID ?? "") }),
           let amount = protein.amount, protein.unit == .grams {
            let extra = Double(servings) * 50
            tweaks.append(MacroTweak(title: "Add \(Int(extra)) g more \(protein.food?.name.lowercased() ?? protein.name)",
                                     detail: "Gets you closer to 30 g protein a portion without changing the dish.",
                                     changesFlavour: false, replaceFoodID: protein.foodID, withFoodID: nil, amountFactor: (amount + extra) / amount))
        }
        return tweaks
    }

    static func apply(_ tweak: MacroTweak, to ingredients: [RecipeIngredient]) -> [RecipeIngredient] {
        ingredients.map { ingredient in
            guard ingredient.foodID == tweak.replaceFoodID else { return ingredient }
            var changed = ingredient.scaled(tweak.amountFactor)
            if let replacement = tweak.withFoodID, let food = FoodCatalogue.byID[replacement] {
                changed.foodID = replacement
                changed.name = food.name.lowercased()
            }
            return changed
        }
    }
}
