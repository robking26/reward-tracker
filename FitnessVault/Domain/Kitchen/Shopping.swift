import Foundation

// MARK: Inventory (I4)

enum InventorySource: String, Codable, Sendable {
    case receipt, userStated, batchCook, manual
}

/// How likely something is to be in the house. There's deliberately no "definitely": only the user can say that,
/// and only recently (I4).
enum Presence: String, Codable, Sendable, Comparable, CaseIterable {
    case out, probablyNot, maybe, probably, have

    var title: String {
        switch self {
        case .out: "Out"
        case .probablyNot: "Probably gone"
        case .maybe: "Might be in, check"
        case .probably: "Probably in"
        case .have: "You said it's in"
        }
    }

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func < (lhs: Presence, rhs: Presence) -> Bool { lhs.order < rhs.order }

    var lower: Presence {
        switch self {
        case .have: .probably
        case .probably: .maybe
        case .maybe, .probablyNot: .probablyNot
        case .out: .out
        }
    }
}

struct InventorySnapshot: Sendable, Hashable {
    var addedAt: Date?
    var source: InventorySource
    /// The user said it's there.
    var confirmedAt: Date?
    /// The user said it's run out.
    var outAt: Date?
    var shelfLifeDays: Int
    /// A planned meal has probably used some since.
    var usedSinceAdded: Bool
    /// Counted things, e.g. freezer portions.
    var portions: Int?
}

enum InventoryEstimator {
    static func presence(_ item: InventorySnapshot, now: Date) -> Presence {
        let lastIn = [item.addedAt, item.confirmedAt].compactMap { $0 }.max()
        if let out = item.outAt, lastIn.map({ out >= $0 }) ?? true { return .out }
        if let portions = item.portions, portions <= 0 { return .out }

        func days(since date: Date) -> Double { now.timeIntervalSince(date) / 86_400 }
        let shelf = Double(max(1, item.shelfLifeDays))
        var result: Presence
        if let confirmed = item.confirmedAt, confirmed >= (item.addedAt ?? .distantPast) {
            let age = days(since: confirmed)
            result = age <= 2 ? .have : age <= shelf ? .probably : .maybe
        } else if let added = item.addedAt {
            // A receipt says it was bought, not that it's still there.
            let age = days(since: added)
            if item.source == .batchCook || item.source == .userStated || item.source == .manual {
                result = age <= 2 ? .have : age <= shelf ? .probably : .maybe
            } else {
                result = age <= shelf / 2 ? .probably : age <= shelf ? .maybe : .probablyNot
            }
        } else {
            return .probablyNot
        }
        if item.usedSinceAdded && item.portions == nil { result = result.lower }
        return result
    }
}

// MARK: Shopping list (I2)

struct ShoppingNeed: Sendable, Hashable {
    var foodID: String?
    var name: String
    var amount: Double?
    var unit: KitchenUnit?
    var forMeal: String

    init(_ ingredient: RecipeIngredient, forMeal: String) {
        foodID = ingredient.foodID
        name = ingredient.name
        amount = ingredient.amount
        unit = ingredient.unit
        self.forMeal = forMeal
    }

    init(foodID: String?, name: String, amount: Double?, unit: KitchenUnit?, forMeal: String) {
        self.foodID = foodID
        self.name = name
        self.amount = amount
        self.unit = unit
        self.forMeal = forMeal
    }
}

struct ShoppingLine: Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var department: AisleDepartment
    var packs: Int
    var quantityText: String
    var estimatePence: Int?
    var reasons: [String]
    /// It might be in already: worth a look before buying.
    var checkFirst: Bool
}

