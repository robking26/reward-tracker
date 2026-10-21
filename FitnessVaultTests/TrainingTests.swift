import XCTest
@testable import FitnessVault

final class ExerciseLibraryTests: XCTestCase {
    func testEveryExerciseHasTwoSwapsAndADemo() {
        for exercise in ExerciseLibrary.all {
            XCTAssertGreaterThanOrEqual(exercise.alternatives.count, 2, "\(exercise.id) needs swaps")
            XCTAssertFalse(exercise.alternatives.contains(exercise.id), "\(exercise.id) can't swap for itself")
            XCTAssertNotNil(ExerciseVideos.videoID(for: exercise.id), "\(exercise.id) needs a demo video")
        }
        for (exerciseID, video) in ExerciseVideos.byExercise {
            XCTAssertNotNil(ExerciseLibrary.exercise(exerciseID), "Video for an unknown exercise: \(exerciseID)")
            XCTAssertEqual(video.count, 11, "\(exerciseID): YouTube IDs are 11 characters")
        }
    }

    func testLowerBodySwapsNeverLoadTheKneeMore() {
        for exercise in ExerciseLibrary.all where exercise.kneeLoad >= .moderate {
            let gentler = exercise.alternatives.compactMap(ExerciseLibrary.exercise).filter { $0.kneeLoad < exercise.kneeLoad }
            XCTAssertFalse(gentler.isEmpty, "\(exercise.id) needs a gentler swap for an irritable knee")
        }
    }

    func testBriefStartingLoads() {
        XCTAssertEqual(ExerciseLibrary.exercise("inclineDBBench")?.startingKg, 16)
        XCTAssertEqual(ExerciseLibrary.exercise("inclineDBBench")?.warmUpKg, 12)
        XCTAssertEqual(ExerciseLibrary.exercise("barbellRow")?.targetReps, 8)
        XCTAssertEqual(ExerciseLibrary.exercise("ezBarCurl")?.sets, 4)
        XCTAssertEqual(ExerciseLibrary.exercise("cleanAndPress")?.startingKg, 30, "Bar plus 5 kg each side")
        XCTAssertNil(ExerciseLibrary.exercise("singleLegPress")?.startingKg, "Found safely in the first session")
    }

    func testAlternativesExistAndHeavyCompoundsRestProperly() {
        for exercise in ExerciseLibrary.all {
            for alternative in exercise.alternatives {
                XCTAssertNotNil(ExerciseLibrary.exercise(alternative), "\(exercise.id) → \(alternative)")
            }
        }
        XCTAssertGreaterThanOrEqual(ExerciseLibrary.exercise("barbellSquat")!.restSeconds, 120)
        XCTAssertEqual(Set(ExerciseLibrary.all.map(\.id)).count, ExerciseLibrary.all.count, "Unique ids")
        XCTAssertGreaterThanOrEqual(ExerciseLibrary.exercise("deadlift")!.restSeconds, 120)
    }
}

final class ProgramGeneratorTests: XCTestCase {
    private func input(_ focus: TrainingFocus, variant: Int = 0, minutes: Int = 60, rehabFirst: Bool = true,
                       knee: KneeStatus = .settled) -> ProgramInput {
        ProgramInput(focus: focus, variant: variant, availableMinutes: minutes, rehabFirst: rehabFirst, knee: knee, weights: [:])
    }

    func testLowerDayStartsWithRehab() {
        let plan = ProgramGenerator.plan(input(.lower))
        XCTAssertTrue(plan.exercises.first?.isRehab ?? false, "Rehab near the start, after the warm-up (R2)")
        XCTAssertEqual(plan.exercises.filter(\.isRehab).count, 5)
        XCTAssertTrue(plan.exercises.contains { $0.exerciseID == "barbellSquat" })
    }

    func testRehabCanGoLastIfTheUserChooses() {
        let plan = ProgramGenerator.plan(input(.upper, rehabFirst: false))
        XCTAssertTrue(plan.exercises.last?.isRehab ?? false)
    }

    func testShortOnTimeDropsOptionalsNeverRehabOrMains() {
        let plan = ProgramGenerator.plan(input(.upper, minutes: 40))
        XCTAssertTrue(plan.exercises.contains { $0.exerciseID == "inclineDBBench" })
        XCTAssertTrue(plan.exercises.contains { $0.exerciseID == "barbellRow" })
        XCTAssertEqual(plan.exercises.filter(\.isRehab).count, 2)
        XCTAssertFalse(plan.exercises.contains { $0.exerciseID == "lateralRaise" })
        XCTAssertFalse(plan.notes.isEmpty)
    }

    func testFullSessionFitsAnHour() {
        let plan = ProgramGenerator.plan(input(.upper))
        XCTAssertLessThanOrEqual(plan.estimatedMinutes, 60)
        XCTAssertGreaterThanOrEqual(plan.estimatedMinutes, 35)
    }

