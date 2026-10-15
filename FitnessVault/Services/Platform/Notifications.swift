import Foundation
import UserNotifications

/// Calm, factual local notifications. Starling's own approval notification may or may not
/// arrive, so the app always lets you check pending payments directly.
enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func awaitingApproval(_ amount: Pence) {
        post(id: "payment.approval", body: "\(amount.formatted()) is awaiting approval in Starling.")
    }

    static func paid(_ amount: Pence) {
        post(id: "payment.paid", body: "\(amount.formatted()) has been paid to Monzo.")
    }

    static func vaultCompleted(_ allocation: Pence) {
        post(id: "vault.complete", body: "You've unlocked your full \(allocation.formatted()).")
    }

    static func dailyProgress(_ amount: Pence) {
        post(id: "daily.progress", body: "You've earned \(amount.formatted()) today.")
    }

    private static func post(id: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Fitness Vault"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
