import Foundation

enum MealRole: String, Codable, Sendable, CaseIterable, Identifiable {
    case lunch, dinner, both, breakfast

    var id: String { rawValue }
    var title: String {
        switch self {
        case .lunch: "Work lunch"
        case .dinner: "Dinner"
        case .both: "Lunch or dinner"
        case .breakfast: "Breakfast"
        }
    }
    var suitsLunch: Bool { self == .lunch || self == .both }
    var suitsDinner: Bool { self == .dinner || self == .both }
}

enum MealSlot: String, Codable, Sendable {
    case lunch, dinner
}

/// What the planner needs to know about a recipe.
struct MealCandidate: Sendable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var role: MealRole
    var servings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var washUpMinutes: Int
    var usesSlowCooker: Bool
    var isFakeaway: Bool
    var freezable: Bool
    var favourite: Bool
    var excluded: Bool
    var lastCooked: DayKey?

    var totalMinutes: Int { prepMinutes + cookMinutes }
    var isQuick: Bool { usesSlowCooker || totalMinutes <= 30 }
}

/// Portions of a cooked meal in the freezer (F6).
struct FreezerMeal: Sendable, Hashable {
    var title: String
    var portions: Int
    var recipeID: UUID?
}

struct PlannedMeal: Sendable, Hashable {
    var day: DayKey
    var slot: MealSlot
    var recipeID: UUID?
    var title: String
    /// Dinner is two identical portions (F2); lunch one.
    var portions: Int
    var fromFreezer: Bool
    var note: String?
}

/// One day of the week being planned, from the calendar.
struct MealDayContext: Sendable, Hashable {
    var day: DayKey
    /// ISO weekday, Monday = 1.
    var weekday: Int
    var workFromHome: Bool
    var office: Bool
    var eatingOut: Bool
    /// Something in the evening (gym, social) that leaves little time to cook.
    var lateFinish: Bool
}

struct MealPlanInput: Sendable {
    var days: [MealDayContext]
    var candidates: [MealCandidate]
    var freezer: [FreezerMeal]
    /// 0…3: which week of the four-week lunch rotation (F2).
    var rotationWeek: Int
    /// Don't repeat a dinner cooked within this many days.
    var varietyDays: Int = 10
}

enum MealPlanner {
    /// Which week of the four-week lunch rotation a date falls in, counted from a fixed Monday.
    static func rotationWeek(for day: DayKey, calendar: Calendar) -> Int {
        let anchor = DayKey(year: 2026, month: 1, day: 5).startDate(calendar: calendar)
        let days = calendar.dateComponents([.day], from: anchor, to: day.startDate(calendar: calendar)).day ?? 0
        let weeks = Int((Double(days) / 7).rounded(.down))
        return ((weeks % 4) + 4) % 4
    }

    static func plan(_ input: MealPlanInput) -> [PlannedMeal] {
        var meals: [PlannedMeal] = []

        // Lunch: the same batch-cooked lunch Monday to Friday, rotating weekly (F2).
        let lunches = input.candidates.filter { $0.role.suitsLunch && !$0.excluded && !$0.isFakeaway }.sorted { $0.title < $1.title }
        if !lunches.isEmpty {
            let lunch = lunches[input.rotationWeek % lunches.count]
            for day in input.days where day.weekday <= 5 {
                meals.append(PlannedMeal(day: day.day, slot: .lunch, recipeID: lunch.id, title: lunch.title, portions: 1,
                                         fromFreezer: false, note: "From the weekly batch cook"))
            }
        }

        // Dinner: shared, two identical portions, varied (F2).
        var used: Set<UUID> = []
        var freezer = input.freezer.filter { $0.portions >= 2 }
        for day in input.days {
            if day.eatingOut {
                meals.append(PlannedMeal(day: day.day, slot: .dinner, recipeID: nil, title: "Eating out", portions: 0,
                                         fromFreezer: false, note: nil))
                continue
            }
            let pool = input.candidates.filter { candidate in
                guard candidate.role.suitsDinner, !candidate.excluded, !used.contains(candidate.id) else { return false }
                // Slow-cooker prep happens in the morning, so never on an office day (F4).
                if candidate.usesSlowCooker && day.office { return false }
                if let last = candidate.lastCooked, last > day.day.adding(days: -input.varietyDays) { return false }
                return true
            }
            // A late evening wants something quick, or the freezer.
            let fitting = day.lateFinish ? pool.filter(\.isQuick) : pool
            // Fakeaways are for Friday and the weekend; midweek they're the last resort after the freezer.
            let preferred = day.weekday <= 4 ? fitting.filter { !$0.isFakeaway } : fitting
            if let chosen = best(in: preferred, on: day) {
                used.insert(chosen.id)
                meals.append(cooked(chosen, on: day.day))
            } else if let index = freezer.indices.filter({ freezer[$0].portions >= 2 }).max(by: { freezer[$0].portions < freezer[$1].portions }) {
                meals.append(freezerDinner(&freezer[index], on: day.day))
            } else if let chosen = best(in: fitting, on: day) {
                used.insert(chosen.id)
                meals.append(cooked(chosen, on: day.day))
            } else {
                meals.append(PlannedMeal(day: day.day, slot: .dinner, recipeID: nil, title: "Something easy, picked on the night",
                                         portions: 2, fromFreezer: false, note: nil))
            }
        }
        return meals
    }

