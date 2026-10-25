import Foundation

// Evening meals ("teas") from your own recipe books: the bank comes from recipes you give Claude, which turns photos
// and PDFs into the JSON below. Each week you say who's eating which night, swipe through the bank (Rob, then
// Becky), and the matches fill the nights. Monday to Thursday meals have to be quick.

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

    /// Your portion: the book's recipe resized, and topped up with lean protein when the book's version doesn't
    /// carry enough, so it lands on 600–700 kcal with at least 50 g protein. Nil only if nothing gets there.
    var portion: TeaPortion? { TeaPortion.fit(self) }

    var meetsTargets: Bool { portion != nil }

    /// 30 minutes or less, prep and cook.
    var isQuick: Bool { totalMinutes <= TeaTargets.quickMinutes }

    /// Goes in the slow cooker: prepped in the morning routine, ready for tea.
    var isSlowCooker: Bool {
        tags.contains { $0.lowercased() == "slow cooker" } || title.lowercased().contains("slow cooker")
    }

    /// Monday to Thursday: quick, or in the slow cooker since the morning.
    var suitsAWeeknight: Bool { isQuick || isSlowCooker }

    /// Your portion's numbers.
    var portionKcal: Double { portion?.kcal(self) ?? kcal }
    var portionProtein: Double { portion?.protein(self) ?? protein }
    var portionCarbs: Double { portion?.carbs(self) ?? carbs }
    var portionFat: Double { portion?.fat(self) ?? fat }

    /// The ingredients for your portion: gram and ml amounts scaled ("240g chicken" becomes "310g chicken"), counts
    /// like "1 onion" left as they are, and any protein top-up on the end.
    var portionIngredients: [String] {
        guard let portion else { return ingredients }
        var lines = abs(portion.scale - 1) > 0.001 ? ingredients.map { Self.scaled($0, by: portion.scale) } : ingredients
        if let boost = portion.boost { lines.append("+ \(Int(portion.boostGrams))g \(boost.name) (extra, for protein)") }
        return lines
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
    /// Monday to Thursday teas: prep and cook inside this.
    static let quickMinutes = 30
}

/// Lean protein added to a recipe that's light on it. Per 100 g raw, Aldi's own.
struct TeaBoost: Hashable, Sendable {
    let name: String
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let how: String

    static let chicken = TeaBoost(name: "chicken breast", kcal: 106, protein: 24, carbs: 0, fat: 1.1,
                                  how: "Dice the extra chicken and cook it with the rest (or in a hot pan on its own for 6–8 minutes, until cooked through), then stir it in or serve it alongside.")
    static let prawns = TeaBoost(name: "king prawns", kcal: 66, protein: 15.4, carbs: 0, fat: 0.6,
                                 how: "Add the extra prawns for the last 3–4 minutes of cooking, until pink all the way through.")
    static let cod = TeaBoost(name: "cod loin", kcal: 76, protein: 17.5, carbs: 0, fat: 0.6,
                              how: "Season the cod and bake it alongside at 200°C for 12–15 minutes (or air fry for 10), then flake it in or serve it on the side.")
    static let beef = TeaBoost(name: "5% lean beef mince", kcal: 124, protein: 21.5, carbs: 0, fat: 4.5,
                               how: "Brown the extra mince with the rest of the beef (or in its own pan for 6–8 minutes) and stir it through.")
    static let turkey = TeaBoost(name: "turkey breast mince", kcal: 108, protein: 23, carbs: 0, fat: 1.9,
                                 how: "Brown the extra turkey with the rest of the mince (or in its own pan for 6–8 minutes) and stir it through.")
    static let pork = TeaBoost(name: "pork loin medallions", kcal: 123, protein: 22.8, carbs: 0, fat: 3.6,
                               how: "Dice the pork loin and fry it in a hot pan for 6–8 minutes, until cooked through, then stir it in.")

    /// The top-up that suits the dish: more of what's already in it, chicken otherwise.
    static func best(for recipe: TeaRecipe) -> TeaBoost {
        let text = ([recipe.title] + recipe.ingredients).joined(separator: " ").lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        if has("chicken") { return .chicken }
        if has("prawn") { return .prawns }
        if has("salmon", "cod", "fish", "haddock", "basa") { return .cod }
        if has("turkey") { return .turkey }
        if has("beef", "mince", "steak", "burger", "meatball") { return .beef }
        if has("pork", "sausage", "gammon") { return .pork }
        return .chicken
    }
}

/// How to eat a recipe on target: a share of the book's portion, plus any top-up.
struct TeaPortion: Hashable, Sendable {
    var scale: Double
    var boost: TeaBoost?
    var boostGrams: Double = 0

    // To one decimal place, so a portion right on 50 g reads 50 and not 49.99999.
    func kcal(_ recipe: TeaRecipe) -> Double { Self.tidy(recipe.kcal * scale + extra(\.kcal)) }
    func protein(_ recipe: TeaRecipe) -> Double { Self.tidy(recipe.protein * scale + extra(\.protein)) }
    func carbs(_ recipe: TeaRecipe) -> Double { Self.tidy(recipe.carbs * scale + extra(\.carbs)) }
    func fat(_ recipe: TeaRecipe) -> Double { Self.tidy(recipe.fat * scale + extra(\.fat)) }

