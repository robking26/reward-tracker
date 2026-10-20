import XCTest
import SwiftData
@testable import FitnessVault

@MainActor
final class KitchenModelTests: XCTestCase {
    private var london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    private let monday = DayKey(year: 2026, month: 10, day: 19)

    private func at(_ hour: Int, _ minute: Int = 0, day: DayKey? = nil) -> Date {
        (day ?? monday).startDate(calendar: london).addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    private struct Harness {
        var kitchen: KitchenModel
        var reminders: RecordingReminderScheduler
        var clock: TestClock
    }

    private func make(at date: Date, defaults: UserDefaults? = nil) -> Harness {
        let clock = TestClock(date)
        let container = Persistence.makeContainer(inMemory: true)
        let store = defaults ?? UserDefaults(suiteName: "kitchen.test.\(UUID().uuidString)")!
        let reminders = RecordingReminderScheduler()
        let kitchen = KitchenModel(container: container, reminders: reminders, countdowns: RecordingCountdowns(),
                                   defaults: store, calendar: london, now: { clock.date })
        kitchen.start()
        return Harness(kitchen: kitchen, reminders: reminders, clock: clock)
    }

    func testStartSeedsRecipesAndPlansTheWeek() {
        let h = make(at: at(9))
        XCTAssertEqual(h.kitchen.recipes.count, StarterRecipes.all.count)
        let days = (0..<7).map { monday.adding(days: $0, calendar: london) }
        for day in days {
            XCTAssertNotNil(h.kitchen.dinner(on: day), "Dinner planned for \(day)")
        }
        let lunches = h.kitchen.plan.filter { $0.slot == .lunch }
        XCTAssertEqual(lunches.count, 5, "Monday to Friday")
        XCTAssertEqual(Set(lunches.map(\.title)).count, 1, "The same batch-cooked lunch all week")
        let dinners = h.kitchen.plan.filter { $0.slot == .dinner && $0.recipeID != nil && !$0.fromFreezer }.map(\.title)
        XCTAssertEqual(Set(dinners).count, dinners.count, "No dinner twice in a week")

        // Starting again doesn't seed twice or duplicate the plan.
        h.kitchen.start()
        XCTAssertEqual(h.kitchen.recipes.count, StarterRecipes.all.count)
        XCTAssertEqual(h.kitchen.plan.filter { $0.slot == .lunch }.count, 5)
    }

    func testInventoryCorrections() {
        let h = make(at: at(18))
        _ = h.kitchen.markOut("milk")
        let milk = FoodCatalogue.byID["milk"]!
        XCTAssertEqual(h.kitchen.presence(of: milk), .out)
        _ = h.kitchen.addToShopping("milk")
        XCTAssertTrue(h.kitchen.shopping.contains { $0.key == "milk" })

        _ = h.kitchen.confirm("chilli", portions: 3)
        XCTAssertEqual(h.kitchen.freezerMeals().first { $0.title == "Slow cooker turkey chilli" }?.portions, 3)

        _ = h.kitchen.confirm("eggs", portions: nil)
        XCTAssertEqual(h.kitchen.presence(of: FoodCatalogue.byID["eggs"]!), .have)
    }

    func testTickingAListItemUpdatesTheInventory() {
        let h = make(at: at(10))
        h.kitchen.generateShoppingList()
        XCTAssertFalse(h.kitchen.shopping.isEmpty)
        h.kitchen.addToShopping("milk")
        let item = h.kitchen.shopping.first { $0.key == "milk" }!
        h.kitchen.toggle(item)
        XCTAssertEqual(h.kitchen.presence(of: FoodCatalogue.byID["milk"]!), .have)
        // Rebuilding keeps ticked and hand-added lines.
        h.kitchen.generateShoppingList()
        XCTAssertTrue(h.kitchen.shopping.contains { $0.key == "milk" && $0.ticked })
        h.kitchen.clearTicked()
        XCTAssertFalse(h.kitchen.shopping.contains { $0.key == "milk" })
    }

    func testEatingAFreezableDinnerFreezesTheSpares() {
        let h = make(at: at(19))
        let tonight = h.kitchen.tonight!
        let ragu = h.kitchen.recipes.first { $0.title == "Beef ragu pasta" }!
        h.kitchen.swap(tonight, to: ragu)
        let note = h.kitchen.markCooked(tonight)
        XCTAssertEqual(note, "Two portions of Beef ragu pasta into the freezer.")
        XCTAssertEqual(h.kitchen.freezerMeals().first { $0.title == "Beef ragu pasta" }?.portions, 2)
        XCTAssertEqual(ragu.timesCooked, 1)
        XCTAssertNotNil(ragu.lastCookedAt)
    }

    func testDefrostReminderAndForgottenDefrost() {
        let h = make(at: at(9))
        h.kitchen.adjustFreezer(title: "Chicken curry (freezer favourite)", by: 4)
        let tuesday = monday.adding(days: 1, calendar: london)
        let tomorrow = h.kitchen.dinner(on: tuesday)!
        h.kitchen.useFreezer(tomorrow, meal: FreezerMeal(title: "Chicken curry (freezer favourite)", portions: 4, recipeID: nil))
        let reminder = h.reminders.latest.first { $0.id.hasPrefix(DefrostPlanner.prefix) }
        XCTAssertEqual(reminder?.date, at(20, 30))
        XCTAssertTrue(reminder?.body.contains("Move two portions") ?? false)

        // Next day: it wasn't moved to the fridge.
        h.clock.date = at(17, day: tuesday)
        h.kitchen.refresh()
        XCTAssertTrue(h.kitchen.tonightNeedsDefrosting)
        XCTAssertFalse(h.kitchen.rescueOptions(defrostForgotten: true).isEmpty)

        h.kitchen.markDefrosted(h.kitchen.tonight!)
        XCTAssertFalse(h.kitchen.tonightNeedsDefrosting)
    }

    func testReceiptsRefuseDuplicatesAndCountTowardsTheCeiling() {
        let h = make(at: at(12))
        let lines = [ReceiptLine(name: "CHICKEN BREAST FILLETS", quantity: 1, pricePence: 449, foodID: "chicken-breast", uncertain: false)]
        XCTAssertEqual(h.kitchen.saveReceipt(merchant: .aldi, date: at(11), totalPence: 4_230, lines: lines, needsReview: false, manual: false), .saved)
        XCTAssertEqual(h.kitchen.saveReceipt(merchant: .aldi, date: at(15), totalPence: 4_230, lines: lines, needsReview: false, manual: false),
                       .duplicate, "Same shop, same day, same total")
        XCTAssertEqual(h.kitchen.saveReceipt(merchant: .takeaway, date: at(20), totalPence: 2_450, lines: [], needsReview: false, manual: true), .saved)
        XCTAssertEqual(h.kitchen.budget.spent, Pence(6_680))
        XCTAssertEqual(h.kitchen.budget.remaining, Pence(40_000 - 6_680))
        XCTAssertEqual(h.kitchen.presence(of: FoodCatalogue.byID["chicken-breast"]!), .probably, "A receipt is never 'definitely'")
    }

    func testDinnerRescueWithNothingPlanned() {
        let h = make(at: at(18))
        let options = h.kitchen.rescueOptions(defrostForgotten: false)
        XCTAssertFalse(options.isEmpty)
        XCTAssertLessThanOrEqual(options.count, 3)
        XCTAssertTrue(options.contains { $0.kind == .takeaway }, "Full budget allows a takeaway option")
    }

    func testHomeWorkdaysPersistAndGateSlowCookerMeals() {
        let defaults = UserDefaults(suiteName: "kitchen.test.\(UUID().uuidString)")!
        let h = make(at: at(6), defaults: defaults)
        let week = h.kitchen.dayContexts(from: monday)
        XCTAssertTrue(week.prefix(5).allSatisfy { $0.office && !$0.workFromHome }, "Office by default")
        XCTAssertTrue(week.suffix(2).allSatisfy { !$0.office && !$0.workFromHome }, "Weekends aren't workdays")

        h.kitchen.setHomeWorkday(1, true)
        h.kitchen.setHomeWorkday(3, true)
        XCTAssertEqual(h.kitchen.dayContexts(from: monday).filter(\.workFromHome).map(\.weekday), [1, 3])

        let reopened = KitchenModel(container: Persistence.makeContainer(inMemory: true), reminders: RecordingReminderScheduler(),
                                    countdowns: RecordingCountdowns(), defaults: defaults, calendar: london, now: { h.clock.date })
        XCTAssertEqual(reopened.homeWorkdays, [1, 3])

        // Any slow-cooker reminder lands at 07:10 on the day.
        for note in h.kitchen.reminderPlan() where note.id.hasPrefix(KitchenModel.reminderPrefix + "slow.") {
            let day = DayKey(string: String(note.id.dropFirst((KitchenModel.reminderPrefix + "slow.").count)))!
            XCTAssertEqual(note.date, day.date(atMinute: 7 * 60 + 10, calendar: london))
        }
    }
}
