import Foundation
import HealthKit
import Observation
import WatchConnectivity
import WatchKit

/// The watch side of a workout: mirrors the iPhone's rest timer, taps your wrist when rest is over, and runs a
/// HealthKit workout session so the app stays awake between sets and the session is saved to Apple Health.
@MainActor
@Observable
final class WatchWorkoutModel: NSObject {
    static let shared = WatchWorkoutModel()

    private(set) var isActive = false
    private(set) var title = "Workout"
    private(set) var setLabel = ""
    private(set) var next = ""
    private(set) var restEndsAt: Date?
    private(set) var isPhoneReachable = false
    private(set) var healthError: String?

    @ObservationIgnored private let health = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var hapticTask: Task<Void, Never>?

    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var isResting: Bool { (restEndsAt ?? .distantPast) > .now }

    // MARK: From the iPhone

    func apply(_ state: [String: Any]) {
        if let active = state["active"] as? Bool {
            if active && !isActive { Task { await startWorkoutSession() } }
            if !active && isActive { Task { await endWorkoutSession() } }
            isActive = active
        }
        if let title = state["title"] as? String { self.title = title }
        if let label = state["setLabel"] as? String { setLabel = label }
        if let next = state["next"] as? String { self.next = next }
        if let seconds = state["restEndsAt"] as? Double {
            restEndsAt = seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
            scheduleRestHaptic()
        }
    }

    /// A firm tap when rest is over, even with the screen down (the workout session keeps the app running).
    private func scheduleRestHaptic() {
        hapticTask?.cancel()
        guard let end = restEndsAt, end > .now else { return }
        hapticTask = Task {
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.notification)
        }
    }

    // MARK: To the iPhone

    func skipRest() {
        restEndsAt = nil
        hapticTask?.cancel()
        send(["command": "skipRest"])
    }

    func endWorkout() {
        send(["command": "end"])
        isActive = false
        restEndsAt = nil
        hapticTask?.cancel()
        Task { await endWorkoutSession() }
    }

    private func send(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(message)
            }
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    // MARK: HealthKit workout session

    func startWorkoutSession() async {
        guard session == nil, HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)],
                                                  read: [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)])
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            let workoutSession = try HKWorkoutSession(healthStore: health, configuration: configuration)
            let workoutBuilder = workoutSession.associatedWorkoutBuilder()
            workoutBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: configuration)
            session = workoutSession
            builder = workoutBuilder
            let start = Date.now
            workoutSession.startActivity(with: start)
            try await workoutBuilder.beginCollection(at: start)
            isActive = true
            healthError = nil
        } catch {
            healthError = "Couldn't start the workout on the watch."
        }
    }

    /// Ending on either device closes the session and saves it to Apple Health (W5).
    func endWorkoutSession() async {
        guard let session, let builder else { return }
        session.end()
        do {
            try await builder.endCollection(at: .now)
            _ = try await builder.finishWorkout()
        } catch {
            healthError = "The workout couldn't be saved to Apple Health."
        }
        self.session = nil
        self.builder = nil
    }
}

extension WatchWorkoutModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        Task { @MainActor in
            WatchWorkoutModel.shared.isPhoneReachable = reachable
            if !context.isEmpty { WatchWorkoutModel.shared.apply(context) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in WatchWorkoutModel.shared.isPhoneReachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let state = applicationContext
        Task { @MainActor in WatchWorkoutModel.shared.apply(state) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let state = message
        Task { @MainActor in WatchWorkoutModel.shared.apply(state) }
    }
}
