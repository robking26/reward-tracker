import Foundation
import SwiftData

// Phase 4 kitchen entities. All new, so existing stores open with lightweight migration.

/// A recipe in the personal library (F7). Imported text is kept only as the structured recipe for personal use.
@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var title: String
    var roleRaw: String
    var servings: Int
    var ingredientsData: Data
    var steps: [String]
    var prepMinutes: Int
    var cookMinutes: Int
    var washUpMinutes: Int
    var usesSlowCooker: Bool
    var isFakeaway: Bool
    var freezable: Bool
    var favourite: Bool
    var sourceRaw: String
    /// Per portion. User-corrected figures replace the estimate.
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var confidenceRaw: String
    var notes: String?
    var createdAt: Date
    var lastCookedAt: Date?
    var timesCooked: Int
    var archived: Bool

    init(title: String, role: MealRole, servings: Int, ingredients: [RecipeIngredient], steps: [String], prepMinutes: Int,
         cookMinutes: Int, washUpMinutes: Int, usesSlowCooker: Bool = false, isFakeaway: Bool = false, freezable: Bool = false,
         source: RecipeSource) {
        id = UUID()
        self.title = title
        roleRaw = role.rawValue
        self.servings = max(1, servings)
        ingredientsData = (try? JSONEncoder().encode(ingredients)) ?? Data()
        self.steps = steps
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.washUpMinutes = washUpMinutes
        self.usesSlowCooker = usesSlowCooker
        self.isFakeaway = isFakeaway
        self.freezable = freezable
        favourite = false
        sourceRaw = source.rawValue
        let estimate = NutritionEstimator.estimate(ingredients, servings: max(1, servings))
        kcal = estimate.perPortion.kcal
        protein = estimate.perPortion.protein
        carbs = estimate.perPortion.carbs
        fat = estimate.perPortion.fat
        confidenceRaw = estimate.confidence.rawValue
        createdAt = .now
        timesCooked = 0
        archived = false
    }

    var role: MealRole {
        get { MealRole(rawValue: roleRaw) ?? .dinner }
        set { roleRaw = newValue.rawValue }
    }
    var source: RecipeSource { RecipeSource(rawValue: sourceRaw) ?? .manual }
    var confidence: EstimateConfidence { EstimateConfidence(rawValue: confidenceRaw) ?? .rough }
    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    var ingredients: [RecipeIngredient] {
        get { (try? JSONDecoder().decode([RecipeIngredient].self, from: ingredientsData)) ?? [] }
        set {
            ingredientsData = (try? JSONEncoder().encode(newValue)) ?? ingredientsData
            if confidence != .confirmed { recalculate() }
        }
    }

    var excludedIngredient: String? {
        FoodExclusions.excluded(([title] + ingredients.map(\.original)).joined(separator: " "))
    }

    func recalculate() {
        let estimate = NutritionEstimator.estimate(ingredients, servings: servings)
        kcal = estimate.perPortion.kcal
        protein = estimate.perPortion.protein
        carbs = estimate.perPortion.carbs
        fat = estimate.perPortion.fat
        confidenceRaw = estimate.confidence.rawValue
    }

    func candidate(calendar: Calendar) -> MealCandidate {
        MealCandidate(id: id, title: title, role: role, servings: servings, prepMinutes: prepMinutes, cookMinutes: cookMinutes,
                      washUpMinutes: washUpMinutes, usesSlowCooker: usesSlowCooker, isFakeaway: isFakeaway, freezable: freezable,
                      favourite: favourite, excluded: excludedIngredient != nil || archived,
                      lastCooked: lastCookedAt.map { DayKey($0, calendar: calendar) })
    }
}

enum RecipeSource: String, Codable, Sendable {
    case starter, camera, screenshot, pdf, file, manual, conversation

    var title: String {
        switch self {
        case .starter: "Starter recipe"
        case .camera: "Photo"
        case .screenshot: "Screenshot"
        case .pdf: "PDF"
        case .file: "File"
        case .manual: "Typed in"
        case .conversation: "Added by hand"
        }
    }
}

/// One meal in the week's plan.
@Model
final class MealPlanEntry {
    var id: UUID
    var day: String
    var slotRaw: String
    var recipeID: UUID?
    var title: String
    var portions: Int
    var fromFreezer: Bool
    var note: String?
    /// For freezer meals: moved to the fridge.
    var defrosted: Bool
    var cooked: Bool
    var createdAt: Date

