import Foundation

// The Kitchen's 8-week cycle: one batch-cooked lunch (Monday to Friday) and one five-minute breakfast (every day) per
// week. Every meal is built from the catalogue by weight, so its numbers are calculated, not typed in, and the unit
// tests hold each one to its target: lunches ≈ 600 kcal, breakfasts ≈ 500 kcal, both 50 g+ protein and low fat.

enum CycleSlot: String, Codable, Sendable, CaseIterable, Identifiable {
    case breakfast, lunch

    var id: String { rawValue }
    var title: String { self == .breakfast ? "Breakfast" : "Lunch" }
    /// Portions needed each week: breakfast every day, lunch on work days.
    var portionsPerWeek: Int { self == .breakfast ? 7 : 5 }
    var targetKcal: Double { self == .breakfast ? 500 : 600 }
}

/// One ingredient of a single portion, by weight.
struct CycleIngredient: Sendable, Hashable {
    let foodID: String
    let grams: Double

    var food: FoodItem? { FoodCatalogue.byID[foodID] }

    /// "200 g chicken breast", "2 eggs" or "½ lemon": small things bought by the item are counted, everything
    /// else is weighed.
    func text(portions: Int = 1) -> String {
        let total = grams * Double(portions)
        guard let food else { return "\(Int(total)) g \(foodID)" }
        let name = food.name.lowercased()
        if food.isStaple && (food.per100?.kcal ?? 0) == 0 { return name }
        if food.pack.unit == .items, let each = food.gramsPerItem, each <= 130 {
            let halves = max(1, (total / each * 2).rounded())
            let count = halves / 2
            let whole = Int(count.rounded(.down))
            let half = halves.truncatingRemainder(dividingBy: 2) == 1
            let number = whole == 0 ? "½" : (half ? "\(whole)½" : "\(whole)")
            if food.id == "garlic" { return "\(number) garlic \(count <= 1 ? "clove" : "cloves")" }
            return "\(number) \(count <= 1 ? Self.singular(name) : name)"
        }
        let unit = food.pack.unit == .millilitres ? "ml" : "g"
        if total >= 1_000 {
            let kilos = total / 1_000
            let number = kilos.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(kilos)) : String(format: "%.1f", kilos)
            return "\(number) \(unit == "ml" ? "l" : "kg") \(name)"
        }
        return "\(Int(total.rounded())) \(unit) \(name)"
    }

    private static func singular(_ name: String) -> String {
        if name.hasSuffix("oes") { return String(name.dropLast(2)) }
        if name.hasSuffix("s") { return String(name.dropLast()) }
        return name
    }
}

struct CycleMeal: Sendable, Hashable, Identifiable {
    let id: String
    let slot: CycleSlot
    /// 1 to 8.
    let week: Int
    let title: String
    let summary: String
    let prepMinutes: Int
    let cookMinutes: Int
    let ingredients: [CycleIngredient]
    let steps: [String]
    /// How to keep it: fridge days, freezing, reheating.
    let storage: String
    let symbol: String

    /// Per portion, from the catalogue.
    var macros: Macros {
        ingredients.reduce(Macros.zero) { total, ingredient in
            guard let per100 = ingredient.food?.per100 else { return total }
            return total + per100.scaled(ingredient.grams / 100)
        }
    }
}

enum MealCycle {
    static let weeks = 8

    /// The cycle week (1...8) that `day` falls in, counting from the Monday that started week 1.
    static func week(of day: DayKey, anchor: DayKey, calendar: Calendar) -> Int {
        let start = anchor.startDate(calendar: calendar)
        let date = day.startDate(calendar: calendar)
        let days = calendar.dateComponents([.day], from: start, to: date).day ?? 0
        let offset = Int((Double(days) / 7).rounded(.down))
        return ((offset % weeks) + weeks) % weeks + 1
    }

    /// The Monday that makes `today` fall in `week`.
    static func anchor(today: DayKey, week: Int, calendar: Calendar) -> DayKey {
        let monday = mondayOf(today, calendar: calendar)
        return monday.adding(days: -7 * (min(max(week, 1), weeks) - 1), calendar: calendar)
    }

    static func mondayOf(_ day: DayKey, calendar: Calendar) -> DayKey {
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        return day.adding(days: -((weekday + 5) % 7), calendar: calendar)
    }

    static func meal(_ slot: CycleSlot, week: Int) -> CycleMeal {
        let list = slot == .breakfast ? breakfasts : lunches
        return list[(min(max(week, 1), weeks) - 1) % list.count]
    }

    static func meal(id: String) -> CycleMeal? {
        (lunches + breakfasts).first { $0.id == id }
    }

