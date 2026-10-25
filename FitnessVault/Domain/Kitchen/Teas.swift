import Foundation

// Evening meals ("teas") from your own recipe books: the bank comes from recipes you give Claude, which turns photos
// and PDFs into the JSON below. Each week you say who's eating which night, swipe through the bank (Rob, then
// Becky), and the matches fill the nights. Monday to Thursday meals have to freeze.

struct TeaRecipe: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    /// e.g. "Pinch of Nom Everyday Light, p. 84".
    var source: String?
    var servings: Int
    /// Per portion.
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var prepMinutes: Int
    var cookMinutes: Int
    var freezable: Bool
    var ingredients: [String]
    var method: [String]
    var tags: [String]

    var totalMinutes: Int { prepMinutes + cookMinutes }

    /// How much of the book's portion to eat so it lands on 600–700 kcal with at least 50 g protein: the smallest
    /// step of 0.05 that gets there. Nil when it can't (not enough protein for the calories).
    var portionScale: Double? {
        guard kcal > 0, protein > 0 else { return nil }
        let needed = max(TeaTargets.kcal.lowerBound / kcal, TeaTargets.minProtein / protein)
        let scale = (needed * 20 - 0.000_1).rounded(.up) / 20
        return kcal * scale <= TeaTargets.kcal.upperBound ? scale : nil
    }

    /// 600–700 kcal and at least 50 g protein a portion, at the right portion size.
    var meetsTargets: Bool { portionScale != nil }

    /// Your portion's numbers.
    var portionKcal: Double { kcal * (portionScale ?? 1) }
    var portionProtein: Double { protein * (portionScale ?? 1) }
    var portionCarbs: Double { carbs * (portionScale ?? 1) }
    var portionFat: Double { fat * (portionScale ?? 1) }

    /// The ingredients with weights and volumes scaled to your portion ("240g chicken" becomes "312g chicken").
    /// Counts like "1 onion" are left as they are.
    var portionIngredients: [String] {
        guard let scale = portionScale, abs(scale - 1) > 0.001 else { return ingredients }
        return ingredients.map { Self.scaled($0, by: scale) }
    }

    static func scaled(_ line: String, by scale: Double) -> String {
        guard let match = line.range(of: #"^\s*\d+(\.\d+)?\s*(g|kg|ml|l)\b"#, options: .regularExpression) else { return line }
        let quantity = String(line[match])
        let number = Double(quantity.filter { $0.isNumber || $0 == "." }) ?? 0
        let unit = quantity.drop { !$0.isLetter }
        let value = number * scale
        let rounded = value >= 20 ? (value / 5).rounded() * 5 : (value * 2).rounded() / 2
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return text + unit + line[match.upperBound...]
    }

    init(id: String, title: String, source: String? = nil, servings: Int = 2, kcal: Double, protein: Double,
         carbs: Double = 0, fat: Double = 0, prepMinutes: Int = 15, cookMinutes: Int = 30, freezable: Bool = false,
         ingredients: [String] = [], method: [String] = [], tags: [String] = []) {
        self.id = id
        self.title = title
        self.source = source
        self.servings = servings
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.freezable = freezable
        self.ingredients = ingredients
        self.method = method
        self.tags = tags
    }

    // Lenient reading, so a file from Claude with a missing or differently named field still comes in.
    private enum CodingKeys: String, CodingKey {
        case id, title, name, source, book, servings, serves, kcal, calories, protein, carbs, carbohydrate, fat
        case prepMinutes, prep_minutes, cookMinutes, cook_minutes, freezable, ingredients, method, steps, tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ keys: CodingKeys...) -> Double? {
            for key in keys {
                if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
                if let text = try? c.decodeIfPresent(String.self, forKey: key),
                   let value = Double(text.filter { $0.isNumber || $0 == "." }) { return value }
            }
            return nil
        }
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Untitled"
        id = (try? c.decodeIfPresent(String.self, forKey: .id))
            ?? title.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }.replacingOccurrences(of: " ", with: "-")
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? (try? c.decodeIfPresent(String.self, forKey: .book))
        servings = Int(number(.servings, .serves) ?? 2)
        kcal = number(.kcal, .calories) ?? 0
        protein = number(.protein) ?? 0
        carbs = number(.carbs, .carbohydrate) ?? 0
        fat = number(.fat) ?? 0
        prepMinutes = Int(number(.prepMinutes, .prep_minutes) ?? 15)
        cookMinutes = Int(number(.cookMinutes, .cook_minutes) ?? 30)
        freezable = (try? c.decodeIfPresent(Bool.self, forKey: .freezable)) ?? false
        ingredients = (try? c.decodeIfPresent([String].self, forKey: .ingredients)) ?? []
        method = (try? c.decodeIfPresent([String].self, forKey: .method)) ?? (try? c.decodeIfPresent([String].self, forKey: .steps)) ?? []
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encode(servings, forKey: .servings)
        try c.encode(kcal, forKey: .kcal)
        try c.encode(protein, forKey: .protein)
        try c.encode(carbs, forKey: .carbs)
        try c.encode(fat, forKey: .fat)
        try c.encode(prepMinutes, forKey: .prepMinutes)
        try c.encode(cookMinutes, forKey: .cookMinutes)
        try c.encode(freezable, forKey: .freezable)
        try c.encode(ingredients, forKey: .ingredients)
        try c.encode(method, forKey: .method)
        try c.encode(tags, forKey: .tags)
    }
}