enum ShoppingListBuilder {
    /// Consolidates needs, takes off what's probably in, rounds up to real pack sizes and groups by Aldi department.
    /// `extras` are things the user asked for or ran out of; they're always included.
    static func build(needs: [ShoppingNeed], presence: (FoodItem) -> Presence?, extras: [String] = []) -> [ShoppingLine] {
        var grouped: [String: (FoodItem?, String, Double, Bool, [String])] = [:] // key → (food, name, base amount, amountKnown, meals)
        for need in needs {
            let food = need.foodID.flatMap { FoodCatalogue.byID[$0] }
            let key = food?.id ?? need.name.lowercased()
            var entry = grouped[key] ?? (food, food?.name ?? need.name.capitalized, 0, true, [])
            if let amount = baseAmount(need, food: food) {
                entry.2 += amount
            } else {
                entry.3 = false
            }
            if !entry.4.contains(need.forMeal) { entry.4.append(need.forMeal) }
            grouped[key] = entry
        }

        var lines: [ShoppingLine] = []
        for (key, entry) in grouped {
            let (food, name, amount, known, meals) = entry
            let state = food.flatMap(presence)
            var checkFirst = false
            if let food {
                switch state {
                case .have, .probably: continue
                case .maybe: checkFirst = true
                case .out, .probablyNot: break
                case .none: if food.isStaple { continue }
                }
            }
            let packs = food.map { packsNeeded(amount: known ? amount : 0, food: $0) } ?? 1
            lines.append(ShoppingLine(id: key, name: name, department: food?.department ?? .other, packs: packs,
                                      quantityText: food.map { packText($0, packs: packs) } ?? "",
                                      estimatePence: food.map { $0.pack.pricePence * packs },
                                      reasons: meals, checkFirst: checkFirst))
        }
        for extra in extras {
            let food = FoodCatalogue.match(extra)
            let key = food?.id ?? extra.lowercased()
            if let index = lines.firstIndex(where: { $0.id == key }) {
                lines[index].checkFirst = false
                if !lines[index].reasons.contains("You asked") { lines[index].reasons.append("You asked") }
                continue
            }
            lines.append(ShoppingLine(id: key, name: food?.name ?? extra.capitalized, department: food?.department ?? .other,
                                      packs: 1, quantityText: food.map { packText($0, packs: 1) } ?? "",
                                      estimatePence: food?.pack.pricePence, reasons: ["You asked"], checkFirst: false))
        }
        let order = AisleDepartment.allCases
        return lines.sorted {
            let left = order.firstIndex(of: $0.department) ?? 0
            let right = order.firstIndex(of: $1.department) ?? 0
            return left != right ? left < right : $0.name < $1.name
        }
    }

    static func estimate(_ lines: [ShoppingLine]) -> Pence {
        lines.sum { Pence($0.estimatePence ?? 0) }
    }

    /// The need in the pack's own unit.
    private static func baseAmount(_ need: ShoppingNeed, food: FoodItem?) -> Double? {
        guard let amount = need.amount else { return nil }
        guard let food else { return amount }
        let packUnit = food.pack.unit
        let unit = need.unit ?? .items
        if unit == packUnit { return amount }
        if packUnit == .items, let each = food.gramsPerItem, unit != .items { return amount / each }
        if unit == .items, let each = food.gramsPerItem { return amount * each }
        // Grams and millilitres are close enough for shopping.
        if packUnit != .items && unit != .items { return amount }
        return nil
    }

    static func packsNeeded(amount: Double, food: FoodItem) -> Int {
        guard amount > 0, food.pack.amount > 0 else { return 1 }
        return max(1, Int((amount / food.pack.amount - 0.05).rounded(.up)))
    }

    static func packText(_ food: FoodItem, packs: Int) -> String {
        let size: String
        switch food.pack.unit {
        case .grams: size = food.pack.amount >= 1000 ? "\(formatted(food.pack.amount / 1000)) kg" : "\(Int(food.pack.amount)) g"
        case .millilitres: size = food.pack.amount >= 1000 ? "\(formatted(food.pack.amount / 1000)) l" : "\(Int(food.pack.amount)) ml"
        case .items: size = food.pack.amount > 1 ? "pack of \(Int(food.pack.amount))" : ""
        }
        if size.isEmpty { return packs == 1 ? "1" : "\(packs)" }
        return packs == 1 ? size : "\(packs) × \(size)"
    }

    private static func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }
}

// MARK: Household budget (I1)