    /// Whole days from `a` to `b`, independent of time zone and daylight saving.
    static func daysBetween(_ a: DayKey, _ b: DayKey) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        return utc.dateComponents([.day], from: a.startDate(calendar: utc), to: b.startDate(calendar: utc)).day ?? 0
    }

    private static func best(in candidates: [MealCandidate], on day: MealDayContext) -> MealCandidate? {
        candidates.max { left, right in
            let a = rank(left, on: day)
            let b = rank(right, on: day)
            return a < b || (a == b && left.title > right.title)
        }
    }

    private static func cooked(_ meal: MealCandidate, on day: DayKey) -> PlannedMeal {
        var note: String?
        if meal.usesSlowCooker { note = "Ten minutes of slow-cooker prep this morning" }
        if meal.isFakeaway { note = "Fakeaway night" }
        return PlannedMeal(day: day, slot: .dinner, recipeID: meal.id, title: meal.title, portions: 2, fromFreezer: false, note: note)
    }

    private static func freezerDinner(_ meal: inout FreezerMeal, on day: DayKey) -> PlannedMeal {
        meal.portions -= 2
        return PlannedMeal(day: day, slot: .dinner, recipeID: meal.recipeID, title: meal.title, portions: 2,
                           fromFreezer: true, note: "From the freezer. Defrost in the fridge the night before.")
    }

    private static func rank(_ candidate: MealCandidate, on day: MealDayContext) -> Double {
        var score = 0.0
        if candidate.favourite { score += 3 }
        if candidate.isFakeaway { score += day.weekday == 5 ? 6 : -3 }
        if candidate.washUpMinutes <= 10 { score += 1 }
        if day.lateFinish && candidate.isQuick { score += 3 }
        if day.weekday >= 6 && candidate.totalMinutes > 40 { score += 1 } // weekends suit a longer cook
        let rested = candidate.lastCooked.map { Double(daysBetween($0, day.day)) } ?? 30
        score += min(30, rested) / 10
        return score
    }
}

struct BatchItem: Sendable, Hashable {
    var title: String
    var portions: Int
    var forFreezer: Bool
}

struct BatchCookPlan: Sendable, Hashable {
    var items: [BatchItem]
    var minutes: Int
    var fits: Bool
    var adjustments: [String]
}

/// One weekly session of an hour at most: five lunches, plus freezer dinners when they fit (F5).
enum BatchCookPlanner {
    static let limit = 60

    static func plan(lunch: MealCandidate?, lunchPortions: Int = 5, freezerDinners: [MealCandidate],
                     extraPortions: Int = 4) -> BatchCookPlan {
        var adjustments: [String] = []
        var dinners = freezerDinners.filter(\.freezable)
        func elapsed(_ lunch: MealCandidate?, _ dinners: [MealCandidate]) -> Int {
            var handsOn = 0
            var longestCook = 0
            if let lunch {
                handsOn += scaledPrep(lunch, portions: lunchPortions)
                longestCook = max(longestCook, lunch.cookMinutes)
            }
            for dinner in dinners {
                handsOn += scaledPrep(dinner, portions: extraPortions)
                // A slow cooker runs on its own; anything else shares the oven and hob time.
                if !dinner.usesSlowCooker { longestCook = max(longestCook, dinner.cookMinutes) }
            }
            return handsOn + longestCook + 10 // portioning into tubs
        }
        var minutes = elapsed(lunch, dinners)
        while minutes > limit, let dropped = dinners.popLast() {
            adjustments.append("Left \(dropped.title) for another day so the session stays under an hour.")
            minutes = elapsed(lunch, dinners)
        }
        var items: [BatchItem] = []
        if let lunch { items.append(BatchItem(title: lunch.title, portions: lunchPortions, forFreezer: false)) }
        items += dinners.map { BatchItem(title: $0.title, portions: extraPortions, forFreezer: true) }
        let fits = minutes <= limit
        if !fits, let lunch {
            adjustments.append("\(lunch.title) takes about \(minutes) minutes for \(lunchPortions) portions. Pick a quicker lunch, or cook 3 now and 2 midweek.")
        }
        return BatchCookPlan(items: items, minutes: minutes, fits: fits, adjustments: adjustments)
    }

