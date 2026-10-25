import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FitnessVault

/// Renders the Gym and Kitchen screens with realistic sample data and saves JPEGs to `screenshots/`, so design
/// changes can be reviewed from CI. Runs only when CI sets SCREENSHOTS=1 (via TEST_RUNNER_SCREENSHOTS).
@MainActor
final class ScreenshotTests: XCTestCase {
    private var enabled: Bool { ProcessInfo.processInfo.environment["SCREENSHOTS"] == "1" }

    private var folder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("screenshots", isDirectory: true)
    }

    func testGymScreens() async throws {
        try XCTSkipUnless(enabled, "Screenshots are only rendered in CI")
        let model = PreviewFixtures.model()
        let container = Persistence.makeContainer(inMemory: true)
        Self.addTrainingHistory(container: container)
        let training = TrainingModel(container: container, restAlerts: RecordingRestAlerts())
        let kitchen = PreviewFixtures.kitchen()

        try await capture("gym-tab", height: 852, GymView(showingSettings: .constant(false)), model, training, kitchen)
        try await capture("gym-tab-full", height: 2_600, GymView(showingSettings: .constant(false)), model, training, kitchen)
        try await capture("gym-setup", height: 1_400, WorkoutFlowView(), model, training, kitchen)
        try await capture("gym-rehab-setup", height: 1_000, WorkoutFlowView(rehabOnly: true), model, training, kitchen)

        let knee = NavigationStack { KneeCheckView(timing: .nextDay) { _, _, _ in "" } }
        try await capture("gym-knee-check", height: 852, knee, model, training, kitchen)

        let plan = training.makePlan(focus: .push, variant: 0, availableMinutes: 90, rehabFirst: false)
        training.start(plan)
        try await capture("gym-active", height: 1_300, WorkoutFlowView(), model, training, kitchen)
        training.logSet(weight: plan.exercises.first?.weightKg, reps: plan.exercises.first?.targetReps ?? 10)
        try await capture("gym-active-resting", height: 1_300, WorkoutFlowView(), model, training, kitchen)
        training.logSet(weight: plan.exercises.first?.weightKg, reps: 10)
        training.logSet(weight: plan.exercises.first?.weightKg, reps: 9)
        try await capture("gym-active-next-up", height: 1_300, WorkoutFlowView(), model, training, kitchen)
        training.end()
    }

    func testDayScreens() async throws {
        try XCTSkipUnless(enabled, "Screenshots are only rendered in CI")
        let model = PreviewFixtures.model()
        let training = PreviewFixtures.training()
        let kitchen = PreviewFixtures.kitchen()
        let planner = PreviewFixtures.planner()
        await planner.refresh()
        try await capture("day-tab", height: 852, DayView(showingSettings: .constant(false)), model, training, kitchen, planner)
        try await capture("day-tab-full", height: 2_600, DayView(showingSettings: .constant(false)), model, training, kitchen, planner)
        try await capture("day-settings", height: 1_800, DaySettingsView(), model, training, kitchen, planner)
        let routines = PreviewFixtures.routines()
        try await capture("routine-checklist", height: 1_300,
                          NavigationStack { RoutineChecklistView(part: .morning, day: routines.today) },
                          model, training, kitchen, planner, routines: routines)
        try await capture("journal", height: 1_700, NavigationStack { JournalView() }, model, training, kitchen, planner)
        try await capture("journal-compose", height: 1_100,
                          NavigationStack { JournalComposer(prompt: "Three wins from today", routineItemID: "wins") { _ in } },
                          model, training, kitchen, planner)
        try await capture("routine-questionnaire", height: 1_900, RoutineQuestionnaireView(startStep: 3), model, training, kitchen,
                          planner, routines: RoutineModel(container: Persistence.makeContainer(inMemory: true),
                                                          reminders: RecordingReminderScheduler(),
                                                          defaults: UserDefaults(suiteName: "shots.\(UUID().uuidString)")!))
    }

    func testVaultBattery() async throws {
        try XCTSkipUnless(enabled, "Screenshots are only rendered in CI")
        let model = PreviewFixtures.model()
        await model.syncHealth()
        let training = PreviewFixtures.training()
        let kitchen = PreviewFixtures.kitchen()
        let battery = PreviewFixtures.battery()
        try await capture("vault-tab", height: 1_400, ActivityView(showingSettings: .constant(false)), model, training, kitchen,
                          battery: battery)
        try await capture("battery-detail", height: 2_200, NavigationStack { BatteryDetailView() }, model, training, kitchen,
                          battery: battery)
    }

    func testKitchenScreens() async throws {
        try XCTSkipUnless(enabled, "Screenshots are only rendered in CI")
        let model = PreviewFixtures.model()
        let training = PreviewFixtures.training()
        let kitchen = PreviewFixtures.kitchen()
        kitchen.logCycle(.breakfast, on: kitchen.today)
        let yoghurt = FoodProduct(barcode: "4088600123456", name: "Protein Yogurt Strawberry", brand: "Brooklea",
                                  per100: Macros(kcal: 62, protein: 10, carbs: 4, fat: 0.4), servingGrams: 200, servingText: "200 g")
        kitchen.log(yoghurt, grams: 200, amountText: "200 g", meal: .snack)
        kitchen.logManual(name: "Chicken stir-fry", macros: Macros(kcal: 640, protein: 48, carbs: 70, fat: 14), meal: .evening)
        let monday = kitchen.shoppingMonday(next: false)
        if let first = kitchen.shoppingList(.lunch, weekStarting: monday).first {
            kitchen.toggle(first, slot: .lunch, monday: monday)
        }

        for section in KitchenSection.allCases {
            let view = NavigationStack { KitchenView(showingSettings: .constant(false), section: section) }
            try await capture("kitchen-\(section.id.lowercased())", height: 2_200, view, model, training, kitchen)
        }
        try await capture("kitchen-top", height: 852,
                          NavigationStack { KitchenView(showingSettings: .constant(false)) }, model, training, kitchen)
        try await capture("kitchen-lunch", height: 2_000,
                          NavigationStack { CycleMealDetailView(meal: MealCycle.meal(.lunch, week: 1)) }, model, training, kitchen)
        try await capture("kitchen-amount", height: 852,
                          NavigationStack { ProductAmountView(product: yoghurt) {} }, model, training, kitchen)
    }

    // MARK: - Rendering

    private func capture<V: View>(_ name: String, height: CGFloat, _ view: V,
                                  _ model: AppModel, _ training: TrainingModel, _ kitchen: KitchenModel,
                                  _ planner: PlannerModel? = nil, routines: RoutineModel? = nil,
                                  battery: LifeBatteryModel? = nil) async throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 393, height: height)
        window.overrideUserInterfaceStyle = .dark
        let root = view
            .environment(model)
            .environment(training)
            .environment(kitchen)
            .environment(planner ?? PreviewFixtures.planner())
            .environment(routines ?? PreviewFixtures.routines())
            .environment(PreviewFixtures.journal())
            .environment(PreviewFixtures.teas())
            .environment(battery ?? PreviewFixtures.battery())
            .preferredColorScheme(.dark)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(2))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.5
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // JPEG keeps the log small enough to read back.
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.6))
        try data.write(to: folder.appendingPathComponent(name + ".jpg"))
        window.isHidden = true
        window.rootViewController = nil
    }

    // MARK: - Sample data

    /// Six weeks of alternating upper and lower sessions with slowly rising weights, plus knee check-ins.
    private static func addTrainingHistory(container: ModelContainer) {
        var date = Date.now.addingTimeInterval(-42 * 86_400)
        let history = TrainingModel(container: container, restAlerts: RecordingRestAlerts(), now: { date })
        var index = 0
        while date < Date.now.addingTimeInterval(-86_400) {
            let focus = history.suggestedFocus(for: nil).0
            let plan = history.makePlan(focus: focus, variant: 0, availableMinutes: 90, rehabFirst: true)
            history.start(plan)
            var guardCount = 0
            while history.current != nil && guardCount < 60 {
                guardCount += 1
                if history.awaitingReady {
                    history.ready()
                    continue
                }
                let item = history.current
                history.logSet(weight: item?.weightKg, reps: item?.targetReps ?? 10)
                date = date.addingTimeInterval(150)
            }
            history.end()
            let pain = index % 5 == 0 ? 3 : 1
            _ = history.logSymptom(timing: .nextDay, pain: pain, swelling: false, sharp: false)
            index += 1
            date = date.addingTimeInterval(index % 3 == 0 ? 3 * 86_400 : 2 * 86_400)
        }
    }
}
