import AppIntents
import Foundation

// Siri, Shortcuts, Spotlight and the Action button (Phase 7). Each intent uses the same models as the app,
// through `AppRuntime`, so a spoken "Done" changes exactly what tapping Done would.

struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What's next"
    static let description = IntentDescription("Hear the one thing to do now.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let coach = AppRuntime.shared.coach
        await coach.refresh()
        return .result(dialog: "\(coach.whatsNext().text)")
    }
}

struct MarkDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark it done"
    static let description = IntentDescription("Marks the current commitment as done.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let coach = AppRuntime.shared.coach
        await coach.refresh()
        return .result(dialog: "\(coach.markCurrentDone().text)")
    }
}

struct ImReadyIntent: AppIntent {
    static let title: LocalizedStringResource = "I'm ready"
    static let description = IntentDescription("Opens the coach and starts today's briefing.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRuntime.shared.router.pending = .ready
        return .result()
    }
}

struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start my workout"
    static let description = IntentDescription("Opens the workout logger for today's gym session.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRuntime.shared.router.pending = .workout
        return .result()
    }
}

struct AddToShoppingListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to the shopping list"
    static let description = IntentDescription("Adds something to the Aldi list.")

    @Parameter(title: "Item", requestValueDialog: "What do you need?")
    var item: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = AppRuntime.shared.kitchen.addToShopping(item)
        return .result(dialog: "\(name) is on the list.")
    }
}

struct FeelingRoughIntent: AppIntent {
    static let title: LocalizedStringResource = "I'm feeling rough"
    static let description = IntentDescription("Makes today a recovery day: nothing demanding, and no fine for the gym.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let coach = AppRuntime.shared.coach
        await coach.refresh()
        return .result(dialog: "\(coach.feelingRough().text)")
    }
}

struct VaultalityShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhatsNextIntent(),
                    phrases: ["What's next in \(.applicationName)", "\(.applicationName) what's next", "Ask \(.applicationName) what's next"],
                    shortTitle: "What's next", systemImageName: "arrow.forward.circle")
        AppShortcut(intent: MarkDoneIntent(),
                    phrases: ["Mark it done in \(.applicationName)", "\(.applicationName) done", "Tell \(.applicationName) I'm done"],
                    shortTitle: "Mark done", systemImageName: "checkmark.circle")
        AppShortcut(intent: ImReadyIntent(),
                    phrases: ["I'm ready in \(.applicationName)", "\(.applicationName) I'm ready", "Start my day with \(.applicationName)"],
                    shortTitle: "I'm ready", systemImageName: "sunrise")
        AppShortcut(intent: StartWorkoutIntent(),
                    phrases: ["Start my workout in \(.applicationName)", "\(.applicationName) start workout"],
                    shortTitle: "Start workout", systemImageName: "dumbbell")
        AppShortcut(intent: AddToShoppingListIntent(),
                    phrases: ["Add to my \(.applicationName) shopping list", "\(.applicationName) shopping list"],
                    shortTitle: "Shopping list", systemImageName: "cart")
        AppShortcut(intent: FeelingRoughIntent(),
                    phrases: ["I'm feeling rough in \(.applicationName)", "Tell \(.applicationName) I'm feeling rough"],
                    shortTitle: "Feeling rough", systemImageName: "leaf")
    }
}
