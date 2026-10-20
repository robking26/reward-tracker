import Foundation
import Observation
import SwiftData

/// One set of models for the whole process, so the app, Siri and widget buttons all act on the same data.
/// Created on first use: by the app at launch, or by an App Intent when iOS runs one in the background.
@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let container: ModelContainer
    let model: AppModel
    let coach: CoachModel
    let training: TrainingModel
    let kitchen: KitchenModel
    let situation: SituationModel
    let router = AppRouter()

    private init() {
        container = Persistence.makeContainer()
        model = AppModel(container: container)
        model.observeHealthChanges()
        coach = CoachModel(container: container, settingsStore: model.settingsStore)
        training = TrainingModel(container: container, coach: coach)
        kitchen = KitchenModel(container: container, coach: coach)
        situation = SituationModel(container: container, coach: coach, kitchen: kitchen)
        let trainingModel = training
        let coachModel = coach
        // The watch can skip rest or end the workout; the iPhone stays the logger.
        WatchBridge.shared.onCommand = { command in
            switch command {
            case .skipRest: trainingModel.skipRest()
            case .end: trainingModel.end()
            }
        }
        // Widget buttons run their intents in this process.
        WidgetActionRouter.handler = { action in
            switch action {
            case .complete(let id): coachModel.complete(id)
            }
        }
    }
}

/// Where a link, a widget or Siri wants the app to go.
enum AppRoute: Equatable {
    case today, coach, ready, workout
}

@MainActor
@Observable
final class AppRouter {
    var pending: AppRoute? = nil

    /// `vaultality://ready`, `://workout`, `://coach`, `://today`.
    func handle(_ url: URL) {
        guard url.scheme == AppLink.scheme else { return }
        switch url.host {
        case "ready": pending = .ready
        case "workout": pending = .workout
        case "coach": pending = .coach
        default: pending = .today
        }
    }
}
