import Foundation
import SwiftData

/// One morning or night routine on one day: where you were, what you ticked and when it was all done.
/// Kept in the store because a missed home routine changes that day's earnings.
@Model
final class RoutineLog {
    /// "<day>|<part>", e.g. "2026-11-02|evening".
    @Attribute(.unique) var id: String
    var day: String
    var partRaw: String
    var placeRaw: String
    var tickedIDs: [String]
    var completedAt: Date?
    var updatedAt: Date

    init(day: DayKey, part: RoutinePart) {
        id = Self.id(day: day, part: part)
        self.day = day.description
        partRaw = part.rawValue
        placeRaw = RoutinePlace.home.rawValue
        tickedIDs = []
        updatedAt = .now
    }

    static func id(day: DayKey, part: RoutinePart) -> String { "\(day.description)|\(part.rawValue)" }

    var record: RoutineRecord? {
        guard let dayKey = DayKey(string: day), let part = RoutinePart(rawValue: partRaw) else { return nil }
        return RoutineRecord(day: dayKey, part: part, place: RoutinePlace(rawValue: placeRaw) ?? .home,
                             ticked: Set(tickedIDs), completedAt: completedAt)
    }
}
