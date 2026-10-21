import Foundation

// Phase 4 kitchen domain: pure, deterministic and unit tested. Nutrition figures are rounded typical values per 100 g
// (or 100 ml), close to UK composition tables, and are always presented as estimates (F7).

enum KitchenUnit: String, Codable, Sendable, Hashable {
    case grams, millilitres, items

    var symbol: String {
        switch self {
        case .grams: "g"
        case .millilitres: "ml"
        case .items: ""
        }
    }
}

/// Where things are in a typical Aldi, in walking order, so the list follows the shop (I2).
enum AisleDepartment: String, Codable, Sendable, CaseIterable, Identifiable {
    case fruitVeg, bakery, meatFish, dairyEggs, chilled, cupboard, world, frozen, drinks, household, toiletries, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fruitVeg: "Fruit and veg"
        case .bakery: "Bakery"
        case .meatFish: "Meat and fish"
        case .dairyEggs: "Dairy and eggs"
        case .chilled: "Chilled"
        case .cupboard: "Cupboard"
        case .world: "Sauces and world foods"
        case .frozen: "Frozen"
        case .drinks: "Drinks"
        case .household: "Cleaning and household"
        case .toiletries: "Toiletries"
        case .other: "Other"
        }
    }
}

enum StorageLocation: String, Codable, Sendable, CaseIterable {
    case fridge, freezer, cupboard, bathroom, underSink

    var title: String {
        switch self {
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .cupboard: "Cupboard"
        case .bathroom: "Bathroom"
        case .underSink: "Under the sink"
        }
    }
}

/// Energy and macronutrients. Per 100 g in the catalogue, per portion on a recipe.
struct Macros: Codable, Sendable, Hashable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = Macros(kcal: 0, protein: 0, carbs: 0, fat: 0)

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(kcal: lhs.kcal + rhs.kcal, protein: lhs.protein + rhs.protein, carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }

    func scaled(_ factor: Double) -> Macros {
        Macros(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }
}

/// A realistic pack on the shelf, used to round the shopping list (I2). Prices are typical Aldi prices and only
/// ever shown as estimates.
struct PackSize: Sendable, Hashable {
    var amount: Double
    var unit: KitchenUnit
    var pricePence: Int
}

struct FoodItem: Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let department: AisleDepartment
    /// Per 100 g or 100 ml. Nil for non-food.
    let per100: Macros?
    /// For things counted in items (an onion, an egg).
    let gramsPerItem: Double?
    let pack: PackSize
    let location: StorageLocation
    /// How long it's typically still usable after buying, for probabilistic inventory (I4).
    let shelfLifeDays: Int
    /// Salt, oil, spices: assumed present unless the user says they've run out.
    let isStaple: Bool

    /// Every lowercased name that identifies this item, longest first.
    var matchNames: [String] {
        ([name] + aliases).map { $0.lowercased().replacingOccurrences(of: "-", with: " ") }.sorted { $0.count > $1.count }
    }
}

/// Foods the user never wants suggested (F3).
enum FoodExclusions {
    static let words = ["mushroom", "courgette", "zucchini", "cauliflower"]

    static func excluded(_ text: String) -> String? {
        let lower = text.lowercased()
        return words.first { lower.contains($0) }
    }
}

