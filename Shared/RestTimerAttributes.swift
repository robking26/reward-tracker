import ActivityKit
import Foundation

/// The rest-timer Live Activity (WG2): shown on the Lock Screen and in the Dynamic Island during a workout.
/// Time-bounded: it starts with the first rest and ends with the workout.
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var restEndsAt: Date
        /// "Set 2 of 3" or "Next exercise".
        var setLabel: String
        /// The exercise coming up.
        var next: String
    }

    var workoutTitle: String
}
