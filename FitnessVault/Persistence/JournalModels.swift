import Foundation
import SwiftData

/// A journal entry: a mood, how you felt, and what you wrote. Linked to a routine item when written from one.
@Model
final class JournalEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var moodRaw: Int
    var feelings: [String]
    var text: String
    /// The question it answered, e.g. "Three wins from today".
    var prompt: String?
    var routineItemID: String?

    init(date: Date, mood: Mood, feelings: [String], text: String, prompt: String? = nil, routineItemID: String? = nil) {
        id = UUID()
        self.date = date
        moodRaw = mood.rawValue
        self.feelings = feelings
        self.text = text
        self.prompt = prompt
        self.routineItemID = routineItemID
    }

    var mood: Mood { Mood(rawValue: moodRaw) ?? .okay }
    var snapshot: JournalSnapshot { JournalSnapshot(date: date, mood: mood, feelings: feelings) }
}
