import XCTest
@testable import FitnessVault

final class KitchenDomainTests: XCTestCase {
    private var london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    // MARK: The cycle meets its targets

    func testEightWeeksOfEach() {
        XCTAssertEqual(MealCycle.lunches.count, 8)
        XCTAssertEqual(MealCycle.breakfasts.count, 8)
        XCTAssertEqual(MealCycle.lunches.map(\.week), Array(1...8))
        XCTAssertEqual(MealCycle.breakfasts.map(\.week), Array(1...8))
        XCTAssertEqual(Set((MealCycle.lunches + MealCycle.breakfasts).map(\.id)).count, 16, "Unique ids")
    }

    func testLunchesAreAbout600KcalHighProteinLowFat() {
        for meal in MealCycle.lunches {
            let macros = meal.macros
            XCTAssertEqual(macros.kcal, 600, accuracy: 40, meal.title)
            XCTAssertGreaterThanOrEqual(macros.protein, 50, meal.title)
            XCTAssertLessThanOrEqual(macros.fat, 15, "\(meal.title) is low fat")
        }
    }

    func testBreakfastsAreAbout500KcalHighProteinLowFatAndQuick() {
        for meal in MealCycle.breakfasts {
            let macros = meal.macros
            XCTAssertEqual(macros.kcal, 500, accuracy: 40, meal.title)
            XCTAssertGreaterThanOrEqual(macros.protein, 50, meal.title)
            XCTAssertLessThanOrEqual(macros.fat, 15, "\(meal.title) is low fat")
            XCTAssertLessThanOrEqual(meal.prepMinutes + meal.cookMinutes, 5, "\(meal.title) takes five minutes")
        }
    }

    func testEveryIngredientIsInTheCatalogueWithoutExclusions() {
        for meal in MealCycle.lunches + MealCycle.breakfasts {
            for ingredient in meal.ingredients {
                XCTAssertNotNil(ingredient.food, "\(meal.title): \(ingredient.foodID)")
            }
            XCTAssertNil(FoodExclusions.excluded(meal.title + " " + meal.ingredients.map(\.foodID).joined(separator: " ")), meal.title)
        }
    }

    // MARK: Weeks

    func testWeeksRotateEveryMondayAndWrapAfterEight() {
        let anchor = DayKey(year: 2026, month: 10, day: 19) // a Monday
        XCTAssertEqual(MealCycle.week(of: anchor, anchor: anchor, calendar: london), 1)
        XCTAssertEqual(MealCycle.week(of: DayKey(year: 2026, month: 10, day: 25), anchor: anchor, calendar: london), 1, "Sunday is still week 1")
        XCTAssertEqual(MealCycle.week(of: DayKey(year: 2026, month: 10, day: 26), anchor: anchor, calendar: london), 2)
        XCTAssertEqual(MealCycle.week(of: anchor.adding(days: 7 * 7, calendar: london), anchor: anchor, calendar: london), 8)
        XCTAssertEqual(MealCycle.week(of: anchor.adding(days: 7 * 8, calendar: london), anchor: anchor, calendar: london), 1)
        XCTAssertEqual(MealCycle.week(of: anchor.adding(days: -1, calendar: london), anchor: anchor, calendar: london), 8, "Before the anchor wraps backwards")
    }

    func testSettingTheWeekMovesTheAnchor() {
        let wednesday = DayKey(year: 2026, month: 10, day: 21)
        let anchor = MealCycle.anchor(today: wednesday, week: 3, calendar: london)
        XCTAssertEqual(MealCycle.week(of: wednesday, anchor: anchor, calendar: london), 3)
        XCTAssertEqual(MealCycle.mondayOf(wednesday, calendar: london), DayKey(year: 2026, month: 10, day: 19))
    }

    // MARK: Shopping

