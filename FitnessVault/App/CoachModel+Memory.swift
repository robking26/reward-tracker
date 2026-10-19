import Foundation
import SwiftData

extension CoachModel {
    private static let seededKey = "coach.seeded.v1"

    // MARK: Seeding

    /// Loads the brief's facts, the house-sale backlog and suggested (disabled) routines, once.
    func seedIfNeeded() {
        guard !defaults.bool(forKey: Self.seededKey) else { return }
        for fact in SeedProfile.facts {
            context.insert(MemoryRecord(store: fact.store, key: fact.key, value: fact.value, source: .brief,
                                        sensitivity: fact.sensitivity))
        }
        for seed in SeedProfile.routines {
            context.insert(Routine(title: seed.title, kind: seed.kind, weekdays: seed.weekdays, minuteOfDay: seed.minuteOfDay,
                                   durationMinutes: seed.durationMinutes, isEnabled: false, reason: seed.reason))
        }
        for (index, seed) in SeedProfile.houseSale.enumerated() {
            let parent = TaskItem(title: seed.title, area: .houseSale, estimatedMinutes: seed.minutes,
                                  priority: seed.priority, sortIndex: index * 100)
            context.insert(parent)
            var previous: UUID?
            for (step, sub) in seed.subtasks.enumerated() {
                // Each step depends on the one before, so only the next real step is ever suggested.
                let child = TaskItem(title: sub.0, area: .houseSale, parentID: parent.id,
                                     dependsOn: previous.map { [$0] } ?? [], estimatedMinutes: sub.1,
                                     priority: seed.priority, sortIndex: index * 100 + step + 1)
                context.insert(child)
                previous = child.id
            }
        }
        context.insert(CoachMessage(role: .coach,
                                    text: "I'm your coach. I've loaded what you told me in your brief; you can check or change any of it in Settings › Coach memory. Nothing is agreed yet, so nothing can cost you money. Say \"What's next?\" any time.",
                                    quickReplies: ["What's next?"]))
        defaults.set(true, forKey: Self.seededKey)
        save()
    }

    // MARK: Memory (M1–M4)

    func memories(in store: MemoryStore? = nil) -> [MemoryRecord] {
        let all = (try? context.fetch(FetchDescriptor<MemoryRecord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return all.filter { ($0.status != .superseded) && (store == nil || $0.store == store) }
    }

    func remember(_ value: String, key: String, in store: MemoryStore, source: MemorySource = .userStated,
                  sensitivity: Sensitivity = .general) {
        context.insert(MemoryRecord(store: store, key: key, value: value, source: source, sensitivity: sensitivity))
        save()
    }

    /// A correction by the user: the value changes and the record becomes a confirmed, user-stated fact.
    func correct(_ record: MemoryRecord, value: String) {
        record.value = value
        record.sourceRaw = MemorySource.userStated.rawValue
        record.statusRaw = MemoryStatus.confirmed.rawValue
        record.updatedAt = now()
        save()
    }

    func confirm(_ record: MemoryRecord) {
        record.statusRaw = MemoryStatus.confirmed.rawValue
        record.updatedAt = now()
        save()
    }

    func setSensitivity(_ sensitivity: Sensitivity, for record: MemoryRecord) {
        record.sensitivityRaw = sensitivity.rawValue
        record.updatedAt = now()
        save()
    }

    func forget(_ record: MemoryRecord) {
        context.delete(record)
        save()
    }

    // MARK: Tasks (H1–H3)

    func allTasks() -> [TaskItem] {
        (try? context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
    }

    func activeTasks() -> [TaskItem] {
        allTasks().filter { $0.state.isActive }
    }

    func setState(_ state: TaskState, for task: TaskItem) {
        task.state = state
        save()
        reload()
    }

    // MARK: Export and deletion (M4, E3)

    struct Export: Encodable {
        struct Memory: Encodable { var store, key, value, source, status, sensitivity: String; var updatedAt: Date }
        struct CommitmentRow: Encodable {
            var day, title, kind, state: String
            var weight: Int
            var start: Date?
            var excuse, note: String?
        }
        struct Change: Encodable { var commitmentID: UUID; var from, to, actor: String; var reason: String?; var at: Date }
        struct Day: Encodable { var day: String; var score: Int?; var finePence: Int; var simulated: Bool; var explanation: String }
        struct TaskRow: Encodable { var title, area, state: String; var minutes: Int; var note: String? }
        struct Message: Encodable { var role, text: String; var at: Date }

        var exportedAt: Date
        var memories: [Memory]
        var commitments: [CommitmentRow]
        var changes: [Change]
        var days: [Day]
        var tasks: [TaskRow]
        var conversation: [Message]
    }

    /// Everything the coach stores, as JSON in a temporary file for the share sheet.
    func exportCoachData() throws -> URL {
        let events = (try? context.fetch(FetchDescriptor<CommitmentEvent>(sortBy: [SortDescriptor(\.at)]))) ?? []
        let days = (try? context.fetch(FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.day)]))) ?? []
        let export = Export(
            exportedAt: now(),
            memories: memories().map {
                Export.Memory(store: $0.storeRaw, key: $0.key, value: $0.value, source: $0.sourceRaw, status: $0.statusRaw,
                      sensitivity: $0.sensitivityRaw, updatedAt: $0.updatedAt)
            },
            commitments: allCommitments().map {
                Export.CommitmentRow(day: $0.day, title: $0.title, kind: $0.kindRaw, state: $0.stateRaw, weight: $0.weight,
                      start: $0.scheduledStart, excuse: $0.excuseRaw, note: $0.note)
            },
            changes: events.map {
                Export.Change(commitmentID: $0.commitmentID, from: $0.fromRaw, to: $0.toRaw, actor: $0.actorRaw, reason: $0.reason, at: $0.at)
            },
            days: days.map {
                Export.Day(day: $0.day, score: $0.scorePercent, finePence: $0.finePence, simulated: $0.isSimulation,
                      explanation: $0.explanation)
            },
            tasks: allTasks().map {
                Export.TaskRow(title: $0.title, area: $0.areaRaw, state: $0.stateRaw, minutes: $0.estimatedMinutes, note: $0.resumeNote)
            },
            conversation: messages.map { Export.Message(role: $0.roleRaw, text: $0.text, at: $0.createdAt) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vaultality-coach-\(today.description).json")
        try encoder.encode(export).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Deletes the conversation only.
    func deleteConversation() {
        for message in (try? context.fetch(FetchDescriptor<CoachMessage>())) ?? [] { context.delete(message) }
        save()
        reload()
    }

    /// Deletes every coaching record: memory, conversation, commitments and their history, routines, tasks and
    /// day records. Money records (ledger, transfers, payments) are kept because they reflect real bank activity.
    func deleteAllCoachData() {
        func wipe<T: PersistentModel>(_ type: T.Type) {
            for item in (try? context.fetch(FetchDescriptor<T>())) ?? [] { context.delete(item) }
        }
        wipe(MemoryRecord.self)
        wipe(CoachMessage.self)
        wipe(Commitment.self)
        wipe(CommitmentEvent.self)
        wipe(Routine.self)
        wipe(TaskItem.self)
        wipe(DayRecord.self)
        save()
        reload()
    }
}
