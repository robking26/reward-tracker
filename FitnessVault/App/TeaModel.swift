import Foundation
import Observation

/// Evening meals: your recipe bank, this week's nights, both of your swipes and the plan they make.
@MainActor
@Observable
final class TeaModel {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let reminders: ReminderScheduling
    let calendar: Calendar
    let now: () -> Date

    private(set) var recipes: [TeaRecipe]
    private(set) var week: TeaWeek?

    static let recipesKey = "teas.recipes"
    static let weekKey = "teas.week"

    init(reminders: ReminderScheduling? = nil, defaults: UserDefaults = .standard, calendar: Calendar = .current,
         now: @escaping () -> Date = { .now }, bundled: [TeaRecipe]? = nil) {
        self.reminders = reminders ?? LocalReminderScheduler(prefix: "teas.")
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        // Recipes Claude added to the app, then the ones you've imported (yours win on the same ID).
        var merged: [String: TeaRecipe] = [:]
        for recipe in bundled ?? Self.bundledRecipes() { merged[recipe.id] = recipe }
        let saved = defaults.data(forKey: Self.recipesKey).flatMap { try? JSONDecoder().decode([TeaRecipe].self, from: $0) } ?? []
        for recipe in saved { merged[recipe.id] = recipe }
        recipes = merged.values.sorted { $0.title < $1.title }
        week = defaults.data(forKey: Self.weekKey).flatMap { try? JSONDecoder().decode(TeaWeek.self, from: $0) }
    }

