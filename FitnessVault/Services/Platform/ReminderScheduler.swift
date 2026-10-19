import Foundation
import UserNotifications

/// Schedules the coach's commitment reminders. Local notifications only (no push on a free developer team).
@MainActor
protocol ReminderScheduling: AnyObject {
    /// Replaces every pending commitment reminder with `plan`.
    func replace(with plan: [PlannedNotification])
}

@MainActor
final class LocalReminderScheduler: ReminderScheduling {
    func replace(with plan: [PlannedNotification]) {
        Task {
            let center = UNUserNotificationCenter.current()
            // Ask at the first moment it matters: when there's an agreed commitment to remind about.
            if !plan.isEmpty, await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            let pending = await center.pendingNotificationRequests()
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(NotificationPlanner.prefix) }
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
