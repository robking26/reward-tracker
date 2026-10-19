import XCTest
@testable import FitnessVault

final class KitchenDomainTests: XCTestCase {
    // MARK: Ingredients and recipes

    func testIngredientParsingConvertsUnits() {
        let chicken = IngredientParser.parse("400g chicken breast, diced")
        XCTAssertEqual(chicken.foodID, "chicken-breast")
        XCTAssertEqual(chicken.amount, 400)
        XCTAssertEqual(chicken.unit, .grams)

        let oil = IngredientParser.parse("2 tbsp olive oil")
        XCTAssertEqual(oil.foodID, "olive-oil")
        XCTAssertEqual(oil.amount, 30)
        XCTAssertEqual(oil.unit, .millilitres)

        let tins = IngredientParser.parse("2 tins chopped tomatoes")
        XCTAssertEqual(tins.foodID, "chopped-tomatoes")
        XCTAssertEqual(tins.grams, 800)

        let weighed = IngredientParser.parse("1 x 400g tin kidney beans")
        XCTAssertEqual(weighed.foodID, "kidney-beans")
        XCTAssertEqual(weighed.grams, 400)

        let rice = IngredientParser.parse("1kg basmati rice")
        XCTAssertEqual(rice.amount, 1000)

        let half = IngredientParser.parse("½ lemon")
        XCTAssertEqual(half.amount, 0.5)
        XCTAssertEqual(half.foodID, "lemon")
    }

    func testCatalogueMatchesLongestName() {
        XCTAssertEqual(FoodCatalogue.match("chicken thighs")?.id, "chicken-thigh")
        XCTAssertEqual(FoodCatalogue.match("turkey mince")?.id, "turkey-mince")
        XCTAssertEqual(FoodCatalogue.match("green beans")?.id, "green-beans")
        XCTAssertEqual(FoodCatalogue.match("chickpeas")?.id, "chickpeas", "Doesn't match 'peas' inside a word")
        XCTAssertNil(FoodCatalogue.match("unicorn steak"))
    }

    func testRecipeParserReadsAStructuredRecipe() {
        let text = """
        Lemon Chicken Traybake
        Serves 2
        Prep time: 10 mins
        Cook time: 35 mins
        Ingredients
        400g chicken thighs
        500g baby potatoes
        1 lemon
        2 tbsp olive oil
        Method
        1. Heat the oven to 200C.
        2. Put everything on a baking tray and roast for 35 minutes.
        """
        let draft = RecipeParser.parse(text)
        XCTAssertEqual(draft.title, "Lemon Chicken Traybake")
        XCTAssertEqual(draft.servings, 2)
        XCTAssertTrue(draft.servingsWasRead)
        XCTAssertEqual(draft.prepMinutes, 10)
        XCTAssertEqual(draft.cookMinutes, 35)
        XCTAssertEqual(draft.ingredients.count, 4)
        XCTAssertEqual(draft.steps.count, 2)
        XCTAssertEqual(draft.steps.first, "Heat the oven to 200C.")
        XCTAssertTrue(draft.isOnePan)
        XCTAssertTrue(draft.excluded.isEmpty)
        XCTAssertEqual(draft.nutrition.confidence, .good)
        // 400 g thighs + 500 g potatoes + a lemon + 30 ml oil, over two portions ≈ 685 kcal.
        XCTAssertGreaterThan(draft.nutrition.perPortion.kcal, 600)
        XCTAssertLessThan(draft.nutrition.perPortion.kcal, 760)
        XCTAssertGreaterThan(draft.nutrition.perPortion.protein, 35)
    }

    func testRecipeParserWithoutHeadingsAndUnknownIngredients() {
        let text = """
        Mystery stew
        300g dragon fruit
        200g beef mince
        Fry the mince in a frying pan, then add the fruit and simmer in a saucepan for 20 minutes.
        """
        let draft = RecipeParser.parse(text)
        XCTAssertEqual(draft.ingredients.count, 2)
        XCTAssertEqual(draft.steps.count, 1)
        XCTAssertFalse(draft.servingsWasRead, "Defaults to two and says so")
        XCTAssertEqual(draft.servings, 2)
        XCTAssertEqual(draft.nutrition.unmatched, ["dragon fruit"])
        XCTAssertEqual(draft.nutrition.confidence, .rough)
        XCTAssertEqual(draft.cookware, 2)
        XCTAssertFalse(draft.isOnePan)
    }

