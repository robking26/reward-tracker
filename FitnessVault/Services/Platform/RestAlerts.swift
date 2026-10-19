import ActivityKit
import Foundation
import UserNotifications

/// Tells the user when rest is over, even if they've switched to another app between sets (W5).
@MainActor
protocol RestAlerting: AnyObject {
    func workoutStarted(title: String)
    func restStarted(until end: Date, next: String, setLabel: String)
    func restCancelled()
    func workoutEnded()
}

/// A local notification at the end of each rest, plus the rest-timer Live Activity on the Lock Screen and
/// in the Dynamic Island. The Activity starts with the first rest and ends with the workout (WG2).
@MainActor
final class LocalRestAlerts: RestAlerting {
    private static let id = "rest.timer"
    private var activity: Activity<RestTimerAttributes>?

    func workoutStarted(title: String) {
        WatchBridge.shared.workoutStarted(title: title)
    }

    func restStarted(until end: Date, next: String, setLabel: String) {
        updateActivity(RestTimerAttributes.ContentState(restEndsAt: end, setLabel: setLabel, next: next))
        WatchBridge.shared.rest(until: end, next: next, setLabel: setLabel)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.id])
        let seconds = end.timeIntervalSinceNow
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest's up"
        content.body = "\(setLabel): \(next)."
        content.sound = .default
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: Self.id, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        center.add(request)
    }

    func restCancelled() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.id])
        WatchBridge.shared.restCleared()
    }

    func workoutEnded() {
        restCancelled()
        WatchBridge.shared.workoutEnded()
        let ending = activity
        activity = nil
        Task { await ending?.end(nil, dismissalPolicy: .immediate) }
    }

    private func updateActivity(_ state: RestTimerAttributes.ContentState) {
        let content = ActivityContent(state: state, staleDate: state.restEndsAt.addingTimeInterval(10 * 60))
        if let activity {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(attributes: RestTimerAttributes(workoutTitle: "Workout"), content: content)
        }
    }
}

/// Records calls for tests.
@MainActor
final class RecordingRestAlerts: RestAlerting {
    private(set) var started: [(Date, String)] = []
    private(set) var cancelled = 0
    private(set) var ended = 0
    private(set) var workoutsStarted: [String] = []

    func workoutStarted(title: String) { workoutsStarted.append(title) }
    func restStarted(until end: Date, next: String, setLabel: String) { started.append((end, next)) }
    func restCancelled() { cancelled += 1 }
    func workoutEnded() { ended += 1 }
}
