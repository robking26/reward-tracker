import XCTest
@testable import FitnessVault

final class ExerciseLibraryTests: XCTestCase {
    func testEveryExerciseHasTwoSwapsAndADemo() {
        for exercise in ExerciseLibrary.all {
            XCTAssertGreaterThanOrEqual(exercise.alternatives.count, 2, "\(exercise.id) needs swaps")
            XCTAssertFalse(exercise.alternatives.contains(exercise.id), "\(exercise.id) can't swap for itself")
            if FormDemo.noFrames.contains(exercise.id) {
                XCTAssertTrue(exercise.id == "swim" || ExerciseVideos.videoID(for: exercise.id) != nil,
                              "\(exercise.id) has no form loop, so it needs a full video")
            } else {
                XCTAssertTrue(FormDemo.hasFrames(exercise.id), "\(exercise.id) needs a form loop")
            }
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
    private func input(_ focus: TrainingFocus, minutes: Int = 90, rehabFirst: Bool = true,
                       knee: KneeStatus = .settled) -> ProgramInput {
        ProgramInput(focus: focus, variant: 0, availableMinutes: minutes, rehabFirst: rehabFirst, knee: knee, weights: [:])
    }

    private func main(_ plan: WorkoutPlan) -> [PlannedExercise] { plan.exercises.filter { !$0.isRehab } }

    func testPushPullLegsUseYourOwnExercises() {
        let push = main(ProgramGenerator.plan(input(.push)))
        XCTAssertEqual(push.map(\.exerciseID), ["inclineDBBench", "flatDBBench", "seatedDBShoulderPress", "lateralRaise",
                                                "tricepsMachine", "skullCrusher"])
        XCTAssertEqual(push.map { "\($0.sets)x\($0.targetReps)" }, ["3x10", "3x10", "3x10", "3x10", "3x10", "3x10"])

        let pull = main(ProgramGenerator.plan(input(.pull)))
        XCTAssertEqual(pull.map(\.exerciseID), ["barbellRow", "latPulldown", "trapMachine", "ezBarCurl", "hammerCurl"])
        XCTAssertEqual(pull.map { "\($0.sets)x\($0.targetReps)" }, ["3x8", "3x10", "3x10", "4x10", "3x10"])

        let legs = main(ProgramGenerator.plan(input(.legs)))
        XCTAssertEqual(legs.map(\.exerciseID), ["barbellSquat", "deadlift", "singleLegPress", "cleanAndPress", "plank",
                                                "cableCrunch"])
        XCTAssertEqual(legs.first?.restSeconds, 150)
    }

    func testSessionTitles() {
        XCTAssertEqual(ProgramGenerator.plan(input(.push)).title, "Push")
        XCTAssertEqual(ProgramGenerator.plan(input(.extra)).title, "Functional and swim")
    }

    func testFullSessionsFitNinetyMinutes() {
        for focus in TrainingFocus.rotation + [.extra] {
            let plan = ProgramGenerator.plan(input(focus))
            XCTAssertLessThanOrEqual(plan.estimatedMinutes, 90, focus.title)
            XCTAssertEqual(main(plan).count, ProgramGenerator.templates(focus, variant: 0).count, "\(focus.title): nothing dropped")
        }
    }

    func testWorkoutsAreLiftingOnlyNow() {
        // Knee rehab moved to the morning routine.
        for focus in TrainingFocus.rotation + [.extra] {
            XCTAssertFalse(ProgramGenerator.plan(input(focus)).exercises.contains(where: \.isRehab), focus.title)
        }
        XCTAssertEqual(ProgramGenerator.plan(input(.legs)).exercises.first?.exerciseID, "barbellSquat")
        XCTAssertTrue(ProgramGenerator.rehabOnly(knee: .settled, weights: [:]).exercises.allSatisfy(\.isRehab),
                      "Rehab on its own is still there")
    }

    func testShortOnTimeDropsOptionalsNeverRehabOrMains() {
        let plan = ProgramGenerator.plan(input(.push, minutes: 45))
        for id in ["inclineDBBench", "flatDBBench", "seatedDBShoulderPress"] {
            XCTAssertTrue(plan.exercises.contains { $0.exerciseID == id }, id)
        }
        XCTAssertLessThan(main(plan).count, 6)
        XCTAssertTrue(plan.notes.contains { $0.contains("dropped") })
    }

    func testIrritableKneeSwapsLegWorkWithoutDoublingUp() {
        let plan = ProgramGenerator.plan(input(.legs, knee: .irritable))
        let ids = plan.exercises.map(\.exerciseID)
        XCTAssertFalse(ids.contains("barbellSquat"))
        XCTAssertTrue(ids.contains("hipThrust"))
        XCTAssertEqual(Set(ids).count, ids.count, "No exercise twice")
        XCTAssertTrue(plan.exercises.allSatisfy { ($0.exercise?.kneeLoad ?? .none) <= .low })
        XCTAssertTrue(plan.notes.contains { $0.contains("swapped") })
    }

    func testFlareMeansRehabOnlyOnLegDay() {
        let plan = ProgramGenerator.plan(input(.legs, knee: .flare))
        XCTAssertTrue(plan.exercises.allSatisfy(\.isRehab))
        XCTAssertTrue(plan.notes.contains { $0.contains("physio") })
        XCTAssertTrue(main(ProgramGenerator.plan(input(.pull, knee: .flare))).count > 0, "Upper days still go ahead")
    }

    func testOptionalSessionIsKneeFriendly() {
        let plan = ProgramGenerator.plan(input(.extra))
        XCTAssertFalse(main(plan).isEmpty)
        XCTAssertTrue(plan.exercises.allSatisfy { ($0.exercise?.kneeLoad ?? .none) <= .low })
        XCTAssertEqual(plan.exercises.last?.exerciseID, "swim", "Finishes with a swim")
        let core = main(plan).filter { $0.exercise?.role == .core }
        XCTAssertGreaterThanOrEqual(core.count, 3, "Ab-focused")
        XCTAssertEqual(plan.exercises.first { $0.exerciseID == "pushUp" }?.sets, 2, "Shorter: two sets of the full-body moves")
        XCTAssertLessThan(plan.estimatedMinutes, ProgramGenerator.plan(input(.legs)).estimatedMinutes)
    }

    func testEveryProgrammeExerciseHasADemoAndSwaps() {
        for focus in TrainingFocus.rotation + [.extra] {
            for id in ProgramGenerator.templates(focus, variant: 0) {
                let exercise = ExerciseLibrary.exercise(id)
                XCTAssertNotNil(exercise, id)
                XCTAssertTrue(FormDemo.hasFrames(id) || FormDemo.noFrames.contains(id), "\(id) demo")
                XCTAssertGreaterThanOrEqual(exercise?.alternatives.count ?? 0, 2, "\(id) swaps")
            }
        }
    }

    func testFirstSessionIsAValidation() {
        let plan = ProgramGenerator.plan(input(.push))
        let incline = plan.exercises.first { $0.exerciseID == "inclineDBBench" }
        XCTAssertEqual(incline?.weightKg, 16)
        XCTAssertTrue(incline?.isValidation ?? false)
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
        let history = [record(1, 16, [10, 10, 10]), record(4, 16, [10, 10, 10]), record(8, 16, [11, 10, 10])]
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

    func testAssistedMachinesDontProgressByWeight() {
        XCTAssertFalse(ExerciseLibrary.exercise("assistedDip")!.usesWeight, "More assistance isn't progress")
        XCTAssertFalse(ExerciseLibrary.exercise("assistedPullUp")!.usesWeight)
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
        let plan = ProgramGenerator.plan(ProgramInput(focus: .legs, variant: 0, availableMinutes: 90, rehabFirst: false,
                                                      knee: .settled, weights: [:]))
        let squatIndex = plan.exercises.firstIndex { $0.exerciseID == "barbellSquat" }!
        let adapted = SessionAdaptation.afterKneePain(plan, currentIndex: squatIndex, severity: .irritable)
        let rest = adapted.exercises.dropFirst(squatIndex + 1)
        XCTAssertTrue(rest.allSatisfy { ($0.exercise?.kneeLoad ?? .none) <= .low })
        XCTAssertEqual(Array(adapted.exercises.prefix(squatIndex + 1)), Array(plan.exercises.prefix(squatIndex + 1)),
                       "Work already done stays done")
        XCTAssertFalse(adapted.exercises.contains { $0.exerciseID == "legPress" })
        let ids = adapted.exercises.map(\.exerciseID)
        XCTAssertEqual(Set(ids).count, ids.count, "No exercise twice")
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
        let plan = ProgramGenerator.plan(ProgramInput(focus: .push, variant: 0, availableMinutes: 90, rehabFirst: false,
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
