import HealthKit
import SwiftUI
import WatchKit

@main
struct FitnessVaultWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environment(WatchWorkoutModel.shared)
        }
    }
}

/// Starting a workout on the iPhone opens this app with a workout configuration (W5).
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in WatchWorkoutModel.shared.activate() }
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in await WatchWorkoutModel.shared.startWorkoutSession() }
    }
}
