import Foundation

/// A step-by-step start in progress (C3).
struct LaunchState: Equatable {
    var commitmentID: UUID
    var steps: [String]
    var index: Int
}

extension CoachModel {
    private static let briefingDayKey = "coach.briefing.day"

    // MARK: Morning briefing (B1–B3)

    /// True once "I'm ready" has been said today.
    var hasBriefedToday: Bool { defaults.string(forKey: Self.briefingDayKey) == today.description }

    /// Show the "I'm ready" prompt in the morning until the briefing has happened (B1: never automatic).
    var shouldOfferBriefing: Bool {
        !hasBriefedToday && calendar.component(.hour, from: now()) < 12
    }

    /// Builds today's suggestions as proposals and asks about the first one only.
    func startBriefing() -> CoachReply {
        defaults.set(today.description, forKey: Self.briefingDayKey)
        let input = recommendationInput()
        let recovering: Bool
        if case .recovering = input.recovery { recovering = true } else { recovering = false }
        let plan = RecommendationEngine.morning(input)
        // The plan checker (Phase 8): anything that could never be right is removed and recorded for fixing.
        let issues = PlanAuditor.audit(plan, events: events, settings: coach, day: today, calendar: calendar,
                                       forecast: input.forecast, recovering: recovering)
        for issue in issues { context.insert(PlanAuditRecord(day: today, issue: issue, at: now())) }
        for recommendation in PlanAuditor.filtered(plan, issues: issues) {
            let item = propose(recommendation.title, kind: recommendation.kind, start: recommendation.start,
                               durationMinutes: recommendation.durationMinutes, weight: recommendation.weight,
                               objective: recommendation.objective, reason: recommendation.reason)
            item.detail = recommendation.question
        }
        save()
        reload()

        var opening: [String] = []
        if !needsVerification.isEmpty {
            opening.append("\(needsVerification.count == 1 ? "One thing" : "\(needsVerification.count) things") from earlier need checking on Today.")
        }
        if hasNoWorkCalendar && isWorkdayToday {
            opening.append("I can't see a work calendar, so I'm treating 8 to 4 as work.")
        } else if let meeting = events.first(where: { $0.kind == .workMeeting && $0.event.start > now() }) {
            opening.append("First meeting: \(meeting.event.title) at \(time(meeting.event.start)).")
        }
        if workLocation != .unknown { opening.append(workLocation.title + ".") }
        if let weather = situation?.weatherSummary { opening.append(weather + ".") }
        switch situation?.recoveryStatus(on: today) ?? .clear {
        case .recovering(let feeling):
            opening.append("Recovery day. " + (RecoveryPlanner.guidance(feeling).first ?? ""))
        case .restarting:
            opening.append("First day back. Let's keep it to one easy thing.")
        case .clear:
            break
        }
        if let social = situation?.socialEveningStart(on: today) {
            opening.append("You're out from \(time(social)), so I've kept the evening clear.")
        }
        return nextProposalReply(prefix: opening.joined(separator: " "))
    }

    /// Asks about the next proposal, or wraps up when there are none left.
    func nextProposalReply(prefix: String = "") -> CoachReply {
        let lead = prefix.isEmpty ? "" : prefix + " "
        if let next = proposals.first {
            let question = next.detail ?? "\(next.title)\(next.scheduledStart.map { " at \(time($0))" } ?? "")?"
            let reason = next.reason.map { " \($0)" } ?? ""
            return CoachReply(text: lead + question + reason, quickReplies: ["Yes", "No thanks"], relatedCommitmentID: next.id)
        }
        if let first = currentAction ?? nextCommitment {
            return CoachReply(text: lead + "That's the plan. First up: \(first.title)\(first.scheduledStart.map { " at \(time($0))" } ?? "").",
                              quickReplies: ["Start", "What's next?"])
        }
        return CoachReply(text: lead + "Nothing else to plan. Enjoy the day.")
    }

