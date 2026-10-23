import Foundation
import Observation
import SwiftData

/// Journal entries: written from a routine or any time, with mood and feelings for the trends.
@MainActor
@Observable
final class JournalModel {
    @ObservationIgnored private let container: ModelContainer
    let context: ModelContext
    let calendar: Calendar
    let now: () -> Date

    private(set) var entries: [JournalEntry] = []

    init(container: ModelContainer, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        self.container = container
        context = container.mainContext
        self.calendar = calendar
        self.now = now
        reload()
    }

    var today: DayKey { DayKey(now(), calendar: calendar) }
    var snapshots: [JournalSnapshot] { entries.map(\.snapshot) }

    func reload() {
        let descriptor = FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        entries = (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func add(mood: Mood, feelings: [String], text: String, prompt: String? = nil, routineItemID: String? = nil) -> JournalEntry {
        let entry = JournalEntry(date: now(), mood: mood, feelings: feelings,
                                 text: text.trimmingCharacters(in: .whitespacesAndNewlines), prompt: prompt,
                                 routineItemID: routineItemID)
        context.insert(entry)
        try? context.save()
        reload()
        return entry
    }

    func delete(_ entry: JournalEntry) {
        context.delete(entry)
        try? context.save()
        reload()
    }

    func entries(on day: DayKey) -> [JournalEntry] {
        entries.filter { DayKey($0.date, calendar: calendar) == day }
    }

    var todaysMood: Mood? { entries(on: today).first?.mood }
    var streak: Int { JournalStats.streak(snapshots, today: today, calendar: calendar) }

    func averageMood(lastDays: Int, endingDaysAgo: Int = 0) -> Double? {
        let end = today.adding(days: -endingDaysAgo, calendar: calendar)
        let start = end.adding(days: -(lastDays - 1), calendar: calendar)
        return JournalStats.average(snapshots, from: start, through: end, calendar: calendar)
    }

    func moodSeries(days: Int) -> [(day: DayKey, mood: Double)] {
        JournalStats.dailyMood(snapshots, from: today.adding(days: -(days - 1), calendar: calendar), through: today,
                               calendar: calendar)
    }

    func topFeelings(days: Int, limit: Int = 6) -> [(feeling: String, count: Int)] {
        let start = today.adding(days: -(days - 1), calendar: calendar)
        let recent = snapshots.filter { DayKey($0.date, calendar: calendar) >= start }
        return JournalStats.topFeelings(recent, limit: limit)
    }
}
