import XCTest
import SwiftData
@testable import FitnessVault

private let london: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    return calendar
}()

/// The clocks go back on Sunday 25 October 2026 and forward on Sunday 29 March 2026.
final class ClockChangeTests: XCTestCase {
    private let autumn = DayKey(year: 2026, month: 10, day: 25)
    private let spring = DayKey(year: 2026, month: 3, day: 29)

    private func wallClock(_ date: Date) -> String {
        let parts = london.dateComponents([.hour, .minute], from: date)
        return String(format: "%02ld:%02ld", parts.hour ?? -1, parts.minute ?? -1)
    }

    func testTimesOfDayStayOnTheWallClock() {
        XCTAssertEqual(wallClock(autumn.date(atMinute: 355, calendar: london)), "05:55")
        XCTAssertEqual(wallClock(autumn.date(atMinute: 21 * 60 + 30, calendar: london)), "21:30")
        XCTAssertEqual(wallClock(spring.date(atMinute: 8 * 60, calendar: london)), "08:00")
        let ordinary = DayKey(year: 2026, month: 10, day: 19)
        XCTAssertEqual(ordinary.date(atMinute: 90, calendar: london), ordinary.startDate(calendar: london).addingTimeInterval(90 * 60))
        // The old "midnight plus seconds" would have said 04:55 on the autumn change.
        XCTAssertEqual(wallClock(autumn.startDate(calendar: london).addingTimeInterval(355 * 60)), "04:55")
    }

    func testSelfCareAndWindowsOnTheChangeDay() {
        let settings = CoachSettings()
        let now = autumn.date(atMinute: 6 * 60, calendar: london)
        let windows = Availability.windows(on: autumn, shape: settings.shape(isWorkday: false), blocks: [], notBefore: now, calendar: london)
        XCTAssertEqual(wallClock(windows.first!.interval.start), "06:00")
        let input = RecommendationInput(day: autumn, now: now, calendar: london, settings: settings, isWorkday: false,
                                        windows: windows, events: [], existingKinds: [], workoutsThisWeek: 0,
                                        consecutiveWorkoutDays: 0, lastWorkoutWasUpper: nil, houseTask: nil)
        let selfCare = RecommendationEngine.morning(input).first { $0.kind == .selfCare }
        XCTAssertEqual(wallClock(selfCare!.start!), "21:30", "Not 20:30 or 22:30 on the clock-change day")
    }

    @MainActor
    func testSettlementStaysAtEight() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "dst.\(UUID().uuidString)")!)
        let next = store.nextSettlement(after: autumn.date(atMinute: 60, calendar: london), calendar: london)
        XCTAssertEqual(wallClock(next), "08:00")
        XCTAssertEqual(DayKey(next, calendar: london), autumn)
    }
}

final class PlanAuditorTests: XCTestCase {
    private let day = DayKey(year: 2026, month: 10, day: 19)
    private func at(_ hour: Int, _ minute: Int = 0) -> Date { day.date(atMinute: hour * 60 + minute, calendar: london) }

    private func suggestion(_ title: String, _ kind: CommitmentKind, at start: Date, minutes: Int) -> Recommendation {
        Recommendation(title: title, kind: kind, start: start, durationMinutes: minutes, weight: 2, objective: .health,
                       reason: "", alternative: nil, question: "")
    }

    private let meeting = ClassifiedEvent(event: CalendarEventInfo(id: "m", calendarID: "w", title: "Budget review",
                                                                   start: DayKey(year: 2026, month: 10, day: 19).date(atMinute: 14 * 60, calendar: london),
                                                                   end: DayKey(year: 2026, month: 10, day: 19).date(atMinute: 15 * 60, calendar: london),
                                                                   isAllDay: false),
                                          role: .work, kind: .workMeeting)

    func testClashesAndNightTimeAreRemoved() {
        let plan = [suggestion("Walk", .walk, at: at(14, 30), minutes: 30),
                    suggestion("Rehab", .rehab, at: at(4, 0), minutes: 15),
                    suggestion("Evening self-care", .selfCare, at: at(21, 30), minutes: 15)]
        let issues = PlanAuditor.audit(plan, events: [meeting], settings: CoachSettings(), day: day, calendar: london,
                                       forecast: [], recovering: false)
        XCTAssertEqual(issues.filter { $0.severity == .blocking }.map(\.title), ["Walk", "Rehab"])
        XCTAssertTrue(issues.contains { $0.problem == "Clashes with work meeting" })
        XCTAssertEqual(PlanAuditor.filtered(plan, issues: issues).map(\.title), ["Evening self-care"])
    }

