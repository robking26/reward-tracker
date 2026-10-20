import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct FitnessVaultApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @State private var training: TrainingModel
    @State private var kitchen: KitchenModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = Persistence.makeContainer()
        self.container = container
        let model = AppModel(container: container)
        model.observeHealthChanges()
        _model = State(initialValue: model)
        let training = TrainingModel(container: container)
        _training = State(initialValue: training)
        _kitchen = State(initialValue: KitchenModel(container: container, settingsStore: model.settingsStore))
        // The watch can skip rest or end the workout; the iPhone stays the logger.
        WatchBridge.shared.onCommand = { command in
            switch command {
            case .skipRest: training.skipRest()
            case .end: training.end()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(training)
                .environment(kitchen)
                .modelContainer(container)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
                .task {
                    kitchen.start()
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
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    kitchen.refresh()
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