    private static func g(_ id: String, _ grams: Double) -> CycleIngredient {
        CycleIngredient(foodID: id, grams: grams)
    }

    // MARK: Lunches: batch-cook five on Sunday

    static let lunches: [CycleMeal] = makeLunches()

    private static func makeLunches() -> [CycleMeal] {
        var list: [CycleMeal] = []
        list.append(CycleMeal(
            id: "lunch-burrito", slot: .lunch, week: 1, title: "Chicken burrito bowls",
            summary: "Fajita-spiced chicken, rice, beans, peppers and salsa.", prepMinutes: 15, cookMinutes: 25,
            ingredients: [g("chicken-breast", 200), g("rice", 75), g("kidney-beans", 60), g("peppers", 80), g("salsa", 60),
                          g("onion", 40), g("fajita-seasoning", 5), g("spray-oil", 1)],
            steps: ["Cook the rice.",
                    "Slice the chicken, onions and peppers; toss the chicken in the fajita seasoning.",
                    "Fry the chicken in spray oil for 8 minutes, add the onions and peppers for 5 more, then the drained beans.",
                    "Split the rice and chicken between five boxes and top each with salsa."],
            storage: "Fridge for 4 days. Reheat until piping hot.", symbol: "flame.fill"))
        list.append(CycleMeal(
            id: "lunch-chilli", slot: .lunch, week: 2, title: "Turkey chilli and rice",
            summary: "Lean turkey chilli with kidney beans over rice.", prepMinutes: 10, cookMinutes: 35,
            ingredients: [g("turkey-mince", 200), g("rice", 65), g("kidney-beans", 70), g("chopped-tomatoes", 160),
                          g("onion", 50), g("peppers", 60), g("fajita-seasoning", 4), g("spray-oil", 1)],
            steps: ["Soften the chopped onion and pepper in spray oil for 5 minutes.",
                    "Brown the turkey mince, then stir in the seasoning, tomatoes and drained beans.",
                    "Simmer for 25 minutes while the rice cooks.",
                    "Portion into five boxes."],
            storage: "Fridge for 4 days, or freeze. Reheat until piping hot.", symbol: "flame.fill"))
        list.append(CycleMeal(
            id: "lunch-tikka", slot: .lunch, week: 3, title: "Chicken tikka and rice",
            summary: "Yoghurt-marinated chicken tikka with spinach and basmati.", prepMinutes: 15, cookMinutes: 25,
            ingredients: [g("chicken-breast", 200), g("rice", 80), g("greek-yoghurt", 60), g("curry-paste", 12),
                          g("onion", 50), g("spinach", 50), g("spray-oil", 1)],
            steps: ["Mix the yoghurt and tikka paste; coat the diced chicken.",
                    "Cook the rice.",
                    "Fry the onion in spray oil, add the chicken and cook for 12 minutes, then wilt in the spinach.",
                    "Portion into five boxes."],
            storage: "Fridge for 4 days. Reheat until piping hot.", symbol: "flame.fill"))
        list.append(CycleMeal(
            id: "lunch-teriyaki", slot: .lunch, week: 4, title: "Teriyaki chicken noodles",
            summary: "Soy and honey chicken with stir-fry veg and egg noodles.", prepMinutes: 10, cookMinutes: 15,
            ingredients: [g("chicken-breast", 200), g("noodles", 80), g("stir-fry-veg", 150), g("soy-sauce", 15),
                          g("honey", 12), g("garlic", 4), g("spray-oil", 1)],
            steps: ["Cook the noodles, drain and rinse under cold water.",
                    "Stir-fry the sliced chicken in spray oil for 7 minutes, then the veg and garlic for 3.",
                    "Add the soy sauce and honey, then toss through the noodles.",
                    "Portion into five boxes."],
            storage: "Fridge for 4 days. Reheat until piping hot.", symbol: "frying.pan.fill"))
        list.append(CycleMeal(
            id: "lunch-bolognese", slot: .lunch, week: 5, title: "Lean beef bolognese",
            summary: "5% beef ragu with peppers over pasta.", prepMinutes: 10, cookMinutes: 30,
            ingredients: [g("beef-mince-5", 190), g("pasta", 80), g("chopped-tomatoes", 160), g("onion", 50),
                          g("peppers", 50), g("dried-herbs", 1), g("spray-oil", 1)],
            steps: ["Soften the onion and pepper in spray oil.",
                    "Brown the mince, add the tomatoes and herbs, and simmer for 20 minutes.",
                    "Cook the pasta and stir it through the sauce.",
                    "Portion into five boxes."],
            storage: "Fridge for 4 days, or freeze. Reheat until piping hot.", symbol: "fork.knife"))
        list.append(CycleMeal(
            id: "lunch-orzo", slot: .lunch, week: 6, title: "Lemon chicken orzo",
            summary: "Garlic and lemon chicken orzo with spinach.", prepMinutes: 10, cookMinutes: 20,
            ingredients: [g("chicken-breast", 200), g("orzo", 90), g("spinach", 60), g("lemon", 30), g("stock", 5),
                          g("garlic", 4), g("greek-yoghurt", 40), g("spray-oil", 1)],
            steps: ["Fry the diced chicken and garlic in spray oil for 8 minutes.",
                    "Add the orzo and the stock made up to 1 litre; simmer for 10 minutes, stirring.",
                    "Stir in the spinach, lemon juice and zest, then the yoghurt off the heat.",
                    "Portion into five boxes."],
            storage: "Fridge for 4 days. Add a splash of water when reheating.", symbol: "frying.pan.fill"))
        list.append(CycleMeal(
            id: "lunch-tuna-pasta", slot: .lunch, week: 7, title: "Tuna and sweetcorn pasta",
            summary: "Creamy yoghurt tuna pasta with veg and a little cheese.", prepMinutes: 10, cookMinutes: 12,
            ingredients: [g("tuna", 140), g("pasta", 85), g("frozen-veg", 80), g("greek-yoghurt", 60),
                          g("light-cheddar", 15), g("lemon", 15)],
            steps: ["Cook the pasta, adding the frozen veg for the last 3 minutes; drain and cool.",
                    "Mix the drained tuna with the yoghurt, lemon juice and grated cheese.",
                    "Stir everything together and portion into five boxes."],
            storage: "Fridge for 3 days. Good cold or warmed through.", symbol: "fish.fill"))
        list.append(CycleMeal(
            id: "lunch-traybake", slot: .lunch, week: 8, title: "Chicken and sweet potato traybake",
            summary: "Spiced chicken, roast sweet potato, peppers and beans, with a yoghurt dip.", prepMinutes: 15,
            cookMinutes: 35,
            ingredients: [g("chicken-breast", 210), g("sweet-potato", 320), g("peppers", 80), g("green-beans", 80),
                          g("fajita-seasoning", 4), g("greek-yoghurt", 60), g("spray-oil", 1)],
            steps: ["Heat the oven to 200°C. Cube the sweet potato and roast with spray oil for 15 minutes.",
                    "Add the seasoned chicken and sliced peppers and roast for 20 minutes more.",
                    "Steam the green beans.",
                    "Portion into five boxes with a pot of yoghurt each."],
            storage: "Fridge for 4 days. Reheat until piping hot; keep the yoghurt cold.", symbol: "oven.fill"))
        return list
    }