    func testRainRecoveryAndTooMuchAreFlagged() {
        let rain = (11...13).map { HourlyWeather(date: at($0), temperature: 10, precipitationProbability: 90, precipitation: 2) }
        var plan = [suggestion("Walk", .walk, at: at(12, 5), minutes: 30),
                    suggestion("Upper body at Nuffield", .workout, at: at(17, 0), minutes: 100)]
        let issues = PlanAuditor.audit(plan, events: [], settings: CoachSettings(), day: day, calendar: london,
                                       forecast: rain, recovering: true)
        XCTAssertTrue(issues.contains { $0.title == "Walk" && $0.severity == .warning })
        XCTAssertTrue(issues.contains { $0.title == "Upper body at Nuffield" && $0.severity == .blocking })

        plan = (0..<6).map { suggestion("Thing \($0)", .household, at: at(9 + $0), minutes: 10) }
        let crowded = PlanAuditor.audit(plan, events: [], settings: CoachSettings(), day: day, calendar: london,
                                        forecast: [], recovering: false)
        XCTAssertTrue(crowded.contains { $0.problem.contains("too many") })
        XCTAssertTrue(crowded.contains { $0.problem.contains("twice") })
    }

    func testTheEngineDoesNotTripTheChecker() {
        // A normal work-from-home day, a day off, a rainy day, a recovery day and a restart day.
        let settings = CoachSettings()
        let events = [meeting]
        let now = at(6, 30)
        for isWorkday in [true, false] {
            for recovery in [RecoveryStatus.clear, .recovering(.gettingThere), .restarting] {
                let windows = Availability.windows(on: day, shape: settings.shape(isWorkday: isWorkday),
                                                   blocks: CalendarClassifier.blocks(from: events), notBefore: now, calendar: london)
                let input = RecommendationInput(day: day, now: now, calendar: london, settings: settings, isWorkday: isWorkday,
                                                windows: windows, events: events, existingKinds: [], workoutsThisWeek: 0,
                                                consecutiveWorkoutDays: 0, lastWorkoutWasUpper: nil,
                                                houseTask: HouseTaskSuggestion(title: "Tidy the attic", minutes: 30),
                                                recovery: recovery)
                let plan = RecommendationEngine.morning(input)
                var recovering = false
                if case .recovering = recovery { recovering = true }
                let issues = PlanAuditor.audit(plan, events: events, settings: settings, day: day, calendar: london,
                                               forecast: [], recovering: recovering)
                XCTAssertTrue(issues.isEmpty, "\(isWorkday) \(recovery): \(issues.map(\.problem))")
            }
        }
    }
}

