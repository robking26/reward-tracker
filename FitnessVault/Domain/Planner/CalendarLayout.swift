import Foundation

/// Something with a time span to place on an hour-by-hour calendar.
struct CalendarSlot: Hashable, Sendable {
    var id: String
    var start: Date
    var end: Date
}

/// Which column an item sits in, and how many columns its overlapping group shares.
struct CalendarColumn: Hashable, Sendable {
    var column: Int
    var count: Int
}

enum CalendarLayout {
    /// Overlapping items sit side by side, like a calendar app: each group of overlaps shares the width, and an item
    /// takes the first column that's free when it starts.
    static func columns(_ slots: [CalendarSlot]) -> [String: CalendarColumn] {
        let sorted = slots.sorted { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }
        var result: [String: CalendarColumn] = [:]
        var group: [(slot: CalendarSlot, column: Int)] = []
        var groupEnd = Date.distantPast

        func close() {
            let count = (group.map { $0.column }.max() ?? 0) + 1
            for member in group { result[member.slot.id] = CalendarColumn(column: member.column, count: count) }
            group = []
        }

        for slot in sorted {
            if slot.start >= groupEnd { close() }
            var column = 0
            while group.contains(where: { $0.column == column && $0.slot.end > slot.start }) { column += 1 }
            group.append((slot, column))
            groupEnd = max(groupEnd, slot.end)
        }
        close()
        return result
    }
}
