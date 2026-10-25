#if DEBUG
import SwiftData
import SwiftUI

/// Preview-only wiring: an in-memory store, generated Health data and the mock bank.
/// Production views never contain sample balances or activity values.
@MainActor
enum PreviewFixtures {
    static func training() -> TrainingModel {
        TrainingModel(container: Persistence.makeContainer(inMemory: true), restAlerts: RecordingRestAlerts())
    }

    static func kitchen() -> KitchenModel {
        let kitchen = KitchenModel(container: Persistence.makeContainer(inMemory: true), products: FixedProductLookup(),
                                   reminders: RecordingReminderScheduler(),
                                   defaults: UserDefaults(suiteName: "preview.kitchen.\(UUID().uuidString)") ?? .standard)
        kitchen.start()
        return kitchen
    }

    /// Routines set up from the questionnaire's defaults, with this morning half done.
    static func routines() -> RoutineModel {
        let defaults = UserDefaults(suiteName: "preview.routines.\(UUID().uuidString)") ?? .standard
        let routines = RoutineModel(container: Persistence.makeContainer(inMemory: true), reminders: RecordingReminderScheduler(),
                                    defaults: defaults)
        var items: [String: [RoutineItem]] = [:]
        for key in RoutineKey.all { items[key.id] = RoutineCatalogue.defaults(for: key) }
        routines.save(items, times: [:])
        let today = routines.today
        let part = routines.currentPart
        for item in routines.items(part, on: today).prefix(3) {
            routines.toggle(item, part: part, on: today)
        }
        return routines
    }

    /// A month of journal entries with a gently rising mood.
    static func journal() -> JournalModel {
        let container = Persistence.makeContainer(inMemory: true)
        let start = Date.now.addingTimeInterval(-27 * 86_400)
        for offset in stride(from: 0, to: 28, by: 1) where offset % 4 != 3 {
            let mood = Mood(rawValue: min(5, max(1, 2 + offset / 8 + (offset % 3 == 0 ? 1 : 0)))) ?? .okay
            let feelings = [JournalFeelings.all[offset % 6], JournalFeelings.all[6 + offset % 6]]
            container.mainContext.insert(JournalEntry(date: start.addingTimeInterval(TimeInterval(offset * 86_400 + 21 * 3_600)),
                                                      mood: mood, feelings: feelings,
                                                      text: "1. Gym before work\n2. Lunch prepped\n3. Walk with Becky",
                                                      prompt: "Three wins from today", routineItemID: "wins"))
        }
        try? container.mainContext.save()
        return JournalModel(container: container)
    }

    /// A battery started 60 days ago, filled from the demo Health data.
    static func battery() -> LifeBatteryModel {
        let defaults = UserDefaults(suiteName: "preview.battery.\(UUID().uuidString)") ?? .standard
        defaults.set(DayKey(Date.now.addingTimeInterval(-60 * 86_400)).description, forKey: LifeBatteryModel.startKey)
        return LifeBatteryModel(defaults: defaults)
    }

    /// A small bank of teas and a week started, for previews and screenshots.
    static func teas() -> TeaModel {
        let defaults = UserDefaults(suiteName: "preview.teas.\(UUID().uuidString)") ?? .standard
        let samples = [
            TeaRecipe(id: "chilli", title: "Smoky turkey chilli", source: "Sample", servings: 4, kcal: 640, protein: 56, carbs: 62,
                      fat: 14, prepMinutes: 15, cookMinutes: 40, freezable: true,
                      ingredients: ["500 g 2% turkey mince", "Kidney beans", "Chopped tomatoes", "Smoked paprika", "Basmati rice"]),
            TeaRecipe(id: "katsu", title: "Chicken katsu curry", source: "Sample", servings: 2, kcal: 680, protein: 58, carbs: 78,
                      fat: 12, prepMinutes: 20, cookMinutes: 25, freezable: true,
                      ingredients: ["Chicken breast", "Panko", "Katsu sauce", "Rice", "Pak choi"]),
            TeaRecipe(id: "salmon", title: "Miso salmon, noodles and greens", source: "Sample", servings: 2, kcal: 660, protein: 52,
                      carbs: 60, fat: 20, prepMinutes: 10, cookMinutes: 15, freezable: false,
                      ingredients: ["Salmon fillets", "White miso", "Egg noodles", "Tenderstem", "Spring onion"]),
            TeaRecipe(id: "lasagne", title: "Lean beef lasagne", source: "Sample", servings: 4, kcal: 690, protein: 54, carbs: 66,
                      fat: 18, prepMinutes: 25, cookMinutes: 45, freezable: true,
                      ingredients: ["5% beef mince", "Lasagne sheets", "Passata", "Light white sauce", "Mozzarella"]),
        ]
        let teas = TeaModel(reminders: RecordingReminderScheduler(), defaults: defaults, bundled: samples)
        teas.startWeek()
        return teas
    }

    static func planner() -> PlannerModel {
        let defaults = UserDefaults(suiteName: "preview.planner.\(UUID().uuidString)") ?? .standard
        let planner = PlannerModel(calendarService: DemoCalendarService(), location: FixedLocationService(nil),
                                   weather: FixedWeatherService(hours: sampleForecast()), travel: FixedTravelService(minutes: 12),
                                   defaults: defaults)
        planner.setRoles(DemoCalendarService.roles)
        let places: [(PlaceID, String)] = [(.home, "Home"), (.office, "Spinningfields office"), (.gym, "PureGym Bolton"),
                                           (.pool, "Horwich Leisure Centre"), (.aldi, "Aldi Bolton")]
        for (id, name) in places {
            planner.update { $0.places[id] = SavedPlace(name: name, coordinate: .bolton) }
        }
        return planner
    }

    /// A week of mild weather with afternoon showers every third day.
    static func sampleForecast() -> [HourlyWeather] {
        let start = Calendar.current.startOfDay(for: .now)
        return (0..<(7 * 24)).map { hour in
            let clock = hour % 24
            let showery = (hour / 24) % 3 == 1 && (14...17).contains(clock)
            return HourlyWeather(date: start.addingTimeInterval(TimeInterval(hour * 3_600)), temperature: 8 + Double(clock % 12) / 2,
                                 precipitationProbability: showery ? 70 : 10, precipitation: showery ? 0.8 : 0,
                                 isDaylight: (7...17).contains(clock))
        }
    }

    static func model() -> AppModel {
        let defaults = UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        let settings = SettingsStore(defaults: defaults)
        settings.settings.demoMode = true
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), settingsStore: settings)
        Task { await model.start() }
        return model
    }
}

#Preview("Metric card") {
    MetricCard(title: "Steps", symbol: "figure.walk", timeframe: "Today", measurement: "8,412", unit: "steps",
               earned: Pence(168))
        .frame(width: 180)
        .padding()
        .pageBackground()
        .preferredColorScheme(.dark)
}

#Preview("Vault hero") {
    VaultHeroCard(summary: VaultSummary(month: MonthKey(.now), allocation: .pounds(400), earned: Pence(12_345)))
        .padding()
        .pageBackground()
        .preferredColorScheme(.dark)
}
#endif