final class ValidationSummaryTests: XCTestCase {
    func testSummaryAndReport() {
        typealias Suggestion = ValidationInput.Suggestion
        typealias Outcome = ValidationInput.Outcome
        typealias CheckIn = ValidationInput.CheckIn
        typealias Feedback = ValidationInput.Feedback
        let suggestions: [Suggestion] = [
            Suggestion(kind: .walk, agreed: true, declined: false),
            Suggestion(kind: .workout, agreed: false, declined: true),
            Suggestion(kind: .walk, agreed: false, declined: true),
            Suggestion(kind: .rehab, agreed: true, declined: false),
            Suggestion(kind: .walk, agreed: false, declined: true),
        ]
        let outcomes: [Outcome] = [
            Outcome(state: .completed, assumedMissed: false),
            Outcome(state: .missed, assumedMissed: true),
            Outcome(state: .excused, assumedMissed: false),
        ]
        let checkIns: [CheckIn] = [
            CheckIn(usefulness: .very, effort: .light, note: nil),
            CheckIn(usefulness: .notReally, effort: .tooMuch, note: "Too many pings"),
            CheckIn(usefulness: .somewhat, effort: .tooMuch, note: nil),
        ]
        let feedback: [Feedback] = [
            Feedback(title: "Walk", reason: .wrongTime, note: nil),
            Feedback(title: "Walk", reason: .wrongTime, note: "Lunch is 1pm"),
            Feedback(title: "Gym", reason: .tooMuch, note: nil),
        ]
        let issues: [String] = ["2026-10-20: Walk: Rain is forecast then"]
        let input = ValidationInput(from: DayKey(year: 2026, month: 10, day: 19), to: DayKey(year: 2026, month: 10, day: 25),
                                    suggestions: suggestions, outcomes: outcomes, checkIns: checkIns, feedback: feedback,
                                    issues: issues, messagesSent: 8, unknownMessages: 3)
        let summary = ValidationSummary(input, calendar: london)
        XCTAssertEqual(summary.days, 7)
        XCTAssertEqual(summary.agreed, 2)
        XCTAssertEqual(summary.declined, 3)
        XCTAssertEqual(summary.reasons.first?.reason, .wrongTime)
        XCTAssertEqual(summary.reasons.first?.count, 2)
        XCTAssertEqual(summary.averageUsefulness, 2)
        XCTAssertEqual(summary.tooMuchDays, 2)
        XCTAssertEqual(summary.priorities.count, 6, "Checker, wrong times, low agreement, effort, unanswered misses, misunderstood messages")
        let report = summary.report(feedback: input.feedback, notes: ["2026-10-21: Too many pings"])
        XCTAssertTrue(report.hasPrefix("Vaultality test report (7 days)"))
        XCTAssertTrue(report.contains("Wrong time: 2"))
        XCTAssertTrue(report.contains("Walk: Wrong time: Lunch is 1pm"))
        XCTAssertTrue(report.contains("Too many pings"))
        XCTAssertTrue(report.contains("Fix first:"))
        XCTAssertFalse(report.contains("£"), "No money in the report")
    }
}

@MainActor
final class ValidationModelTests: XCTestCase {
    private func make(_ clock: TestClock) async -> CoachModel {
        let defaults = UserDefaults(suiteName: "validation.test.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.settings.demoMode = true
        let demo = DemoCalendarService(calendar: london)
        let coach = CoachModel(container: Persistence.makeContainer(inMemory: true), settingsStore: settings, liveCalendar: demo,
                               demoCalendar: demo, defaults: defaults, reminders: RecordingReminderScheduler(),
                               countdowns: RecordingCountdowns(), languageModel: nil, calendar: london, now: { clock.date })
        await coach.start()
        return coach
    }

    private let monday = DayKey(year: 2026, month: 10, day: 19)

    func testFlaggingASuggestionDeclinesItAndRecordsWhy() async {
        let clock = TestClock(monday.date(atMinute: 7 * 60, calendar: london))
        let coach = await make(clock)
        _ = coach.respond(to: "I'm ready")
        let first = try? XCTUnwrap(coach.proposals.first)
        guard let first else { return XCTFail("The briefing proposes something") }
        coach.flagWrong(first, reason: .wrongTime, note: "Lunch is at one")
        XCTAssertEqual(first.state, .cancelled)
        let input = coach.validationInput()
        XCTAssertEqual(input.feedback.first?.reason, .wrongTime)
        XCTAssertEqual(input.feedback.first?.note, "Lunch is at one")
        XCTAssertTrue(input.issues.isEmpty, "The demo day's plan passes the checker: \(input.issues)")
        XCTAssertTrue(coach.validationReport().contains("1 marked wrong"))
    }

    func testCheckInIsAskedOnceInTheEvening() async {
        let clock = TestClock(monday.date(atMinute: 15 * 60, calendar: london))
        let coach = await make(clock)
        XCTAssertFalse(coach.shouldAskForCheckIn, "Not in the afternoon")
        clock.date = monday.date(atMinute: 20 * 60, calendar: london)
        XCTAssertTrue(coach.shouldAskForCheckIn)
        coach.saveCheckIn(usefulness: .somewhat, effort: .fine, note: "Walk time was good")
        XCTAssertFalse(coach.shouldAskForCheckIn, "Once a day")
        XCTAssertEqual(coach.validationInput().checkIns.first?.usefulness, .somewhat)
        XCTAssertTrue(coach.validationReport().contains("Walk time was good"))

        clock.date = monday.adding(days: 1, calendar: london).date(atMinute: 20 * 60, calendar: london)
        await coach.refresh()
        XCTAssertTrue(coach.shouldAskForCheckIn)
        coach.skipCheckIn()
        XCTAssertFalse(coach.shouldAskForCheckIn, "Skipping counts for the day")
    }
}