    /// Prep grows with quantity, but not linearly: chopping two onions isn't twice the work of one.
    private static func scaledPrep(_ recipe: MealCandidate, portions: Int) -> Int {
        let batches = Double(portions) / Double(max(1, recipe.servings))
        let factor = 1 + max(0, batches - 1) * 0.3
        return Int((Double(recipe.prepMinutes) * factor).rounded(.up))
    }
}

/// Thawing frozen meals safely, in the fridge, the night before (I5).
enum DefrostPlanner {
    static let prefix = "kitchen.defrost."
    /// 20:30, after dinner and before wind-down.
    static let reminderMinute = 20 * 60 + 30

    static func reminders(for meals: [PlannedMeal], now: Date, calendar: Calendar,
                          minute: Int = reminderMinute) -> [PlannedNotification] {
        meals.filter(\.fromFreezer).compactMap { meal in
            let evening = meal.day.adding(days: -1, calendar: calendar).startDate(calendar: calendar)
                .addingTimeInterval(TimeInterval(minute * 60))
            guard evening > now else { return nil }
            let whose = meal.slot == .dinner ? "dinner" : "lunch"
            return PlannedNotification(id: prefix + meal.day.description + "." + meal.slot.rawValue, date: evening,
                                       body: "Tomorrow's \(whose) is \(meal.title). Move \(portionsText(meal.portions)) from the freezer to the fridge tonight.",
                                       isDiscreet: false)
        }
    }

    static func portionsText(_ portions: Int) -> String {
        portions == 1 ? "one portion" : portions == 2 ? "two portions" : "\(portions) portions"
    }

    /// What to do when it wasn't defrosted (I5). Never thaw on the worktop.
    static func forgottenAdvice(_ title: String) -> String {
        "Don't leave \(title) out on the side to thaw. Either defrost it in the microwave and reheat it straight away until it's piping hot all the way through, or have something else tonight and move it to the fridge for tomorrow."
    }
}

enum RescueKind: String, Sendable {
    case cupboard, freezer, topUp, takeaway
}

struct RescueOption: Sendable, Hashable, Identifiable {
    var id: String { title }
    var kind: RescueKind
    var title: String
    var detail: String
}

/// Scenario G: dinner isn't ready. Offer something low-effort based on what's probably in, never a lecture.
enum DinnerRescue {
    struct QuickOption: Sendable, Hashable {
        var meal: MealCandidate
        var missing: [String]
        var missingCost: Pence
    }

    static func options(quick: [QuickOption], freezer: [FreezerMeal], foodBudgetLeft: Pence,
                        defrostForgotten: Bool) -> [RescueOption] {
        var result: [RescueOption] = []
        let fast = quick.filter { $0.meal.totalMinutes <= 30 && !$0.meal.excluded }
            .sorted { ($0.missing.count, $0.meal.totalMinutes, $0.meal.title) < ($1.missing.count, $1.meal.totalMinutes, $1.meal.title) }
        if let ready = fast.first(where: { $0.missing.isEmpty }) {
            result.append(RescueOption(kind: .cupboard, title: ready.meal.title,
                                       detail: "You've probably got everything. About \(ready.meal.totalMinutes) minutes."))
        }
        if let frozen = freezer.filter({ $0.portions >= 2 }).max(by: { $0.portions < $1.portions }) {
            let detail = defrostForgotten
                ? "Defrost two portions in the microwave, then reheat straight away until piping hot."
                : "Two portions, reheated. Barely any washing up."
            result.append(RescueOption(kind: .freezer, title: frozen.title + " from the freezer", detail: detail))
        }
        if let topUp = fast.first(where: { !$0.missing.isEmpty && $0.missing.count <= 2 }) {
            result.append(RescueOption(kind: .topUp, title: topUp.meal.title,
                                       detail: "Co-op top-up for \(topUp.missing.joined(separator: " and ")) (about \(topUp.missingCost.formatted()))."))
        }
        if result.count < 3 {
            if foodBudgetLeft >= Pence.pounds(25) {
                result.append(RescueOption(kind: .takeaway, title: "Takeaway",
                                           detail: "From the food budget; \(foodBudgetLeft.formatted(wholePounds: true)) left this month. No guilt."))
            } else {
                result.append(RescueOption(kind: .takeaway, title: "Freezer fakeaway",
                                           detail: "Oven chips and fish fingers or whatever's quick in the freezer."))
            }
        }
        return Array(result.prefix(3))
    }
}
