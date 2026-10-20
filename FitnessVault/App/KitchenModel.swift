import Foundation
import Observation
import SwiftData

/// Meals, recipes, the freezer, the shopping list and receipts (Phase 4). The planning, estimating and parsing are
/// pure domain code; this model persists them and reads the calendar through the coach. Food never affects fines.
@MainActor
@Observable
final class KitchenModel {
    let context: ModelContext
    let calendar: Calendar
    let now: () -> Date
    @ObservationIgnored private weak var coach: CoachModel?
    @ObservationIgnored private let reminders: ReminderScheduling
    @ObservationIgnored private var lastReminderSignature: String? = nil
    @ObservationIgnored private let countdowns: CountdownControlling
    /// The dinner being cooked right now, for the cooking timer (Phase 7).
    private(set) var cooking: UUID? = nil

    private(set) var recipes: [Recipe] = []
    private(set) var plan: [MealPlanEntry] = []
    private(set) var inventory: [InventoryItem] = []
    private(set) var shopping: [ShoppingItem] = []
    private(set) var receipts: [ReceiptRecord] = []

    static let reminderPrefix = "kitchen."

    init(container: ModelContainer, coach: CoachModel?, reminders: ReminderScheduling? = nil,
         countdowns: CountdownControlling? = nil,
         calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        context = container.mainContext
        self.coach = coach
        self.reminders = reminders ?? LocalReminderScheduler(prefix: KitchenModel.reminderPrefix)
        self.countdowns = countdowns ?? LocalCountdowns.shared
        self.calendar = calendar
        self.now = now
        coach?.kitchen = self
        reload()
    }

    func start() {
        seedIfNeeded()
        refresh()
    }

    func refresh() {
        ensurePlan()
        reload()
        scheduleReminders()
    }

    // MARK: Days

    var today: DayKey { DayKey(now(), calendar: calendar) }

    func isoWeekday(_ day: DayKey) -> Int {
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        return ((weekday + 5) % 7) + 1
    }

    func weekStart(of day: DayKey) -> DayKey {
        day.adding(days: -(isoWeekday(day) - 1), calendar: calendar)
    }

    /// Work location, evening plans and eating out for each day, from the calendar and agreed commitments.
    func dayContexts(from start: DayKey, days: Int = 7) -> [MealDayContext] {
        (0..<days).map { offset in
            let day = start.adding(days: offset, calendar: calendar)
            let events = coach?.classifiedEvents(on: day) ?? []
            let weekday = isoWeekday(day)
            let isWorkday = (coach?.coach.isWorkday(day, calendar: calendar) ?? (weekday <= 5)) && !CalendarClassifier.isOnLeave(events)
            let location = CalendarClassifier.workLocation(from: events)
            let evening = day.startDate(calendar: calendar).addingTimeInterval(17 * 3600)
            let lateEvent = events.contains { item in
                !item.event.isAllDay && item.role != .shared && item.role != .ignored && item.event.start >= evening
                    && item.event.start < evening.addingTimeInterval(3 * 3600)
            }
            let lateCommitment = (coach?.commitments(on: day) ?? []).contains { item in
                guard item.state.isOpen, let start = item.scheduledStart else { return false }
                return start >= evening && [.workout, .swim, .social].contains(item.kind)
            }
            let eatingOut = events.contains { item in
                !item.event.isAllDay && item.role != .ignored && item.event.start >= evening
                    && CalendarClassifier.matches(item.event.title, ["dinner out", "restaurant", "meal out", "takeaway", "curry night", "pub tea", "eating out"])
            }
            return MealDayContext(day: day, weekday: weekday, workFromHome: isWorkday && location == .home,
                                  office: isWorkday && location != .home, eatingOut: eatingOut,
                                  lateFinish: lateEvent || lateCommitment)
        }
    }

    // MARK: Recipes

    func seedIfNeeded() {
        guard ((try? context.fetchCount(FetchDescriptor<Recipe>())) ?? 0) == 0 else { return }
        for starter in StarterRecipes.all {
            let ingredients = starter.ingredients.map(IngredientParser.parse)
            let washUp = WashUpEstimator.estimate(starter.steps.joined(separator: " "))
            context.insert(Recipe(title: starter.title, role: starter.role, servings: starter.servings, ingredients: ingredients,
                                  steps: starter.steps, prepMinutes: starter.prepMinutes, cookMinutes: starter.cookMinutes,
                                  washUpMinutes: washUp.minutes, usesSlowCooker: starter.slowCooker, isFakeaway: starter.fakeaway,
                                  freezable: starter.freezable, source: .starter))
        }
        save()
        reload()
    }

