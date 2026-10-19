import XCTest
import SwiftData
@testable import FitnessVault

/// A stand-in for the on-device model: runs a script against the real, validated toolbox.
@MainActor
final class FakeLanguageModel: CoachLanguageModel {
    var status: CoachAIStatus = .available
    var calls = 0
    var lastContext = ""
    var script: (String, CoachToolbox) throws -> String

    init(script: @escaping (String, CoachToolbox) throws -> String) {
        self.script = script
    }

    func reply(to message: String, context: String, toolbox: CoachToolbox) async throws -> String {
        calls += 1
        lastContext = context
        return try script(message, toolbox)
    }
}

@MainActor
final class CoachAITests: XCTestCase {
    private var london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    private let monday = DayKey(year: 2026, month: 10, day: 19)

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        monday.startDate(calendar: london).addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    private func make(_ model: FakeLanguageModel?, at date: Date) async -> CoachModel {
        let defaults = UserDefaults(suiteName: "ai.test.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.settings.demoMode = true
        let demo = DemoCalendarService(calendar: london)
        let coach = CoachModel(container: Persistence.makeContainer(inMemory: true), settingsStore: settings,
                               liveCalendar: demo, demoCalendar: demo, defaults: defaults,
                               reminders: RecordingReminderScheduler(), languageModel: model,
                               calendar: london, now: { date })
        await coach.start()
        return coach
    }

    private func send(_ text: String, to coach: CoachModel) async {
        coach.send(text)
        await coach.pendingReply?.value
    }

    func testToolActionsAreReportedFromTheToolboxNotTheModel() async {
        let model = FakeLanguageModel { _, toolbox in
            _ = toolbox.addTask(title: "book the valuation", minutes: 15)
            return "Done, it's on the list."
        }
        let coach = await make(model, at: at(9))
        await send("Can you make sure I book the valuation this week", to: coach)
        XCTAssertEqual(model.calls, 1)
        XCTAssertTrue(coach.activeTasks().contains { $0.title == "Book the valuation" })
        XCTAssertEqual(coach.messages.last?.toolSummary, "Added to your list: Book the valuation")
        XCTAssertFalse(coach.isThinking)
    }

    func testTheModelCanOnlySuggestNeverAgree() async {
        let model = FakeLanguageModel { _, toolbox in
            _ = toolbox.suggestCommitment(title: "Badminton with Becky", kind: "social", startTime: "19:30", minutes: 60)
            return "You're both free tonight. Fancy badminton at 19:30?"
        }
        let coach = await make(model, at: at(17))
        await send("Becky's free tonight, any ideas?", to: coach)
        let suggestion = coach.commitments.first { $0.title == "Badminton with Becky" }
        XCTAssertEqual(suggestion?.state, .proposed, "Nothing counts until the user agrees")
        XCTAssertEqual(coach.messages.last?.quickReplies, ["Yes", "No thanks"])
        coach.send("Yes")
        XCTAssertEqual(suggestion?.state, .approved)
    }

    func testInvalidOrClashingSuggestionsAreRefused() async {
        var results: [String] = []
        let model = FakeLanguageModel { _, toolbox in
            results.append(toolbox.suggestCommitment(title: "Walk", kind: "walk", startTime: "25:99", minutes: 30))
            results.append(toolbox.suggestCommitment(title: "Walk", kind: "walk", startTime: "13:30", minutes: 30))
            results.append(toolbox.suggestCommitment(title: "Walk", kind: "walk", startTime: "07:00", minutes: 30))
            return "Hmm."
        }
        let coach = await make(model, at: at(9))
        await send("Find me a walk", to: coach)
        XCTAssertTrue(results.allSatisfy { $0.hasPrefix("Not done") }, "\(results)")
        XCTAssertTrue(results[1].contains("Focus time"), "Focus blocks are protected")
        XCTAssertTrue(coach.proposals.isEmpty)
        XCTAssertNil(coach.messages.last?.toolSummary)
    }

    func testNotFancyingItCantBeExcusedThroughTheModel() async {
        var result = ""
        let model = FakeLanguageModel { _, toolbox in
            result = toolbox.updateCurrent(action: "excuse", reason: "doesn't fancy it")
            return "OK."
        }
        let coach = await make(model, at: at(16, 50))
        let gym = coach.addCommitment("Gym", kind: .workout, start: at(17), durationMinutes: 100)
        await send("Can you just let me off the gym", to: coach)
        XCTAssertTrue(result.hasPrefix("Not done"))
        XCTAssertEqual(gym.state, .approved)
    }

    func testClaimsWithoutActionsAreFlagged() async {
        let model = FakeLanguageModel { _, _ in "I've added that to your list." }
        let coach = await make(model, at: at(9))
        await send("Remember the bins go out Thursday night", to: coach)
        XCTAssertTrue(coach.messages.last?.text.contains("Nothing was actually changed") ?? false)
    }

    func testKnownCommandsNeverReachTheModel() async {
        let model = FakeLanguageModel { _, _ in "should not happen" }
        let coach = await make(model, at: at(9))
        await send("What's next?", to: coach)
        await send("Put clean the oven on my list", to: coach)
        XCTAssertEqual(model.calls, 0)
    }

    func testWithoutTheModelTheCoachExplainsAndCarriesOn() async {
        let model = FakeLanguageModel { _, _ in "unused" }
        model.status = .unavailable("Apple Intelligence is turned off in Settings")
        let coach = await make(model, at: at(9))
        await send("Find us something to do Friday", to: coach)
        XCTAssertEqual(model.calls, 0)
        XCTAssertTrue(coach.messages.last?.text.contains("Apple Intelligence is turned off") ?? false)
    }

    func testModelErrorsFallBack() async {
        struct Failure: Error {}
        let model = FakeLanguageModel { _, _ in throw Failure() }
        let coach = await make(model, at: at(9))
        await send("Find us something to do Friday", to: coach)
        XCTAssertTrue(coach.messages.last?.text.hasPrefix("The on-device model couldn't answer") ?? false)
        XCTAssertFalse(coach.isThinking)
    }

    func testContextIsSmallAndRelevant() async {
        let model = FakeLanguageModel { _, _ in "Try the chicken traybake." }
        let coach = await make(model, at: at(9))
        await send("What should we have for dinner? Nothing with mushrooms", to: coach)
        XCTAssertTrue(model.lastContext.contains("Mushrooms"), "The food exclusions are relevant")
        XCTAssertFalse(model.lastContext.contains("Darwen"), "Unrelated memories stay out")
        XCTAssertTrue(model.lastContext.contains("Focus time"))
        XCTAssertLessThan(model.lastContext.count, 3_000)
    }
}

final class ToolParsingTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    private let day = DayKey(year: 2026, month: 10, day: 19)

