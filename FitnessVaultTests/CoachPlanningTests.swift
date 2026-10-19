import XCTest
import SwiftData
@testable import FitnessVault

@MainActor
final class CoachPlanningTests: XCTestCase {
    private var london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private let monday = DayKey(year: 2026, month: 10, day: 19)

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        monday.startDate(calendar: london).addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    private struct Harness {
        var coach: CoachModel
        var calendar: DemoCalendarService
        var reminders: RecordingReminderScheduler
        var clock: TestClock
    }

    private func make(at date: Date) async -> Harness {
        let clock = TestClock(date)
        let defaults = UserDefaults(suiteName: "planning.test.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.settings.demoMode = true
        let demo = DemoCalendarService(calendar: london)
        let reminders = RecordingReminderScheduler()
        let coach = CoachModel(container: Persistence.makeContainer(inMemory: true), settingsStore: settings,
                               liveCalendar: demo, demoCalendar: demo, defaults: defaults, reminders: reminders, languageModel: nil,
                               calendar: london, now: { clock.date })
        await coach.start()
        return Harness(coach: coach, calendar: demo, reminders: reminders, clock: clock)
    }

    func testBriefingOffersOneThingAtATime() async {
        // Scenario A.
        let h = await make(at: at(6, 30))
        let coach = h.coach
        XCTAssertTrue(coach.shouldOfferBriefing)
        coach.send("I'm ready")
        XCTAssertFalse(coach.shouldOfferBriefing, "The briefing runs once a day, and only when asked")
        XCTAssertEqual(coach.proposals.map(\.kind), [.walk, .workout, .selfCare])
        XCTAssertTrue(coach.commitments.allSatisfy { $0.state == .proposed }, "Nothing counts until agreed")
        XCTAssertEqual(coach.messages.last?.relatedCommitmentID, coach.proposals.first?.id)
        XCTAssertEqual(coach.messages.last?.quickReplies, ["Yes", "No thanks"])

        let gymID = coach.proposals[1].id
        coach.send("Yes")
        XCTAssertEqual(coach.messages.last?.relatedCommitmentID, gymID, "Agreeing moves on to the next question")
        coach.send("No thanks")
        coach.send("Yes")
        XCTAssertTrue(coach.messages.last?.text.contains("That's the plan") ?? false)
        XCTAssertEqual(coach.commitments.filter { $0.state == .approved }.map(\.kind), [.walk, .selfCare])
        XCTAssertEqual(coach.commitments.first { $0.kind == .workout }?.state, .cancelled)

        let count = coach.commitments.count
        coach.send("I'm ready")
        XCTAssertEqual(coach.commitments.count, count, "Asking again doesn't duplicate suggestions")
    }

    func testNewMeetingTakesTheGymOffTheScoreAndOffersAnotherSlot() async {
        // Scenario B: no fine, no change to Outlook, a feasible alternative.
        let h = await make(at: at(14))
        let coach = h.coach
        let gym = coach.addCommitment("Upper body at Nuffield", kind: .workout, start: at(16), durationMinutes: 100)
        h.calendar.extraEvents = [CalendarEventInfo(id: "exec", calendarID: DemoCalendarService.workID, title: "Exec sync",
                                                    start: at(16), end: at(17), isAllDay: false)]
        await coach.refresh()

        XCTAssertEqual(gym.state, .excused)
        XCTAssertEqual(gym.excuse, .calendarConflict)
        XCTAssertEqual(coach.projection.worstCaseFine, .zero, "An unavoidable clash is never fined")
        let offer = coach.proposals.first
        XCTAssertEqual(offer?.scheduledStart, at(17))
        XCTAssertEqual(offer?.weight, gym.weight)
        XCTAssertEqual(coach.messages.last?.toolSummary, "Taken off today's score: Upper body at Nuffield")

        let messages = coach.messages.count
        await coach.refresh()
        XCTAssertEqual(coach.messages.count, messages, "Replanning happens once, not on every refresh")
    }

    func testNoRoomForTheGymOffersAWalk() async {
        let h = await make(at: at(14))
        let coach = h.coach
        let gym = coach.addCommitment("Upper body at Nuffield", kind: .workout, start: at(16), durationMinutes: 100)
        h.calendar.extraEvents = [CalendarEventInfo(id: "late", calendarID: DemoCalendarService.workID, title: "Launch",
                                                    start: at(16), end: at(18, 30), isAllDay: false)]
        await coach.refresh()
        XCTAssertEqual(gym.state, .excused)
        XCTAssertEqual(coach.proposals.first?.kind, .walk)
    }

    func testRemindersOnlyForAgreedCommitmentsAndNeverDuplicated() async {
        let h = await make(at: at(9))
        let coach = h.coach
        let walk = coach.addCommitment("Lunchtime walk", kind: .walk, start: at(12, 5), durationMinutes: 30)
        XCTAssertEqual(h.reminders.latest.map(\.date), [at(12), at(12, 10), at(12, 25)])
        XCTAssertTrue(h.reminders.latest.allSatisfy { $0.id.hasPrefix("commitment.\(walk.id.uuidString)") })

        let sent = h.reminders.plans.count
        coach.reload()
        coach.reload()
        XCTAssertEqual(h.reminders.plans.count, sent, "An unchanged plan isn't rescheduled")

        coach.transition(walk, .complete)
        XCTAssertTrue(h.reminders.latest.isEmpty, "Done means no more nudges")
    }

    func testLaunchModeBacksOffOnceStarted() async {
        let h = await make(at: at(7))
        let coach = h.coach
        let gym = coach.addCommitment("Upper body at Nuffield", kind: .workout, start: at(7, 15), durationMinutes: 100)
        coach.send("Start")
        XCTAssertEqual(gym.state, .inProgress)
        XCTAssertEqual(coach.messages.last?.text, "Go. Kit on.")
        coach.send("Next step")
        XCTAssertEqual(coach.messages.last?.text, "Bottle filled, bag by the door.")
        coach.send("I'm in")
        XCTAssertNil(coach.launch)
        XCTAssertEqual(coach.messages.last?.text, "Good. I'll leave you to it.")
    }
}