    private static func bundledRecipes() -> [TeaRecipe] {
        guard let url = Bundle.main.url(forResource: "TeaRecipes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? TeaPlanner.decode(data)) ?? []
    }

    var today: DayKey { DayKey(now(), calendar: calendar) }
    var onTarget: [TeaRecipe] { recipes.filter(\.meetsTargets) }
    func recipe(_ id: String?) -> TeaRecipe? { id.flatMap { id in recipes.first { $0.id == id } } }

    // MARK: Recipe bank

    /// Adds recipes from Claude's JSON. Returns how many came in.
    @discardableResult
    func importRecipes(_ data: Data) throws -> Int {
        let incoming = try TeaPlanner.decode(data)
        guard !incoming.isEmpty else { return 0 }
        var imported = savedImports()
        for recipe in incoming {
            imported.removeAll { $0.id == recipe.id }
            imported.append(recipe)
        }
        saveImports(imported)
        var merged = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        for recipe in incoming { merged[recipe.id] = recipe }
        recipes = merged.values.sorted { $0.title < $1.title }
        return incoming.count
    }

    /// Changes whether a recipe freezes (the books don't say, so it starts as a guess from the dish).
    func setFreezable(_ freezable: Bool, for recipe: TeaRecipe) {
        var changed = recipe
        changed.freezable = freezable
        update(changed)
    }

    /// Corrects a recipe's times (the books don't give them, so they start as an estimate from the method).
    func setMinutes(prep: Int, cook: Int, for recipe: TeaRecipe) {
        var changed = recipe
        changed.prepMinutes = max(0, prep)
        changed.cookMinutes = max(0, cook)
        update(changed)
    }

    private func update(_ changed: TeaRecipe) {
        var imported = savedImports()
        imported.removeAll { $0.id == changed.id }
        imported.append(changed)
        saveImports(imported)
        if let index = recipes.firstIndex(where: { $0.id == changed.id }) { recipes[index] = changed }
    }

    func delete(_ recipe: TeaRecipe) {
        saveImports(savedImports().filter { $0.id != recipe.id })
        recipes.removeAll { $0.id == recipe.id }
    }

    private func savedImports() -> [TeaRecipe] {
        defaults.data(forKey: Self.recipesKey).flatMap { try? JSONDecoder().decode([TeaRecipe].self, from: $0) } ?? []
    }

    private func saveImports(_ list: [TeaRecipe]) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: Self.recipesKey) }
    }

    // MARK: The week

    var nights: [DayKey] {
        let start = week.flatMap { DayKey(string: $0.start) } ?? today
        return TeaPlanner.nights(from: start, calendar: calendar)
    }

    /// The current plan, or nil once its seven nights are over.
    var currentWeek: TeaWeek? {
        guard let week, let start = DayKey(string: week.start) else { return nil }
        return start.adding(days: TeaPlanner.nightsInAWeek, calendar: calendar) > today ? week : nil
    }

    /// Starts a new week from tonight: every night together until you say otherwise, and a freshly shuffled deck.
    func startWeek() {
        var fresh = TeaWeek(start: today.description)
        fresh.order = onTarget.map(\.id).shuffled()
        for night in TeaPlanner.nights(from: today, calendar: calendar) { fresh.diners[night.description] = .together }
        save(fresh)
    }

    func diner(on night: DayKey) -> TeaDiner { week?.diners[night.description] ?? .notCooking }

    func setDiner(_ diner: TeaDiner, on night: DayKey) {
        guard var current = week else { return }
        current.diners[night.description] = diner
        save(current)
    }

    /// Whether this person has nights to choose for.
    func needs(_ swiper: TeaSwiper) -> Bool {
        nights.contains { night in
            let diner = diner(on: night)
            return swiper == .rob ? diner.includesRob : diner.includesBecky
        }
    }

    /// How many meals this person picks: one for each night they're eating.
    func target(for swiper: TeaSwiper) -> Int {
        nights.filter { night in
            let diner = diner(on: night)
            return swiper == .rob ? diner.includesRob : diner.includesBecky
        }.count
    }

    func picked(_ swiper: TeaSwiper) -> Int { week?.likes(swiper).count ?? 0 }

    /// What's left for this person to swipe, in the week's shuffled order, until they've picked enough. Becky sees
    /// Rob's picks first, so together nights can be ones you both chose.
    func deck(for swiper: TeaSwiper) -> [TeaRecipe] {
        guard let week, picked(swiper) < target(for: swiper) else { return [] }
        let seen = Set(week.seen(swiper))
        let byID = Dictionary(onTarget.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ids = week.order ?? TeaPlanner.deck(recipes, week: week.start).map(\.id)
        // Recipes added since the week started go at the end.
        let known = Set(ids)
        ids += onTarget.map(\.id).filter { !known.contains($0) }
        if swiper == .becky {
            let robs = week.robLikes
            ids = robs + ids.filter { !robs.contains($0) }
        }
        return ids.filter { !seen.contains($0) }.compactMap { byID[$0] }
    }

    func swipe(_ recipe: TeaRecipe, liked: Bool, by swiper: TeaSwiper) {
        guard var current = week else { return }
        switch swiper {
        case .rob:
            current.robSeen.append(recipe.id)
            if liked { current.robLikes.append(recipe.id) }
        case .becky:
            current.beckySeen.append(recipe.id)
            if liked { current.beckyLikes.append(recipe.id) }
        }
        save(current)
    }

    /// Recipes you both picked, in Rob's order.
    var matches: [TeaRecipe] {
        guard let week else { return [] }
        let becky = Set(week.beckyLikes)
        return week.robLikes.filter { becky.contains($0) }.compactMap { recipe($0) }
    }

    /// Fills the nights from the swipes.
    func makePlan() {
        guard var current = week else { return }
        let plan = TeaPlanner.plan(nights: nights, diners: current.diners, recipes: recipes,
                                   robLikes: current.robLikes, beckyLikes: current.beckyLikes, calendar: calendar)
        current.meals = plan.meals
        current.leftovers = plan.leftovers
        save(current)
    }

    /// The night this one's meal was cooked, when it's the second portion.
    func cookedOn(_ night: DayKey) -> DayKey? {
        week?.leftovers?[night.description].flatMap(DayKey.init(string:))
    }

    /// The night the second portion of this one's meal is eaten.
    func keptFor(_ night: DayKey) -> DayKey? {
        week?.leftovers?.first { $0.value == night.description }.flatMap { DayKey(string: $0.key) }
    }

    func setMeal(_ recipe: TeaRecipe?, on night: DayKey) {
        guard var current = week else { return }
        // Changing either night of a shared meal makes them separate meals.
        current.leftovers = current.leftovers?.filter { $0.key != night.description && $0.value != night.description }
        current.meals[night.description] = recipe?.id
        save(current)
    }

    /// Choices for a night: quick or slow cooker ones Monday to Thursday, the night's diners' likes first.
    func options(for night: DayKey) -> [TeaRecipe] {
        let quick = TeaPlanner.needsQuick(night, calendar: calendar)
        let liked = Set((week?.robLikes ?? []) + (week?.beckyLikes ?? []))
        return onTarget.filter { !quick || $0.suitsAWeeknight }
            .sorted { liked.contains($0.id) == liked.contains($1.id) ? $0.title < $1.title : liked.contains($0.id) }
    }

    /// Your tea on a night, if one's planned and you're eating.
    func plannedTea(on day: DayKey) -> TeaRecipe? {
        guard let week = currentWeek, diner(on: day).includesRob else { return nil }
        return recipe(week.meals[day.description])
    }

    /// Tonight's slow cooker tea, as a morning routine item: it goes on in the morning.
    func slowCookerPrep(on day: DayKey) -> RoutineItem? {
        guard let week = currentWeek, diner(on: day) != .notCooking, cookedOn(day) == nil,
              let recipe = recipe(week.meals[day.description]), recipe.isSlowCooker else { return nil }
        return RoutineItem(id: RoutineRules.slowCookerID, title: "Slow cooker on: \(recipe.title)",
                           symbol: "frying.pan.fill", minutes: max(5, recipe.prepMinutes))
    }

    func resetSwipes() {
        guard var current = week else { return }
        current.robLikes = []
        current.beckyLikes = []
        current.robSeen = []
        current.beckySeen = []
        current.meals = [:]
        current.leftovers = nil
        current.order = onTarget.map(\.id).shuffled()
        save(current)
    }

    private func save(_ next: TeaWeek) {
        week = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.weekKey) }
    }

    // MARK: Reminders

    /// Saturday mornings at 9: time to pick the week's teas. The next four Saturdays.
    func scheduleReminders() {
        var plan: [PlannedNotification] = []
        var day = today
        while plan.count < 4 {
            if calendar.component(.weekday, from: day.startDate(calendar: calendar)) == 7 {
                let date = day.date(atMinute: 9 * 60, calendar: calendar)
                if date > now() {
                    plan.append(PlannedNotification(id: "teas.\(day)", date: date,
                                                    body: "Saturday: time to pick this week's teas with Becky.",
                                                    isDiscreet: false))
                }
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        reminders.replace(with: plan)
    }
}
