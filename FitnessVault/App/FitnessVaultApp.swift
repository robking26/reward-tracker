import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct FitnessVaultApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @State private var coach: CoachModel
    @State private var training: TrainingModel
    @State private var kitchen: KitchenModel
    @State private var situation: SituationModel
    @State private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let runtime = AppRuntime.shared
        container = runtime.container
        _model = State(initialValue: runtime.model)
        _coach = State(initialValue: runtime.coach)
        _training = State(initialValue: runtime.training)
        _kitchen = State(initialValue: runtime.kitchen)
        _situation = State(initialValue: runtime.situation)
        _router = State(initialValue: runtime.router)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(coach)
                .environment(training)
                .environment(kitchen)
                .environment(situation)
                .environment(router)
                .modelContainer(container)
                .onOpenURL { router.handle($0) }
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
                .task {
                    await coach.start()
                    kitchen.start()
                    // Network-bound context loads alongside Health rather than before it (fast launch).
                    Task { await situation.refresh() }
                    await model.start()
                    BackgroundRefresh.schedule(at: model.nextSettlement)
                }
                // While the app is on screen, read Apple Health every minute. Stops as soon as it isn't.
                .task(id: scenePhase == .active) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        guard !Task.isCancelled else { return }
                        await model.syncHealth()
                        await coach.refresh()
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await coach.refresh()
                    kitchen.refresh()
                    await situation.refresh()
                    await model.syncHealth()
                    await model.settleIfDue()
                }
            case .background:
                BackgroundRefresh.schedule(at: model.nextSettlement)
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await model.backgroundRefresh()
            await BackgroundRefresh.schedule(at: model.nextSettlement)
        }
    }
}

/// Best-effort background refresh near the settlement time. iOS decides whether and when it runs,
/// so settlement also runs whenever the app is opened after the settlement time.
enum BackgroundRefresh {
    static let identifier = "com.robking.FitnessVault.settlement"

    static func schedule(at date: Date) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        try? BGTaskScheduler.shared.submit(request)
    }
}
