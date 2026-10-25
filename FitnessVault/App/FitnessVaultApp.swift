import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct FitnessVaultApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @State private var training: TrainingModel
    @State private var kitchen: KitchenModel
    @State private var planner: PlannerModel
    @State private var routines: RoutineModel
    @State private var journal: JournalModel
    @State private var battery = LifeBatteryModel()
    @State private var teas = TeaModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = Persistence.makeContainer()
        self.container = container
        let model = AppModel(container: container)
        model.observeHealthChanges()
        _model = State(initialValue: model)
        let training = TrainingModel(container: container)
        _training = State(initialValue: training)
        _kitchen = State(initialValue: KitchenModel(container: container))
        // A missed home routine halves that day's earnings; changes re-apply straight away.
        let routines = RoutineModel(container: container)
        model.routinePenalty = { routines.isPenalised($0) }
        routines.onChange = { model.applyRoutineChanges() }
        _routines = State(initialValue: routines)
        _journal = State(initialValue: JournalModel(container: container))
        // Demo mode shows a sample week instead of your calendars.
        let planner = model.settings.demoMode
            ? PlannerModel(calendarService: DemoCalendarService(), location: FixedLocationService(nil),
                           defaults: UserDefaults(suiteName: "demo.planner") ?? .standard)
            : PlannerModel()
        _planner = State(initialValue: planner)
        // Leave days, the first event and nights out come from the Day tab's calendars and location.
        routines.dayInfo = { planner.routineInfo(for: $0) }
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
                .environment(planner)
                .environment(routines)
                .environment(journal)
                .environment(battery)
                .environment(teas)
                .modelContainer(container)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
                .task {
                    kitchen.start()
                    routines.scheduleReminders()
                    teas.scheduleReminders()
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
                    journal.reload()
                    await planner.refresh()
                    routines.refreshSchedule()
                    routines.scheduleReminders()
                    PlannerWidgetPublisher.publishDay(planner: planner, routines: routines)
                    await model.syncHealth()
                    battery.refresh(model: model, training: training, gymPerWeek: planner.settings.gymPerWeek)
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
