import Foundation

/// A coach reply: short text, at most a few quick replies, and a record of what the app actually did (N3).
struct CoachReply: Equatable {
    var text: String
    var quickReplies: [String] = []
    /// Shown under the reply. Only set after the change has been saved.
    var toolSummary: String? = nil
    var relatedCommitmentID: UUID? = nil
}

extension CoachModel {
    /// Handles a message from the user: records it, acts on it through the same functions the Today screen uses,
    /// and records the reply. Works with no language model (scenario N).
    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        context.insert(CoachMessage(role: .user, text: text))
        // Known commands are handled by rules, instantly and offline. Anything else goes to the on-device model.
        if case .unknown = CoachIntentParser.parse(text), awaitingResumeNote == nil,
           let model = languageModel, model.status.isAvailable {
            save()
            reload()
            isThinking = true
            pendingReply = Task { await self.replyWithModel(text, model: model) }
            return
        }
        let reply = respond(to: text)
        context.insert(CoachMessage(role: .coach, text: reply.text, quickReplies: reply.quickReplies,
                                    relatedCommitmentID: reply.relatedCommitmentID, toolSummary: reply.toolSummary))
        save()
        reload()
    }

    /// Adds a coach message without user input, e.g. after a quick action on Today.
    func say(_ reply: CoachReply) {
        context.insert(CoachMessage(role: .coach, text: reply.text, quickReplies: reply.quickReplies,
                                    relatedCommitmentID: reply.relatedCommitmentID, toolSummary: reply.toolSummary))
        save()
        reload()
    }

    func respond(to text: String) -> CoachReply {
        // A pending "where have you got to?" takes the next free-text message as the note (C4).
        if let id = awaitingResumeNote, case .unknown = CoachIntentParser.parse(text) {
            awaitingResumeNote = nil
            return saveResumeNote(text, for: id)
        }
        awaitingResumeNote = nil

        switch CoachIntentParser.parse(text) {
        case .whatsNext: return whatsNext()
        case .ready: return hasBriefedToday ? (proposals.isEmpty ? whatsNext() : nextProposalReply()) : startBriefing()
        case .nextStep: return nextLaunchStep()
        case .imIn: return endLaunch()
        case .done: return markCurrentDone()
        case .start: return startCurrent()
        case .notNow: return notNow()
        case .moveLater(let minutes): return moveCurrent(to: now().addingTimeInterval(TimeInterval(minutes * 60)))
        case .moveToEvening: return moveCurrentToEvening()
        case .blocked: return blocked()
        case .unavoidable: return excuseCurrent(.calendarConflict)
        case .unwell(let reason): return unwell(reason)
        case .dontFancy: return challenge()
        case .park: return park()
        case .back: return resume()
        case .bored: return bored()
        case .yes: return acceptProposal()
        case .no: return declineProposal()
        case .addTask(let title): return addTask(title)
        case .ranOut(let item): return ranOut(item)
        case .unknown:
            let why = aiStatus.isAvailable ? "" : " (\(aiStatus.title), so I'm on simple commands only)"
            return CoachReply(text: "I can't do that one\(why). I can tell you what's next, mark things done, move or excuse a commitment, park and resume, and add things to your list.",
                              quickReplies: ["What's next?", "Done"])
        }
    }

    // MARK: Intents

    func whatsNext() -> CoachReply {
        if let current = currentAction {
            let when = current.scheduledStart.map { $0 <= now() ? "now" : "at \(time($0))" } ?? "today"
            var text = "\(current.title), \(when)."
            if let reason = current.reason, current.state == .approved { text += " \(reason)" }
            return CoachReply(text: text, quickReplies: current.state == .inProgress ? ["Done", "Park this"] : ["Start", "Done", "Not now"],
                              relatedCommitmentID: current.id)
        }
        if let proposal = proposals.first {
            return CoachReply(text: "\(proposal.title)\(proposal.scheduledStart.map { " at \(time($0))" } ?? "")? \(proposal.reason ?? "")",
                              quickReplies: ["Yes", "No thanks"], relatedCommitmentID: proposal.id)
        }
        if let window = nextOpportunity {
            let options = opportunityTasks(minutes: window.minutes).map(\.title)
            if !options.isEmpty {
                return CoachReply(text: "Nothing agreed right now. You've got \(window.minutes) minutes from \(time(window.interval.start)). Pick one: \(options.joined(separator: ", ")). Or rest; that's allowed too.",
                                  quickReplies: Array(options.prefix(3)))
            }
            return CoachReply(text: "Nothing agreed right now, and you've got time from \(time(window.interval.start)). Rest counts.")
        }
        return CoachReply(text: "Nothing else agreed today. Protect your evening.")
    }

    func markCurrentDone() -> CoachReply {
        guard let current = currentAction else {
            return CoachReply(text: "There's nothing open to mark done. Want to add something?", quickReplies: ["What's next?"])
        }
        guard transition(current, .complete) else { return failure() }
        let next = currentAction
        let score = projection.score.confirmedPercent.map { " You're on \($0)% so far." } ?? ""
        let text = "Done: \(current.title).\(score)" + (next.map { " Next: \($0.title)." } ?? "")
        return CoachReply(text: text, quickReplies: next == nil ? [] : ["Start", "What's next?"],
                          toolSummary: "Marked done: \(current.title)", relatedCommitmentID: current.id)
    }

    func startCurrent() -> CoachReply {
        guard let current = currentAction else { return whatsNext() }
        if current.state == .inProgress {
            return CoachReply(text: "You're already on \(current.title). Tell me when it's done.", quickReplies: ["Done", "Park this"])
        }
        guard transition(current, .start) else { return failure() }
        return beginLaunch(for: current)
    }

    func notNow() -> CoachReply {
        guard let current = currentAction else { return whatsNext() }
        return CoachReply(text: "When, then? Later today keeps it on track. Moving it to another day needs a real reason.",
                          quickReplies: ["In an hour", "This evening", "Something's blocking me"], relatedCommitmentID: current.id)
    }

    func moveCurrent(to date: Date) -> CoachReply {
        guard let current = currentAction else { return whatsNext() }
        guard let moved = reschedule(current, to: date) else {
            return CoachReply(text: lastError ?? "I couldn't move that.", quickReplies: ["Something's blocking me"])
        }
        return CoachReply(text: "Moved to \(time(date)). I'll hold you to it.",
                          toolSummary: "Moved: \(moved.title) → \(time(date))", relatedCommitmentID: moved.id)
    }

    func moveCurrentToEvening() -> CoachReply {
        let evening = today.startDate(calendar: calendar).addingTimeInterval(TimeInterval(max(coach.workEndMinute + 60, 18 * 60) * 60))
        guard evening > now() else {
            return CoachReply(text: "It's already evening. Do it now, or tell me what's blocking you.", quickReplies: ["Start", "Something's blocking me"])
        }
        return moveCurrent(to: evening)
    }

    func blocked() -> CoachReply {
        CoachReply(text: "What's in the way?",
                   quickReplies: ["I'm ill", "My knee hurts", "Something unavoidable came up", "I don't fancy it"],
                   relatedCommitmentID: currentAction?.id)
    }

    func excuseCurrent(_ reason: ExcuseReason) -> CoachReply {
        guard let current = currentAction else {
            return CoachReply(text: "Nothing's agreed right now, so there's nothing to excuse.")
        }
        guard transition(current, .excuse(reason), reason: reason.title) else { return failure() }
        return CoachReply(text: "Fair enough. \(current.title) won't count against today. Want me to find another slot?",
                          quickReplies: ["What's next?"], toolSummary: "Excused: \(current.title) (\(reason.title))",
                          relatedCommitmentID: current.id)
    }

    /// Illness, injury or exhaustion: physical commitments today are excused, never fined (A6, scenario O).
    func unwell(_ reason: ExcuseReason) -> CoachReply {
        let physical: Set<CommitmentKind> = reason == .injurySymptoms ? [.workout, .swim, .walk] : [.workout, .swim, .walk, .rehab]
        let affected = commitments.filter { $0.state.isOpen && physical.contains($0.kind) }
        for item in affected { transition(item, .excuse(reason), reason: reason.title) }
        let summary = affected.isEmpty ? nil : "Excused today: " + affected.map(\.title).joined(separator: ", ")
        switch reason {
        case .injurySymptoms:
            return CoachReply(text: "Stop anything that provokes it. If the pain is sharp, there's swelling, or it's worse tomorrow, book your physio. Note how it feels in the morning too; next-day pain matters. Nothing physical counts against today.",
                              toolSummary: summary)
        case .illness:
            return CoachReply(text: "Rest, fluids, normal meals. No fines for being ill. Tell me when you're back on your feet and we'll restart with one easy thing.",
                              toolSummary: summary)
        default:
            return CoachReply(text: "Take it easy today. Rest is part of the plan, not a failure of it.", toolSummary: summary)
        }
    }

    /// Avoidance gets a firm, respectful challenge and a minimum version (C2, scenario C). It's never excused.
    func challenge() -> CoachReply {
        guard let current = currentAction else {
            return CoachReply(text: "Then don't. Nothing's agreed right now.")
        }
        return CoachReply(text: "You agreed to \(current.title.lowercased()). Is there a real blocker, or is it just starting that's hard? If it's starting, do ten minutes and decide after.",
                          quickReplies: ["Start", "Something's blocking me"], relatedCommitmentID: current.id)
    }

    func park() -> CoachReply {
        if let current = currentAction, current.state == .inProgress {
            awaitingResumeNote = current.id
            return CoachReply(text: "Parked. Where have you got to?", relatedCommitmentID: current.id)
        }
        if let task = activeTasks().first(where: { $0.state == .inProgress }) {
            task.state = .parked
            awaitingResumeNote = task.id
            save()
            return CoachReply(text: "Parked \(task.title). Where have you got to?", toolSummary: "Parked: \(task.title)")
        }
        return CoachReply(text: "Nothing's in progress to park.")
    }

    func saveResumeNote(_ note: String, for id: UUID) -> CoachReply {
        if let item = allCommitments().first(where: { $0.id == id }) {
            item.note = note
            item.updatedAt = now()
            save()
            return CoachReply(text: "Got it. I'll remind you when you're back.", toolSummary: "Note saved on \(item.title)")
        }
        if let task = allTasks().first(where: { $0.id == id }) {
            task.resumeNote = note
            task.updatedAt = now()
            save()
            return CoachReply(text: "Got it. I'll remind you when you're back.", toolSummary: "Note saved on \(task.title)")
        }
        return CoachReply(text: "I couldn't find what you parked, so I didn't save that.")
    }

    func resume() -> CoachReply {
        if let current = currentAction, let note = current.note, !note.isEmpty {
            return CoachReply(text: "You're back on \(current.title). Where you got to: \(note)", quickReplies: ["Start"],
                              relatedCommitmentID: current.id)
        }
        if let task = activeTasks().filter({ $0.state == .parked }).max(by: { $0.updatedAt < $1.updatedAt }) {
            let note = task.resumeNote.map { " Where you got to: \($0)" } ?? ""
            return CoachReply(text: "You're back on \(task.title).\(note)", quickReplies: ["Start"])
        }
        return whatsNext()
    }

    func bored() -> CoachReply {
        let minutes = nextOpportunity?.minutes ?? 30
        let options = opportunityTasks(minutes: minutes)
        guard !options.isEmpty else { return whatsNext() }
        return CoachReply(text: "Pick one: " + options.map { "\($0.title) (\($0.estimatedMinutes) min)" }.joined(separator: ", ") + ".",
                          quickReplies: options.map(\.title))
    }

    func acceptProposal() -> CoachReply {
        guard let proposal = proposals.first else { return whatsNext() }
        guard transition(proposal, .approve) else { return failure() }
        // One at a time (B3): agree, then ask about the next suggestion.
        var reply = nextProposalReply(prefix: "Agreed.")
        reply.toolSummary = "Committed: \(proposal.title)"
        return reply
    }

    func declineProposal() -> CoachReply {
        guard let proposal = proposals.first else { return CoachReply(text: "OK.") }
        guard transition(proposal, .cancel, reason: "Declined") else { return failure() }
        var reply = nextProposalReply(prefix: "No problem.")
        reply.toolSummary = "Not on the plan: \(proposal.title)"
        return reply
    }

    func addTask(_ title: String) -> CoachReply {
        let cleaned = title.prefix(1).uppercased() + title.dropFirst()
        let area = SeedProfile.area(forTask: cleaned)
        let task = TaskItem(title: cleaned, area: area, sortIndex: (allTasks().map(\.sortIndex).max() ?? 0) + 1)
        context.insert(task)
        save()
        return CoachReply(text: "On the list under \(area.title.lowercased()). I'll bring it up when there's a good gap.",
                          toolSummary: "Added to your list: \(cleaned)")
    }

    func ranOut(_ item: String) -> CoachReply {
        let record = MemoryRecord(store: .inventory, key: item.capitalized, value: "Run out (you said so)", source: .userStated)
        context.insert(record)
        save()
        return CoachReply(text: "Noted: no \(item). Shopping lists arrive in a later update, and this will be on it.",
                          toolSummary: "Remembered: out of \(item)")
    }

    // MARK: Helpers

    /// Small backlog tasks that fit a gap, highest priority first (H3). At most three.
    func opportunityTasks(minutes: Int) -> [TaskItem] {
        let done = Set(allTasks().filter { $0.state == .done }.map(\.id.uuidString))
        let parents = Set(allTasks().compactMap(\.parentID))
        return activeTasks()
            .filter { $0.state == .open && !parents.contains($0.id) && $0.estimatedMinutes <= max(5, minutes - 5) }
            .filter { $0.dependsOn.allSatisfy(done.contains) }
            .sorted { ($0.priority, -$0.sortIndex) > ($1.priority, -$1.sortIndex) }
            .prefix(3)
            .map { $0 }
    }

    func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func failure() -> CoachReply {
        CoachReply(text: lastError ?? "That didn't work, so nothing changed.")
    }
}
