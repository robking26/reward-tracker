import XCTest
@testable import FitnessVault

final class TeaPlannerTests: XCTestCase {
    let london = PlannerFixtures().london
    /// Saturday 31 October 2026.
    let saturday = DayKey(year: 2026, month: 10, day: 31)

    private func recipe(_ id: String, kcal: Double = 650, protein: Double = 55, quick: Bool = false) -> TeaRecipe {
        TeaRecipe(id: id, title: id.capitalized, kcal: kcal, protein: protein, prepMinutes: 10, cookMinutes: quick ? 20 : 40)
    }

    func testTargets() {
        XCTAssertEqual(recipe("a", kcal: 600, protein: 50).portion, TeaPortion(scale: 1))
        XCTAssertEqual(recipe("a", kcal: 551, protein: 48).portion, TeaPortion(scale: 1.1), "The bolognaise: a tenth more")
        XCTAssertEqual(recipe("a", kcal: 720, protein: 55).portion, TeaPortion(scale: 0.95), "A little less")
        XCTAssertNil(recipe("a", kcal: 1600, protein: 10).portion, "Even half is over 700 kcal")
        let bolognaise = recipe("a", kcal: 551, protein: 48)
        XCTAssertEqual(bolognaise.portionKcal, 606.1, accuracy: 0.01)
        XCTAssertEqual(TeaRecipe.scaled("240g chicken breast", by: 1.3), "310g chicken breast")
        XCTAssertEqual(TeaRecipe.scaled("10ml Worcester sauce", by: 1.3), "13ml Worcester sauce")
        XCTAssertEqual(TeaRecipe.scaled("1 onion", by: 1.3), "1 onion")
        XCTAssertEqual(TeaPlanner.deck([recipe("ok"), recipe("big", kcal: 1600, protein: 10)], week: "x").map(\.id), ["ok"])
    }

    func testLightRecipesGetAProteinTopUp() throws {
        let casserole = TeaRecipe(id: "sausage", title: "Slow Cooker Sausage Casserole", kcal: 497, protein: 28,
                                  ingredients: ["6 skinny pork sausages", "360g potato", "1 onion"])
        let portion = try XCTUnwrap(casserole.portion, "Resizing alone can't get it there; a top-up can")
        XCTAssertEqual(portion.boost, .pork, "More of what's in it")
        XCTAssertTrue(TeaTargets.kcal.contains(casserole.portionKcal))
        XCTAssertGreaterThanOrEqual(casserole.portionProtein, 50)
        XCTAssertEqual(portion.boostGrams.truncatingRemainder(dividingBy: 10), 0)
        XCTAssertTrue(casserole.portionIngredients.last?.contains("pork loin") == true)

        let curry = TeaRecipe(id: "curry", title: "Chicken Curry", kcal: 542, protein: 37, ingredients: ["240g chicken breast"])
        XCTAssertEqual(curry.portion?.boost, .chicken)
        XCTAssertGreaterThanOrEqual(curry.portionProtein, 50)
        XCTAssertLessThanOrEqual(curry.portionKcal, 700)
        XCTAssertEqual(TeaRecipe(id: "x", title: "Veg Chilli", kcal: 450, protein: 15).portion?.boost, .chicken, "Chicken otherwise")
    }

    func testMondayToThursdayAreQuick() {
        XCTAssertTrue(recipe("a", quick: true).isQuick)
        XCTAssertFalse(recipe("a").isQuick)
        let nights = TeaPlanner.nights(from: saturday, calendar: london)
        XCTAssertEqual(nights.map { TeaPlanner.needsQuick($0, calendar: london) },
                       [false, false, true, true, true, true, false], "Sat, Sun, Mon–Thu, Fri")
    }

    func testNightsFilledFromMatchesWithQuickOnesMidweek() {
        let nights = TeaPlanner.nights(from: saturday, calendar: london)
        let monday = nights[2], tuesday = nights[3]
        let recipes = [recipe("curry", quick: true), recipe("stir-fry"), recipe("chilli", quick: true), recipe("pie", quick: true)]
        var diners: [String: TeaDiner] = [:]
        for night in nights { diners[night.description] = TeaDiner.notCooking }
        diners[saturday.description] = .together
        diners[monday.description] = .together
        diners[tuesday.description] = .rob
        let plan = TeaPlanner.assign(nights: nights, diners: diners, recipes: recipes, robLikes: ["curry", "stir-fry", "chilli"],
                                     beckyLikes: ["curry", "stir-fry"], calendar: london)
        XCTAssertEqual(plan[monday.description], "curry", "Monday: a quick match")
        XCTAssertEqual(plan[saturday.description], "stir-fry", "The other match, not repeated")
        XCTAssertEqual(plan[tuesday.description], "chilli", "Rob's own quick like")
        XCTAssertEqual(plan.count, 3, "Nothing on nights nobody's cooking")
    }

