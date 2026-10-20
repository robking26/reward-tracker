import ActivityKit
import Foundation

/// Time-bounded countdowns on the Lock Screen and in the Dynamic Island (WG2): leaving for the gym,
/// a task you've started, or dinner cooking. Each ends at its time; there's never an all-day activity.
struct CountdownAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
        /// "Upper body at Nuffield", "Ready about 19:05".
        var subtitle: String
    }

    /// `departure`, `task` or `cooking`.
    var kind: String
    var title: String
    var symbol: String
}
