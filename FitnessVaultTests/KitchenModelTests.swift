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
        var coach: CoachModel
        var kitchen: KitchenModel
        var reminders: RecordingReminderScheduler
        var clock: TestClock
    }

    private func make(at date: Date) async -> Harness {
        let clock = TestClock(date)
        let container = Persistence.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "kitchen.test.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.settings.demoMode = true
        let demo = DemoCalendarService(calendar: london)
        let coach = CoachModel(container: container, settingsStore: settings, liveCalendar: demo, demoCalendar: demo,
                               defaults: defaults, reminders: RecordingReminderScheduler(), languageModel: nil,
                               calendar: london, now: { clock.date })
        await coach.start()
        let reminders = RecordingReminderScheduler()
        let kitchen = KitchenModel(container: container, coach: coach, reminders: reminders, calendar: london, now: { clock.date })
        kitchen.start()
        return Harness(coach: coach, kitchen: kitchen, reminders: reminders, clock: clock)
    }

    func testStartSeedsRecipesAndPlansTheWeek() async {
        let h = await make(at: at(9))
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

    func testConversationalInventoryCorrections() async {
        let h = await make(at: at(18))
        let reply = h.coach.respond(to: "We've run out of milk")
        XCTAssertTrue(reply.text.contains("shopping list"))
        let milk = FoodCatalogue.byID["milk"]!
        XCTAssertEqual(h.kitchen.presence(of: milk), .out)
        XCTAssertTrue(h.kitchen.shopping.contains { $0.key == "milk" })

        _ = h.coach.respond(to: "We've got three portions of chilli left")
        XCTAssertEqual(h.kitchen.freezerMeals().first { $0.title == "Slow cooker turkey chilli" }?.portions, 3)

        _ = h.coach.respond(to: "We've got eggs")
        XCTAssertEqual(h.kitchen.presence(of: FoodCatalogue.byID["eggs"]!), .have)

        let shopping = h.coach.respond(to: "Add bin bags to the shopping list")
        XCTAssertEqual(shopping.toolSummary, "Shopping list: Bin bags")
        XCTAssertTrue(h.coach.commitments.allSatisfy { $0.kind != .meal }, "Food never becomes a commitment or a fine")
    }

    func testTickingAListItemUpdatesTheInventory() async {
        let h = await make(at: at(10))
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

    func testEatingAFreezableDinnerFreezesTheSpares() async {
        let h = await make(at: at(19))
        let tonight = h.kitchen.tonight!
        let ragu = h.kitchen.recipes.first { $0.title == "Beef ragu pasta" }!
        h.kitchen.swap(tonight, to: ragu)
        let note = h.kitchen.markCooked(tonight)
        XCTAssertEqual(note, "Two portions of Beef ragu pasta into the freezer.")
        XCTAssertEqual(h.kitchen.freezerMeals().first { $0.title == "Beef ragu pasta" }?.portions, 2)
        XCTAssertEqual(ragu.timesCooked, 1)
        XCTAssertNotNil(ragu.lastCookedAt)
    }

    func testDefrostReminderAndForgottenDefrost() async {
        let h = await make(at: at(9))
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
        let reply = h.coach.respond(to: "I forgot to defrost it")
        XCTAssertTrue(reply.text.contains("piping hot"))
        XCTAssertTrue(reply.text.contains("Easy options"))

        _ = h.coach.respond(to: "It's defrosted")
        XCTAssertFalse(h.kitchen.tonightNeedsDefrosting)
    }

    func testWhatsForDinner() async {
        let h = await make(at: at(17))
        let reply = h.coach.respond(to: "What's for dinner?")
        XCTAssertTrue(reply.text.contains(h.kitchen.tonight!.title))
        XCTAssertTrue(reply.text.contains("two portions"))
    }

    func testReceiptsRefuseDuplicatesAndCountTowardsTheCeiling() async {
        let h = await make(at: at(12))
        let lines = [ReceiptLine(name: "CHICKEN BREAST FILLETS", quantity: 1, pricePence: 449, foodID: "chicken-breast", uncertain: false)]
        XCTAssertEqual(h.kitchen.saveReceipt(merchant: .aldi, date: at(11), totalPence: 4_230, lines: lines, needsReview: false, manual: false), .saved)
        XCTAssertEqual(h.kitchen.saveReceipt(merchant: .aldi, date: at(15), totalPence: 4_230, lines: lines, needsReview: false, manual: false),
                       .duplicate, "Same shop, same day, same total")
        XCTAssertEqual(h.kitchen.saveReceipt(merchant: .takeaway, date: at(20), totalPence: 2_450, lines: [], needsReview: false, manual: true), .saved)
        XCTAssertEqual(h.kitchen.budget.spent, Pence(6_680))
        XCTAssertEqual(h.kitchen.budget.remaining, Pence(40_000 - 6_680))
        XCTAssertEqual(h.kitchen.presence(of: FoodCatalogue.byID["chicken-breast"]!), .probably, "A receipt is never 'definitely'")
    }

    func testDinnerRescueWithNothingPlanned() async {
        let h = await make(at: at(18))
        let options = h.kitchen.rescueOptions(defrostForgotten: false)
        XCTAssertFalse(options.isEmpty)
        XCTAssertLessThanOrEqual(options.count, 3)
        XCTAssertTrue(options.contains { $0.kind == .takeaway }, "Full budget allows a takeaway option")
    }

    func testHouseholdChainStagesDependOnEachOther() async {
        let h = await make(at: at(10))
        let parent = h.coach.addChain(HouseholdChains.template("laundry")!)
        let steps = h.coach.allTasks().filter { $0.parentID == parent.id }.sorted { $0.sortIndex < $1.sortIndex }
        XCTAssertEqual(steps.map(\.title), ["Put a wash on", "Hang it out or put it in the dryer", "Fold it and put it away"])
        XCTAssertTrue(steps[0].dependsOn.isEmpty)
        XCTAssertEqual(steps[1].dependsOn, [steps[0].id.uuidString])
        XCTAssertEqual(steps[2].dependsOn, [steps[1].id.uuidString])
        let offered = h.coach.opportunityTasks(minutes: 60).map(\.title)
        XCTAssertFalse(offered.contains("Hang it out or put it in the dryer"), "Later stages wait for the earlier ones")
        XCTAssertFalse(offered.contains("Fold it and put it away"))
        h.coach.setState(.done, for: steps[0])
        XCTAssertNotEqual(parent.state, .done, "The first stage doesn't finish the chain")
    }
}