    init(_ meal: PlannedMeal) {
        id = UUID()
        day = meal.day.description
        slotRaw = meal.slot.rawValue
        recipeID = meal.recipeID
        title = meal.title
        portions = meal.portions
        fromFreezer = meal.fromFreezer
        note = meal.note
        defrosted = false
        cooked = false
        createdAt = .now
    }

    var dayKey: DayKey? { DayKey(string: day) }
    var slot: MealSlot { MealSlot(rawValue: slotRaw) ?? .dinner }
    var planned: PlannedMeal? {
        dayKey.map { PlannedMeal(day: $0, slot: slot, recipeID: recipeID, title: title, portions: portions, fromFreezer: fromFreezer, note: note) }
    }
}

/// Something probably in the house (I4). Keyed by catalogue ID, or by the lowercased name for anything else.
@Model
final class InventoryItem {
    @Attribute(.unique) var key: String
    var name: String
    var foodID: String?
    var locationRaw: String
    var sourceRaw: String
    var addedAt: Date?
    var confirmedAt: Date?
    var outAt: Date?
    /// Counted things, such as freezer portions.
    var portions: Int?
    var usedSinceAdded: Bool
    var updatedAt: Date

    init(key: String, name: String, foodID: String?, location: StorageLocation, source: InventorySource) {
        self.key = key
        self.name = name
        self.foodID = foodID
        locationRaw = location.rawValue
        sourceRaw = source.rawValue
        usedSinceAdded = false
        updatedAt = .now
    }

    var location: StorageLocation { StorageLocation(rawValue: locationRaw) ?? .cupboard }
    var source: InventorySource { InventorySource(rawValue: sourceRaw) ?? .manual }
    var food: FoodItem? { foodID.flatMap { FoodCatalogue.byID[$0] } }

    func presence(now: Date) -> Presence {
        InventoryEstimator.presence(InventorySnapshot(addedAt: addedAt, source: source, confirmedAt: confirmedAt, outAt: outAt,
                                                      shelfLifeDays: food?.shelfLifeDays ?? (location == .freezer ? 90 : 7),
                                                      usedSinceAdded: usedSinceAdded, portions: portions), now: now)
    }
}

/// A shop: from a scanned receipt or typed in (I3). The fingerprint refuses the same receipt twice.
@Model
final class ReceiptRecord {
    @Attribute(.unique) var fingerprint: String
    var id: UUID
    var merchantRaw: String
    var date: Date
    var month: String
    var totalPence: Int
    var linesData: Data
    var needsReview: Bool
    var manual: Bool
    var createdAt: Date

    init(merchant: Merchant, date: Date, totalPence: Int, lines: [ReceiptLine], needsReview: Bool, manual: Bool, calendar: Calendar) {
        let day = DayKey(date, calendar: calendar)
        fingerprint = ReceiptParser.fingerprint(merchant: merchant, day: day, totalPence: totalPence)
        id = UUID()
        merchantRaw = merchant.rawValue
        self.date = date
        month = day.monthKey.description
        self.totalPence = totalPence
        linesData = (try? JSONEncoder().encode(lines)) ?? Data()
        self.needsReview = needsReview
        self.manual = manual
        createdAt = .now
    }

    var merchant: Merchant { Merchant(rawValue: merchantRaw) ?? .other }
    var total: Pence { Pence(totalPence) }
    var lines: [ReceiptLine] {
        get { (try? JSONDecoder().decode([ReceiptLine].self, from: linesData)) ?? [] }
        set { linesData = (try? JSONEncoder().encode(newValue)) ?? linesData }
    }
}

/// A line on the current shopping list. Ticked lines stay until the list is cleared.
@Model
final class ShoppingItem {
    @Attribute(.unique) var key: String
    var name: String
    var departmentRaw: String
    var quantityText: String
    var estimatePence: Int?
    var reasons: [String]
    var checkFirst: Bool
    var manual: Bool
    var ticked: Bool
    var createdAt: Date

    init(_ line: ShoppingLine, manual: Bool) {
        key = line.id
        name = line.name
        departmentRaw = line.department.rawValue
        quantityText = line.quantityText
        estimatePence = line.estimatePence
        reasons = line.reasons
        checkFirst = line.checkFirst
        self.manual = manual
        ticked = false
        createdAt = .now
    }

    var department: AisleDepartment { AisleDepartment(rawValue: departmentRaw) ?? .other }
}