    func testExclusionsAreFlagged() {
        let draft = RecipeParser.parse("Veg bake\nIngredients\n1 courgette\n200g mushrooms\n1 onion")
        XCTAssertEqual(Set(draft.excluded), ["courgette", "mushroom"])
        XCTAssertEqual(FoodExclusions.excluded("Cauliflower cheese"), "cauliflower")
    }

    func testMacroTweaksMarkFlavourChanges() {
        let ingredients = ["500g beef mince", "300ml double cream", "4 tbsp olive oil", "100g cheddar"].map(IngredientParser.parse)
        let tweaks = MacroTweaks.suggest(ingredients, servings: 4)
        let lean = tweaks.first { $0.withFoodID == "beef-mince-5" }
        XCTAssertNotNil(lean)
        XCTAssertFalse(lean?.changesFlavour ?? true)
        XCTAssertTrue(tweaks.first { $0.withFoodID == "creme-fraiche" }?.changesFlavour ?? false, "Cream swap needs approval")
        let applied = MacroTweaks.apply(lean!, to: ingredients)
        let before = NutritionEstimator.estimate(ingredients, servings: 4).perPortion.kcal
        let after = NutritionEstimator.estimate(applied, servings: 4).perPortion.kcal
        XCTAssertLessThan(after, before)
        XCTAssertEqual(applied.first?.amount, 500, "Same amount, leaner meat")
    }

    // MARK: Meal planning

    private func candidate(_ title: String, role: MealRole = .dinner, minutes: Int = 30, slowCooker: Bool = false,
                           fakeaway: Bool = false, freezable: Bool = false, favourite: Bool = false, excluded: Bool = false,
                           lastCooked: DayKey? = nil) -> MealCandidate {
        MealCandidate(id: UUID(), title: title, role: role, servings: role == .lunch ? 5 : 2, prepMinutes: 10,
                      cookMinutes: minutes - 10, washUpMinutes: 8, usesSlowCooker: slowCooker, isFakeaway: fakeaway,
                      freezable: freezable, favourite: favourite, excluded: excluded, lastCooked: lastCooked)
    }

    private let monday = DayKey(year: 2026, month: 10, day: 19)

    private func week(office: Set<Int> = [1, 2, 3, 4, 5], home: Set<Int> = [], late: Set<Int> = [], out: Set<Int> = []) -> [MealDayContext] {
        (1...7).map { weekday in
            MealDayContext(day: monday.adding(days: weekday - 1), weekday: weekday, workFromHome: home.contains(weekday),
                           office: office.contains(weekday) && !home.contains(weekday), eatingOut: out.contains(weekday),
                           lateFinish: late.contains(weekday))
        }
    }

    func testPlanHasSameLunchMondayToFridayAndVariedDinners() {
        let lunches = [candidate("A lunch", role: .lunch), candidate("B lunch", role: .lunch)]
        let dinners = (1...8).map { candidate("Dinner \($0)") }
        let plan = MealPlanner.plan(MealPlanInput(days: week(), candidates: lunches + dinners, freezer: [], rotationWeek: 1))
        let lunchTitles = plan.filter { $0.slot == .lunch }.map(\.title)
        XCTAssertEqual(lunchTitles, Array(repeating: "B lunch", count: 5), "Rotation week 1 picks the second lunch")
        let dinnerTitles = plan.filter { $0.slot == .dinner }.map(\.title)
        XCTAssertEqual(dinnerTitles.count, 7)
        XCTAssertEqual(Set(dinnerTitles).count, 7, "No repeats in a week")
        XCTAssertTrue(plan.filter { $0.slot == .dinner }.allSatisfy { $0.portions == 2 }, "Two identical portions")
    }

