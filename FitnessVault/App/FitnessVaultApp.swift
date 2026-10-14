import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct FitnessVaultApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = Persistence.makeContainer()
        self.container = container
        _model = State(initialValue: AppModel(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(container)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
                .task {
                    await model.start()
                    BackgroundRefresh.schedule(at: model.nextSettlement)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
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