    // MARK: Breakfasts: five minutes, every day

    static let breakfasts: [CycleMeal] = makeBreakfasts()

    private static func makeBreakfasts() -> [CycleMeal] {
        var list: [CycleMeal] = []
        list.append(CycleMeal(
            id: "breakfast-overnight-oats", slot: .breakfast, week: 1, title: "Protein overnight oats",
            summary: "Oats, skyr, protein and berries, made the night before.", prepMinutes: 3, cookMinutes: 0,
            ingredients: [g("oats", 50), g("skyr", 150), g("protein-powder", 32), g("milk", 120), g("berries", 80)],
            steps: ["The night before: stir the oats, protein powder, milk and skyr together in a tub.",
                    "Top with the berries and leave in the fridge overnight."],
            storage: "Make up to two days ahead.", symbol: "takeoutbag.and.cup.and.straw.fill"))
        list.append(CycleMeal(
            id: "breakfast-skyr-bowl", slot: .breakfast, week: 2, title: "Skyr berry crunch bowl",
            summary: "Protein skyr with berries, toasted oats and honey.", prepMinutes: 4, cookMinutes: 0,
            ingredients: [g("skyr", 300), g("protein-powder", 20), g("berries", 100), g("oats", 40), g("honey", 8)],
            steps: ["Stir the protein powder into the skyr.",
                    "Top with the berries (straight from frozen is fine), oats and honey."],
            storage: "Assemble fresh.", symbol: "mug.fill"))
        list.append(CycleMeal(
            id: "breakfast-bacon-wrap", slot: .breakfast, week: 3, title: "Bacon wrap and yoghurt",
            summary: "Bacon medallions, cottage cheese and tomato in a wrap, yoghurt on the side.", prepMinutes: 5,
            cookMinutes: 0,
            ingredients: [g("bacon", 120), g("wraps", 62), g("cottage-cheese", 80), g("tomatoes", 60),
                          g("greek-yoghurt", 150)],
            steps: ["Microwave the bacon medallions on a plate for 2 minutes, or grill them.",
                    "Spread the wrap with cottage cheese, add the bacon and sliced tomato, and roll.",
                    "Yoghurt on the side."],
            storage: "Assemble fresh.", symbol: "takeoutbag.and.cup.and.straw.fill"))
        list.append(CycleMeal(
            id: "breakfast-shake", slot: .breakfast, week: 4, title: "Banana protein shake and skyr",
            summary: "A thick banana shake and a pot of skyr.", prepMinutes: 3, cookMinutes: 0,
            ingredients: [g("protein-powder", 40), g("milk", 300), g("bananas", 120), g("skyr", 120)],
            steps: ["Blend the milk, protein powder and banana.",
                    "Have the skyr alongside."],
            storage: "Blend fresh.", symbol: "mug.fill"))
        list.append(CycleMeal(
            id: "breakfast-porridge", slot: .breakfast, week: 5, title: "Chocolate protein porridge",
            summary: "Microwave porridge with chocolate protein, skyr and banana.", prepMinutes: 2, cookMinutes: 3,
            ingredients: [g("oats", 45), g("milk", 200), g("protein-powder", 40), g("skyr", 100), g("bananas", 40)],
            steps: ["Microwave the oats and milk for 2½ minutes, stirring halfway.",
                    "Stir in the protein powder and a splash of water, then the skyr.",
                    "Top with sliced banana."],
            storage: "Make fresh.", symbol: "mug.fill"))
        list.append(CycleMeal(
            id: "breakfast-ham-toast", slot: .breakfast, week: 6, title: "Ham and cottage cheese toast",
            summary: "Wholemeal toast with cottage cheese, ham and tomato, skyr on the side.", prepMinutes: 5,
            cookMinutes: 0,
            ingredients: [g("bread", 80), g("ham", 100), g("cottage-cheese", 150), g("tomatoes", 80), g("skyr", 100)],
            steps: ["Toast two slices.",
                    "Top with cottage cheese, ham and sliced tomato; black pepper.",
                    "Skyr on the side."],
            storage: "Assemble fresh.", symbol: "fork.knife"))
        list.append(CycleMeal(
            id: "breakfast-smoothie-bowl", slot: .breakfast, week: 7, title: "Berry protein smoothie bowl",
            summary: "Thick berry yoghurt bowl with banana and oats.", prepMinutes: 4, cookMinutes: 0,
            ingredients: [g("greek-yoghurt", 250), g("protein-powder", 30), g("berries", 150), g("bananas", 60), g("oats", 30)],
            steps: ["Blend the yoghurt, protein powder and frozen berries until thick.",
                    "Top with sliced banana and the oats."],
            storage: "Blend fresh.", symbol: "mug.fill"))
        list.append(CycleMeal(
            id: "breakfast-egg-bacon", slot: .breakfast, week: 8, title: "Egg and bacon on toast",
            summary: "Microwave egg and bacon on wholemeal toast, skyr and berries after.", prepMinutes: 5,
            cookMinutes: 0,
            ingredients: [g("eggs", 58), g("bacon", 90), g("bread", 80), g("skyr", 170), g("berries", 60)],
            steps: ["Microwave the bacon for 2 minutes. Beat the egg in a mug and microwave for 50 seconds.",
                    "Toast the bread and stack it up.",
                    "Skyr with berries afterwards."],
            storage: "Make fresh.", symbol: "fork.knife"))
        return list
    }
}

