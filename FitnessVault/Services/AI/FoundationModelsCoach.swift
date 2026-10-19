#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Apple's on-device model (D-006). Free, private, works offline. A fresh session per message keeps the
/// small context window for what matters: the app's summary of today and the few relevant memories.
@available(iOS 26.0, *)
@MainActor
final class FoundationModelsCoach: CoachLanguageModel {
    nonisolated init() {}

    var status: CoachAIStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .unavailable("This iPhone doesn't support Apple Intelligence")
            case .appleIntelligenceNotEnabled: return .unavailable("Apple Intelligence is turned off in Settings")
            case .modelNotReady: return .unavailable("Apple's model is still downloading")
            @unknown default: return .unavailable("Apple's model isn't available right now")
            }
        }
    }

    func reply(to message: String, context: String, toolbox: CoachToolbox) async throws -> String {
        let tools: [any Tool] = [
            AddTaskTool(toolbox: toolbox),
            SuggestCommitmentTool(toolbox: toolbox),
            UpdateCurrentTool(toolbox: toolbox),
            RememberTool(toolbox: toolbox),
            FreeTimeTool(toolbox: toolbox),
            ListTasksTool(toolbox: toolbox),
        ]
        let session = LanguageModelSession(tools: tools, instructions: CoachAI.instructions)
        let prompt = "\(context)\n\nThe user says: \(message)"
        let response = try await session.respond(to: prompt)
        return response.content
    }
}

@available(iOS 26.0, *)
struct AddTaskTool: Tool {
    let toolbox: CoachToolbox
    let name = "addTask"
    let description = "Adds a task to the user's to-do list. Use only when the user asks to add, put or remember a task."

    @Generable
    struct Arguments {
        @Guide(description: "Short task title in sentence case, for example 'Clean the attic'")
        var title: String
        @Guide(description: "Estimated minutes to do it, between 5 and 480")
        var minutes: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.addTask(title: arguments.title, minutes: arguments.minutes)
    }
}

@available(iOS 26.0, *)
struct SuggestCommitmentTool: Tool {
    let toolbox: CoachToolbox
    let name = "suggestCommitment"
    let description = "Suggests something for the user to do today. It only counts if they agree, so ask them afterwards."

    @Generable
    struct Arguments {
        @Guide(description: "What to do, for example 'Walk' or 'Prepare gym kit'")
        var title: String
        @Guide(description: "One of: workout, walk, swim, rehab, household, meal, selfCare, work, social, other")
        var kind: String
        @Guide(description: "Start time today as HH:mm, or empty for any time today")
        var startTime: String
        @Guide(description: "How long in minutes, between 5 and 240")
        var minutes: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.suggestCommitment(title: arguments.title, kind: arguments.kind,
                                        startTime: arguments.startTime, minutes: arguments.minutes)
    }
}

@available(iOS 26.0, *)
struct UpdateCurrentTool: Tool {
    let toolbox: CoachToolbox
    let name = "updateCurrentCommitment"
    let description = "Marks the user's current commitment as done or started, or excuses it for a legitimate reason they gave."

    @Generable
    struct Arguments {
        @Guide(description: "One of: done, start, excuse")
        var action: String
        @Guide(description: "For excuse only: illness, injury, rest, sleep, unavoidable clash or outside control. Otherwise empty.")
        var reason: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.updateCurrent(action: arguments.action, reason: arguments.reason)
    }
}

@available(iOS 26.0, *)
struct RememberTool: Tool {
    let toolbox: CoachToolbox
    let name = "remember"
    let description = "Remembers a lasting fact or preference about the user for future coaching."

    @Generable
    struct Arguments {
        @Guide(description: "Short topic, for example 'Gym' or 'Fridays'")
        var topic: String
        @Guide(description: "The fact in one sentence")
        var fact: String
        @Guide(description: "True only if the user said it directly; false if it's your guess")
        var userSaidIt: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.remember(topic: arguments.topic, fact: arguments.fact, userSaidIt: arguments.userSaidIt)
    }
}

@available(iOS 26.0, *)
struct FreeTimeTool: Tool {
    let toolbox: CoachToolbox
    let name = "findFreeTime"
    let description = "Lists today's free stretches outside work that are at least the given length."

    @Generable
    struct Arguments {
        @Guide(description: "Minimum minutes needed")
        var minutes: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.freeTime(minutes: arguments.minutes)
    }
}

@available(iOS 26.0, *)
struct ListTasksTool: Tool {
    let toolbox: CoachToolbox
    let name = "listTasks"
    let description = "Lists the next few tasks on the user's to-do list, most important first."

    @Generable
    struct Arguments {
        @Guide(description: "Always true")
        var include: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.listTasks()
    }
}
#endif