    func testLunchListCoversFivePortionsInWholePacks() {
        let burrito = MealCycle.meal(.lunch, week: 1)
        let list = CycleShopping.list(for: burrito)
        let chicken = list.first { $0.foodID == "chicken-breast" }
        // 5 × 200 g = 1 kg, sold in 650 g packs: two packs.
        XCTAssertEqual(chicken?.packs, "2 × 650 g")
        XCTAssertEqual(chicken?.needed, "1 kg chicken breast")
        XCTAssertEqual(chicken?.pricePence, 2 * 449)
        XCTAssertEqual(list.first { $0.foodID == "spray-oil" }?.checkFirst, true, "Staples are checked, not bought")
        XCTAssertEqual(list.first { $0.foodID == "rice" }?.checkFirst, true, "Long-life packs usually last more than a week")
        XCTAssertEqual(list.first { $0.foodID == "kidney-beans" }?.checkFirst, false, "Tins the week uses up are bought")
        XCTAssertEqual(list.first { $0.foodID == "salsa" }?.checkFirst, false, "A jar the week empties is bought")
        let estimate = CycleShopping.estimate(list)
        XCTAssertEqual(estimate.value, list.filter { !$0.checkFirst }.reduce(0) { $0 + $1.pricePence })
    }

    func testBreakfastListCoversSevenPortions() {
        let shake = MealCycle.meal(.breakfast, week: 4)
        let list = CycleShopping.list(for: shake)
        // 7 × 120 g of banana is 7 bananas: two packs of five.
        XCTAssertEqual(list.first { $0.foodID == "bananas" }?.needed, "7 bananas")
        XCTAssertEqual(list.first { $0.foodID == "bananas" }?.packs, "2 × pack of 5")
        // 7 × 300 ml of milk is 2.1 litres: one 2,272 ml bottle.
        XCTAssertEqual(list.first { $0.foodID == "milk" }?.packs, "2.3 l")
    }

    func testListsFollowTheShop() {
        let order = AisleDepartment.allCases
        let list = CycleShopping.list(for: MealCycle.meal(.lunch, week: 2))
        let positions = list.map { order.firstIndex(of: $0.department) ?? 0 }
        XCTAssertEqual(positions, positions.sorted())
    }

    func testIngredientWording() {
        XCTAssertEqual(CycleIngredient(foodID: "eggs", grams: 58).text(), "1 egg")
        XCTAssertEqual(CycleIngredient(foodID: "eggs", grams: 58).text(portions: 7), "7 eggs")
        XCTAssertEqual(CycleIngredient(foodID: "lemon", grams: 30).text(), "½ lemon")
        XCTAssertEqual(CycleIngredient(foodID: "garlic", grams: 4).text(portions: 5), "5 garlic cloves")
        XCTAssertEqual(CycleIngredient(foodID: "chicken-breast", grams: 210).text(), "210 g chicken breast")
        XCTAssertEqual(CycleIngredient(foodID: "milk", grams: 300).text(portions: 7), "2.1 l semi-skimmed milk")
        XCTAssertEqual(CycleIngredient(foodID: "spray-oil", grams: 1).text(), "spray oil")
    }

    func testCatalogueMatchesLongestName() {
        XCTAssertEqual(FoodCatalogue.match("chicken thighs")?.id, "chicken-thigh")
        XCTAssertEqual(FoodCatalogue.match("turkey mince")?.id, "turkey-mince")
        XCTAssertEqual(FoodCatalogue.match("chickpeas")?.id, "chickpeas", "Doesn't match 'peas' inside a word")
        XCTAssertEqual(FoodCatalogue.match("skyr")?.id, "skyr")
        XCTAssertNil(FoodCatalogue.match("unicorn steak"))
    }

    // MARK: Barcodes

    func testOpenFoodFactsProductIsRead() throws {
        let json = """
        {"status":1,"product":{"product_name":"Protein Yogurt","brands":"Brooklea, Aldi","serving_quantity":"200","serving_size":"200 g",
         "nutriments":{"energy-kcal_100g":62,"proteins_100g":"10.2","carbohydrates_100g":4.1,"fat_100g":0.4}}}
        """
        let result = OpenFoodFacts.parse(Data(json.utf8), barcode: "4088600123456")
        let product = try result.get()
        XCTAssertEqual(product.name, "Protein Yogurt")
        XCTAssertEqual(product.brand, "Brooklea")
        XCTAssertEqual(product.per100.protein, 10.2, accuracy: 0.001)
        XCTAssertEqual(product.servingGrams, 200)
        let serving = product.macros(grams: 200)
        XCTAssertEqual(serving.kcal, 124, accuracy: 0.01)
        XCTAssertEqual(serving.protein, 20.4, accuracy: 0.01)
    }