    private static func tidy(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    private func extra(_ value: KeyPath<TeaBoost, Double>) -> Double {
        boost.map { $0[keyPath: value] * boostGrams / 100 } ?? 0
    }

    /// The book's recipe resized if that's enough; otherwise the least top-up (in 10 g steps) that gets there.
    static func fit(_ recipe: TeaRecipe) -> TeaPortion? {
        guard recipe.kcal > 0 else { return nil }
        if let scale = scale(recipe, extraKcal: 0, extraProtein: 0) { return TeaPortion(scale: scale) }
        let boost = TeaBoost.best(for: recipe)
        for grams in stride(from: 10.0, through: 300, by: 10) {
            if let scale = scale(recipe, extraKcal: boost.kcal * grams / 100, extraProtein: boost.protein * grams / 100) {
                return TeaPortion(scale: scale, boost: boost, boostGrams: grams)
            }
        }
        return nil
    }

    /// The smallest share of the book's portion, in steps of 0.05 and at least half, that reaches 600 kcal and 50 g
    /// protein without going over 700 kcal.
    private static func scale(_ recipe: TeaRecipe, extraKcal: Double, extraProtein: Double) -> Double? {
        let forKcal = (TeaTargets.kcal.lowerBound - extraKcal) / recipe.kcal
        let forProtein = recipe.protein > 0 ? (TeaTargets.minProtein - extraProtein) / recipe.protein
            : (extraProtein >= TeaTargets.minProtein ? 0 : .infinity)
        let needed = max(forKcal, forProtein, 0.5)
        guard needed.isFinite else { return nil }
        let scale = (needed * 20 - 0.000_1).rounded(.up) / 20
        return recipe.kcal * scale + extraKcal <= TeaTargets.kcal.upperBound ? scale : nil
    }
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
    /// This week's shuffled deck: recipe IDs in the order they're shown. Nil for weeks saved before shuffling.
    var order: [String]? = nil

    func likes(_ swiper: TeaSwiper) -> [String] { swiper == .rob ? robLikes : beckyLikes }
    func seen(_ swiper: TeaSwiper) -> [String] { swiper == .rob ? robSeen : beckySeen }
}

enum TeaPlanner {
    static let nightsInAWeek = 7

    static func nights(from start: DayKey, calendar: Calendar) -> [DayKey] {
        (0..<nightsInAWeek).map { start.adding(days: $0, calendar: calendar) }
    }

    /// Monday to Thursday teas have to be quick (30 minutes or less) or slow cooker ones prepped in the morning.
    static func needsQuick(_ day: DayKey, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        return (2...5).contains(weekday)
    }

    /// The recipes to swipe on: on target only, in a steady shuffle for the week so both of you see the same order.
    static func deck(_ recipes: [TeaRecipe], week: String) -> [TeaRecipe] {
        // On target means at your portion: resized and topped up where the book's version is light.
        recipes.filter(\.meetsTargets).sorted { stableHash($0.id + week) < stableHash($1.id + week) }
    }

    /// Fills each night from the picks, in the order they were picked: together nights from what you both liked
    /// (then either of your picks if there aren't enough), solo nights from that person's picks. Monday to Thursday
    /// only quick or slow cooker meals. No meal twice unless there aren't enough to go round.
    static func assign(nights: [DayKey], diners: [String: TeaDiner], recipes: [TeaRecipe], robLikes: [String],
                       beckyLikes: [String], calendar: Calendar) -> [String: String] {
        let eligible = Dictionary(recipes.filter(\.meetsTargets).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let beckySet = Set(beckyLikes)
        let both = robLikes.filter { beckySet.contains($0) }
        var used = Set<String>()
        var result: [String: String] = [:]
        // Quick nights first: they have fewer choices.
        let ordered = nights.sorted { lhs, rhs in
            let left = needsQuick(lhs, calendar: calendar), right = needsQuick(rhs, calendar: calendar)
            return left == right ? lhs < rhs : left
        }
        for night in ordered {
            let diner = diners[night.description] ?? .notCooking
            guard diner != .notCooking else { continue }
            let pool: [[String]]
            switch diner {
            case .together: pool = [both, robLikes, beckyLikes]
            case .rob: pool = [robLikes]
            case .becky: pool = [beckyLikes]
            case .notCooking: pool = []
            }
            let quick = needsQuick(night, calendar: calendar)
            let fits = { (recipe: TeaRecipe) in !quick || recipe.suitsAWeeknight }
            var pick: TeaRecipe?
            for allowRepeat in [false, true] where pick == nil {
                for likes in pool where pick == nil {
                    pick = likes.lazy.compactMap { eligible[$0] }
                        .first { fits($0) && (allowRepeat || !used.contains($0.id)) }
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