enum TeaTargets {
    static let kcal: ClosedRange<Double> = 600...700
    static let minProtein: Double = 50
}

/// Who's eating a home-cooked tea that night.
enum TeaDiner: String, Codable, CaseIterable, Sendable, Identifiable {
    case together, rob, becky, notCooking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .together: "Together"
        case .rob: "Just me"
        case .becky: "Just Becky"
        case .notCooking: "Not cooking"
        }
    }

    var symbol: String {
        switch self {
        case .together: "person.2.fill"
        case .rob, .becky: "person.fill"
        case .notCooking: "moon.zzz"
        }
    }

    var includesRob: Bool { self == .together || self == .rob }
    var includesBecky: Bool { self == .together || self == .becky }
}

enum TeaSwiper: String, Codable, Sendable {
    case rob, becky

    var name: String { self == .rob ? "Rob" : "Becky" }
}

/// One week's teas: who's eating each night, what each of you swiped right on, and what's planned.
struct TeaWeek: Codable, Hashable, Sendable {
    /// The first night, yyyy-MM-dd.
    var start: String
    /// Night (yyyy-MM-dd) to who's eating.
    var diners: [String: TeaDiner] = [:]
    var robLikes: [String] = []
    var beckyLikes: [String] = []
    var robSeen: [String] = []
    var beckySeen: [String] = []
    /// Night to recipe ID.
    var meals: [String: String] = [:]

    func likes(_ swiper: TeaSwiper) -> [String] { swiper == .rob ? robLikes : beckyLikes }
    func seen(_ swiper: TeaSwiper) -> [String] { swiper == .rob ? robSeen : beckySeen }
}

enum TeaPlanner {
    static let nightsInAWeek = 7

    static func nights(from start: DayKey, calendar: Calendar) -> [DayKey] {
        (0..<nightsInAWeek).map { start.adding(days: $0, calendar: calendar) }
    }

    /// Monday to Thursday teas are cooked ahead and frozen.
    static func needsFreezing(_ day: DayKey, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        return (2...5).contains(weekday)
    }

    /// The recipes to swipe on: on target only, in a steady shuffle for the week so both of you see the same order.
    static func deck(_ recipes: [TeaRecipe], week: String) -> [TeaRecipe] {
        // On target means at the right portion size: most book recipes are a little under 600 kcal as printed.
        recipes.filter(\.meetsTargets).sorted { stableHash($0.id + week) < stableHash($1.id + week) }
    }

    /// Fills each night: together nights from what you both liked, solo nights from that person's likes (shared likes
    /// first). Monday to Thursday only freezable meals. No meal twice unless there aren't enough to go round.
    static func assign(nights: [DayKey], diners: [String: TeaDiner], recipes: [TeaRecipe], robLikes: Set<String>,
                       beckyLikes: Set<String>, calendar: Calendar) -> [String: String] {
        let eligible = recipes.filter(\.meetsTargets)
        let both = robLikes.intersection(beckyLikes)
        var used = Set<String>()
        var result: [String: String] = [:]
        // Freezer nights first: they have fewer choices.
        let ordered = nights.sorted { lhs, rhs in
            let left = needsFreezing(lhs, calendar: calendar), right = needsFreezing(rhs, calendar: calendar)
            return left == right ? lhs < rhs : left
        }
        for night in ordered {
            let diner = diners[night.description] ?? .notCooking
            guard diner != .notCooking else { continue }
            let pool: [Set<String>]
            switch diner {
            case .together: pool = [both]
            case .rob: pool = [both, robLikes]
            case .becky: pool = [both, beckyLikes]
            case .notCooking: pool = []
            }
            let freezing = needsFreezing(night, calendar: calendar)
            let fits = { (recipe: TeaRecipe) in !freezing || recipe.freezable }
            var pick: TeaRecipe?
            for allowRepeat in [false, true] where pick == nil {
                for likes in pool where pick == nil {
                    pick = eligible.first { likes.contains($0.id) && fits($0) && (allowRepeat || !used.contains($0.id)) }
                }
            }
            if let pick {
                result[night.description] = pick.id
                used.insert(pick.id)
            }
        }
        return result
    }

    /// Recipes from a JSON file or pasted text: an array, or an object with a "recipes" array.
    static func decode(_ data: Data) throws -> [TeaRecipe] {
        struct Wrapped: Decodable { var recipes: [TeaRecipe] }
        if let list = try? JSONDecoder().decode([TeaRecipe].self, from: data) { return list }
        return try JSONDecoder().decode(Wrapped.self, from: data).recipes
    }

    /// The same number every run (Swift's own hash changes between launches).
    static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    /// What to ask Claude for, so the recipes come back in the right shape.
    static let claudePrompt = """
    Read these recipes and give me JSON only: an array of objects with id (short, lowercase, hyphens), title, \
    source (book and page), servings, kcal, protein, carbs, fat (all per portion, numbers), prepMinutes, cookMinutes, \
    freezable (true/false), ingredients (array of strings with amounts), method (array of steps) and tags. \
    If the book gives nutrition, use it; otherwise estimate from the ingredients.
    """
}