/// The £400 a month household ceiling. A ceiling, not a target: nothing here ever suggests spending what's left.
struct HouseholdBudget: Sendable, Hashable {
    static let ceiling = Pence.pounds(400)

    var spent: Pence
    var dayOfMonth: Int
    var daysInMonth: Int

    var remaining: Pence { (Self.ceiling - spent).nonNegative }
    var isOver: Bool { spent > Self.ceiling }

    /// Where spending would be by now if it were spread evenly, for a calm comparison.
    var evenPace: Pence {
        Pence(Self.ceiling.value * dayOfMonth / max(1, daysInMonth))
    }

    var summary: String {
        if isOver { return "\((spent - Self.ceiling).formatted()) over the £400 ceiling this month." }
        if spent > evenPace + Pence.pounds(30) { return "A bit ahead of an even pace. \(remaining.formatted()) left under the ceiling." }
        return "\(remaining.formatted()) left under the ceiling. It's a ceiling, not a target."
    }

    /// A note for a list that would push the month over the ceiling.
    func warning(forList estimate: Pence) -> String? {
        guard spent + estimate > Self.ceiling else { return nil }
        return "This list (about \(estimate.formatted())) would take the month to \((spent + estimate).formatted()), over the £400 ceiling. Drop anything that can wait, or swap for cheaper cuts."
    }
}

// MARK: Receipts (I3)

enum Merchant: String, Codable, Sendable, CaseIterable, Identifiable {
    case aldi, coop, takeaway, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .aldi: "Aldi"
        case .coop: "Co-op"
        case .takeaway: "Takeaway or meal out"
        case .other: "Other"
        }
    }
}

struct ReceiptLine: Codable, Sendable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var quantity: Int
    var pricePence: Int
    var foodID: String?
    /// Hard to read, or doesn't add up: shown for review (I3).
    var uncertain: Bool
}

struct ParsedReceipt: Sendable, Hashable {
    var merchant: Merchant
    var date: Date?
    var lines: [ReceiptLine]
    var totalPence: Int?
    /// The lines don't add up to the total, or key fields are missing.
    var needsReview: Bool

    var effectiveTotal: Int { totalPence ?? lines.reduce(0) { $0 + $1.pricePence } }
}

enum ReceiptParser {
    private static let ignored = ["subtotal", "sub total", "change", "card", "visa", "mastercard", "contactless", "cash", "vat",
                                  "tax", "balance", "tendered", "auth", "merchant", "terminal", "aid:", "pan seq", "thank",
                                  "savings", "you saved", "points", "multibuy", "receipt", "store", "tel", "www", "items sold"]
    private static let takeawayWords = ["deliveroo", "just eat", "uber eats", "pizza", "kebab", "chinese", "indian", "takeaway",
                                        "chippy", "fish bar", "restaurant", "burger", "nando", "wetherspoon", "pub", "tavern"]

    static func parse(_ text: String, calendar: Calendar = .current) -> ParsedReceipt {
        let lower = text.lowercased()
        let merchant: Merchant
        if lower.contains("aldi") { merchant = .aldi }
        else if lower.contains("co-op") || lower.contains("coop") || lower.contains("co op") || lower.contains("co-operative") { merchant = .coop }
        else if takeawayWords.contains(where: { lower.contains($0) }) { merchant = .takeaway }
        else { merchant = .other }

        var total: Int?
        var lines: [ReceiptLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lowerLine = line.lowercased()
            guard let price = trailingPrice(line) else { continue }
            if lowerLine.contains("total") && !lowerLine.contains("sub") || lowerLine.hasPrefix("amount due") || lowerLine.hasPrefix("to pay") {
                total = price.pence
                continue
            }
            if ignored.contains(where: { lowerLine.contains($0) }) { continue }
            var name = price.rest.trimmingCharacters(in: CharacterSet(charactersIn: " £*"))
            var quantity = 1
            // "2 x Milk" or "Milk 2 @ 1.45"
            if let groups = RegexHelper.firstMatch(#"^(\d+)\s*[x@]\s*(.+)$"#, in: name), let count = Int(groups[0]) {
                quantity = count
                name = groups[1]
            } else if let groups = RegexHelper.firstMatch(#"^(.+?)\s+(\d+)\s*@\s*£?\d+\.\d{2}$"#, in: name), let count = Int(groups[1]) {
                quantity = count
                name = groups[0]
            }
            let letters = name.filter(\.isLetter).count
            guard letters > 0 else { continue }
            lines.append(ReceiptLine(name: name, quantity: quantity, pricePence: price.pence,
                                     foodID: FoodCatalogue.match(name)?.id, uncertain: letters < 3 || price.pence <= 0))
        }

        let date = parseDate(text, calendar: calendar)
        let sum = lines.reduce(0) { $0 + $1.pricePence }
        var needsReview = date == nil || total == nil || lines.isEmpty
        if let total, abs(total - sum) > 1 { needsReview = true }
        return ParsedReceipt(merchant: merchant, date: date, lines: lines, totalPence: total, needsReview: needsReview)
    }