enum FoodCatalogue {
    private static func food(_ id: String, _ name: String, _ aliases: [String] = [], _ department: AisleDepartment,
                             kcal: Double, protein: Double, carbs: Double, fat: Double, each: Double? = nil,
                             pack: Double, _ unit: KitchenUnit = .grams, pence: Int, _ location: StorageLocation = .cupboard,
                             days: Int, staple: Bool = false) -> FoodItem {
        FoodItem(id: id, name: name, aliases: aliases, department: department,
                 per100: Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat), gramsPerItem: each,
                 pack: PackSize(amount: pack, unit: unit, pricePence: pence), location: location, shelfLifeDays: days, isStaple: staple)
    }

    private static func thing(_ id: String, _ name: String, _ aliases: [String] = [], _ department: AisleDepartment,
                              pack: Double, pence: Int, _ location: StorageLocation, days: Int) -> FoodItem {
        FoodItem(id: id, name: name, aliases: aliases, department: department, per100: nil, gramsPerItem: nil,
                 pack: PackSize(amount: pack, unit: .items, pricePence: pence), location: location, shelfLifeDays: days, isStaple: false)
    }

    static let all: [FoodItem] = [
        // Meat and fish
        food("chicken-breast", "Chicken breast", ["chicken breasts", "chicken fillet", "chicken fillets", "diced chicken"], .meatFish,
             kcal: 106, protein: 24, carbs: 0, fat: 1.1, pack: 650, pence: 449, .fridge, days: 3),
        food("chicken-thigh", "Chicken thighs", ["chicken thigh", "boneless thighs"], .meatFish,
             kcal: 177, protein: 19, carbs: 0, fat: 11, pack: 500, pence: 299, .fridge, days: 3),
        food("turkey-mince", "Turkey mince", ["turkey breast mince", "minced turkey"], .meatFish,
             kcal: 120, protein: 23, carbs: 0, fat: 3, pack: 500, pence: 329, .fridge, days: 3),
        food("beef-mince-5", "5% beef mince", ["lean beef mince", "lean mince"], .meatFish,
             kcal: 125, protein: 21, carbs: 0, fat: 5, pack: 500, pence: 349, .fridge, days: 3),
        food("beef-mince", "Beef mince", ["minced beef", "mince"], .meatFish,
             kcal: 250, protein: 18, carbs: 0, fat: 20, pack: 500, pence: 299, .fridge, days: 3),
        food("pork-loin", "Pork loin steaks", ["pork loin", "pork steaks", "pork steak", "pork chops", "pork"], .meatFish,
             kcal: 150, protein: 22, carbs: 0, fat: 7, pack: 500, pence: 319, .fridge, days: 4),
        food("pork-mince", "Pork mince", ["minced pork"], .meatFish,
             kcal: 200, protein: 19, carbs: 0, fat: 14, pack: 500, pence: 279, .fridge, days: 3),
        food("sausages", "Sausages", ["sausage", "pork sausages", "chicken sausages"], .meatFish,
             kcal: 230, protein: 15, carbs: 8, fat: 15, each: 57, pack: 8, .items, pence: 229, .fridge, days: 5),
        food("salmon", "Salmon fillets", ["salmon fillet", "salmon"], .meatFish,
             kcal: 200, protein: 21, carbs: 0, fat: 13, each: 120, pack: 2, .items, pence: 399, .fridge, days: 3),
        food("cod", "Cod fillets", ["cod fillet", "cod", "white fish"], .frozen,
             kcal: 80, protein: 18, carbs: 0, fat: 0.7, each: 120, pack: 4, .items, pence: 449, .freezer, days: 180),
        food("prawns", "King prawns", ["prawns"], .frozen,
             kcal: 70, protein: 16, carbs: 0, fat: 0.6, pack: 250, pence: 349, .freezer, days: 180),
        food("tuna", "Tuna chunks in spring water", ["tuna", "tinned tuna", "tuna chunks"], .cupboard,
             kcal: 109, protein: 25, carbs: 0, fat: 1, each: 112, pack: 4, .items, pence: 349, days: 540),
        food("ham", "Wafer thin ham", ["ham", "sliced ham", "honey roast ham", "turkey slices"], .chilled,
             kcal: 105, protein: 19, carbs: 1.5, fat: 2.5, pack: 400, pence: 249, .fridge, days: 5),
        food("bacon", "Bacon medallions", ["bacon"], .meatFish,
             kcal: 115, protein: 21, carbs: 1, fat: 3, pack: 300, pence: 249, .fridge, days: 7),
        food("chorizo", "Chorizo", [], .chilled,
             kcal: 455, protein: 24, carbs: 2, fat: 39, pack: 225, pence: 199, .fridge, days: 21),

        // Dairy and eggs
        food("eggs", "Eggs", ["egg", "free range eggs"], .dairyEggs,
             kcal: 131, protein: 12.6, carbs: 0, fat: 9, each: 58, pack: 12, .items, pence: 289, .fridge, days: 21),
        food("milk", "Semi-skimmed milk", ["milk", "skimmed milk"], .dairyEggs,
             kcal: 47, protein: 3.5, carbs: 4.8, fat: 1.7, pack: 2272, .millilitres, pence: 145, .fridge, days: 7),
        food("greek-yoghurt", "Greek-style yoghurt (0%)", ["greek yoghurt", "greek yogurt", "fat free yoghurt", "natural yoghurt", "yoghurt", "yogurt"], .dairyEggs,
             kcal: 57, protein: 10, carbs: 4, fat: 0.2, pack: 500, pence: 109, .fridge, days: 10),
        food("skyr", "Icelandic style skyr", ["skyr", "protein yoghurt"], .dairyEggs,
             kcal: 64, protein: 11, carbs: 4, fat: 0.2, pack: 450, pence: 125, .fridge, days: 14),
        food("cheddar", "Mature cheddar", ["cheddar", "cheese", "grated cheese"], .dairyEggs,
             kcal: 416, protein: 25, carbs: 0.1, fat: 35, pack: 400, pence: 319, .fridge, days: 21),
        food("light-cheddar", "Lighter mature cheddar", ["reduced fat cheddar", "light cheese"], .dairyEggs,
             kcal: 314, protein: 27, carbs: 0.1, fat: 22, pack: 350, pence: 299, .fridge, days: 21),
        food("mozzarella", "Mozzarella", ["light mozzarella"], .dairyEggs,
             kcal: 165, protein: 18, carbs: 1, fat: 10, pack: 125, pence: 69, .fridge, days: 10),
        food("feta", "Greek salad cheese", ["feta"], .dairyEggs,
             kcal: 270, protein: 16, carbs: 1, fat: 22, pack: 200, pence: 129, .fridge, days: 21),
        food("creme-fraiche", "Light crème fraîche", ["creme fraiche", "crème fraîche", "light creme fraiche"], .dairyEggs,
             kcal: 160, protein: 3, carbs: 4.5, fat: 15, pack: 300, pence: 99, .fridge, days: 10),
        food("cream", "Double cream", ["cream", "single cream"], .dairyEggs,
             kcal: 450, protein: 1.7, carbs: 2.6, fat: 48, pack: 300, .millilitres, pence: 115, .fridge, days: 7),
        food("butter", "Butter", [], .dairyEggs,
             kcal: 740, protein: 0.6, carbs: 0.6, fat: 82, pack: 250, pence: 199, .fridge, days: 45, staple: true),
        food("cottage-cheese", "Cottage cheese", [], .dairyEggs,
             kcal: 80, protein: 11, carbs: 3, fat: 2.5, pack: 300, pence: 99, .fridge, days: 10),

        // Fruit and veg
        food("onion", "Onions", ["onion", "red onion", "red onions", "white onion"], .fruitVeg,
             kcal: 36, protein: 1.1, carbs: 7.9, fat: 0.2, each: 150, pack: 3, .items, pence: 89, days: 21),
        food("garlic", "Garlic", ["garlic clove", "garlic cloves", "cloves garlic", "clove garlic"], .fruitVeg,
             kcal: 98, protein: 7.9, carbs: 16, fat: 0.6, each: 4, pack: 4, .items, pence: 59, days: 30, staple: true),
        food("peppers", "Peppers", ["pepper", "red pepper", "red peppers", "green pepper", "yellow pepper", "bell pepper"], .fruitVeg,
             kcal: 26, protein: 1, carbs: 5, fat: 0.3, each: 160, pack: 3, .items, pence: 109, .fridge, days: 7),
        food("carrots", "Carrots", ["carrot"], .fruitVeg,
             kcal: 34, protein: 0.6, carbs: 7.9, fat: 0.3, each: 80, pack: 1000, pence: 59, .fridge, days: 14),
        food("broccoli", "Broccoli", ["tenderstem"], .fruitVeg,
             kcal: 34, protein: 4.4, carbs: 2, fat: 0.6, pack: 360, pence: 75, .fridge, days: 5),
        food("green-beans", "Green beans", ["fine beans"], .fruitVeg,
             kcal: 25, protein: 1.8, carbs: 3.2, fat: 0.5, pack: 220, pence: 85, .fridge, days: 5),
        food("spinach", "Spinach", ["baby spinach"], .fruitVeg,
             kcal: 25, protein: 2.8, carbs: 1.6, fat: 0.8, pack: 240, pence: 109, .fridge, days: 4),
        food("tomatoes", "Tomatoes", ["tomato", "cherry tomatoes", "salad tomatoes"], .fruitVeg,
             kcal: 18, protein: 0.7, carbs: 3.1, fat: 0.3, each: 85, pack: 6, .items, pence: 89, .fridge, days: 7),
        food("potatoes", "Potatoes", ["potato", "baby potatoes", "new potatoes", "maris piper"], .fruitVeg,
             kcal: 77, protein: 2, carbs: 17, fat: 0.1, each: 170, pack: 2000, pence: 129, days: 21),
        food("sweet-potato", "Sweet potatoes", ["sweet potato"], .fruitVeg,
             kcal: 86, protein: 1.6, carbs: 20, fat: 0.1, each: 200, pack: 1000, pence: 119, days: 21),
        food("lemon", "Lemons", ["lemon", "lemon juice"], .fruitVeg,
             kcal: 29, protein: 1.1, carbs: 9, fat: 0.3, each: 100, pack: 4, .items, pence: 79, .fridge, days: 21),
        food("lime", "Limes", ["lime"], .fruitVeg,
             kcal: 30, protein: 0.7, carbs: 10, fat: 0.2, each: 60, pack: 4, .items, pence: 79, .fridge, days: 21),
        food("lettuce", "Lettuce", ["little gem", "salad leaves", "iceberg"], .fruitVeg,
             kcal: 15, protein: 1.2, carbs: 2, fat: 0.2, pack: 1, .items, pence: 59, .fridge, days: 5),
        food("cucumber", "Cucumber", [], .fruitVeg,
             kcal: 15, protein: 0.7, carbs: 3.6, fat: 0.1, each: 300, pack: 1, .items, pence: 59, .fridge, days: 7),
        food("bananas", "Bananas", ["banana"], .fruitVeg,
             kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, each: 120, pack: 5, .items, pence: 79, days: 5),
        food("berries", "Frozen berries", ["mixed berries", "frozen fruit"], .frozen,
             kcal: 45, protein: 1, carbs: 9, fat: 0.3, pack: 500, pence: 199, .freezer, days: 240),
        food("frozen-veg", "Frozen mixed veg", ["frozen vegetables", "mixed vegetables", "frozen peas", "peas", "sweetcorn"], .frozen,
             kcal: 60, protein: 3.5, carbs: 9, fat: 0.6, pack: 1000, pence: 99, .freezer, days: 240),
        food("stir-fry-veg", "Stir-fry vegetables", ["stir fry veg", "stir-fry veg", "stir fry vegetables"], .fruitVeg,
             kcal: 30, protein: 1.5, carbs: 4.5, fat: 0.3, pack: 600, pence: 129, .fridge, days: 4),

        // Bakery and cupboard
        food("wraps", "Tortilla wraps", ["tortilla", "tortillas", "wrap", "flatbread", "flatbreads", "pitta", "pittas"], .bakery,
             kcal: 300, protein: 8.5, carbs: 50, fat: 7, each: 62, pack: 8, .items, pence: 89, days: 10),
        food("bread", "Wholemeal bread", ["bread", "toast", "seeded bread"], .bakery,
             kcal: 240, protein: 10, carbs: 40, fat: 3, each: 40, pack: 800, pence: 75, days: 5),
        food("burger-buns", "Brioche buns", ["burger buns", "buns", "bun"], .bakery,
             kcal: 330, protein: 9, carbs: 52, fat: 9, each: 50, pack: 6, .items, pence: 109, days: 5),
        food("rice", "Basmati rice", ["rice", "long grain rice", "basmati"], .cupboard,
             kcal: 350, protein: 8, carbs: 78, fat: 1, pack: 1000, pence: 149, days: 365),
        food("microwave-rice", "Microwave rice", ["rice pouch", "microwave rice pouch", "pouch of rice"], .cupboard,
             kcal: 150, protein: 3.3, carbs: 31, fat: 1.5, each: 250, pack: 1, .items, pence: 55, days: 270),
        food("pasta", "Pasta", ["penne", "fusilli", "spaghetti", "rigatoni", "linguine"], .cupboard,
             kcal: 355, protein: 12.5, carbs: 71, fat: 1.5, pack: 500, pence: 49, days: 365),
        food("orzo", "Orzo", [], .cupboard,
             kcal: 355, protein: 12.5, carbs: 71, fat: 1.5, pack: 500, pence: 99, days: 365),
        food("noodles", "Egg noodles", ["noodles", "straight to wok noodles"], .cupboard,
             kcal: 350, protein: 12, carbs: 70, fat: 2.5, pack: 250, pence: 59, days: 270),
        food("oats", "Porridge oats", ["oats", "rolled oats"], .cupboard,
             kcal: 375, protein: 11, carbs: 60, fat: 8, pack: 1000, pence: 85, days: 270),
        food("chopped-tomatoes", "Chopped tomatoes", ["tinned tomatoes", "tin of tomatoes", "chopped tomatoes", "passata"], .cupboard,
             kcal: 22, protein: 1.1, carbs: 3.8, fat: 0.1, each: 400, pack: 1, .items, pence: 35, days: 540),
        food("kidney-beans", "Kidney beans", ["red kidney beans"], .cupboard,
             kcal: 100, protein: 7, carbs: 14, fat: 0.5, each: 240, pack: 1, .items, pence: 39, days: 540),
        food("baked-beans", "Baked beans", ["beans"], .cupboard,
             kcal: 80, protein: 4.7, carbs: 13, fat: 0.4, each: 415, pack: 1, .items, pence: 35, days: 540),
        food("chickpeas", "Chickpeas", [], .cupboard,
             kcal: 115, protein: 7, carbs: 14, fat: 2.5, each: 240, pack: 1, .items, pence: 45, days: 540),
        food("lentils", "Red lentils", ["lentils"], .cupboard,
             kcal: 330, protein: 24, carbs: 49, fat: 1.5, pack: 500, pence: 119, days: 365),
        food("coconut-milk", "Light coconut milk", ["coconut milk"], .world,
             kcal: 75, protein: 0.6, carbs: 1.5, fat: 7, each: 400, pack: 1, .items, pence: 89, days: 540),
        food("stock", "Stock cubes", ["stock cube", "chicken stock", "beef stock", "stock pot", "vegetable stock", "stock"], .cupboard,
             kcal: 10, protein: 0.3, carbs: 1, fat: 0.5, each: 10, pack: 12, .items, pence: 75, days: 540, staple: true),
        food("olive-oil", "Olive oil", ["oil", "vegetable oil", "rapeseed oil", "sunflower oil"], .cupboard,
             kcal: 828, protein: 0, carbs: 0, fat: 92, pack: 500, .millilitres, pence: 349, days: 540, staple: true),
        food("spray-oil", "Spray oil", ["cooking spray", "1 cal spray", "low calorie spray"], .cupboard,
             kcal: 0, protein: 0, carbs: 0, fat: 0, pack: 1, .items, pence: 115, days: 540, staple: true),
        food("honey", "Honey", [], .cupboard,
             kcal: 330, protein: 0.3, carbs: 82, fat: 0, pack: 340, pence: 149, days: 540, staple: true),
        food("soy-sauce", "Soy sauce", ["soy", "light soy"], .world,
             kcal: 60, protein: 8, carbs: 6, fat: 0, pack: 150, .millilitres, pence: 69, days: 540, staple: true),
        food("sweet-chilli", "Sweet chilli sauce", ["sweet chili sauce", "sweet chilli"], .world,
             kcal: 200, protein: 0.4, carbs: 49, fat: 0.2, pack: 300, .millilitres, pence: 79, days: 365),
        food("curry-paste", "Curry paste", ["tikka paste", "korma paste", "thai curry paste", "madras paste", "curry powder"], .world,
             kcal: 300, protein: 4, carbs: 15, fat: 25, pack: 190, pence: 99, days: 365),
        food("fajita-seasoning", "Fajita seasoning", ["fajita spice", "fajita kit", "taco seasoning", "chilli powder", "cajun seasoning", "smoked paprika", "paprika"], .world,
             kcal: 300, protein: 10, carbs: 50, fat: 6, pack: 30, pence: 59, days: 540, staple: true),
        food("salsa", "Salsa", ["tomato salsa"], .world,
             kcal: 40, protein: 1.3, carbs: 7, fat: 0.3, pack: 300, pence: 99, days: 365),
        food("pesto", "Pesto", ["green pesto"], .world,
             kcal: 450, protein: 5, carbs: 6, fat: 45, pack: 190, pence: 99, days: 365),
        food("katsu-sauce", "Katsu curry sauce", ["katsu sauce"], .world,
             kcal: 110, protein: 1.5, carbs: 13, fat: 5.5, pack: 350, pence: 99, days: 365),
        food("breadcrumbs", "Panko breadcrumbs", ["breadcrumbs", "panko"], .cupboard,
             kcal: 370, protein: 11, carbs: 75, fat: 3, pack: 200, pence: 89, days: 365),
        food("protein-powder", "Protein powder", ["whey"], .other,
             kcal: 380, protein: 75, carbs: 8, fat: 6, pack: 1000, pence: 1499, days: 365),
        food("dried-herbs", "Dried herbs", ["mixed herbs", "oregano", "italian herbs", "cumin", "salt", "black pepper", "salt and pepper", "chilli flakes", "garam masala", "turmeric"], .cupboard,
             kcal: 0, protein: 0, carbs: 0, fat: 0, pack: 1, .items, pence: 59, days: 720, staple: true),

        // Frozen convenience
        food("frozen-chips", "Oven chips", ["chips", "frozen chips", "potato wedges", "wedges"], .frozen,
             kcal: 150, protein: 2.5, carbs: 25, fat: 4.5, pack: 1500, pence: 149, .freezer, days: 240),
        food("fish-fingers", "Fish fingers", ["fish finger"], .frozen,
             kcal: 200, protein: 13, carbs: 19, fat: 8, each: 28, pack: 10, .items, pence: 179, .freezer, days: 240),

        // Household and toiletries: tracked loosely, never with replacement alerts (I4)
        thing("washing-up-liquid", "Washing-up liquid", ["fairy"], .household, pack: 1, pence: 99, .underSink, days: 60),
        thing("laundry-detergent", "Laundry detergent", ["washing powder", "washing liquid", "laundry capsules", "pods"], .household, pack: 1, pence: 399, .underSink, days: 45),
        thing("bin-bags", "Bin bags", ["bin liners"], .household, pack: 1, pence: 149, .underSink, days: 60),
        thing("kitchen-roll", "Kitchen roll", [], .household, pack: 1, pence: 199, .cupboard, days: 21),
        thing("toilet-roll", "Toilet roll", ["loo roll", "toilet paper"], .household, pack: 1, pence: 499, .bathroom, days: 30),
        thing("surface-spray", "Antibacterial spray", ["surface spray", "cleaning spray"], .household, pack: 1, pence: 89, .underSink, days: 45),
        thing("shower-gel", "Shower gel", ["body wash"], .toiletries, pack: 1, pence: 99, .bathroom, days: 30),
        thing("shampoo", "Shampoo", [], .toiletries, pack: 1, pence: 129, .bathroom, days: 45),
        thing("toothpaste", "Toothpaste", [], .toiletries, pack: 1, pence: 89, .bathroom, days: 45),
        thing("deodorant", "Deodorant", [], .toiletries, pack: 1, pence: 129, .bathroom, days: 45),
    ]

    static let byID: [String: FoodItem] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Every (name, item) pair, longest name first, so "chicken thighs" wins over "chicken".
    private static let index: [(String, FoodItem)] = all
        .flatMap { item in item.matchNames.map { ($0, item) } }
        .sorted { $0.0.count > $1.0.count }

    /// The catalogue item a free-text name refers to, matched on whole words.
    static func match(_ text: String) -> FoodItem? {
        let lower = " " + text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ") + " "
        for (name, item) in index where lower.contains(" " + name + " ") || lower.contains(" " + name + "s ") {
            return item
        }
        return nil
    }
}