    func recommendationInput() -> RecommendationInput {
        let all = allCommitments()
        let existing = Set(commitments.filter { $0.state.isApplicable || $0.state == .proposed }.map(\.kind))
        let monday = startOfWeek(today)
        let completedWorkouts = all.filter { $0.kind == .workout && $0.state == .completed }
        let thisWeek = completedWorkouts.filter { item in
            guard let day = item.dayKey else { return false }
            return day >= monday && day < today
        }.count
        var consecutive = 0
        var day = today.adding(days: -1, calendar: calendar)
        while completedWorkouts.contains(where: { $0.day == day.description }) && consecutive < 7 {
            consecutive += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        let last = completedWorkouts.filter { $0.day < today.description }.max { $0.day < $1.day }
        let house = opportunityTasks(minutes: 120).first { $0.area == .houseSale }
        return RecommendationInput(
            day: today, now: now(), calendar: calendar, settings: coach, isWorkday: isWorkdayToday,
            windows: windows, events: events, existingKinds: existing, workoutsThisWeek: thisWeek,
            consecutiveWorkoutDays: consecutive,
            lastWorkoutWasUpper: last.map { $0.title.localizedCaseInsensitiveContains("upper") },
            houseTask: house.map { HouseTaskSuggestion(title: $0.title, minutes: $0.estimatedMinutes) },
            forecast: situation?.forecast ?? [],
            recovery: situation?.recoveryStatus(on: today) ?? .clear,
            gymTravelMinutes: situation?.gymTravelMinutes,
            busyness: situation?.busynessReports() ?? [],
            socialEveningStart: situation?.socialEveningStart(on: today))
    }

    private func startOfWeek(_ day: DayKey) -> DayKey {
        day.adding(days: -(isoWeekday(day) - 1), calendar: calendar)
    }

    // MARK: Replanning (S3, scenario B)

    /// When the calendar changes, anything that now clashes is taken off the score (no fine) and the coach offers
    /// another slot the same day. Only the affected commitments change; the rest of the day is left alone.
    func replanForCalendarChanges() {
        let items = commitments.compactMap { item -> ScheduledItem? in
            guard item.state == .approved || item.state == .proposed,
                  let start = item.scheduledStart, let end = item.scheduledEnd, end > start else { return nil }
            return ScheduledItem(id: item.id, interval: DateInterval(start: start, end: end))
        }
        let conflicts = Replanner.conflicts(items, events: events, now: now())
        for conflict in conflicts {
            guard let item = commitments.first(where: { $0.id == conflict.commitmentID }) else { continue }
            let why = "Clashes with \(conflict.eventTitle) at \(time(conflict.eventStart))"
            let wasAgreed = item.state == .approved
            transition(item, wasAgreed ? .excuse(.calendarConflict) : .cancel, actor: .system, reason: why)

            let physical: Set<CommitmentKind> = [.workout, .walk, .swim]
            var usable = windows
            if physical.contains(item.kind) {
                usable = RecommendationEngine.protectEvenings(usable, day: today, settings: coach, calendar: calendar)
            }
            let need = ActivityNeed(activeMinutes: item.durationMinutes, allowedKinds: item.kind == .walk ? [.free, .lunch] : [.free])
            let summary = wasAgreed ? "Taken off today's score: \(item.title)" : nil
            let lead = "\(conflict.eventTitle) now clashes with \(item.title.lowercased()) at \(item.scheduledStart.map(time) ?? "")."
                + (wasAgreed ? " It won't count against today." : "")

            if let alternative = Replanner.alternative(for: need, in: usable, notBefore: now()) {
                let proposal = propose(item.title, kind: item.kind, start: alternative, durationMinutes: item.durationMinutes,
                                       weight: item.weight, objective: item.objective,
                                       reason: "Moved because of \(conflict.eventTitle).")
                proposal.detail = "\(item.title) at \(time(alternative)) instead?"
                say(CoachReply(text: "\(lead) \(time(alternative)) works instead. Want it?", quickReplies: ["Yes", "No thanks"],
                               toolSummary: summary, relatedCommitmentID: proposal.id))
            } else if item.kind == .workout,
                      let walkStart = Replanner.alternative(for: ActivityNeed(activeMinutes: 30, allowedKinds: [.free, .lunch]),
                                                            in: usable, notBefore: now()) {
                let walk = propose("Walk", kind: .walk, start: walkStart, durationMinutes: 30, objective: .health,
                                   reason: "No room for the gym today now. The session moves to another day this week.")
                walk.detail = "A 30-minute walk at \(time(walkStart)) instead?"
                say(CoachReply(text: "\(lead) There's no room for the full trip today. A 30-minute walk at \(time(walkStart)) instead?",
                               quickReplies: ["Yes", "No thanks"], toolSummary: summary, relatedCommitmentID: walk.id))
            } else {
                say(CoachReply(text: "\(lead) There's no other slot today.", toolSummary: summary))
            }
        }
        if !conflicts.isEmpty { save() }
    }

    // MARK: Reminders (NO1–NO2)

    func reminderPlan() -> [PlannedNotification] {
        let items = commitments.compactMap { item -> NotifiableCommitment? in
            guard let start = item.scheduledStart else { return nil }
            return NotifiableCommitment(id: item.id, title: item.title, kind: item.kind, start: start, state: item.state)
        }
        return NotificationPlanner.plan(items, blocks: CalendarClassifier.blocks(from: events), now: now(),
                                        quietFrom: today.date(atMinute: coach.bedtimeMinute, calendar: calendar),
                                        quietUntil: today.date(atMinute: coach.wakeMinute, calendar: calendar),
                                        office: workLocation == .office)
    }

    /// Sends the plan to iOS only when it changed, so repeated refreshes never duplicate reminders.
    func scheduleReminders() {
        let plan = settings.notificationsEnabled ? reminderPlan() : []
        let signature = plan.map { "\($0.id)@\(Int($0.date.timeIntervalSince1970))" }.joined(separator: "|")
        guard signature != lastReminderSignature else { return }
        lastReminderSignature = signature
        reminders.replace(with: plan)
    }

    // MARK: Launch mode (C3)

    func beginLaunch(for item: Commitment) -> CoachReply {
        let steps = LaunchSteps.steps(for: item.kind)
        launch = LaunchState(commitmentID: item.id, steps: steps, index: 0)
        return CoachReply(text: "Go. \(steps[0])", quickReplies: ["Next step", "I'm in"],
                          toolSummary: "Started: \(item.title)", relatedCommitmentID: item.id)
    }

    func nextLaunchStep() -> CoachReply {
        guard var state = launch else { return whatsNext() }
        state.index += 1
        guard state.index < state.steps.count else {
            launch = nil
            return CoachReply(text: "That's it. You're going. I'll leave you to it.", quickReplies: ["Done"])
        }
        launch = state
        return CoachReply(text: state.steps[state.index], quickReplies: ["Next step", "I'm in"])
    }

    func endLaunch() -> CoachReply {
        launch = nil
        return CoachReply(text: "Good. I'll leave you to it.", quickReplies: ["Done", "Park this"])
    }
}
