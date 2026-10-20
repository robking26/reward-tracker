import Foundation

/// Phase 7: widget actions, the week summary for widgets, and departure and task countdowns.
extension CoachModel {
    /// The widget's Done button (and Siri): completes today's commitment if it's still open.
    @discardableResult
    func complete(_ id: UUID) -> Bool {
        guard let item = commitments.first(where: { $0.id == id }),
              [.approved, .inProgress, .pendingVerification].contains(item.state) else { return false }
        return transition(item, .complete, reason: "Marked done from the widget")
    }

    /// The last seven finished days' scores, oldest first. Nil for a day with nothing scored.
    func weekScores() -> [Int?] {
        (1...7).reversed().map { offset in
            let record = dayRecord(today.adding(days: -offset, calendar: calendar))
            guard let record, record.finalisedAt != nil else { return nil }
            return record.scorePercent
        }
    }

    /// Completed workouts since Monday, today included.
    func workoutsThisWeek() -> Int {
        let monday = today.adding(days: -(isoWeekday(today) - 1), calendar: calendar).description
        let todayKey = today.description
        return allCommitments().filter { item in
            item.kind == .workout && item.state == .completed && item.day >= monday && item.day <= todayKey
        }.count
    }

    /// "Leave for the gym" from 45 minutes before an agreed gym session or swim until it starts.
    /// The commitment's start is the door-to-door start, so it's when to leave.
    func updateDepartureCountdown() {
        let current = now()
        let next = commitments.first { item in
            guard item.state == .approved, [.workout, .swim].contains(item.kind), let start = item.scheduledStart else { return false }
            return current >= start.addingTimeInterval(-45 * 60) && current < start
        }
        guard let next, let start = next.scheduledStart else {
            countdowns.end(.departure, id: nil)
            return
        }
        countdowns.show(.departure, id: next.id.uuidString, title: next.kind == .swim ? "Leave for your swim" : "Leave for the gym",
                        subtitle: next.title, symbol: "car.fill", endsAt: start)
    }

    /// Starting a task shows a countdown for its length; finishing, parking or moving it ends it.
    /// Workouts have their own rest timer instead.
    func updateTaskCountdown(_ item: Commitment, action: CommitmentAction) {
        guard ![.workout, .swim].contains(item.kind) else { return }
        if action == .start {
            let end = now().addingTimeInterval(TimeInterval(max(5, item.durationMinutes) * 60))
            countdowns.show(.task, id: item.id.uuidString, title: item.title,
                            subtitle: "\(item.durationMinutes) minutes", symbol: item.kind.symbol, endsAt: end)
        } else {
            countdowns.end(.task, id: item.id.uuidString)
        }
    }
}
