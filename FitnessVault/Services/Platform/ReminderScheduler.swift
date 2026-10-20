import Foundation
import UserNotifications

/// A local notification the app intends to schedule. Pure data, so plans can be unit tested.
struct PlannedNotification: Hashable, Sendable {
    var id: String
    var date: Date
    var body: String
    /// No sound, delivered quietly.
    var isDiscreet: Bool
}

/// Schedules the kitchen's defrost and slow-cooker reminders. Local notifications only (no push on a free team).
@MainActor
protocol ReminderScheduling: AnyObject {
    /// Replaces every pending reminder with this scheduler's prefix with `plan`.
    func replace(with plan: [PlannedNotification])
}

@MainActor
final class LocalReminderScheduler: ReminderScheduling {
    /// Only pending reminders with this prefix are replaced, so other notifications are never cleared.
    private let prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }

    func replace(with plan: [PlannedNotification]) {
        let prefix = self.prefix
        Task {
            let center = UNUserNotificationCenter.current()
            // Ask at the first moment it matters: when there's something to remind about.
            if !plan.isEmpty, await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            let pending = await center.pendingNotificationRequests()
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            for item in plan {
                let content = UNMutableNotificationContent()
                content.title = "Vaultality"
                content.body = item.body
                content.sound = item.isDiscreet ? nil : .default
                content.interruptionLevel = item.isDiscreet ? .passive : .active
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }
}

/// Records plans instead of scheduling them, for tests and previews.
@MainActor
final class RecordingReminderScheduler: ReminderScheduling {
    private(set) var plans: [[PlannedNotification]] = []
    var latest: [PlannedNotification] { plans.last ?? [] }

    func replace(with plan: [PlannedNotification]) {
        plans.append(plan)
    }
}