    var activeRecipes: [Recipe] { recipes.filter { !$0.archived } }

    func recipe(_ id: UUID?) -> Recipe? {
        guard let id else { return nil }
        return recipes.first { $0.id == id }
    }

    @discardableResult
    func save(_ draft: RecipeDraft, role: MealRole, source: RecipeSource, freezable: Bool, fakeaway: Bool) -> Recipe {
        let recipe = Recipe(title: draft.title, role: role, servings: draft.servings, ingredients: draft.ingredients, steps: draft.steps,
                            prepMinutes: draft.prepMinutes ?? 15, cookMinutes: draft.cookMinutes ?? 25,
                            washUpMinutes: draft.washUpMinutes, usesSlowCooker: draft.usesSlowCooker, isFakeaway: fakeaway,
                            freezable: freezable, source: source)
        context.insert(recipe)
        save()
        reload()
        return recipe
    }

    func toggleFavourite(_ recipe: Recipe) {
        recipe.favourite.toggle()
        save()
        reload()
    }

    func archive(_ recipe: Recipe) {
        recipe.archived = true
        save()
        reload()
    }

    /// Applies a macro tweak. Callers ask first when `changesFlavour` is set (F7).
    func apply(_ tweak: MacroTweak, to recipe: Recipe) {
        recipe.ingredients = MacroTweaks.apply(tweak, to: recipe.ingredients)
        save()
        reload()
    }

    /// The user's own nutrition figures replace the estimate.
    func correctNutrition(_ recipe: Recipe, kcal: Double, protein: Double) {
        recipe.kcal = kcal
        recipe.protein = protein
        recipe.confidenceRaw = EstimateConfidence.confirmed.rawValue
        save()
        reload()
    }

    // MARK: Meal plan

    func entries(on day: DayKey) -> [MealPlanEntry] {
        plan.filter { $0.day == day.description }.sorted { $0.slot == .lunch && $1.slot == .dinner }
    }

    func dinner(on day: DayKey) -> MealPlanEntry? {
        plan.first { $0.day == day.description && $0.slot == .dinner }
    }

    var tonight: MealPlanEntry? { dinner(on: today) }

    /// Plans this week (and next, from Friday) if it hasn't been planned yet.
    func ensurePlan() {
        let start = weekStart(of: today)
        var weeks = [start]
        if isoWeekday(today) >= 5 { weeks.append(start.adding(days: 7, calendar: calendar)) }
        let existing = allEntries()
        for week in weeks {
            let end = week.adding(days: 7, calendar: calendar)
            let planned = existing.contains { entry in
                guard let day = entry.dayKey else { return false }
                return day >= week && day < end
            }
            if !planned { generate(week: week) }
        }
    }

    /// Replans the rest of a week. Cooked and past meals stay as they were.
    func replan(week: DayKey? = nil) {
        let start = week ?? weekStart(of: today)
        let end = start.adding(days: 7, calendar: calendar)
        for entry in allEntries() {
            guard let day = entry.dayKey, day >= start, day < end, day >= today, !entry.cooked else { continue }
            context.delete(entry)
        }
        generate(week: start)
        reload()
        scheduleReminders()
    }

    private func generate(week start: DayKey) {
        let contexts = dayContexts(from: start).filter { $0.day >= today }
        guard !contexts.isEmpty else { return }
        let taken = Set(allEntries().filter { entry in contexts.contains { $0.day.description == entry.day } }
            .map { "\($0.day)|\($0.slotRaw)" })
        let input = MealPlanInput(days: contexts, candidates: activeRecipes.map { $0.candidate(calendar: calendar) },
                                  freezer: freezerMeals(), rotationWeek: MealPlanner.rotationWeek(for: start, calendar: calendar))
        for meal in MealPlanner.plan(input) where !taken.contains("\(meal.day.description)|\(meal.slot.rawValue)") {
            context.insert(MealPlanEntry(meal))
        }
        save()
    }

