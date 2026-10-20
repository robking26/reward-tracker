import Foundation

/// Phase 6 replies: home or office, gym busyness, social plans and recovery. Recovery is never fined (SO3, A6).
extension CoachModel {
    func setWorkMode(_ mode: WorkLocation) -> CoachReply {
        settingsStore.settings.coach.modeOverride = mode
        settingsStore.settings.coach.modeOverrideDay = today
        refreshCalendar()
        reload()
        let text = mode == .home
            ? "Got it, working from home today. Reminders can make a sound and I'll read replies aloud after voice messages."
            : "Office day. Reminders stay silent and replies stay as text."
        return CoachReply(text: text, toolSummary: "Today: \(mode.title.lowercased())")
    }

    func reportGym(_ level: BusynessLevel) -> CoachReply {
        guard let situation else { return CoachReply(text: "Noted.") }
        situation.reportGym(level)
        let text = level == .busy
            ? "Thanks. I'll remember it was busy at this time and suggest quieter times when I can."
            : "Good to know it's quiet then. I'll favour that time."
        return CoachReply(text: text, toolSummary: "Gym: \(level.rawValue) at \(time(now()))")
    }

    func feelingRough() -> CoachReply {
        guard let situation else { return unwell(.restOrRecovery) }
        if situation.activeRecovery == nil {
            situation.startRecovery(from: today, days: 1, reason: "You said you felt rough")
        }
        situation.setFeeling(.rough)
        // Demanding things today come off the score, with no fine (SO3).
        var excused: [String] = []
        for item in commitments where item.state == .approved && [.workout, .swim].contains(item.kind) {
            if transition(item, .excuse(.restOrRecovery), reason: "Recovery day") { excused.append(item.title) }
        }
        var text = RecoveryPlanner.guidance(.rough).joined(separator: " ")
        if !excused.isEmpty { text = "\(excused.joined(separator: " and ")) is off today, with no fine. " + text }
        return CoachReply(text: text, quickReplies: ["Back to normal"], toolSummary: "Recovery day")
    }

    func backToNormal() -> CoachReply {
        guard let situation, situation.activeRecovery != nil else { return CoachReply(text: "Glad to hear it.") }
        situation.setFeeling(.normal)
        return startBriefing()
    }

    func goingOut() -> CoachReply {
        guard let situation else { return CoachReply(text: "Have a good night.") }
        situation.addTonight()
        return CoachReply(text: "Have a good night. Want a plan for drinks? Deciding beforehand makes it easier.",
                          quickReplies: ["Alcohol-free", "Lighter", "Moderate", "Not decided"])
    }

    func chooseDrinkingPlan(_ drinking: DrinkingPlan) -> CoachReply {
        guard let situation else { return CoachReply(text: "Noted.") }
        let horizon = now().addingTimeInterval(36 * 3600)
        guard let plan = situation.plans.first(where: { $0.going && $0.end > now() && $0.start < horizon }) else {
            return CoachReply(text: "Noted. Tell me when you're going out and I'll plan around it.")
        }
        situation.save(plan, drinking: drinking, driving: plan.driving, going: true)
        let steps = SocialPlanner.preparation(plan: drinking, eventDays: plan.days, nextDayHasWorkout: false)
        var lines = SocialPlanner.advice(kind: plan.kind, plan: drinking, driving: plan.driving, eventDays: plan.days)
        if let recovery = steps.first(where: { $0.action == .planRecovery }) {
            lines.append(situation.prepare(recovery, for: plan))
        }
        if steps.contains(where: { $0.action == .freezerMealNextDay }) {
            lines.append("Want a freezer meal on for tomorrow? It's on the social card on Today.")
        }
        return CoachReply(text: "\(drinking.title). " + lines.joined(separator: " "), toolSummary: "Plan: \(drinking.title.lowercased())")
    }
}
