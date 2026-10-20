import AppIntents
import Foundation

/// What a widget button asks the app to do.
enum WidgetAction: Sendable {
    case complete(UUID)
}

/// Lets intents shared with the widget reach the app's models. The app sets the handler at launch;
/// in the widget extension it stays nil, which is why the intents below run in the app's process.
@MainActor
enum WidgetActionRouter {
    static var handler: ((WidgetAction) -> Void)?

    static func perform(_ action: WidgetAction) {
        handler?(action)
    }
}

/// The widget's Done button. `LiveActivityIntent` makes iOS run it in the app's process, where the store is,
/// without opening the app.
struct CompleteCommitmentIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark done"
    static let description = IntentDescription("Marks the coach's current commitment as done.")
    static let isDiscoverable = false

    @Parameter(title: "Commitment")
    var commitmentID: String

    init() {}

    init(commitmentID: String) {
        self.commitmentID = commitmentID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: commitmentID) {
            await WidgetActionRouter.perform(.complete(id))
        }
        return .result()
    }
}

/// Links from widgets into the app.
enum AppLink {
    static let scheme = "vaultality"
    static let ready = URL(string: "vaultality://ready")!
    static let workout = URL(string: "vaultality://workout")!
    static let coach = URL(string: "vaultality://coach")!
    static let today = URL(string: "vaultality://today")!
}