    /// The same shop on the same day for the same total is treated as the same receipt (I3: duplicates refused).
    static func fingerprint(merchant: Merchant, day: DayKey, totalPence: Int) -> String {
        "\(merchant.rawValue)|\(day.description)|\(totalPence)"
    }

    private static func trailingPrice(_ line: String) -> (rest: String, pence: Int)? {
        guard let groups = RegexHelper.firstMatch(#"^(.*?)\s*(-?)£?\s?(\d{1,4})[.,](\d{2})\s*[A-Z]?\s*$"#, in: line),
              groups.count == 4, let pounds = Int(groups[2]), let pence = Int(groups[3]) else { return nil }
        let value = pounds * 100 + pence
        return (groups[0], groups[1] == "-" ? -value : value)
    }

    private static func parseDate(_ text: String, calendar: Calendar) -> Date? {
        guard let groups = RegexHelper.firstMatch(#"\b(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})\b"#, in: text),
              let day = Int(groups[0]), let month = Int(groups[1]), var year = Int(groups[2]),
              (1...31).contains(day), (1...12).contains(month) else { return nil }
        if year < 100 { year += 2000 }
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}

// MARK: Household chains (H1)

/// A routine job whose stages depend on each other. Doing the first stage doesn't finish the job.
struct ChainTemplate: Sendable, Hashable, Identifiable {
    var id: String
    var title: String
    var steps: [ChainStep]
}

struct ChainStep: Sendable, Hashable {
    var title: String
    var minutes: Int
}

enum HouseholdChains {
    static let all: [ChainTemplate] = [
        ChainTemplate(id: "laundry", title: "Laundry", steps: [
            ChainStep(title: "Put a wash on", minutes: 5),
            ChainStep(title: "Hang it out or put it in the dryer", minutes: 10),
            ChainStep(title: "Fold it and put it away", minutes: 10),
        ]),
        ChainTemplate(id: "gym-kit", title: "Gym kit ready", steps: [
            ChainStep(title: "Wash gym kit and swim things", minutes: 5),
            ChainStep(title: "Dry gym kit", minutes: 5),
            ChainStep(title: "Pack the gym bag", minutes: 5),
        ]),
        ChainTemplate(id: "batch-cook", title: "Weekly batch cook", steps: [
            ChainStep(title: "Clear the worktop and wash the big pan", minutes: 10),
            ChainStep(title: "Cook the lunches", minutes: 40),
            ChainStep(title: "Portion into tubs: fridge and freezer", minutes: 10),
            ChainStep(title: "Wash up", minutes: 10),
        ]),
        ChainTemplate(id: "kitchen-reset", title: "Kitchen reset", steps: [
            ChainStep(title: "Wash up", minutes: 10),
            ChainStep(title: "Wipe the sides and hob", minutes: 5),
            ChainStep(title: "Take the bins out", minutes: 5),
        ]),
    ]

    static func template(_ id: String) -> ChainTemplate? { all.first { $0.id == id } }
}