    func testIrritableKneeSwapsTheSquat() {
        let plan = ProgramGenerator.plan(input(.lower, knee: .irritable))
        XCTAssertFalse(plan.exercises.contains { $0.exerciseID == "barbellSquat" })
        XCTAssertTrue(plan.exercises.contains { $0.exerciseID == "hipThrust" })
        XCTAssertTrue(plan.notes.contains { $0.contains("swapped") })
    }

    func testFlareMeansRehabOnly() {
        let plan = ProgramGenerator.plan(input(.lower, knee: .flare))
        XCTAssertTrue(plan.exercises.allSatisfy(\.isRehab))
        XCTAssertTrue(plan.notes.contains { $0.contains("physio") })
    }

    func testVariantsDiffer() {
        let a = ProgramGenerator.plan(input(.upper, variant: 0)).exercises.map(\.exerciseID)
        let b = ProgramGenerator.plan(input(.upper, variant: 1)).exercises.map(\.exerciseID)
        XCTAssertNotEqual(a, b)
    }

    func testFirstSessionIsAValidation() {
        let plan = ProgramGenerator.plan(input(.upper))
        let bench = plan.exercises.first { $0.exerciseID == "inclineDBBench" }
        XCTAssertEqual(bench?.weightKg, 16)
        XCTAssertTrue(bench?.isValidation ?? false)
    }
}

final class ProgressionTests: XCTestCase {
    private let bench = ExerciseLibrary.exercise("inclineDBBench")!
    private let squat = ExerciseLibrary.exercise("barbellSquat")!

    private func record(_ day: Int, _ kg: Double, _ reps: [Int], pain: Bool = false, form: Bool = false,
                        id: String = "inclineDBBench") -> ExerciseRecord {
        ExerciseRecord(date: Date(timeIntervalSinceReferenceDate: Double(day) * 86_400), exerciseID: id,
                       sets: reps.map { LoggedSet(weightKg: kg, reps: $0) }, pain: pain, techniqueConcern: form)
    }

    func testThreeConsecutiveSessionsOnTargetMoveUp() {
        let history = [record(1, 16, [10, 10, 10]), record(4, 16, [10, 10, 10]), record(8, 16, [10, 10, 10])]
        XCTAssertEqual(Progression.decide(bench, history: history, knee: .settled), .increase(to: 18))
    }

    func testTimeAloneNeverMovesUp() {
        let history = [record(1, 16, [10, 10, 10]), record(4, 16, [10, 10, 9]), record(60, 16, [10, 10, 10])]
        XCTAssertEqual(Progression.decide(bench, history: history, knee: .settled).weight, 16)
    }

    func testStreakResetsAtANewWeight() {
        let history = [record(1, 14, [10, 10, 10]), record(4, 16, [10, 10, 10]), record(8, 16, [10, 10, 10])]
        XCTAssertEqual(Progression.decide(bench, history: history, knee: .settled).weight, 16)
    }

    func testPainReducesAndTechniqueHolds() {
        XCTAssertEqual(Progression.decide(bench, history: [record(1, 16, [10, 10, 10], pain: true)], knee: .settled),
                       .reduce(to: 14, reason: "It hurt last time, so one step lighter."))
        let form = [record(1, 16, [10, 10, 10]), record(4, 16, [10, 10, 10]), record(8, 16, [10, 10, 10], form: true)]
        XCTAssertEqual(Progression.decide(bench, history: form, knee: .settled).weight, 16)
    }

    func testIrritableKneeHoldsLowerBodyLoading() {
        let history = (0..<3).map { record($0 * 3, 60, [10, 10, 10], id: "barbellSquat") }
        XCTAssertEqual(Progression.decide(squat, history: history, knee: .irritable),
                       .hold(at: 60, reason: "Holding while the knee settles."))
        XCTAssertEqual(Progression.decide(squat, history: history, knee: .settled), .increase(to: 62.5))
    }

    func testTwoMissesReduce() {
        let history = [record(1, 18, [8, 7, 6]), record(4, 18, [9, 7, 7])]
        XCTAssertEqual(Progression.decide(bench, history: history, knee: .settled).weight, 16)
    }

    func testIncompleteWorkoutCountsWhatWasDone() {
        // Scenario I: two sets done, then the session ended. No catch-up; it's simply not on target.
        let history = [record(1, 16, [10, 10])]
        let decision = Progression.decide(bench, history: history, knee: .settled)
        XCTAssertEqual(decision.weight, 16)
        XCTAssertFalse(Progression.hitTarget(history[0], bench))
    }

    func testNoHistoryStartsFromTheBriefEstimate() {
        XCTAssertEqual(Progression.decide(bench, history: [], knee: .settled), .start(16))
    }
}