    private func minutes(_ text: String) -> Int? {
        ToolParsing.time(text, on: day, calendar: calendar).map { Int($0.timeIntervalSince(day.startDate(calendar: calendar)) / 60) }
    }

    func testTimes() {
        XCTAssertEqual(minutes("17:30"), 17 * 60 + 30)
        XCTAssertEqual(minutes("5:30pm"), 17 * 60 + 30)
        XCTAssertEqual(minutes("9am"), 9 * 60)
        XCTAssertEqual(minutes("12pm"), 12 * 60)
        XCTAssertNil(minutes("25:99"))
        XCTAssertNil(minutes("soon"))
    }

    func testExcuses() {
        XCTAssertEqual(ToolParsing.excuse("feeling ill"), .illness)
        XCTAssertEqual(ToolParsing.excuse("knee pain"), .injurySymptoms)
        XCTAssertEqual(ToolParsing.excuse("unavoidable meeting"), .calendarConflict)
        XCTAssertNil(ToolParsing.excuse("I will skip it"), "'will' isn't 'ill'")
        XCTAssertNil(ToolParsing.excuse("doesn't fancy it"))
    }

    func testClaimGuard() {
        XCTAssertTrue(ClaimGuard.claimsAChange("I've added it to Friday."))
        XCTAssertFalse(ClaimGuard.claimsAChange("Fancy badminton at 19:30?"))
    }
}