    func swap(_ entry: MealPlanEntry, to recipe: Recipe) {
        entry.recipeID = recipe.id
        entry.title = recipe.title
        entry.fromFreezer = false
        entry.note = nil
        entry.portions = entry.slot == .dinner ? 2 : max(1, entry.portions)
        save()
        reload()
        scheduleReminders()
    }

    func useFreezer(_ entry: MealPlanEntry, meal: FreezerMeal) {
        entry.recipeID = meal.recipeID
        entry.title = meal.title
        entry.fromFreezer = true
        entry.defrosted = false
        entry.portions = entry.slot == .dinner ? 2 : max(1, entry.portions)
        entry.note = "From the freezer. Defrost in the fridge the night before."
        save()
        reload()
        scheduleReminders()
    }

    func markDefrosted(_ entry: MealPlanEntry) {
        entry.defrosted = true
        save()
        reload()
        scheduleReminders()
    }

    /// Marks a meal as eaten: updates the recipe's history and the freezer, and freezes leftover portions.
    /// Returns a short note about the freezer, if anything changed there.
    /// A cooking timer on the Lock Screen for the recipe's prep and cook time.
    func startCooking(_ entry: MealPlanEntry) {
        guard let recipe = recipe(entry.recipeID) else { return }
        let minutes = max(5, recipe.prepMinutes + recipe.cookMinutes)
        let ready = now().addingTimeInterval(TimeInterval(minutes * 60))
        cooking = entry.id
        countdowns.show(.cooking, id: entry.id.uuidString, title: recipe.title,
                        subtitle: "Ready about \(ready.formatted(date: .omitted, time: .shortened))", symbol: "flame", endsAt: ready)
    }

    @discardableResult
    func markCooked(_ entry: MealPlanEntry) -> String? {
        guard !entry.cooked else { return nil }
        countdowns.end(.cooking, id: entry.id.uuidString)
        if cooking == entry.id { cooking = nil }
        entry.cooked = true
        var note: String?
        if entry.fromFreezer {
            adjustFreezer(title: entry.title, by: -entry.portions)
        } else if let recipe = self.recipe(entry.recipeID) {
            recipe.lastCookedAt = now()
            recipe.timesCooked += 1
            let used = Set(recipe.ingredients.compactMap(\.foodID))
            for item in inventory where item.foodID.map({ used.contains($0) }) ?? false { item.usedSinceAdded = true }
            if entry.slot == .dinner, recipe.freezable, recipe.servings > entry.portions {
                let extra = recipe.servings - entry.portions
                adjustFreezer(title: recipe.title, by: extra)
                let portions = DefrostPlanner.portionsText(extra)
                note = portions.prefix(1).uppercased() + portions.dropFirst() + " of \(recipe.title) into the freezer."
            }
        }
        save()
        reload()
        return note
    }

    private func allEntries() -> [MealPlanEntry] {
        (try? context.fetch(FetchDescriptor<MealPlanEntry>())) ?? []
    }

    // MARK: Batch cooking (F5)

    var batchPlan: BatchCookPlan {
        let start = weekStart(of: today)
        let weekDays = Set((0..<7).map { start.adding(days: $0, calendar: calendar).description })
        let lunch = plan.first { $0.slot == .lunch && weekDays.contains($0.day) }.flatMap { recipe($0.recipeID) }
        let plannedIDs = Set(plan.filter { weekDays.contains($0.day) }.compactMap(\.recipeID))
        let freezerStock = Set(freezerMeals().filter { $0.portions >= 2 }.map(\.title))
        let extras = activeRecipes
            .filter { $0.role.suitsDinner && $0.freezable && !plannedIDs.contains($0.id) && !freezerStock.contains($0.title) }
            .sorted { ($0.favourite ? 0 : 1, $0.title) < ($1.favourite ? 0 : 1, $1.title) }
            .prefix(freezerStock.count >= 3 ? 0 : 1)
            .map { $0.candidate(calendar: calendar) }
        return BatchCookPlanner.plan(lunch: lunch?.candidate(calendar: calendar), freezerDinners: Array(extras))
    }