final class KneeRulesTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 900_000_000)

    private func entry(_ hoursAgo: Double, _ pain: Int, timing: SymptomTiming = .general, swelling: Bool = false,
                       sharp: Bool = false) -> SymptomEntry {
        SymptomEntry(date: now.addingTimeInterval(-hoursAgo * 3_600), timing: timing, pain: pain, swelling: swelling, sharp: sharp)
    }

    func testStatus() {
        XCTAssertEqual(KneeRules.status([], now: now), .settled)
        XCTAssertEqual(KneeRules.status([entry(10, 2)], now: now), .settled)
        XCTAssertEqual(KneeRules.status([entry(10, 4)], now: now), .irritable)
        XCTAssertEqual(KneeRules.status([entry(10, 2, swelling: true)], now: now), .flare)
        XCTAssertEqual(KneeRules.status([entry(100, 8)], now: now), .settled, "Older than 72 hours")
    }

    func testDelayedPainCounts() {
        let entries = [entry(20, 0, timing: .during), entry(2, 2, timing: .nextDay)]
        XCTAssertEqual(KneeRules.status(entries, now: now), .irritable, "Worse the next morning matters")
    }

    func testConcerningSymptomsPointToProfessionalCare() {
        XCTAssertTrue(KneeRules.advice(for: entry(0, 3, sharp: true)).contains("physio"))
        XCTAssertFalse(KneeRules.advice(for: entry(0, 1)).contains("physio"))
    }

    func testPainDuringASessionAdaptsTheRest() {
        // Scenario D: pain during the squat; the rest of the session avoids loading the knee.
        let plan = ProgramGenerator.plan(ProgramInput(focus: .lower, variant: 0, availableMinutes: 60, rehabFirst: false,
                                                      knee: .settled, weights: [:]))
        let squatIndex = plan.exercises.firstIndex { $0.exerciseID == "barbellSquat" }!
        let adapted = SessionAdaptation.afterKneePain(plan, currentIndex: squatIndex, severity: .irritable)
        let rest = adapted.exercises.dropFirst(squatIndex + 1)
        XCTAssertTrue(rest.allSatisfy { ($0.exercise?.kneeLoad ?? .none) <= .low })
        XCTAssertEqual(Array(adapted.exercises.prefix(squatIndex + 1)), Array(plan.exercises.prefix(squatIndex + 1)),
                       "Work already done stays done")
        XCTAssertFalse(adapted.exercises.contains { $0.exerciseID == "singleLegPress" })
    }
}

final class SessionAdaptationTests: XCTestCase {
    func testBusyEquipmentOffersAnEquivalent() {
        // Scenario H.
        XCTAssertEqual(SessionAdaptation.alternative(for: "latPulldown", busy: [], knee: .settled)?.id, "seatedCableRow")
        XCTAssertEqual(SessionAdaptation.alternative(for: "inclineDBBench", busy: ["flatDBBench"], knee: .settled)?.id,
                       "chestPressMachine")
    }

    func testMoveLater() {
        let plan = ProgramGenerator.plan(ProgramInput(focus: .upper, variant: 0, availableMinutes: 60, rehabFirst: false,
                                                      knee: .settled, weights: [:]))
        let moved = SessionAdaptation.moveLater(plan, index: 0)
        XCTAssertEqual(moved.exercises[1].exerciseID, plan.exercises[0].exerciseID)
        XCTAssertEqual(moved.exercises.count, plan.exercises.count)
    }
}

final class WalkingAndSwimTests: XCTestCase {
    func testWalkingStartsFromTheRealBaseline() {
        XCTAssertEqual(WalkingTargets.baseline([4_000, 0, 5_200, 4_800, 6_100]), 5_200)
        XCTAssertEqual(WalkingTargets.target(baseline: 4_800, previous: nil, lastWeek: [], knee: .settled), 6_000)
        XCTAssertEqual(WalkingTargets.target(baseline: 9_000, previous: nil, lastWeek: [], knee: .settled), 9_000)
    }

    func testWalkingStepsUpGraduallyAndRespectsTheKnee() {
        let week = [7_200, 7_500, 6_000, 8_000, 7_100, 7_300, 5_000]
        XCTAssertEqual(WalkingTargets.target(baseline: 6_000, previous: 7_000, lastWeek: week, knee: .settled), 7_500)
        XCTAssertEqual(WalkingTargets.target(baseline: 6_000, previous: 7_000, lastWeek: week, knee: .irritable), 7_000)
        XCTAssertEqual(WalkingTargets.target(baseline: 6_000, previous: 12_500, lastWeek: Array(repeating: 13_000, count: 7),
                                             knee: .settled), 12_500)
    }

    func testSwimmingBuildsSlowly() {
        XCTAssertEqual(SwimPlan.next([]).minutes, 20)
        let day = { (n: Int) in Date(timeIntervalSinceReferenceDate: Double(n) * 86_400) }
        XCTAssertEqual(SwimPlan.next([SwimRecord(date: day(1), minutes: 22, metres: 800),
                                      SwimRecord(date: day(8), minutes: 21, metres: 750)]).minutes, 25)
        XCTAssertEqual(SwimPlan.next([SwimRecord(date: day(1), minutes: 22, metres: 800),
                                      SwimRecord(date: day(8), minutes: 15, metres: 500)]).minutes, 20)
    }
}
