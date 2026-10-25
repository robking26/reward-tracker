import Foundation
import Observation
import SwiftData

/// The Kitchen: where you are in the 8-week lunch and breakfast cycle, its Aldi lists, and the food log.
/// Nothing here affects earnings.
@MainActor
@Observable
final class KitchenModel {
    @ObservationIgnored private let container: ModelContainer
    let context: ModelContext
    let calendar: Calendar
    let now: () -> Date
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let products: ProductLookup
    @ObservationIgnored private let reminders: ReminderScheduling

    /// The Monday that began cycle week 1.
    private(set) var anchor: DayKey
    /// Ticked shopping lines, keyed by "<week start>|<slot>|<food>".
    private(set) var ticked: Set<String>
    private(set) var entries: [FoodLogEntry] = []
    private(set) var saved: [SavedProduct] = []

    static let anchorKey = "kitchen.cycleAnchor"
    static let tickedKey = "kitchen.cycleTicked"
    static let restartedKey = "kitchen.cycleRestartedOn"

    /// The Monday Rob's cycle week 1 starts.
    static let robsFirstMonday = DayKey(year: 2026, month: 10, day: 26)

    init(container: ModelContainer, products: ProductLookup? = nil, reminders: ReminderScheduling? = nil,
         defaults: UserDefaults = .standard, calendar: Calendar = .current, now: @escaping () -> Date = { .now },
         restartOn firstMonday: DayKey? = nil) {
        self.container = container
        context = container.mainContext
        self.products = products ?? OpenFoodFactsClient()
        self.reminders = reminders ?? LocalReminderScheduler(prefix: "kitchen.")
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        let today = DayKey(now(), calendar: calendar)
        if let stored = defaults.string(forKey: Self.anchorKey).flatMap(DayKey.init(string:)) {
            anchor = stored
        } else {
            anchor = MealCycle.mondayOf(today, calendar: calendar)
        }
        // Once: week 1 starts on a given Monday, whatever was set before. Changing the week later still works.
        if let firstMonday, defaults.string(forKey: Self.restartedKey) != firstMonday.description {
            anchor = firstMonday
            defaults.set(firstMonday.description, forKey: Self.anchorKey)
            defaults.set(firstMonday.description, forKey: Self.restartedKey)
        }
        ticked = Set(defaults.stringArray(forKey: Self.tickedKey) ?? [])
        reload()
    }

    func start() {
        if defaults.string(forKey: Self.anchorKey) == nil { defaults.set(anchor.description, forKey: Self.anchorKey) }
        // The old dinner planner scheduled defrost and slow-cooker reminders; none apply any more.
        reminders.replace(with: [])
        reload()
    }

    func refresh() { reload() }

    // MARK: Cycle

    var today: DayKey { DayKey(now(), calendar: calendar) }

    func week(of day: DayKey) -> Int { MealCycle.week(of: day, anchor: anchor, calendar: calendar) }
    var currentWeek: Int { week(of: today) }
    var nextWeek: Int { currentWeek % MealCycle.weeks + 1 }

    func meal(_ slot: CycleSlot, on day: DayKey) -> CycleMeal { MealCycle.meal(slot, week: week(of: day)) }

    /// Moves the cycle so this week is `week`.
    func setCurrentWeek(_ week: Int) {
        anchor = MealCycle.anchor(today: today, week: week, calendar: calendar)
        defaults.set(anchor.description, forKey: Self.anchorKey)
    }

    /// Breakfast and lunch are on the cycle Monday to Friday; weekends aren't planned.
    func isCycleDay(_ day: DayKey) -> Bool {
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        return weekday != 1 && weekday != 7
    }

    // MARK: Shopping

    /// The Monday a shop is for: this week, or next week from Saturday so the weekend shop shows what's coming.
    func shoppingMonday(next: Bool) -> DayKey {
        MealCycle.mondayOf(today, calendar: calendar).adding(days: next ? 7 : 0, calendar: calendar)
    }

    func shoppingList(_ slot: CycleSlot, weekStarting monday: DayKey) -> [CycleShoppingLine] {
        CycleShopping.list(for: MealCycle.meal(slot, week: week(of: monday)))
    }

    private func tickKey(_ line: CycleShoppingLine, slot: CycleSlot, monday: DayKey) -> String {
        "\(monday.description)|\(slot.rawValue)|\(line.foodID)"
    }

    func isTicked(_ line: CycleShoppingLine, slot: CycleSlot, monday: DayKey) -> Bool {
        ticked.contains(tickKey(line, slot: slot, monday: monday))
    }

    func toggle(_ line: CycleShoppingLine, slot: CycleSlot, monday: DayKey) {
        let key = tickKey(line, slot: slot, monday: monday)
        if ticked.contains(key) { ticked.remove(key) } else { ticked.insert(key) }
        // Ticks older than a fortnight are dropped so the set never grows.
        let cutoff = today.adding(days: -14, calendar: calendar).description
        ticked = ticked.filter { $0.prefix(10) >= Substring(cutoff) }
        defaults.set(Array(ticked).sorted(), forKey: Self.tickedKey)
    }