    /// After the batch cook: lunches in the fridge, extras in the freezer.
    func recordBatchCook(_ batch: BatchCookPlan) {
        for item in batch.items {
            if item.forFreezer {
                adjustFreezer(title: item.title, by: item.portions)
            } else {
                let key = "meal:" + item.title.lowercased()
                let entry = inventoryItem(key: key, name: item.title, foodID: nil, location: .fridge, source: .batchCook)
                entry.portions = item.portions
                entry.addedAt = now()
                entry.confirmedAt = now()
                entry.outAt = nil
                entry.updatedAt = now()
            }
        }
        save()
        reload()
    }

    // MARK: Freezer and inventory (I4)

    func freezerMeals() -> [FreezerMeal] {
        inventoryItems().filter { $0.key.hasPrefix("meal:") && $0.location == .freezer && ($0.portions ?? 0) > 0 }
            .map { item in FreezerMeal(title: item.name, portions: item.portions ?? 0, recipeID: recipes.first { $0.title == item.name }?.id) }
            .sorted { $0.title < $1.title }
    }

    func adjustFreezer(title: String, by delta: Int) {
        let item = inventoryItem(key: "meal:" + title.lowercased(), name: title, foodID: nil, location: .freezer, source: .batchCook)
        item.portions = max(0, (item.portions ?? 0) + delta)
        if delta > 0 { item.addedAt = now() }
        item.confirmedAt = delta > 0 ? now() : item.confirmedAt
        item.outAt = item.portions == 0 ? now() : nil
        item.updatedAt = now()
        save()
    }

    func presence(of food: FoodItem) -> Presence? {
        inventory.first { $0.key == food.id }?.presence(now: now())
    }

    /// "We've run out of milk." Returns the name used.
    @discardableResult
    func markOut(_ name: String) -> String {
        let (key, display, food, location) = identify(name)
        let item = inventoryItem(key: key, name: display, foodID: food?.id, location: location, source: .userStated)
        item.outAt = now()
        if item.portions != nil { item.portions = 0 }
        item.updatedAt = now()
        save()
        reload()
        return display
    }

    /// "We've got three portions of curry left." Portions of a meal go in the freezer; anything else is confirmed present.
    @discardableResult
    func confirm(_ name: String, portions: Int?) -> String {
        let cleaned = name.replacingOccurrences(of: " in the freezer", with: "").trimmingCharacters(in: .whitespaces)
        // Prefer a freezable dinner: "curry" means the batch-cooked curry, not a curry-flavoured lunch.
        let named = recipes.filter { $0.title.localizedCaseInsensitiveContains(cleaned) || cleaned.localizedCaseInsensitiveContains($0.title) }
        let meal = named.first { $0.freezable && $0.role.suitsDinner } ?? named.first
        if let portions, FoodCatalogue.match(cleaned) == nil || meal != nil {
            let title = meal?.title ?? cleaned.capitalized
            let item = inventoryItem(key: "meal:" + title.lowercased(), name: title, foodID: nil, location: .freezer, source: .userStated)
            item.portions = max(0, portions)
            item.confirmedAt = now()
            item.outAt = portions == 0 ? now() : nil
            item.updatedAt = now()
            save()
            reload()
            return title
        }
        let (key, display, food, location) = identify(cleaned)
        let item = inventoryItem(key: key, name: display, foodID: food?.id, location: location, source: .userStated)
        item.confirmedAt = now()
        item.outAt = nil
        item.usedSinceAdded = false
        if let portions { item.portions = portions }
        item.updatedAt = now()
        save()
        reload()
        return display
    }

    func purchased(_ name: String, at date: Date, source: InventorySource) {
        let (key, display, food, location) = identify(name)
        let item = inventoryItem(key: key, name: display, foodID: food?.id, location: location, source: source)
        item.addedAt = date
        item.sourceRaw = source.rawValue
        item.usedSinceAdded = false
        if let out = item.outAt, out <= date { item.outAt = nil }
        item.updatedAt = now()
    }

    func remove(_ item: InventoryItem) {
        context.delete(item)
        save()
        reload()
    }

    private func identify(_ name: String) -> (String, String, FoodItem?, StorageLocation) {
        if let food = FoodCatalogue.match(name) { return (food.id, food.name, food, food.location) }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return ("name:" + trimmed.lowercased(), trimmed.prefix(1).uppercased() + trimmed.dropFirst(), nil, .cupboard)
    }

