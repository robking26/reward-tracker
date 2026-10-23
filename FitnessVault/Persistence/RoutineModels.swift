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
    /// The version and times worked out while it was open; optional so earlier logs still load.
    var daysRaw: String?
    var windowStart: Date?
    var windowEnd: Date?
    /// You chose home or away yourself, so the 8:30 pm check leaves it alone.
    var placeSetByUser: Bool?
    /// Switched to away because you weren't home by 8:30 pm.
    var autoAway: Bool?
    /// Home day or office day, for a weekday morning's extras.
    var workRaw: String?

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
        var window: DateInterval?
        if let windowStart, let windowEnd, windowEnd > windowStart { window = DateInterval(start: windowStart, end: windowEnd) }
        return RoutineRecord(day: dayKey, part: part, place: RoutinePlace(rawValue: placeRaw) ?? .home,
                             ticked: Set(tickedIDs), completedAt: completedAt,
                             days: daysRaw.flatMap(RoutineDays.init(rawValue:)), window: window,
                             work: workRaw.flatMap(RoutineWorkDay.init(rawValue:)))
    }
}
