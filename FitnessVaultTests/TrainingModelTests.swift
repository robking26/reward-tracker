import XCTest
import SwiftData
@testable import FitnessVault

/// A clock the tests can move forward.
final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor
final class TrainingModelTests: XCTestCase {
    private var london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    private let monday = DayKey(year: 2026, month: 10, day: 19)

    private func at(_ hour: Int, _ minute: Int = 0, day: DayKey? = nil) -> Date {
        (day ?? monday).startDate(calendar: london).addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    private struct Harness {
        var training: TrainingModel
        var alerts: RecordingRestAlerts
        var clock: TestClock
        var container: ModelContainer
    }

    private func make(at date: Date) -> Harness {
        let clock = TestClock(date)
        let container = Persistence.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "training.test.\(UUID().uuidString)")!
        let alerts = RecordingRestAlerts()
        let training = TrainingModel(container: container, restAlerts: alerts, defaults: defaults, calendar: london,
                                     now: { clock.date })
        return Harness(training: training, alerts: alerts, clock: clock, container: container)
    }

    func testLogRestReadyAndFinish() {
        let h = make(at: at(17, 30))
        let plan = h.training.makePlan(focus: .upper, variant: 0, availableMinutes: 60, rehabFirst: true)
        h.training.start(plan)
        XCTAssertTrue(h.training.current?.isRehab ?? false, "Rehab first by default")

        h.training.logSet(weight: nil, reps: 12)
        XCTAssertEqual(h.training.setsDone, 1)
        XCTAssertEqual(h.training.restEndsAt, at(17, 30).addingTimeInterval(30))
        XCTAssertFalse(h.training.awaitingReady)
        h.training.logSet(weight: nil, reps: 12)
        h.training.logSet(weight: nil, reps: 12)
        XCTAssertTrue(h.training.awaitingReady, "Shows what's next and waits for Ready")
        XCTAssertEqual(h.alerts.started.count, 3)

        h.training.ready()
        XCTAssertEqual(h.training.currentIndex, 1)
        XCTAssertEqual(h.training.setsDone, 0)

        let summary = h.training.end()
        XCTAssertEqual(summary?.workingSets, 3)
        XCTAssertEqual(h.training.lastSummary, summary)
        XCTAssertFalse(h.training.isActive)
    }

    func testAPartialWorkoutCountsWhatWasDoneWithoutCatchUp() {
        // Scenario I.
        let h = make(at: at(17, 30))
        let plan = h.training.makePlan(focus: .upper, variant: 0, availableMinutes: 60, rehabFirst: false)
        XCTAssertEqual(plan.exercises.first?.exerciseID, "inclineDBBench")
        h.training.start(plan)
        h.training.logWarmUp(weight: 12, reps: 10)
        h.training.logSet(weight: 16, reps: 10)
        h.training.logSet(weight: 16, reps: 10)
        h.training.end()

        let records = h.training.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.sets.count, 2, "Warm-ups aren't working sets")
        let next = h.training.makePlan(focus: .upper, variant: 0, availableMinutes: 60, rehabFirst: false)
        let bench = next.exercises.first { $0.exerciseID == "inclineDBBench" }
        XCTAssertEqual(bench?.sets, 3, "No extra catch-up sets")
        XCTAssertEqual(bench?.weightKg, 16)
        XCTAssertFalse(bench?.isValidation ?? true)
    }

    func testKneePainMidSessionAdaptsAndIsRemembered() {
        // Scenario D.
        let h = make(at: at(17, 30))
        let plan = h.training.makePlan(focus: .lower, variant: 0, availableMinutes: 60, rehabFirst: false)
        XCTAssertEqual(plan.exercises.first?.exerciseID, "barbellSquat")
        h.training.start(plan)
        h.training.logSet(weight: 60, reps: 10)
        let advice = h.training.reportKneePain(pain: 4, swelling: false, sharp: false)
        XCTAssertFalse(advice.isEmpty)
        XCTAssertTrue(h.training.awaitingReady, "Moves on from the squat")
        let remaining = h.training.plan!.exercises.dropFirst(h.training.currentIndex + 1)
        XCTAssertTrue(remaining.allSatisfy { ($0.exercise?.kneeLoad ?? .none) <= .low })
        XCTAssertEqual(h.training.kneeStatus, .irritable)
        h.training.end()

        let squat = ExerciseLibrary.exercise("barbellSquat")!
        if case .reduce = Progression.decide(squat, history: h.training.records(), knee: .settled) {} else {
            XCTFail("A lift that hurt goes down a step next time")
        }
        let next = h.training.makePlan(focus: .lower, variant: 0, availableMinutes: 60, rehabFirst: true)
        XCTAssertFalse(next.exercises.contains { $0.exerciseID == "barbellSquat" }, "Swapped while the knee is irritable")
    }

    func testBusyEquipmentSwapsTheCurrentExercise() {
        // Scenario H.
        let h = make(at: at(17, 30))
        h.training.start(h.training.makePlan(focus: .upper, variant: 0, availableMinutes: 60, rehabFirst: false))
        XCTAssertEqual(h.training.current?.exerciseID, "inclineDBBench")
        let options = h.training.alternativesForCurrent()
        XCTAssertEqual(options.first?.id, "flatDBBench")
        h.training.swapCurrent(to: options[0])
        XCTAssertEqual(h.training.current?.exerciseID, "flatDBBench")
        h.training.doCurrentLater()
        XCTAssertEqual(h.training.current?.exerciseID, "barbellRow", "Do it later moves it back one")
    }

    func testNextMorningKneeCheckAfterLegs() {
        let h = make(at: at(17, 30))
        h.training.start(h.training.makePlan(focus: .lower, variant: 0, availableMinutes: 60, rehabFirst: true))
        h.training.logSet(weight: nil, reps: 12)
        h.training.end()
        XCTAssertFalse(h.training.needsNextDayKneeCheck)

        h.clock.date = at(7, day: monday.adding(days: 1, calendar: london))
        XCTAssertTrue(h.training.needsNextDayKneeCheck)
        h.training.logSymptom(timing: .nextDay, pain: 1, swelling: false, sharp: false)
        XCTAssertFalse(h.training.needsNextDayKneeCheck)
    }

    func testAnActiveSessionSurvivesARelaunch() {
        let h = make(at: at(17, 30))
        h.training.start(h.training.makePlan(focus: .upper, variant: 1, availableMinutes: 60, rehabFirst: true))
        h.training.logSet(weight: nil, reps: 12)
        let relaunched = TrainingModel(container: h.container, restAlerts: RecordingRestAlerts(),
                                       calendar: london, now: { h.clock.date })
        XCTAssertTrue(relaunched.isActive)
        XCTAssertEqual(relaunched.plan?.title, "Upper body B")
        XCTAssertEqual(relaunched.setsDone, 1)
    }

    func testKneeRehabOnlySession() {
        let h = make(at: at(17, 30))
        let plan = h.training.makeRehabPlan()
        XCTAssertEqual(plan.title, "Knee rehab")
        XCTAssertFalse(plan.exercises.isEmpty)
        XCTAssertTrue(plan.exercises.allSatisfy(\.isRehab))
        h.training.start(plan)
        h.training.logSet(weight: nil, reps: 12)
        h.training.end()

        h.clock.date = at(7, day: monday.adding(days: 1, calendar: london))
        XCTAssertTrue(h.training.needsNextDayKneeCheck, "Rehab loads the knee too")
    }
}
