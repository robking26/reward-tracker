import Foundation
import UserNotifications

/// Tells the user when rest is over, even if they've switched to another app between sets (W5).
@MainActor
protocol RestAlerting: AnyObject {
    func restStarted(until end: Date, next: String, setLabel: String)
    func restCancelled()
    func workoutEnded()
}

/// A local notification at the end of each rest. The Live Activity and the watch build on this.
@MainActor
final class LocalRestAlerts: RestAlerting {
    private static let id = "rest.timer"

    func restStarted(until end: Date, next: String, setLabel: String) {
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
    }

    func workoutEnded() {
        restCancelled()
    }
}

/// Records calls for tests.
@MainActor
final class RecordingRestAlerts: RestAlerting {
    private(set) var started: [(Date, String)] = []
    private(set) var cancelled = 0
    private(set) var ended = 0

    func restStarted(until end: Date, next: String, setLabel: String) { started.append((end, next)) }
    func restCancelled() { cancelled += 1 }
    func workoutEnded() { ended += 1 }
}
