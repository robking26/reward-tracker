import Foundation

/// How a day felt, from awful to great.
enum Mood: Int, Codable, CaseIterable, Sendable, Identifiable {
    case awful = 1, low, okay, good, great

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .awful: "Awful"
        case .low: "Low"
        case .okay: "Okay"
        case .good: "Good"
        case .great: "Great"
        }
    }

    var symbol: String {
        switch self {
        case .awful: "cloud.bolt.rain.fill"
        case .low: "cloud.rain.fill"
        case .okay: "cloud.fill"
        case .good: "cloud.sun.fill"
        case .great: "sun.max.fill"
        }
    }
}

enum JournalFeelings {
    static let all = ["Calm", "Grateful", "Energised", "Focused", "Happy", "Proud",
                      "Tired", "Stressed", "Anxious", "Sore", "Frustrated", "Flat"]
}

/// A journal entry reduced to what the trends need.
struct JournalSnapshot: Hashable, Sendable {
    var date: Date
    var mood: Mood
    var feelings: [String]
}

enum JournalStats {
    /// The average mood for each day that has an entry, oldest first.
    static func dailyMood(_ entries: [JournalSnapshot], from start: DayKey, through end: DayKey,
                          calendar: Calendar) -> [(day: DayKey, mood: Double)] {
        let grouped = Dictionary(grouping: entries) { DayKey($0.date, calendar: calendar) }
        return grouped.keys.filter { $0 >= start && $0 <= end }.sorted().map { day in
            let moods = (grouped[day] ?? []).map { Double($0.mood.rawValue) }
            return (day, moods.reduce(0, +) / Double(max(moods.count, 1)))
        }
    }

    static func average(_ entries: [JournalSnapshot], from start: DayKey, through end: DayKey, calendar: Calendar) -> Double? {
        let moods = entries.filter { entry in
            let day = DayKey(entry.date, calendar: calendar)
            return day >= start && day <= end
        }.map { Double($0.mood.rawValue) }
        guard !moods.isEmpty else { return nil }
        return moods.reduce(0, +) / Double(moods.count)
    }

    /// The feelings that come up most, most common first, ties alphabetical.
    static func topFeelings(_ entries: [JournalSnapshot], limit: Int = 5) -> [(feeling: String, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in entries { for feeling in entry.feelings { counts[feeling, default: 0] += 1 } }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit).map { ($0.key, $0.value) }
    }

    /// Days in a row with at least one entry, counting back from today (or yesterday, if today has none yet).
    static func streak(_ entries: [JournalSnapshot], today: DayKey, calendar: Calendar) -> Int {
        let days = Set(entries.map { DayKey($0.date, calendar: calendar) })
        var day = days.contains(today) ? today : today.adding(days: -1, calendar: calendar)
        var count = 0
        while days.contains(day) {
            count += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        return count
    }
}