    func testOpenFoodFactsFallsBackToKilojoulesAndReportsMissing() {
        let kilojoules = #"{"status":1,"product":{"product_name":"Oat bar","nutriments":{"energy_100g":1674}}}"#
        let product = try? OpenFoodFacts.parse(Data(kilojoules.utf8), barcode: "12345678").get()
        XCTAssertEqual(product?.per100.kcal ?? 0, 400, accuracy: 0.5)
        XCTAssertEqual(product?.per100.protein, 0)

        let missing = #"{"status":0,"status_verbose":"product not found"}"#
        XCTAssertEqual(OpenFoodFacts.parse(Data(missing.utf8), barcode: "12345678"), .failure(.notFound))
        let noNutrition = #"{"status":1,"product":{"product_name":"Mystery","nutriments":{}}}"#
        XCTAssertEqual(OpenFoodFacts.parse(Data(noNutrition.utf8), barcode: "12345678"), .failure(.noNutrition))
        XCTAssertNil(OpenFoodFacts.url(barcode: "123"), "Too short to be a barcode")
    }

    func testDayTotalsByMeal() {
        let day = DayNutrition.summarise([
            (meal: .breakfast, macros: Macros(kcal: 500, protein: 50, carbs: 50, fat: 8)),
            (meal: .evening, macros: Macros(kcal: 600, protein: 40, carbs: 60, fat: 20)),
            (meal: .evening, macros: Macros(kcal: 100, protein: 2, carbs: 10, fat: 5)),
        ])
        XCTAssertEqual(day.total.kcal, 1_200)
        XCTAssertEqual(day.byMeal[.evening]?.kcal, 700)
        XCTAssertNil(day.byMeal[.lunch])
    }

    func testSharedListIsOneListInShopOrder() {
        let veg = CycleShoppingLine(foodID: "peppers", name: "Peppers", department: .fruitVeg, needed: "3", packs: "1 × pack of 3",
                                    pricePence: 99, checkFirst: false)
        let chicken = CycleShoppingLine(foodID: "chicken", name: "Chicken breast", department: .meatFish, needed: "1 kg",
                                        packs: "2 × 650 g", pricePence: 798, checkFirst: false)
        let breakfastVeg = CycleShoppingLine(foodID: "peppers", name: "Peppers", department: .fruitVeg, needed: "2",
                                             packs: "1 × pack of 3", pricePence: 99, checkFirst: false)
        let rice = CycleShoppingLine(foodID: "rice", name: "Basmati rice", department: .cupboard, needed: "300 g", packs: "1 kg",
                                     pricePence: 149, checkFirst: true)
        let text = CycleShopping.shareText(heading: "Aldi list", meals: ["Lunches: Fajita bowls × 5"],
                                           lines: [chicken, veg, rice, breakfastVeg])
        XCTAssertEqual(text, """
        Aldi list
        Lunches: Fajita bowls × 5

        Fruit and veg:
        ☐ Peppers (1 × pack of 3 + 1 × pack of 3)

        Meat and fish:
        ☐ Chicken breast (2 × 650 g)

        Check the cupboard first:
        ☐ Basmati rice (300 g)

        About \(Pence(996).formatted()) at Aldi
        """)
    }

    @MainActor
    func testSharingAfterTickingSendsWhatsLeft() {
        let kitchen = PreviewFixtures.kitchen()
        let monday = kitchen.shoppingMonday(next: false)
        let full = kitchen.shareText(weekStarting: monday)
        XCTAssertTrue(full.hasPrefix("Aldi list · week of"))
        let first = kitchen.shoppingList(.lunch, weekStarting: monday)[0]
        kitchen.toggle(first, slot: .lunch, monday: monday)
        let left = kitchen.shareText(weekStarting: monday)
        XCTAssertTrue(left.hasPrefix("Aldi list, still to get"))
        XCTAssertLessThan(left.count, full.count)
    }
}