// MARK: - Shopping

/// One line of a weekly Aldi list, already rounded to whole packs.
struct CycleShoppingLine: Sendable, Hashable, Identifiable {
    let foodID: String
    let name: String
    let department: AisleDepartment
    /// e.g. "1 kg" or "10 eggs".
    let needed: String
    /// e.g. "2 × 650 g".
    let packs: String
    let pricePence: Int
    /// Staples, and long-life packs a week barely uses: check the cupboard before buying.
    let checkFirst: Bool

    var id: String { foodID }
}

enum CycleShopping {
    /// Everything for one meal's week of portions, in Aldi walking order.
    static func list(for meal: CycleMeal, portions: Int? = nil) -> [CycleShoppingLine] {
        let count = portions ?? meal.slot.portionsPerWeek
        var lines: [CycleShoppingLine] = []
        for ingredient in meal.ingredients {
            guard let food = ingredient.food else { continue }
            let total = ingredient.grams * Double(count)
            let packCount = packsNeeded(food, grams: total)
            let packText = packDescription(food, count: packCount)
            let checkFirst = food.isStaple || barelyUsed(food, grams: total, packs: packCount)
            lines.append(CycleShoppingLine(foodID: food.id, name: food.name, department: food.department,
                                           needed: ingredient.text(portions: count), packs: packText,
                                           pricePence: packCount * food.pack.pricePence, checkFirst: checkFirst))
        }
        let order = AisleDepartment.allCases
        return lines.sorted { left, right in
            let l = order.firstIndex(of: left.department) ?? 0
            let r = order.firstIndex(of: right.department) ?? 0
            return l == r ? left.name < right.name : l < r
        }
    }