    func testExcludedAndRecentDinnersAreNotPlanned() {
        let dinners = [candidate("Cauliflower cheese", excluded: true), candidate("Had it yesterday", lastCooked: monday.adding(days: -1)),
                       candidate("Fine")]
        let plan = MealPlanner.plan(MealPlanInput(days: Array(week().prefix(1)), candidates: dinners, freezer: [], rotationWeek: 0))
        XCTAssertEqual(plan.first { $0.slot == .dinner }?.title, "Fine")
    }

    func testSlowCookerOnlyOnWorkFromHomeDays() {
        let chilli = candidate("Slow chilli", minutes: 300, slowCooker: true, favourite: true)
        let other = candidate("Stir fry")
        let officeMonday = MealPlanner.plan(MealPlanInput(days: Array(week().prefix(1)), candidates: [chilli, other], freezer: [], rotationWeek: 0))
        XCTAssertEqual(officeMonday.first { $0.slot == .dinner }?.title, "Stir fry", "No morning prep on an office day")
        let homeMonday = MealPlanner.plan(MealPlanInput(days: Array(week(home: [1]).prefix(1)), candidates: [chilli, other], freezer: [], rotationWeek: 0))
        XCTAssertEqual(homeMonday.first { $0.slot == .dinner }?.title, "Slow chilli")
    }

    func testFridayPrefersFakeawayAndLateDaysUseQuickOrFreezer() {
        let days = week(late: [2])
        let candidates = [candidate("Katsu", fakeaway: true), candidate("Long roast", minutes: 90), candidate("Quick noodles", minutes: 15)]
        let plan = MealPlanner.plan(MealPlanInput(days: days, candidates: candidates, freezer: [FreezerMeal(title: "Curry", portions: 4)],
                                                  rotationWeek: 0))
        let dinners = Dictionary(uniqueKeysWithValues: plan.filter { $0.slot == .dinner }.map { ($0.day, $0) })
        XCTAssertEqual(dinners[monday.adding(days: 4)]?.title, "Katsu")
        XCTAssertEqual(dinners[monday.adding(days: 1)]?.title, "Quick noodles", "Late finish gets the quick one")
        XCTAssertTrue(dinners.values.contains { $0.fromFreezer && $0.title == "Curry" }, "Freezer fills gaps when recipes run out")
    }

    func testEatingOutHasNoMeal() {
        let plan = MealPlanner.plan(MealPlanInput(days: Array(week(out: [1]).prefix(1)), candidates: [candidate("Fine")], freezer: [], rotationWeek: 0))
        XCTAssertEqual(plan.first { $0.slot == .dinner }?.portions, 0)
    }

    func testRotationWeekCyclesEveryFourWeeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let weeks = (0..<5).map { MealPlanner.rotationWeek(for: monday.adding(days: $0 * 7, calendar: calendar), calendar: calendar) }
        XCTAssertEqual(weeks[0], weeks[4])
        XCTAssertEqual(Set(weeks).count, 4)
    }

    // MARK: Batch cooking (F5)

    func testBatchCookDropsFreezerExtrasToStayUnderAnHour() {
        let lunch = MealCandidate(id: UUID(), title: "Chicken rice", role: .lunch, servings: 5, prepMinutes: 15, cookMinutes: 25,
                                  washUpMinutes: 8, usesSlowCooker: false, isFakeaway: false, freezable: true, favourite: false,
                                  excluded: false, lastCooked: nil)
        let ragu = MealCandidate(id: UUID(), title: "Ragu", role: .dinner, servings: 4, prepMinutes: 10, cookMinutes: 35,
                                 washUpMinutes: 8, usesSlowCooker: false, isFakeaway: false, freezable: true, favourite: false,
                                 excluded: false, lastCooked: nil)
        let curry = MealCandidate(id: UUID(), title: "Curry", role: .dinner, servings: 4, prepMinutes: 20, cookMinutes: 35,
                                  washUpMinutes: 8, usesSlowCooker: false, isFakeaway: false, freezable: true, favourite: false,
                                  excluded: false, lastCooked: nil)
        let plan = BatchCookPlanner.plan(lunch: lunch, freezerDinners: [ragu, curry])
        XCTAssertTrue(plan.fits)
        XCTAssertLessThanOrEqual(plan.minutes, 60)
        XCTAssertFalse(plan.items.contains { $0.title == "Curry" }, "Dropped rather than pretending it fits")
        XCTAssertFalse(plan.adjustments.isEmpty)

        let slowLunch = MealCandidate(id: UUID(), title: "Big roast", role: .lunch, servings: 5, prepMinutes: 40, cookMinutes: 60,
                                      washUpMinutes: 15, usesSlowCooker: false, isFakeaway: false, freezable: false, favourite: false,
                                      excluded: false, lastCooked: nil)
        let tooLong = BatchCookPlanner.plan(lunch: slowLunch, freezerDinners: [])
        XCTAssertFalse(tooLong.fits)
        XCTAssertTrue(tooLong.adjustments.last?.contains("quicker lunch") ?? false)
    }

    // MARK: Defrosting (I5) and scenario G

    func testDefrostReminderTheEveningBefore() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let tuesday = monday.adding(days: 1, calendar: calendar)
        let meal = PlannedMeal(day: tuesday, slot: .dinner, recipeID: nil, title: "Curry", portions: 2, fromFreezer: true, note: nil)
        let morning = monday.startDate(calendar: calendar).addingTimeInterval(9 * 3600)
        let reminders = DefrostPlanner.reminders(for: [meal], now: morning, calendar: calendar)
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.date, monday.startDate(calendar: calendar).addingTimeInterval(TimeInterval(20 * 3600 + 30 * 60)))
        XCTAssertEqual(reminders.first?.body, "Tomorrow's dinner is Curry. Move two portions from the freezer to the fridge tonight.")
        XCTAssertTrue(DefrostPlanner.reminders(for: [meal], now: morning.addingTimeInterval(14 * 3600), calendar: calendar).isEmpty,
                      "Not after the moment has passed")
        XCTAssertTrue(DefrostPlanner.forgottenAdvice("Curry").contains("piping hot"))
        XCTAssertTrue(DefrostPlanner.forgottenAdvice("Curry").contains("Don't leave"))
    }

    func testDinnerRescueOffersLowFrictionOptions() {
        let noodles = candidate("Prawn noodles", minutes: 15)
        let fajitas = candidate("Fajitas", minutes: 30)
        let options = DinnerRescue.options(
            quick: [DinnerRescue.QuickOption(meal: fajitas, missing: ["peppers"], missingCost: Pence(109)),
                    DinnerRescue.QuickOption(meal: noodles, missing: [], missingCost: .zero)],
            freezer: [FreezerMeal(title: "Chilli", portions: 2)], foodBudgetLeft: .pounds(120), defrostForgotten: true)
        XCTAssertEqual(options.map(\.kind), [.cupboard, .freezer, .topUp])
        XCTAssertEqual(options.first?.title, "Prawn noodles")
        XCTAssertTrue(options[1].detail.contains("microwave"), "Forgotten defrost uses a safe microwave route")
        XCTAssertTrue(options[2].detail.contains("Co-op"))

        let lean = DinnerRescue.options(quick: [], freezer: [], foodBudgetLeft: .pounds(10), defrostForgotten: false)
        XCTAssertEqual(lean.map(\.title), ["Freezer fakeaway"], "No takeaway suggestion when the budget is nearly gone")
    }

    // MARK: Inventory (I4)

    func testOldReceiptNeverMeansDefinitelyPresent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func receipt(daysAgo: Double, shelf: Int = 7) -> Presence {
            InventoryEstimator.presence(InventorySnapshot(addedAt: now.addingTimeInterval(-daysAgo * 86_400), source: .receipt,
                                                          confirmedAt: nil, outAt: nil, shelfLifeDays: shelf,
                                                          usedSinceAdded: false, portions: nil), now: now)
        }
        XCTAssertEqual(receipt(daysAgo: 0), .probably, "Even today's receipt isn't 'definitely'")
        XCTAssertEqual(receipt(daysAgo: 5), .maybe)
        XCTAssertEqual(receipt(daysAgo: 30), .probablyNot)

        let told = InventoryEstimator.presence(InventorySnapshot(addedAt: nil, source: .userStated, confirmedAt: now, outAt: nil,
                                                                 shelfLifeDays: 7, usedSinceAdded: false, portions: nil), now: now)
        XCTAssertEqual(told, .have)
        let usedSince = InventoryEstimator.presence(InventorySnapshot(addedAt: now, source: .receipt, confirmedAt: nil, outAt: nil,
                                                                      shelfLifeDays: 7, usedSinceAdded: true, portions: nil), now: now)
        XCTAssertEqual(usedSince, .maybe)
        let ranOut = InventoryEstimator.presence(InventorySnapshot(addedAt: now.addingTimeInterval(-3600), source: .receipt,
                                                                   confirmedAt: nil, outAt: now, shelfLifeDays: 7,
                                                                   usedSinceAdded: false, portions: nil), now: now)
        XCTAssertEqual(ranOut, .out)
    }

    // MARK: Shopping (I2)

    func testShoppingListConsolidatesRoundsAndSkipsWhatsIn() {
        let needs = [
            ShoppingNeed(IngredientParser.parse("400g chicken breast"), forMeal: "Fajitas"),
            ShoppingNeed(IngredientParser.parse("400g chicken breast"), forMeal: "Katsu"),
            ShoppingNeed(IngredientParser.parse("2 peppers"), forMeal: "Fajitas"),
            ShoppingNeed(IngredientParser.parse("2 tbsp olive oil"), forMeal: "Fajitas"),
            ShoppingNeed(IngredientParser.parse("250g rice"), forMeal: "Katsu"),
            ShoppingNeed(IngredientParser.parse("1 lemon"), forMeal: "Katsu"),
        ]
        let presence: (FoodItem) -> Presence? = { food in
            switch food.id {
            case "rice": .probably
            case "lemon": .maybe
            default: nil
            }
        }
        let lines = ShoppingListBuilder.build(needs: needs, presence: presence, extras: ["washing up liquid", "unicorn food"])
        let byID = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })
        XCTAssertEqual(byID["chicken-breast"]?.packs, 2, "800 g → two 650 g packs")
        XCTAssertEqual(byID["chicken-breast"]?.reasons, ["Fajitas", "Katsu"])
        XCTAssertEqual(byID["peppers"]?.packs, 1)
        XCTAssertNil(byID["olive-oil"], "Staples aren't added unless they've run out")
        XCTAssertNil(byID["rice"], "Probably in already")
        XCTAssertTrue(byID["lemon"]?.checkFirst ?? false)
        XCTAssertNotNil(byID["washing-up-liquid"])
        XCTAssertEqual(byID["unicorn food"]?.department, .other)
        let departments = lines.map(\.department)
        XCTAssertEqual(departments, departments.sorted { AisleDepartment.allCases.firstIndex(of: $0)! < AisleDepartment.allCases.firstIndex(of: $1)! },
                       "In Aldi walking order")
        XCTAssertGreaterThan(ShoppingListBuilder.estimate(lines).value, 0)
    }

    func testBudgetIsACeilingNotATarget() {
        let calm = HouseholdBudget(spent: .pounds(150), dayOfMonth: 15, daysInMonth: 30)
        XCTAssertTrue(calm.summary.contains("not a target"))
        XCTAssertNil(calm.warning(forList: .pounds(60)))
        let near = HouseholdBudget(spent: .pounds(370), dayOfMonth: 25, daysInMonth: 30)
        XCTAssertNotNil(near.warning(forList: .pounds(45)))
        let over = HouseholdBudget(spent: .pounds(410), dayOfMonth: 28, daysInMonth: 30)
        XCTAssertTrue(over.isOver)
        XCTAssertEqual(over.remaining, .zero)
    }

    // MARK: Receipts (I3)

    func testReceiptParserReadsAnAldiReceipt() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let text = """
        ALDI
        Stores Ltd
        CHICKEN BREAST FILLETS 4.49 A
        2 x SEMI SKIMMED MILK 2.90 A
        BASMATI RICE 1.49 A
        WASHING UP LIQUID 0.99 B
        TOTAL 9.87
        VISA CONTACTLESS 9.87
        18/10/26 14:32
        """
        let receipt = ReceiptParser.parse(text, calendar: calendar)
        XCTAssertEqual(receipt.merchant, .aldi)
        XCTAssertEqual(receipt.totalPence, 987)
        XCTAssertEqual(receipt.lines.count, 4)
        XCTAssertEqual(receipt.lines[1].quantity, 2)
        XCTAssertEqual(receipt.lines[1].foodID, "milk")
        XCTAssertEqual(receipt.lines[0].foodID, "chicken-breast")
        XCTAssertFalse(receipt.needsReview)
        XCTAssertEqual(receipt.date.map { DayKey($0, calendar: calendar) }, DayKey(year: 2026, month: 10, day: 18))
    }

    func testReceiptThatDoesntAddUpNeedsReview() {
        let receipt = ReceiptParser.parse("Co-op\nMILK 1.45\nBR3AD 1.10\nTOTAL 5.00\n12/10/2026")
        XCTAssertEqual(receipt.merchant, .coop)
        XCTAssertTrue(receipt.needsReview)
        let takeaway = ReceiptParser.parse("Just Eat\nTotal £24.50")
        XCTAssertEqual(takeaway.merchant, .takeaway)
        XCTAssertTrue(takeaway.needsReview, "No date")
    }

    func testReceiptFingerprintIdentifiesDuplicates() {
        let day = DayKey(year: 2026, month: 10, day: 18)
        XCTAssertEqual(ReceiptParser.fingerprint(merchant: .aldi, day: day, totalPence: 987),
                       ReceiptParser.fingerprint(merchant: .aldi, day: day, totalPence: 987))
        XCTAssertNotEqual(ReceiptParser.fingerprint(merchant: .aldi, day: day, totalPence: 987),
                          ReceiptParser.fingerprint(merchant: .coop, day: day, totalPence: 987))
    }

    // MARK: Conversation

    func testKitchenIntents() {
        XCTAssertEqual(CoachIntentParser.parse("We've got three portions of curry left"), .haveLeft(portions: 3, item: "curry"))
        XCTAssertEqual(CoachIntentParser.parse("we have 2 portions of chilli in the freezer"), .haveLeft(portions: 2, item: "chilli"))
        XCTAssertEqual(CoachIntentParser.parse("We've got eggs"), .haveLeft(portions: nil, item: "eggs"))
        XCTAssertEqual(CoachIntentParser.parse("I used the last chicken"), .ranOut("chicken"))
        XCTAssertEqual(CoachIntentParser.parse("Add milk to the shopping list"), .addToShopping("milk"))
        XCTAssertEqual(CoachIntentParser.parse("We need bin bags"), .addToShopping("bin bags"))
        XCTAssertEqual(CoachIntentParser.parse("We need to sort the attic"), .unknown("We need to sort the attic"))
        XCTAssertEqual(CoachIntentParser.parse("What's for dinner?"), .whatsForDinner)
        XCTAssertEqual(CoachIntentParser.parse("I forgot to defrost the curry"), .forgotDefrost)
        XCTAssertEqual(CoachIntentParser.parse("It's defrosted"), .defrosted)
        XCTAssertEqual(CoachIntentParser.parse("There's nothing in for dinner"), .dinnerNotReady)
        XCTAssertEqual(CoachIntentParser.parse("Put cleaning the attic on my list"), .addTask("cleaning the attic"), "Tasks still work")
    }

    func testStarterRecipesAvoidExclusionsAndParseCleanly() {
        for recipe in StarterRecipes.all {
            let text = ([recipe.title] + recipe.ingredients).joined(separator: " ")
            XCTAssertNil(FoodExclusions.excluded(text), recipe.title)
            let parsed = recipe.ingredients.map(IngredientParser.parse)
            XCTAssertTrue(parsed.allSatisfy { $0.foodID != nil }, "\(recipe.title): \(parsed.filter { $0.foodID == nil }.map(\.original))")
            let estimate = NutritionEstimator.estimate(parsed, servings: recipe.servings)
            XCTAssertNotEqual(estimate.confidence, .rough, recipe.title)
            if recipe.role != .breakfast {
                XCTAssertGreaterThan(estimate.perPortion.protein, 25, "\(recipe.title) is high protein")
            }
        }
    }
}
