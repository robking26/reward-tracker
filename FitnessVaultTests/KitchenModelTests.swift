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
    private let wednesday = DayKey(year: 2026, month: 10, day: 21)

    private func at(_ hour: Int, day: DayKey? = nil) -> Date {
        (day ?? wednesday).date(atMinute: hour * 60, calendar: london)
    }

    private struct Harness {
        var kitchen: KitchenModel
        var reminders: RecordingReminderScheduler
        var clock: TestClock
        var defaults: UserDefaults
        var container: ModelContainer
    }

    private let yoghurt = FoodProduct(barcode: "4088600123456", name: "Protein Yogurt", brand: "Brooklea",
                                      per100: Macros(kcal: 62, protein: 10, carbs: 4, fat: 0.4),
                                      servingGrams: 200, servingText: "200 g")

    private func make(at date: Date) -> Harness {
        let clock = TestClock(date)
        let container = Persistence.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "kitchen.test.\(UUID().uuidString)")!
        let reminders = RecordingReminderScheduler()
        let kitchen = KitchenModel(container: container, products: FixedProductLookup(products: [yoghurt.barcode: yoghurt]),
                                   reminders: reminders, defaults: defaults, calendar: london, now: { clock.date })
        kitchen.start()
        return Harness(kitchen: kitchen, reminders: reminders, clock: clock, defaults: defaults, container: container)
    }

    func testTheCycleStartsThisWeekAndCanBeMoved() {
        let h = make(at: at(9))
        XCTAssertEqual(h.kitchen.currentWeek, 1, "First use starts week 1 this Monday")
        XCTAssertEqual(h.kitchen.meal(.lunch, on: wednesday).id, MealCycle.lunches[0].id)

        h.kitchen.setCurrentWeek(5)
        XCTAssertEqual(h.kitchen.currentWeek, 5)
        XCTAssertEqual(h.kitchen.nextWeek, 6)
        XCTAssertEqual(h.kitchen.meal(.breakfast, on: wednesday).week, 5)

        // Next Monday moves on; the setting survives a relaunch.
        h.clock.date = at(9, day: DayKey(year: 2026, month: 10, day: 26))
        let relaunched = KitchenModel(container: h.container, products: FixedProductLookup(), reminders: RecordingReminderScheduler(),
                                      defaults: h.defaults, calendar: london, now: { h.clock.date })
        XCTAssertEqual(relaunched.currentWeek, 6)
    }

    func testWeekOneCanStartOnAChosenMonday() {
        let sunday = at(9, day: DayKey(year: 2026, month: 10, day: 25))
        let clock = TestClock(sunday)
        let defaults = UserDefaults(suiteName: "kitchen.test.\(UUID().uuidString)")!
        defaults.set("2026-10-19", forKey: KitchenModel.anchorKey)
        let container = Persistence.makeContainer(inMemory: true)
        func open() -> KitchenModel {
            KitchenModel(container: container, products: FixedProductLookup(), reminders: RecordingReminderScheduler(),
                         defaults: defaults, calendar: london, now: { clock.date }, restartOn: KitchenModel.robsFirstMonday)
        }
        let kitchen = open()
        XCTAssertEqual(kitchen.week(of: DayKey(year: 2026, month: 10, day: 26)), 1, "Week 1 is tomorrow, whatever was saved")
        XCTAssertEqual(kitchen.week(of: DayKey(year: 2026, month: 11, day: 2)), 2)
        XCTAssertEqual(kitchen.week(of: kitchen.shoppingMonday(next: true)), 1, "Sunday's shop is for week 1")

        // Moving the week by hand afterwards sticks across launches.
        clock.date = at(9, day: DayKey(year: 2026, month: 10, day: 28))
        kitchen.setCurrentWeek(3)
        XCTAssertEqual(open().currentWeek, 3)
    }

    func testStartClearsTheOldDinnerReminders() {
        let h = make(at: at(9))
        XCTAssertEqual(h.reminders.plans.last, [], "Defrost and slow-cooker reminders are gone")
    }

    func testLunchOnlyOnWorkDays() {
        let h = make(at: at(9))
        XCTAssertTrue(h.kitchen.isCycleDay(wednesday))
        XCTAssertFalse(h.kitchen.isCycleDay(DayKey(year: 2026, month: 10, day: 24)), "Saturday: no breakfast or lunch planned")
        XCTAssertFalse(h.kitchen.isCycleDay(DayKey(year: 2026, month: 10, day: 25)), "Sunday")
        XCTAssertEqual(CycleSlot.breakfast.portionsPerWeek, 5, "Breakfasts Monday to Friday")
        h.kitchen.logPlanned("Lasagne", meal: .evening, macros: Macros(kcal: 650, protein: 55, carbs: 60, fat: 15),
                             amountText: "×1.2 portion", on: wednesday)
        h.kitchen.logPlanned("Lasagne", meal: .evening, macros: Macros(kcal: 650, protein: 55, carbs: 60, fat: 15),
                             amountText: "×1.2 portion", on: wednesday)
        XCTAssertTrue(h.kitchen.hasLoggedPlanned("Lasagne", on: wednesday))
        XCTAssertEqual(h.kitchen.entries(on: wednesday).filter { $0.name == "Lasagne" }.count, 1, "Once only")
    }

    func testLoggingTheCycleMealsAddsUpTheDay() {
        let h = make(at: at(8))
        h.kitchen.logCycle(.breakfast, on: wednesday)
        h.kitchen.logCycle(.breakfast, on: wednesday)
        XCTAssertEqual(h.kitchen.entries(on: wednesday).count, 1, "Logging twice doesn't double it")
        XCTAssertTrue(h.kitchen.hasLoggedCycle(.breakfast, on: wednesday))

        h.kitchen.logCycle(.lunch, on: wednesday)
        let day = h.kitchen.nutrition(on: wednesday)
        let expected = MealCycle.meal(.breakfast, week: 1).macros.kcal + MealCycle.meal(.lunch, week: 1).macros.kcal
        XCTAssertEqual(day.total.kcal, expected, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(day.total.protein, 100)
    }

    func testBarcodeLookupLogAndRemember() async {
        let h = make(at: at(19))
        let result = await h.kitchen.lookUp(barcode: "4088600123456")
        guard case .success(let product) = result else { return XCTFail("Should find the yoghurt") }
        h.kitchen.log(product, grams: 200, amountText: "200 g", meal: .evening)
        let entries = h.kitchen.entries(on: wednesday)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.kcal ?? 0, 124, accuracy: 0.01)
        XCTAssertEqual(entries.first?.meal, .evening)
        XCTAssertEqual(entries.first?.source, .barcode)
        XCTAssertEqual(h.kitchen.recentProducts.map(\.barcode), ["4088600123456"], "Remembered for next time")

        let unknown = await h.kitchen.lookUp(barcode: "5000000000000")
        XCTAssertEqual(unknown, .failure(.notFound))

        h.kitchen.delete(entries[0])
        XCTAssertTrue(h.kitchen.entries(on: wednesday).isEmpty)
    }

    func testManualEntryAndDays() {
        let h = make(at: at(20))
        h.kitchen.logManual(name: "  Chippy tea ", macros: Macros(kcal: 950, protein: 35, carbs: 110, fat: 40), meal: .evening)
        XCTAssertEqual(h.kitchen.entries(on: wednesday).first?.name, "Chippy tea")
        h.clock.date = at(8, day: wednesday.adding(days: 1, calendar: london))
        h.kitchen.refresh()
        XCTAssertTrue(h.kitchen.entries(on: h.kitchen.today).isEmpty, "A new day starts empty")
        XCTAssertEqual(h.kitchen.nutrition(on: wednesday).total.kcal, 950)
    }

    func testShoppingTicksAreKeptPerWeekAndList() {
        let h = make(at: at(10))
        let monday = h.kitchen.shoppingMonday(next: false)
        let lines = h.kitchen.shoppingList(.lunch, weekStarting: monday)
        let chicken = lines.first { $0.foodID == "chicken-breast" }!
        h.kitchen.toggle(chicken, slot: .lunch, monday: monday)
        XCTAssertTrue(h.kitchen.isTicked(chicken, slot: .lunch, monday: monday))
        XCTAssertFalse(h.kitchen.isTicked(chicken, slot: .breakfast, monday: monday), "Lists are separate")
        XCTAssertFalse(h.kitchen.isTicked(chicken, slot: .lunch, monday: h.kitchen.shoppingMonday(next: true)), "Weeks are separate")
        h.kitchen.clearTicks(slot: .lunch, monday: monday)
        XCTAssertFalse(h.kitchen.isTicked(chicken, slot: .lunch, monday: monday))
        XCTAssertEqual(h.kitchen.shoppingList(.lunch, weekStarting: h.kitchen.shoppingMonday(next: true)).first?.foodID != nil, true)
    }
}