    /// The list as plain text for Messages, WhatsApp or Notes: one list in Aldi walking order, with lunch and
    /// breakfast amounts of the same thing on one line, and cupboard checks at the end.
    static func shareText(heading: String, meals: [String], lines: [CycleShoppingLine]) -> String {
        var merged: [CycleShoppingLine] = []
        for line in lines {
            if let index = merged.firstIndex(where: { $0.foodID == line.foodID }) {
                let first = merged[index]
                merged[index] = CycleShoppingLine(foodID: first.foodID, name: first.name, department: first.department,
                                                  needed: "\(first.needed) + \(line.needed)",
                                                  packs: "\(first.packs) + \(line.packs)",
                                                  pricePence: first.pricePence + line.pricePence,
                                                  checkFirst: first.checkFirst && line.checkFirst)
            } else {
                merged.append(line)
            }
        }
        let order = AisleDepartment.allCases
        merged.sort { left, right in
            let l = order.firstIndex(of: left.department) ?? 0
            let r = order.firstIndex(of: right.department) ?? 0
            return l == r ? left.name < right.name : l < r
        }

        var text = [heading] + meals
        for department in order {
            let buy = merged.filter { $0.department == department && !$0.checkFirst }
            guard !buy.isEmpty else { continue }
            text.append("")
            text.append("\(department.title):")
            text += buy.map { "☐ \($0.name) (\($0.packs))" }
        }
        let cupboard = merged.filter(\.checkFirst)
        if !cupboard.isEmpty {
            text.append("")
            text.append("Check the cupboard first:")
            text += cupboard.map { "☐ \($0.name) (\($0.needed))" }
        }
        if !merged.isEmpty {
            text.append("")
            text.append("About \(estimate(merged).formatted()) at Aldi")
        }
        return text.joined(separator: "\n")
    }

    /// Estimated cost of the lines you'll actually buy (long-life things you might have are left out).
    static func estimate(_ lines: [CycleShoppingLine]) -> Pence {
        Pence(lines.filter { !$0.checkFirst }.reduce(0) { $0 + $1.pricePence })
    }

    /// Long-life packs a week only dents (rice, oats, protein powder) are probably already in the cupboard.
    /// Tins and jars the week uses up still go on the list.
    static func barelyUsed(_ food: FoodItem, grams: Double, packs: Int) -> Bool {
        guard food.shelfLifeDays >= 90, packs == 1 else { return false }
        let packGrams: Double
        if food.pack.unit == .items {
            packGrams = food.pack.amount * (food.gramsPerItem ?? grams)
        } else {
            packGrams = food.pack.amount
        }
        return grams < packGrams * 0.6
    }

    static func packsNeeded(_ food: FoodItem, grams: Double) -> Int {
        guard grams > 0 else { return 0 }
        switch food.pack.unit {
        case .items:
            let perItem = food.gramsPerItem ?? grams
            let items = (grams / perItem).rounded(.up)
            return max(1, Int((items / max(food.pack.amount, 1)).rounded(.up)))
        case .grams, .millilitres:
            return max(1, Int((grams / food.pack.amount).rounded(.up)))
        }
    }

    private static func packDescription(_ food: FoodItem, count: Int) -> String {
        let size: String
        switch food.pack.unit {
        case .items:
            if food.pack.amount == 1, let each = food.gramsPerItem {
                size = "\(Int(each)) g"
            } else {
                size = food.pack.amount == 1 ? "" : "pack of \(Int(food.pack.amount))"
            }
        case .grams:
            size = food.pack.amount >= 1_000 ? "\(formatted(food.pack.amount / 1_000)) kg" : "\(Int(food.pack.amount)) g"
        case .millilitres:
            size = food.pack.amount >= 1_000 ? "\(formatted(food.pack.amount / 1_000)) l" : "\(Int(food.pack.amount)) ml"
        }
        if size.isEmpty { return count == 1 ? "1" : "\(count)" }
        return count == 1 ? size : "\(count) × \(size)"
    }

    private static func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}
