import ActivityKit
import Foundation

enum CountdownKind: String, Sendable {
    case departure, task, cooking
}

/// Starts and ends the countdown Live Activities (WG2). One per kind at a time.
@MainActor
protocol CountdownControlling: AnyObject {
    func show(_ kind: CountdownKind, id: String, title: String, subtitle: String, symbol: String, endsAt: Date)
    /// Ends the kind's activity; with an `id`, only if it's that one.
    func end(_ kind: CountdownKind, id: String?)
}

@MainActor
final class LocalCountdowns: CountdownControlling {
    static let shared = LocalCountdowns()

    private var activities: [CountdownKind: (id: String, endsAt: Date, activity: Activity<CountdownAttributes>)] = [:]
    /// Unit tests run inside the app; they never start real Live Activities.
    private let isTesting = NSClassFromString("XCTestCase") != nil

    func show(_ kind: CountdownKind, id: String, title: String, subtitle: String, symbol: String, endsAt: Date) {
        guard !isTesting, endsAt > .now else { return }
        let state = CountdownAttributes.ContentState(endsAt: endsAt, subtitle: subtitle)
        let content = ActivityContent(state: state, staleDate: endsAt.addingTimeInterval(10 * 60))
        if let current = activities[kind] {
            guard current.id != id || current.endsAt != endsAt else { return }
            if current.id == id {
                activities[kind] = (id, endsAt, current.activity)
                Task { await current.activity.update(content) }
                return
            }
            end(kind, id: nil)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let activity = try? Activity.request(attributes: CountdownAttributes(kind: kind.rawValue, title: title, symbol: symbol),
                                                   content: content) else { return }
        activities[kind] = (id, endsAt, activity)
    }

    func end(_ kind: CountdownKind, id: String?) {
        guard let current = activities[kind], id == nil || current.id == id else { return }
        activities[kind] = nil
        Task { await current.activity.end(nil, dismissalPolicy: .immediate) }
    }
}

/// Records calls for tests.
@MainActor
final class RecordingCountdowns: CountdownControlling {
    private(set) var shown: [CountdownKind: (id: String, title: String, endsAt: Date)] = [:]
    private(set) var endedKinds: [CountdownKind] = []

    func show(_ kind: CountdownKind, id: String, title: String, subtitle: String, symbol: String, endsAt: Date) {
        shown[kind] = (id, title, endsAt)
    }

    func end(_ kind: CountdownKind, id: String?) {
        guard let current = shown[kind], id == nil || current.id == id else { return }
        shown[kind] = nil
        endedKinds.append(kind)
    }
}