    private func inventoryItem(key: String, name: String, foodID: String?, location: StorageLocation, source: InventorySource) -> InventoryItem {
        if let existing = inventoryItems().first(where: { $0.key == key }) { return existing }
        let item = InventoryItem(key: key, name: name, foodID: foodID, location: location, source: source)
        context.insert(item)
        return item
    }

    private func inventoryItems() -> [InventoryItem] {
        (try? context.fetch(FetchDescriptor<InventoryItem>())) ?? []
    }

    // MARK: Shopping (I2)

    /// Builds the list for the next seven days of planned meals, keeping anything the user added or ticked.
    func generateShoppingList() {
        let start = today
        let end = start.adding(days: 7, calendar: calendar)
        var portionsByRecipe: [UUID: Int] = [:]
        for entry in plan where !entry.cooked && !entry.fromFreezer {
            guard let day = entry.dayKey, day >= start, day < end, let id = entry.recipeID else { continue }
            portionsByRecipe[id, default: 0] += entry.portions
        }
        var needs: [ShoppingNeed] = []
        for (id, portions) in portionsByRecipe {
            guard let recipe = self.recipe(id) else { continue }
            let factor = Double(portions) / Double(max(1, recipe.servings))
            needs += recipe.ingredients.map { ShoppingNeed($0.scaled(factor), forMeal: recipe.title) }
        }
        let existing = shoppingItems()
        let manual = existing.filter { $0.manual && !$0.ticked }.map(\.name)
        let ranOut = inventory.filter { $0.presence(now: now()) == .out && !$0.key.hasPrefix("meal:") }.map(\.name)
        let lines = ShoppingListBuilder.build(needs: needs, presence: { self.presence(of: $0) },
                                              extras: manual + ranOut)
        let manualKeys = Set(existing.filter(\.manual).map(\.key))
        for item in existing where !item.manual && !item.ticked { context.delete(item) }
        for line in lines {
            if let item = existing.first(where: { $0.key == line.id && ($0.ticked || $0.manual) }) {
                item.quantityText = line.quantityText
                item.estimatePence = line.estimatePence
                item.reasons = line.reasons
                continue
            }
            context.insert(ShoppingItem(line, manual: manualKeys.contains(line.id)))
        }
        save()
        reload()
    }

    @discardableResult
    func addToShopping(_ name: String) -> String {
        let lines = ShoppingListBuilder.build(needs: [], presence: { _ in nil }, extras: [name])
        guard let line = lines.first else { return name }
        if let existing = shoppingItems().first(where: { $0.key == line.id }) {
            existing.ticked = false
            existing.manual = true
        } else {
            context.insert(ShoppingItem(line, manual: true))
        }
        save()
        reload()
        return line.name
    }

    /// Ticking a line means it's in the trolley, so the inventory hears about it.
    func toggle(_ item: ShoppingItem) {
        item.ticked.toggle()
        if item.ticked { purchased(item.name, at: now(), source: .manual) }
        save()
        reload()
    }

    func clearTicked() {
        for item in shoppingItems() where item.ticked { context.delete(item) }
        save()
        reload()
    }

    var listEstimate: Pence { shopping.filter { !$0.ticked }.sum { Pence($0.estimatePence ?? 0) } }

    private func shoppingItems() -> [ShoppingItem] {
        (try? context.fetch(FetchDescriptor<ShoppingItem>())) ?? []
    }

    // MARK: Receipts and budget (I1, I3)

    enum ReceiptResult: Equatable {
        case saved
        case duplicate
    }

    @discardableResult
    func saveReceipt(merchant: Merchant, date: Date, totalPence: Int, lines: [ReceiptLine], needsReview: Bool, manual: Bool) -> ReceiptResult {
        let record = ReceiptRecord(merchant: merchant, date: date, totalPence: totalPence, lines: lines, needsReview: needsReview,
                                   manual: manual, calendar: calendar)
        let all = (try? context.fetch(FetchDescriptor<ReceiptRecord>())) ?? []
        guard !all.contains(where: { $0.fingerprint == record.fingerprint }) else { return .duplicate }
        context.insert(record)
        if merchant != .takeaway {
            for line in lines where line.foodID != nil && line.pricePence > 0 {
                purchased(line.name, at: date, source: .receipt)
            }
        }
        save()
        reload()
        return .saved
    }

