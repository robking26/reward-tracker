import Foundation

// Eating out: dish picks from a menu the user photographed or pasted.

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
