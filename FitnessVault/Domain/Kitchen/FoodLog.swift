import Foundation

// Logging what's eaten: cycle meals with one tap, anything else by barcode (Open Food Facts) or by hand.
// Pure and tested; the network call lives in OpenFoodFactsClient. Nothing here affects earnings.

enum FoodMeal: String, Codable, Sendable, CaseIterable, Identifiable {
    case breakfast, lunch, evening, snack

    var id: String { rawValue }
    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .evening: "Evening meal"
        case .snack: "Snacks"
        }
    }
    var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "takeoutbag.and.cup.and.straw.fill"
        case .evening: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }

    /// The meal you're probably logging at this hour.
    static func likely(hour: Int) -> FoodMeal {
        switch hour {
        case ..<11: .breakfast
        case 11..<15: .lunch
        case 17...: .evening
        default: .snack
        }
    }
}

enum FoodLogSource: String, Codable, Sendable {
    case cycle, barcode, manual
}

/// A packaged food, with nutrition per 100 g (or ml) and, when the label gives one, a serving size.
struct FoodProduct: Sendable, Hashable {
    var barcode: String
    var name: String
    var brand: String?
    var per100: Macros
    var servingGrams: Double?
    var servingText: String?

    /// Nutrition for an amount in grams.
    func macros(grams: Double) -> Macros { per100.scaled(max(0, grams) / 100) }
}

enum OpenFoodFacts {
    /// The product lookup for a barcode, asking only for the fields the app uses.
    static func url(barcode: String) -> URL? {
        let digits = barcode.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        return URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=product_name,product_name_en,brands,nutriments,serving_quantity,serving_size")
    }

    enum LookupError: Error, Equatable {
        case notFound
        case noNutrition
        case unreadable
    }

    /// Reads an Open Food Facts v2 response. Energy falls back from kcal to kJ; missing macros count as zero.
    static func parse(_ data: Data, barcode: String) -> Result<FoodProduct, LookupError> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(.unreadable) }
        let status = root["status"] as? Int ?? (root["status"] as? String).flatMap { Int($0) } ?? 0
        guard status == 1, let product = root["product"] as? [String: Any] else { return .failure(.notFound) }
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]

        var kcal = number(nutriments["energy-kcal_100g"])
        if kcal == nil, let kilojoules = number(nutriments["energy_100g"]) { kcal = kilojoules / 4.184 }
        guard let energy = kcal else { return .failure(.noNutrition) }
        let macros = Macros(kcal: energy,
                            protein: number(nutriments["proteins_100g"]) ?? 0,
                            carbs: number(nutriments["carbohydrates_100g"]) ?? 0,
                            fat: number(nutriments["fat_100g"]) ?? 0)

        let english = (product["product_name_en"] as? String)?.trimmingCharacters(in: .whitespaces)
        let local = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces)
        let name = [english, local].compactMap { $0 }.first { !$0.isEmpty } ?? "Unnamed product"
        let brand = (product["brands"] as? String)?
            .split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let serving = number(product["serving_quantity"]).flatMap { $0 > 0 ? $0 : nil }
        let servingText = (product["serving_size"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return .success(FoodProduct(barcode: barcode.filter(\.isNumber), name: name, brand: brand, per100: macros,
                                    servingGrams: serving, servingText: servingText))
    }

    /// Open Food Facts mixes numbers and numeric strings.
    static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
}

/// A day's food in one place.
struct DayNutrition: Sendable, Hashable {
    var total: Macros
    var byMeal: [FoodMeal: Macros]

    static func summarise(_ entries: [(meal: FoodMeal, macros: Macros)]) -> DayNutrition {
        var byMeal: [FoodMeal: Macros] = [:]
        var total = Macros.zero
        for entry in entries {
            byMeal[entry.meal] = (byMeal[entry.meal] ?? .zero) + entry.macros
            total = total + entry.macros
        }
        return DayNutrition(total: total, byMeal: byMeal)
    }
}
