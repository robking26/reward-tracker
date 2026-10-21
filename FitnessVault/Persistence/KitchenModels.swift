import Foundation
import SwiftData

// Retired: the dinner planner, recipe library, stock tracking, receipts and the old shopping list. The Kitchen is now
// the 8-week lunch and breakfast cycle plus a food log. These definitions keep exactly the stored properties of the
// originals so existing stores keep opening; nothing reads or writes them.

@Model
final class Recipe {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var roleRaw: String = ""
    var servings: Int = 0
    var ingredientsData: Data = Data()
    var steps: [String] = []
    var prepMinutes: Int = 0
    var cookMinutes: Int = 0
    var washUpMinutes: Int = 0
    var usesSlowCooker: Bool = false
    var isFakeaway: Bool = false
    var freezable: Bool = false
    var favourite: Bool = false
    var sourceRaw: String = ""
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var confidenceRaw: String = ""
    var notes: String?
    var createdAt: Date = Date.distantPast
    var lastCookedAt: Date?
    var timesCooked: Int = 0
    var archived: Bool = false

    init() {}
}

@Model
final class MealPlanEntry {
    var id: UUID = UUID()
    var day: String = ""
    var slotRaw: String = ""
    var recipeID: UUID?
    var title: String = ""
    var portions: Int = 0
    var fromFreezer: Bool = false
    var note: String?
    var defrosted: Bool = false
    var cooked: Bool = false
    var createdAt: Date = Date.distantPast

    init() {}
}

@Model
final class InventoryItem {
    @Attribute(.unique) var key: String = ""
    var name: String = ""
    var foodID: String?
    var locationRaw: String = ""
    var sourceRaw: String = ""
    var addedAt: Date?
    var confirmedAt: Date?
    var outAt: Date?
    var portions: Int?
    var usedSinceAdded: Bool = false
    var updatedAt: Date = Date.distantPast

    init() {}
}

@Model
final class ReceiptRecord {
    @Attribute(.unique) var fingerprint: String = ""
    var id: UUID = UUID()
    var merchantRaw: String = ""
    var date: Date = Date.distantPast
    var month: String = ""
    var totalPence: Int = 0
    var linesData: Data = Data()
    var needsReview: Bool = false
    var manual: Bool = false
    var createdAt: Date = Date.distantPast

    init() {}
}

@Model
final class ShoppingItem {
    @Attribute(.unique) var key: String = ""
    var name: String = ""
    var departmentRaw: String = ""
    var quantityText: String = ""
    var estimatePence: Int?
    var reasons: [String] = []
    var checkFirst: Bool = false
    var manual: Bool = false
    var ticked: Bool = false
    var createdAt: Date = Date.distantPast

    init() {}
}

// MARK: - Food log

/// Something eaten, logged by barcode, by hand, or from the cycle. Per-entry totals, not per 100 g.
@Model
final class FoodLogEntry {
    @Attribute(.unique) var id: UUID = UUID()
    var date: Date = Date.distantPast
    /// `yyyy-MM-dd`, for grouping by day.
    var day: String = ""
    /// "breakfast", "lunch", "evening" or "snack".
    var mealRaw: String = ""
    var name: String = ""
    var brand: String?
    var barcode: String?
    /// "cycle", "barcode" or "manual".
    var sourceRaw: String = ""
    /// What was eaten, e.g. "150 g" or "1 serving".
    var amountText: String = ""
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    init(date: Date, day: DayKey, meal: FoodMeal, name: String, brand: String? = nil, barcode: String? = nil,
         source: FoodLogSource, amountText: String, macros: Macros) {
        self.date = date
        self.day = day.description
        mealRaw = meal.rawValue
        self.name = name
        self.brand = brand
        self.barcode = barcode
        sourceRaw = source.rawValue
        self.amountText = amountText
        kcal = macros.kcal
        protein = macros.protein
        carbs = macros.carbs
        fat = macros.fat
    }

    var meal: FoodMeal { FoodMeal(rawValue: mealRaw) ?? .evening }
    var source: FoodLogSource { FoodLogSource(rawValue: sourceRaw) ?? .manual }
    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
}

/// A product found by barcode, kept so it can be logged again without a lookup.
@Model
final class SavedProduct {
    @Attribute(.unique) var barcode: String = ""
    var name: String = ""
    var brand: String?
    var kcalPer100: Double = 0
    var proteinPer100: Double = 0
    var carbsPer100: Double = 0
    var fatPer100: Double = 0
    var servingGrams: Double?
    var servingText: String?
    var lastUsed: Date = Date.distantPast

    init(_ product: FoodProduct) {
        barcode = product.barcode
        update(from: product)
    }

    func update(from product: FoodProduct) {
        name = product.name
        brand = product.brand
        kcalPer100 = product.per100.kcal
        proteinPer100 = product.per100.protein
        carbsPer100 = product.per100.carbs
        fatPer100 = product.per100.fat
        servingGrams = product.servingGrams
        servingText = product.servingText
    }

    var product: FoodProduct {
        FoodProduct(barcode: barcode, name: name, brand: brand,
                    per100: Macros(kcal: kcalPer100, protein: proteinPer100, carbs: carbsPer100, fat: fatPer100),
                    servingGrams: servingGrams, servingText: servingText)
    }
}