    func testTheRecipeBooksAreInTheBank() throws {
        let url = try XCTUnwrap(Bundle(for: TeaPlannerTests.self).url(forResource: "TeaRecipes", withExtension: "json")
            ?? Bundle.main.url(forResource: "TeaRecipes", withExtension: "json"))
        let recipes = try TeaPlanner.decode(Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(recipes.count, 100)
        XCTAssertEqual(Set(recipes.map(\.id)).count, recipes.count, "Unique IDs")
        XCTAssertEqual(recipes.filter { !$0.meetsTargets }.map(\.title), [], "Every recipe reaches the targets")
        XCTAssertGreaterThanOrEqual(recipes.filter(\.isQuick).count, 30, "Plenty for Monday to Thursday")
        for recipe in recipes {
            XCTAssertTrue(TeaTargets.kcal.contains(recipe.portionKcal.rounded()), recipe.title)
            XCTAssertGreaterThanOrEqual(recipe.portionProtein, 50, recipe.title)
        }
        XCTAssertTrue(recipes.allSatisfy { !$0.ingredients.isEmpty })
    }

    func testRecipesFromClaudeComeInEvenIfTheShapeVaries() throws {
        let json = #"""
        {"recipes": [
          {"name": "Harissa chicken traybake", "book": "Bored of Lunch, p. 112", "serves": 4, "calories": "655 kcal",
           "protein": 58, "carbs": 52, "fat": 18, "prep_minutes": 10, "cook_minutes": 35, "freezable": true,
           "ingredients": ["4 chicken breasts", "2 tbsp harissa"], "steps": ["Heat the oven to 200C.", "Roast for 35 minutes."]}
        ]}
        """#
        let recipes = try TeaPlanner.decode(Data(json.utf8))
        let first = try XCTUnwrap(recipes.first)
        XCTAssertEqual(first.id, "harissa-chicken-traybake")
        XCTAssertEqual(first.kcal, 655)
        XCTAssertEqual(first.source, "Bored of Lunch, p. 112")
        XCTAssertEqual(first.cookMinutes, 35)
        XCTAssertEqual(first.method.count, 2)
        XCTAssertTrue(first.meetsTargets)
        // And back out again in the standard shape.
        let round = try TeaPlanner.decode(try JSONEncoder().encode(recipes))
        XCTAssertEqual(round, recipes)
    }
}

@MainActor
final class TeaModelTests: XCTestCase {
    func testSwipeBothThenPlan() throws {
        let fixtures = PlannerFixtures()
        let saturday = DayKey(year: 2026, month: 10, day: 31)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "tests.teas.\(UUID().uuidString)"))
        let reminders = RecordingReminderScheduler()
        let teas = TeaModel(reminders: reminders, defaults: defaults, calendar: fixtures.london,
                            now: { saturday.date(atMinute: 8 * 60, calendar: fixtures.london) }, bundled: [])
        let json = #"[{"id":"curry","title":"Curry","kcal":650,"protein":55,"prepMinutes":10,"cookMinutes":15},{"id":"feast","title":"Feast","kcal":1600,"protein":10}]"#
        XCTAssertEqual(try teas.importRecipes(Data(json.utf8)), 2)
        XCTAssertEqual(teas.onTarget.map(\.id), ["curry"], "The feast can't come in under 700 kcal")

        teas.startWeek()
        XCTAssertTrue(teas.needs(.rob))
        XCTAssertTrue(teas.needs(.becky))
        for recipe in teas.deck(for: .rob) { teas.swipe(recipe, liked: true, by: .rob) }
        XCTAssertTrue(teas.deck(for: .rob).isEmpty)
        for recipe in teas.deck(for: .becky) { teas.swipe(recipe, liked: true, by: .becky) }
        XCTAssertEqual(teas.matches.map(\.id), ["curry"])
        teas.makePlan()
        let monday = saturday.adding(days: 2, calendar: fixtures.london)
        XCTAssertEqual(teas.week?.meals[monday.description], "curry")

        teas.scheduleReminders()
        XCTAssertEqual(reminders.latest.count, 4, "The next four Saturdays")
        XCTAssertEqual(reminders.latest.first?.date, saturday.date(atMinute: 9 * 60, calendar: fixtures.london))

        // A fresh model reads it all back.
        let again = TeaModel(reminders: reminders, defaults: defaults, calendar: fixtures.london,
                             now: { saturday.date(atMinute: 8 * 60, calendar: fixtures.london) }, bundled: [])
        XCTAssertEqual(again.recipes.count, 2)
        XCTAssertEqual(again.week?.meals[monday.description], "curry")
    }
}