    /// Both lists for the week as text to send. Once you've started ticking, only what's still to get.
    func shareText(weekStarting monday: DayKey) -> String {
        let slots: [CycleSlot] = [.lunch, .breakfast]
        let all = slots.flatMap { slot in shoppingList(slot, weekStarting: monday).map { (slot, $0) } }
        let left = all.filter { !isTicked($0.1, slot: $0.0, monday: monday) }
        let lines = (left.isEmpty ? all : left).map(\.1)
        let date = monday.startDate(calendar: calendar).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let meals = slots.map { slot -> String in
            let meal = MealCycle.meal(slot, week: week(of: monday))
            return "\(slot == .lunch ? "Lunches" : "Breakfasts"): \(meal.title) × \(slot.portionsPerWeek)"
        }
        let heading = left.count < all.count && !left.isEmpty ? "Aldi list, still to get · week of \(date)" : "Aldi list · week of \(date)"
        return CycleShopping.shareText(heading: heading, meals: meals, lines: lines)
    }

    func clearTicks(slot: CycleSlot, monday: DayKey) {
        let prefix = "\(monday.description)|\(slot.rawValue)|"
        ticked = ticked.filter { !$0.hasPrefix(prefix) }
        defaults.set(Array(ticked).sorted(), forKey: Self.tickedKey)
    }

    // MARK: Food log

    func entries(on day: DayKey) -> [FoodLogEntry] {
        entries.filter { $0.day == day.description }.sorted { $0.date < $1.date }
    }

    func nutrition(on day: DayKey) -> DayNutrition {
        DayNutrition.summarise(entries(on: day).map { (meal: $0.meal, macros: $0.macros) })
    }

    /// True once today's breakfast or lunch from the cycle has been logged.
    func hasLoggedCycle(_ slot: CycleSlot, on day: DayKey) -> Bool {
        hasLoggedPlanned(meal(slot, on: day).title, on: day)
    }

    func logCycle(_ slot: CycleSlot, on day: DayKey) {
        let meal = self.meal(slot, on: day)
        logPlanned(meal.title, meal: slot == .breakfast ? .breakfast : .lunch, macros: meal.macros,
                   amountText: "1 portion", on: day)
    }

    /// A planned meal (the cycle's breakfast or lunch, or tonight's tea), logged with one tap.
    func hasLoggedPlanned(_ name: String, on day: DayKey) -> Bool {
        entries(on: day).contains { $0.source == .cycle && $0.name == name }
    }

    func logPlanned(_ name: String, meal: FoodMeal, macros: Macros, amountText: String, on day: DayKey) {
        guard !hasLoggedPlanned(name, on: day) else { return }
        insert(FoodLogEntry(date: now(), day: day, meal: meal, name: name, source: .cycle, amountText: amountText,
                            macros: macros))
    }

    func log(_ product: FoodProduct, grams: Double, amountText: String, meal: FoodMeal) {
        insert(FoodLogEntry(date: now(), day: today, meal: meal, name: product.name, brand: product.brand,
                            barcode: product.barcode, source: .barcode, amountText: amountText,
                            macros: product.macros(grams: grams)))
        remember(product)
    }

    func logManual(name: String, macros: Macros, meal: FoodMeal) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        insert(FoodLogEntry(date: now(), day: today, meal: meal, name: trimmed.isEmpty ? "Something" : trimmed,
                            source: .manual, amountText: "", macros: macros))
    }

    func delete(_ entry: FoodLogEntry) {
        context.delete(entry)
        save()
        reload()
    }

    private func insert(_ entry: FoodLogEntry) {
        context.insert(entry)
        save()
        reload()
    }

    // MARK: Barcodes

    /// A saved product first (instant, works offline), then Open Food Facts.
    func lookUp(barcode: String) async -> Result<FoodProduct, OpenFoodFacts.LookupError> {
        let digits = barcode.filter(\.isNumber)
        if let known = saved.first(where: { $0.barcode == digits }) { return .success(known.product) }
        return await products.product(barcode: digits)
    }

    private func remember(_ product: FoodProduct) {
        if let existing = saved.first(where: { $0.barcode == product.barcode }) {
            existing.update(from: product)
            existing.lastUsed = now()
        } else {
            let item = SavedProduct(product)
            item.lastUsed = now()
            context.insert(item)
        }
        save()
        reload()
    }

    var recentProducts: [SavedProduct] { Array(saved.prefix(8)) }

    // MARK: Storage

    func reload() {
        // The last 30 days are plenty for the screens; older entries stay in the store.
        let since = today.adding(days: -30, calendar: calendar).description
        let all = (try? context.fetch(FetchDescriptor<FoodLogEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        entries = all.filter { $0.day >= since }
        saved = (try? context.fetch(FetchDescriptor<SavedProduct>(sortBy: [SortDescriptor(\.lastUsed, order: .reverse)]))) ?? []
    }

    func save() {
        try? context.save()
    }
}
