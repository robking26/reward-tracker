import Foundation
import SwiftData

// Phase 6 context entities. All new, so existing stores open with lightweight migration.

/// A social plan the user has looked at: from the calendar or added in conversation (SO1–SO2).
@Model
final class SocialPlan {
    @Attribute(.unique) var eventID: String
    var title: String
    var start: Date
    var end: Date
    var kindRaw: String
    var drinkingRaw: String
    var driving: Bool
    var days: Int
    var going: Bool
    var preparedSteps: [String]
    var createdAt: Date

    init(_ detected: DetectedSocial) {
        eventID = detected.eventID
        title = detected.title
        start = detected.start
        end = detected.end
        kindRaw = detected.kind.rawValue
        drinkingRaw = DrinkingPlan.undecided.rawValue
        driving = false
        days = detected.days
        going = !detected.needsConfirmation
        preparedSteps = []
        createdAt = .now
    }

    var kind: SocialKind { SocialKind(rawValue: kindRaw) ?? .other }
    var drinking: DrinkingPlan {
        get { DrinkingPlan(rawValue: drinkingRaw) ?? .undecided }
        set { drinkingRaw = newValue.rawValue }
    }
}

/// Days after a social event (or a rough day the user reported) when the coach eases off (SO3).
/// Kept after it ends only if the user agreed to pattern tracking.
@Model
final class RecoveryPeriod {
    var id: UUID
    var startDay: String
    var days: Int
    var feelingRaw: String?
    var endedDay: String?
    var reason: String
    var createdAt: Date

    init(start: DayKey, days: Int, reason: String) {
        id = UUID()
        startDay = start.description
        self.days = max(1, days)
        self.reason = reason
        createdAt = .now
    }

    var window: RecoveryWindow? {
        DayKey(string: startDay).map { start in
            RecoveryWindow(start: start, days: days, feeling: feelingRaw.flatMap(RecoveryFeeling.init(rawValue:)),
                           endedOn: endedDay.flatMap(DayKey.init(string:)))
        }
    }
}

/// "The gym was busy": the only source of busyness estimates (L3).
@Model
final class GymBusynessRecord {
    var date: Date
    var levelRaw: String

    init(date: Date, level: BusynessLevel) {
        self.date = date
        levelRaw = level.rawValue
    }

    var report: BusynessReport? { BusynessLevel(rawValue: levelRaw).map { BusynessReport(date: date, level: $0) } }
}

/// Outing ideas already offered, so they're spaced out and not repeated (RE1).
@Model
final class OutingSuggestion {
    var ideaID: String
    var day: String
    var accepted: Bool?
    var budget: String?
    var createdAt: Date

    init(ideaID: String, day: DayKey) {
        self.ideaID = ideaID
        self.day = day.description
        createdAt = .now
    }
}
