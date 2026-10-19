import Foundation

extension CoachModel {
    var aiStatus: CoachAIStatus {
        languageModel?.status ?? .unavailable("Needs iOS 26 and Apple Intelligence")
    }

    /// Writes the reply with the on-device model. What changed is reported from the toolbox, never from the
    /// model's own words; if the model claims a change that didn't happen, the reply says so (N3, AI3).
    func replyWithModel(_ text: String, model: CoachLanguageModel) async {
        let toolbox = CoachToolbox(coach: self)
        do {
            var answer = try await model.reply(to: text, context: aiContext(for: text), toolbox: toolbox)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if answer.isEmpty { answer = "I'm not sure. Try asking another way." }
            if answer.count > 700 { answer = String(answer.prefix(700)) + "…" }
            if toolbox.performed.isEmpty && ClaimGuard.claimsAChange(answer) {
                answer += "\n\n(Nothing was actually changed.)"
            }
            reload()
            say(CoachReply(text: answer, quickReplies: toolbox.suggestedReplies,
                           toolSummary: toolbox.performed.isEmpty ? nil : toolbox.performed.joined(separator: " · ")))
        } catch {
            var fallback = respond(to: text)
            fallback.text = "The on-device model couldn't answer that just now. " + fallback.text
            if !toolbox.performed.isEmpty { fallback.toolSummary = toolbox.performed.joined(separator: " · ") }
            say(fallback)
        }
        isThinking = false
        pendingReply = nil
    }

    /// A compact picture of today plus the few memories relevant to this message. The on-device model's context
    /// is small, so this never includes everything the coach knows (M1).
    func aiContext(for message: String) -> String {
        var lines: [String] = []
        let day = now().formatted(.dateTime.weekday(.wide).day().month(.wide))
        let place = workLocation != .unknown ? workLocation.title : (isWorkdayToday ? "A workday" : "A day off")
        lines.append("Now: \(day), \(time(now())). \(place).")

        let items = commitments.filter { $0.state != .cancelled && $0.state != .rescheduled }
        if items.isEmpty {
            lines.append("Nothing agreed today.")
        } else {
            lines.append("Today's commitments: " + items.map { item in
                "\(item.scheduledStart.map { time($0) } ?? "any time") \(item.title) (\(item.state.title.lowercased()))"
            }.joined(separator: "; ") + ".")
        }
        if let current = currentAction { lines.append("Current: \(current.title).") }

        let timed = events.filter { !$0.event.isAllDay }.prefix(8)
        if !timed.isEmpty {
            lines.append("Calendar: " + timed.map { "\(time($0.event.start))–\(time($0.event.end)) \($0.event.title) (\($0.kind.label.lowercased()))" }
                .joined(separator: "; ") + ".")
        }
        let free = windows.filter { $0.kind != .workGap && $0.minutes >= 15 }.prefix(4)
        if !free.isEmpty {
            lines.append("Free outside work: " + free.map { "\(time($0.interval.start))–\(time($0.interval.end))" }.joined(separator: ", ") + ".")
        }
        if let confirmed = projection.score.confirmedPercent, let possible = projection.score.possiblePercent {
            lines.append("Done so far: \(confirmed)% (up to \(possible)%).")
        }

        let memoryItems = memories().map { MemoryItem(store: $0.store, key: $0.key, value: $0.value, status: $0.status) }
        let relevant = MemoryRetriever.relevant(memoryItems, to: message, limit: 6)
        if !relevant.isEmpty {
            lines.append("What you know about the user:")
            for item in relevant {
                let value = item.value.count > 160 ? String(item.value.prefix(160)) + "…" : item.value
                lines.append("- \(item.key): \(value)\(item.status == .hypothesis ? " (a guess, unconfirmed)" : "")")
            }
        }

        let recent = messages.dropLast().suffix(6)
        if !recent.isEmpty {
            lines.append("Recent conversation:")
            for message in recent {
                let text = message.text.count > 200 ? String(message.text.prefix(200)) + "…" : message.text
                lines.append("\(message.role == .user ? "User" : "Coach"): \(text)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