    func markReviewed(_ receipt: ReceiptRecord, lines: [ReceiptLine], totalPence: Int) {
        receipt.lines = lines
        receipt.totalPence = totalPence
        receipt.needsReview = false
        save()
        reload()
    }

    func delete(_ receipt: ReceiptRecord) {
        context.delete(receipt)
        save()
        reload()
    }

    func spent(in month: MonthKey) -> Pence {
        receipts.filter { $0.month == month.description }.sum(\.total)
    }

    var budget: HouseholdBudget {
        let date = now()
        let month = MonthKey(date, calendar: calendar)
        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        return HouseholdBudget(spent: spent(in: month), dayOfMonth: calendar.component(.day, from: date), daysInMonth: days)
    }

    // MARK: Dinner rescue (scenario G)

    func rescueOptions(defrostForgotten: Bool) -> [RescueOption] {
        let quick = activeRecipes.filter { $0.role.suitsDinner && $0.prepMinutes + $0.cookMinutes <= 30 && $0.excludedIngredient == nil }
            .map { recipe -> DinnerRescue.QuickOption in
                let missing = recipe.ingredients.compactMap { ingredient -> FoodItem? in
                    guard let food = ingredient.food, !food.isStaple else { return nil }
                    return (presence(of: food) ?? .probablyNot) >= .probably ? nil : food
                }
                return DinnerRescue.QuickOption(meal: recipe.candidate(calendar: calendar), missing: missing.map { $0.name.lowercased() },
                                                missingCost: missing.sum { Pence($0.pack.pricePence) })
            }
        return DinnerRescue.options(quick: quick, freezer: freezerMeals(), foodBudgetLeft: budget.remaining, defrostForgotten: defrostForgotten)
    }

    /// True when tonight's dinner comes from the freezer and nobody said it was moved to the fridge.
    var tonightNeedsDefrosting: Bool {
        guard let tonight else { return false }
        return tonight.fromFreezer && !tonight.defrosted && !tonight.cooked
    }

    // MARK: Reminders (I5)

    func reminderPlan() -> [PlannedNotification] {
        let soon = plan.filter { entry in
            guard let day = entry.dayKey else { return false }
            return day >= today && day <= today.adding(days: 2, calendar: calendar) && !entry.cooked
        }
        let defrost = DefrostPlanner.reminders(for: soon.filter { !$0.defrosted }.compactMap(\.planned), now: now(), calendar: calendar)
        let slowCooker = soon.compactMap { entry -> PlannedNotification? in
            guard entry.slot == .dinner, let recipe = self.recipe(entry.recipeID), recipe.usesSlowCooker, let day = entry.dayKey else { return nil }
            let wake = coach?.coach.wakeMinute ?? 355
            let date = day.startDate(calendar: calendar).addingTimeInterval(TimeInterval((wake + 75) * 60))
            guard date > now() else { return nil }
            return PlannedNotification(id: Self.reminderPrefix + "slow." + day.description, date: date,
                                       body: "Ten minutes of slow-cooker prep now and \(recipe.title) is sorted for tonight.", isDiscreet: false)
        }
        return defrost + slowCooker
    }

    func scheduleReminders() {
        let enabled = coach?.settings.notificationsEnabled ?? true
        let plan = enabled ? reminderPlan() : []
        let signature = plan.map { "\($0.id)@\(Int($0.date.timeIntervalSince1970))" }.joined(separator: "|")
        guard signature != lastReminderSignature else { return }
        lastReminderSignature = signature
        reminders.replace(with: plan)
    }

    // MARK: Storage

    func reload() {
        recipes = ((try? context.fetch(FetchDescriptor<Recipe>())) ?? []).sorted { $0.title < $1.title }
        plan = allEntries().sorted { ($0.day, $0.slotRaw == "lunch" ? 0 : 1) < ($1.day, $1.slotRaw == "lunch" ? 0 : 1) }
        inventory = inventoryItems().sorted { $0.name < $1.name }
        shopping = shoppingItems()
        receipts = ((try? context.fetch(FetchDescriptor<ReceiptRecord>())) ?? []).sorted { $0.date > $1.date }
    }

    func save() {
        try? context.save()
    }
}
