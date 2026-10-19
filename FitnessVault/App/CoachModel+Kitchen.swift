import Foundation

/// Kitchen replies (Phase 4): inventory corrections, the shopping list, tonight's dinner and scenario G.
/// Food never creates a fine (A6), so none of this touches commitments or scoring.
extension CoachModel {
    func ranOut(_ item: String) -> CoachReply {
        guard let kitchen else {
            context.insert(MemoryRecord(store: .inventory, key: item.capitalized, value: "Run out (you said so)", source: .userStated))
            save()
            return CoachReply(text: "Noted: no \(item).", toolSummary: "Remembered: out of \(item)")
        }
        let name = kitchen.markOut(item)
        let listed = kitchen.addToShopping(item)
        return CoachReply(text: "Noted: no \(name.lowercased()). It's on the shopping list.",
                          toolSummary: "Out of \(name); added \(listed) to the list")
    }

    func haveLeft(_ portions: Int?, _ item: String) -> CoachReply {
        guard let kitchen else { return CoachReply(text: "Noted.") }
        let name = kitchen.confirm(item, portions: portions)
        if let portions {
            let text = portions == 0 ? "Got it: no \(name) left." : "Got it: \(DefrostPlanner.portionsText(portions)) of \(name)."
            return CoachReply(text: text, toolSummary: "Freezer: \(name) × \(portions)")
        }
        return CoachReply(text: "Got it, \(name.lowercased()) is in.", toolSummary: "In stock: \(name)")
    }

    func addToShopping(_ item: String) -> CoachReply {
        guard let kitchen else { return addTask("Buy " + item) }
        let name = kitchen.addToShopping(item)
        return CoachReply(text: "\(name) is on the shopping list.", toolSummary: "Shopping list: \(name)")
    }

    func whatsForDinner() -> CoachReply {
        guard let kitchen, let dinner = kitchen.tonight else {
            return CoachReply(text: "Nothing's planned for tonight. Want some easy options?", quickReplies: ["Nothing for dinner"])
        }
        if dinner.portions == 0 { return CoachReply(text: "You're eating out tonight. Enjoy it.") }
        if kitchen.tonightNeedsDefrosting {
            return CoachReply(text: "\(dinner.title) from the freezer. Has it been defrosting in the fridge?",
                              quickReplies: ["It's defrosted", "Forgot to defrost"])
        }
        let recipe = kitchen.recipe(dinner.recipeID)
        let timing = recipe.map { " About \($0.prepMinutes + $0.cookMinutes) minutes, \($0.washUpMinutes) minutes of washing up." } ?? ""
        return CoachReply(text: "\(dinner.title), two portions.\(timing)", quickReplies: ["Nothing for dinner"])
    }

    /// Scenario G: a low-effort alternative based on what's probably in. No lecture, no fine.
    func dinnerRescue(defrostForgotten: Bool) -> CoachReply {
        guard let kitchen else { return CoachReply(text: "Something from the freezer or a simple takeaway is fine tonight.") }
        let options = kitchen.rescueOptions(defrostForgotten: defrostForgotten)
        var text = ""
        if defrostForgotten, let dinner = kitchen.tonight, dinner.fromFreezer {
            text = DefrostPlanner.forgottenAdvice(dinner.title) + " "
        }
        let listed = options.map { "\($0.title): \($0.detail)" }.joined(separator: " Or ")
        text += options.isEmpty ? "Keep it simple tonight." : "Easy options. \(listed)"
        return CoachReply(text: text)
    }

    func markDefrosted() -> CoachReply {
        let candidates = [kitchen?.tonight, kitchen?.dinner(on: today.adding(days: 1, calendar: calendar))].compactMap { $0 }
        guard let kitchen, let dinner = candidates.first(where: { $0.fromFreezer && !$0.defrosted && !$0.cooked }) else {
            return CoachReply(text: "Noted.")
        }
        kitchen.markDefrosted(dinner)
        return CoachReply(text: "Good. \(dinner.title) is sorted. Keep it in the fridge and reheat until piping hot.",
                          toolSummary: "Defrosting: \(dinner.title)")
    }

    /// Adds a routine job as dependent steps (H1): the first step doesn't finish the chain.
    @discardableResult
    func addChain(_ template: ChainTemplate) -> TaskItem {
        let base = (allTasks().map(\.sortIndex).max() ?? 0) + 1
        let parent = TaskItem(title: template.title, area: .household, sortIndex: base)
        context.insert(parent)
        var previous: UUID?
        for (index, step) in template.steps.enumerated() {
            let task = TaskItem(title: step.title, area: .household, parentID: parent.id, dependsOn: previous.map { [$0] } ?? [],
                                estimatedMinutes: step.minutes, priority: 3, sortIndex: base + index + 1)
            context.insert(task)
            previous = task.id
        }
        save()
        return parent
    }
}
