import Foundation
import HealthKit
import WatchConnectivity

/// Keeps the Apple Watch in step with the workout on the iPhone (W5). The iPhone stays the set logger;
/// the watch shows the rest countdown, taps your wrist when rest is over, and can skip rest or end the session.
@MainActor
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    enum Command: String {
        case skipRest, end
    }

    /// Set by the app: what to do when the watch asks for something.
    var onCommand: ((Command) -> Void)?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func workoutStarted(title: String) {
        send(["active": true, "title": title])
        // Opens the watch app with a strength workout so it keeps running between sets. Best effort:
        // it needs a paired watch with Vaultality installed.
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        HKHealthStore().startWatchApp(with: configuration) { _, _ in }
    }

    func rest(until end: Date, next: String, setLabel: String) {
        send(["active": true, "restEndsAt": end.timeIntervalSince1970, "next": next, "setLabel": setLabel])
    }

    func restCleared() {
        send(["active": true, "restEndsAt": 0])
    }

    func workoutEnded() {
        send(["active": false])
    }

    private func send(_ state: [String: Any]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }
        var payload = state
        payload["sentAt"] = Date.now.timeIntervalSince1970
        try? WCSession.default.updateApplicationContext(payload)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    fileprivate func handle(_ message: [String: Any]) {
        guard let raw = message["command"] as? String, let command = Command(rawValue: raw) else { return }
        onCommand?(command)
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let command = message["command"] as? String
        Task { @MainActor in WatchBridge.shared.handle(["command": command ?? ""]) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let command = userInfo["command"] as? String
        Task { @MainActor in WatchBridge.shared.handle(["command": command ?? ""]) }
    }
}
