import Foundation

/// What a session trains. Push, pull and legs are the three-day programme; arms and core is the optional extra.
/// Upper and lower are the earlier programme, kept so saved sessions still load.
enum TrainingFocus: String, Codable, CaseIterable, Sendable {
    case push, pull, legs, extra
    case upper, lower

    /// The weekly rotation.
    static let rotation: [TrainingFocus] = [.push, .pull, .legs]

    var title: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .extra: "Functional and swim"
        case .upper: "Upper body"
        case .lower: "Lower body"
        }
    }

    /// Sessions that load the knee: they get the full rehab block and the next-morning knee check.
    var loadsLegs: Bool { self == .legs || self == .lower }

    /// The session's rules, from the programme.
    var sessionNote: String? {
        switch self {
        case .extra: "Optional and shorter: full-body carries, hinge, push and pull, then a core circuit, then a swim. Nothing heavy through the knee."
        case .push, .pull, .legs, .upper, .lower: nil
        }
    }
}

enum ExerciseRole: String, Codable, Sendable {
    /// Compound lifts that anchor the session.
    case main
    /// Nice to have; dropped first when time is short.
    case accessory
    /// Knee rehab: never dropped to save time (R2, W4).
    case rehab
    case core
}

/// How much an exercise loads the right knee (O-B). Used to swap exercises when the knee isn't settled.
enum KneeLoad: Int, Codable, Comparable, Sendable {
    case none = 0, low, moderate, high

    static func < (lhs: KneeLoad, rhs: KneeLoad) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum RepUnit: String, Codable, Sendable {
    case reps, seconds, stepsEachWay, repsEachSide, minutes

    var label: String {
        switch self {
        case .reps: "reps"
        case .seconds: "sec"
        case .stepsEachWay: "steps each way"
        case .repsEachSide: "each side"
        case .minutes: "min"
        }
    }
}

/// One exercise and its defaults (W3). Starting loads are the brief's expectations, not verified
/// performance: the first session validates them.
struct Exercise: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let role: ExerciseRole
    let equipment: String
    let warmUpKg: Double?
    /// Nil means "find a safe starting load in the first session".
    let startingKg: Double?
    /// Dumbbells: the weight is per hand.
    let perSide: Bool
    let incrementKg: Double
    let sets: Int
    let targetReps: Int
    let minReps: Int
    let restSeconds: Int
    let kneeLoad: KneeLoad
    let unit: RepUnit
    /// Equivalent exercises, best first, for busy equipment (W4) or an irritable knee.
    let alternatives: [String]
    let cue: String?

    var usesWeight: Bool { startingKg != nil || warmUpKg != nil || incrementKg > 0 }
}

enum ExerciseLibrary {
    // swiftlint:disable function_parameter_count
    private static func lift(_ id: String, _ name: String, _ role: ExerciseRole, _ equipment: String,
                             warm: Double?, start: Double?, perSide: Bool = false, increment: Double,
                             sets: Int = 3, reps: Int = 10, minReps: Int = 8, rest: Int, knee: KneeLoad = .none,
                             unit: RepUnit = .reps, alternatives: [String] = [], cue: String? = nil) -> Exercise {
        Exercise(id: id, name: name, role: role, equipment: equipment, warmUpKg: warm, startingKg: start,
                 perSide: perSide, incrementKg: increment, sets: sets, targetReps: reps, minReps: minReps,
                 restSeconds: rest, kneeLoad: knee, unit: unit, alternatives: alternatives, cue: cue)
    }

    static let all: [Exercise] = [
        // Upper body (brief's table)
        lift("inclineDBBench", "Incline dumbbell bench", .main, "Dumbbells", warm: 12, start: 16, perSide: true, increment: 2,
             rest: 90, alternatives: ["flatDBBench", "chestPressMachine", "inclineMachinePress", "pushUp"]),
        lift("flatDBBench", "Flat dumbbell bench", .main, "Dumbbells", warm: 12, start: 16, perSide: true, increment: 2,
             rest: 90, alternatives: ["inclineDBBench", "chestPressMachine", "pushUp"]),
        lift("seatedDBShoulderPress", "Seated dumbbell shoulder press", .main, "Dumbbells", warm: 8, start: 10, perSide: true,
             increment: 2, rest: 90, alternatives: ["machineShoulderPress", "cableLateralRaise"]),
        lift("barbellRow", "Barbell row", .main, "Barbell", warm: 20, start: 30, increment: 2.5, reps: 8, minReps: 8, rest: 120,
             alternatives: ["seatedCableRow", "latPulldown", "dumbbellRow"], cue: "Flat back, pull to your belly button."),
        lift("latPulldown", "Lat pulldown", .main, "Machine", warm: 30, start: 40, increment: 2.5, rest: 90,
             alternatives: ["seatedCableRow", "dumbbellRow", "assistedPullUp"]),
        lift("hammerCurl", "Dumbbell hammer curl", .accessory, "Dumbbells", warm: nil, start: 10, perSide: true, increment: 2,
             rest: 60, alternatives: ["ezBarCurl", "cableCurl", "machineCurl"]),
        lift("ezBarCurl", "Small-bar barbell curl", .accessory, "Small barbell", warm: nil, start: 20, increment: 2.5, sets: 4,
             rest: 60, alternatives: ["hammerCurl", "cableCurl"]),
        lift("tricepsMachine", "Triceps machine", .accessory, "Machine", warm: nil, start: 15, increment: 2.5, rest: 60,
             alternatives: ["skullCrusher", "cablePushdown", "overheadTricepsExtension", "assistedDip"]),
        lift("skullCrusher", "Skull crusher", .accessory, "EZ bar", warm: 10, start: 14, increment: 2.5, rest: 60,
             alternatives: ["tricepsMachine", "cablePushdown", "overheadTricepsExtension"]),
        lift("lateralRaise", "Lateral raise", .accessory, "Dumbbells", warm: nil, start: nil, perSide: true, increment: 1, rest: 60,
             alternatives: ["machineShoulderPress", "cableLateralRaise"]),
        lift("trapMachine", "Upper-back / trap machine", .accessory, "Machine", warm: nil, start: nil, increment: 2.5, rest: 60,
             alternatives: ["seatedCableRow", "facePull"]),

        // Upper-body alternatives
        lift("chestPressMachine", "Chest press machine", .main, "Machine", warm: nil, start: nil, increment: 2.5, rest: 90,
             alternatives: ["flatDBBench", "inclineMachinePress", "pushUp"]),
        lift("seatedCableRow", "Seated cable row", .main, "Cable", warm: nil, start: nil, increment: 2.5, rest: 90,
             alternatives: ["latPulldown", "dumbbellRow", "bentOverDBRow"]),
        lift("machineShoulderPress", "Shoulder press machine", .main, "Machine", warm: nil, start: nil, increment: 2.5, rest: 90,
             alternatives: ["seatedDBShoulderPress", "cableLateralRaise"]),
        lift("cablePushdown", "Cable triceps pushdown", .accessory, "Cable", warm: nil, start: nil, increment: 2.5, rest: 60,
             alternatives: ["tricepsMachine", "overheadTricepsExtension"]),

        // Lower body (brief's table): heavy compounds rest properly (W3)
        lift("barbellSquat", "Barbell squat", .main, "Barbell", warm: 40, start: 60, increment: 2.5, rest: 150, knee: .high,
             alternatives: ["boxSquat", "hipThrust", "gobletSquat", "legPress"], cue: "Knees track over toes. Stop if it's sharp."),
        lift("deadlift", "Barbell deadlift", .main, "Barbell", warm: 40, start: 60, increment: 2.5, rest: 150, knee: .moderate,
             alternatives: ["romanianDeadlift", "hipThrust"], cue: "Brace, bar close, hips back."),
        lift("cleanAndPress", "Clean and press", .accessory, "Barbell", warm: 20, start: 30, increment: 2.5, rest: 120,
             knee: .moderate, alternatives: ["seatedDBShoulderPress", "machineShoulderPress"]),
        lift("singleLegPress", "Single-leg press", .main, "Machine", warm: nil, start: nil, increment: 5, rest: 90,
             knee: .moderate, unit: .repsEachSide, alternatives: ["stepUp", "hipThrust", "legCurl"],
             cue: "Start light. Knee in line with your second toe."),

        // Lower-body alternatives with less knee load
        lift("boxSquat", "Box squat (to a high box)", .main, "Barbell", warm: 20, start: nil, increment: 2.5, rest: 120,
             knee: .moderate, alternatives: ["hipThrust", "gobletSquat"]),
        lift("romanianDeadlift", "Dumbbell Romanian deadlift", .main, "Dumbbells", warm: nil, start: nil, perSide: true,
             increment: 2, rest: 90, knee: .low, alternatives: ["hipThrust", "legCurl"]),
        lift("hipThrust", "Hip thrust", .main, "Barbell", warm: nil, start: nil, increment: 5, rest: 90, knee: .low,
             alternatives: ["gluteBridge", "cableKickback"]),
        lift("stepUp", "Low step-up", .accessory, "Bodyweight", warm: nil, start: nil, increment: 0, rest: 60, knee: .low,
             unit: .repsEachSide, alternatives: ["hipThrust", "gluteBridge"]),

        // Core (optional)
        lift("plank", "Plank", .core, "Bodyweight", warm: nil, start: nil, increment: 0, sets: 3, reps: 30, minReps: 20, rest: 45,
             unit: .seconds, alternatives: ["deadBug", "cableCrunch"]),
        lift("cableCrunch", "Cable crunch", .core, "Cable", warm: nil, start: nil, increment: 2.5, sets: 3, reps: 12, minReps: 10,
             rest: 45, alternatives: ["deadBug", "plank"]),

        // Knee rehab candidates from earlier physio advice (R1). Not a clinical prescription.
        lift("gluteBridge", "Glute bridge", .rehab, "Bodyweight", warm: nil, start: nil, increment: 0, sets: 3, reps: 12,
             minReps: 10, rest: 30, knee: .low, alternatives: ["hipThrust", "cableKickback"],
             cue: "Squeeze at the top for two seconds."),
        lift("sideLyingAbduction", "Side-lying hip abduction", .rehab, "Bodyweight", warm: nil, start: nil, increment: 0, sets: 3,
             reps: 15, minReps: 12, rest: 30, unit: .repsEachSide, alternatives: ["clamshell", "bandedLateralWalk"],
             cue: "Toes slightly down, slow on the way back."),
        lift("bandedLateralWalk", "Banded lateral walk", .rehab, "Resistance band", warm: nil, start: nil, increment: 0, sets: 3,
             reps: 10, minReps: 8, rest: 30, knee: .low, unit: .stepsEachWay, alternatives: ["sideLyingAbduction", "clamshell"]),
        lift("stepDown", "Controlled step-down", .rehab, "Step", warm: nil, start: nil, increment: 0, sets: 3, reps: 8,
             minReps: 6, rest: 45, knee: .low, unit: .repsEachSide, alternatives: ["wallSit", "stepUp"],
             cue: "Slow, knee over the second toe, no pain. Lower the step if it hurts."),
        lift("singleLegBalance", "Supported single-leg balance", .rehab, "Bodyweight", warm: nil, start: nil, increment: 0,
             sets: 3, reps: 30, minReps: 20, rest: 30, unit: .seconds, alternatives: ["gluteBridge", "sideLyingAbduction"]),

        // Push, pull and legs sessions
        lift("barbellBench", "Bench press", .main, "Barbell", warm: 20, start: nil, increment: 2.5, sets: 4, reps: 8, minReps: 6,
             rest: 150, alternatives: ["flatDBBench", "chestPressMachine", "pushUp"],
             cue: "Shoulder blades pinned back, bar to mid-chest, 2 seconds down."),
        lift("cableFly", "Cable fly", .accessory, "Cable", warm: nil, start: nil, increment: 2.5, reps: 12, minReps: 10, rest: 120,
             alternatives: ["pecDeck", "flatDBBench"], cue: "Soft elbows, hug a big tree, squeeze at the middle."),
        lift("pecDeck", "Pec deck (machine fly)", .accessory, "Machine", warm: nil, start: nil, increment: 2.5, reps: 12,
             minReps: 10, rest: 90, alternatives: ["cableFly", "chestPressMachine"]),
        lift("assistedDip", "Assisted dip machine", .accessory, "Machine", warm: nil, start: nil, increment: 0, reps: 10, minReps: 8,
             rest: 120, alternatives: ["tricepsMachine", "cablePushdown"],
             cue: "Use as little assistance as lets you do 10 clean reps; reduce it over time."),
        lift("assistedPullUp", "Assisted pull-up", .main, "Machine", warm: nil, start: nil, increment: 0, reps: 10, minReps: 8,
             rest: 120, alternatives: ["latPulldown", "seatedCableRow"],
             cue: "Full stretch at the bottom. Use as little assistance as lets you do 10 clean reps."),
        lift("bentOverDBRow", "Bent-over dumbbell row", .main, "Dumbbells", warm: nil, start: nil, perSide: true, increment: 2,
             reps: 12, minReps: 10, rest: 90, alternatives: ["dumbbellRow", "seatedCableRow", "barbellRow"],
             cue: "Flat back, pull to your hips, no swinging."),
        lift("machineCurl", "Machine biceps curl", .accessory, "Machine", warm: nil, start: nil, increment: 2.5, reps: 12,
             minReps: 10, rest: 60, alternatives: ["cableCurl", "ezBarCurl"], cue: "Full stretch at the bottom, no half reps."),
        lift("legPress", "Leg press", .main, "Machine", warm: nil, start: nil, increment: 5, reps: 15, minReps: 12, rest: 120,
             knee: .moderate, alternatives: ["singleLegPress", "gobletSquat", "hipThrust"],
             cue: "Feet high on the platform, 2–3 seconds down, stop before any knee pain."),
        lift("legExtension", "Seated leg extension", .accessory, "Machine", warm: nil, start: nil, increment: 2.5, reps: 12,
             minReps: 10, rest: 90, knee: .moderate, alternatives: ["gobletSquat", "wallSit"],
             cue: "Light and slow; skip it if the front of the knee complains."),
        lift("seatedCalfRaise", "Seated calf raise", .accessory, "Machine", warm: nil, start: nil, increment: 5, reps: 15,
             minReps: 12, rest: 60, alternatives: ["standingCalfRaise", "singleLegBalance"],
             cue: "Full stretch at the bottom, pause at the top."),
        lift("standingCalfRaise", "Standing calf raise", .accessory, "Bodyweight", warm: nil, start: nil, increment: 0, reps: 15,
             minReps: 12, rest: 60, alternatives: ["seatedCalfRaise", "singleLegBalance"]),

        // The optional functional day: full body, core-focused, finished in the pool
        lift("farmersCarry", "Farmer's carry", .main, "Dumbbells", warm: nil, start: nil, perSide: true, increment: 2, sets: 2,
             reps: 40, minReps: 30, rest: 45, knee: .low, unit: .seconds, alternatives: ["romanianDeadlift", "sidePlank"],
             cue: "Tall, ribs down, short quick steps. Heavy enough that 40 seconds is hard."),
        lift("pallofPress", "Pallof press", .core, "Cable", warm: nil, start: nil, increment: 2.5, sets: 3, reps: 10, minReps: 8,
             rest: 20, unit: .repsEachSide, alternatives: ["deadBug", "sidePlank"],
             cue: "Side-on to the cable, press out and hold for a second without letting it twist you."),
        lift("hangingKneeRaise", "Hanging knee raise", .core, "Pull-up bar", warm: nil, start: nil, increment: 0, sets: 3, reps: 10,
             minReps: 8, rest: 20, alternatives: ["deadBug", "cableCrunch"],
             cue: "No swinging: curl the hips up, lower slowly."),
        lift("sidePlank", "Side plank", .core, "Bodyweight", warm: nil, start: nil, increment: 0, sets: 3, reps: 30, minReps: 20,
             rest: 20, unit: .seconds, alternatives: ["plank", "pallofPress"],
             cue: "Each side. Elbow under the shoulder, hips high, body in one line."),
        lift("swim", "Swim", .main, "Pool", warm: nil, start: nil, increment: 0, sets: 1, reps: 15, minReps: 10, rest: 0,
             unit: .minutes, alternatives: ["rowingMachine", "inclineWalk"],
             cue: "Steady front crawl, breathing every three strokes. Build the time as the Swimming card suggests."),
        lift("rowingMachine", "Rowing machine", .main, "Machine", warm: nil, start: nil, increment: 0, sets: 1, reps: 15,
             minReps: 10, rest: 0, knee: .moderate, unit: .minutes, alternatives: ["inclineWalk", "swim"],
             cue: "Legs, then lean, then arms. Easy, steady pace."),
        lift("inclineWalk", "Incline treadmill walk", .main, "Treadmill", warm: nil, start: nil, increment: 0, sets: 1, reps: 20,
             minReps: 15, rest: 0, knee: .low, unit: .minutes, alternatives: ["swim", "rowingMachine"],
             cue: "Brisk, without holding the rails. Keep the incline where the knee stays comfortable."),

        // Swaps added so every exercise has at least two options, whatever the reason (busy, sore, no kit).
        lift("inclineMachinePress", "Incline chest press machine", .main, "Machine", warm: nil, start: nil, increment: 2.5,
             rest: 90, alternatives: ["inclineDBBench", "chestPressMachine"]),
        lift("pushUp", "Push-up", .accessory, "Bodyweight", warm: nil, start: nil, increment: 0, rest: 60,
             alternatives: ["chestPressMachine", "flatDBBench"], cue: "Body in one line. Hands on a bench makes it easier."),
        lift("dumbbellRow", "Single-arm dumbbell row", .main, "Dumbbells", warm: nil, start: nil, perSide: true, increment: 2,
             rest: 90, unit: .repsEachSide, alternatives: ["seatedCableRow", "barbellRow"], cue: "Knee and hand on the bench, pull to your hip."),
        lift("facePull", "Cable face pull", .accessory, "Cable", warm: nil, start: nil, increment: 2.5, rest: 60,
             alternatives: ["trapMachine", "seatedCableRow"], cue: "Rope to your eyebrows, elbows high."),
        lift("cableCurl", "Cable biceps curl", .accessory, "Cable", warm: nil, start: nil, increment: 2.5, rest: 60,
             alternatives: ["hammerCurl", "ezBarCurl"]),
        lift("overheadTricepsExtension", "Dumbbell overhead triceps extension", .accessory, "Dumbbell", warm: nil, start: nil,
             increment: 2, rest: 60, alternatives: ["cablePushdown", "skullCrusher"]),
        lift("cableLateralRaise", "Cable lateral raise", .accessory, "Cable", warm: nil, start: nil, increment: 1.25, rest: 60,
             unit: .repsEachSide, alternatives: ["lateralRaise", "machineShoulderPress"]),
        lift("gobletSquat", "Dumbbell goblet squat", .main, "Dumbbell", warm: nil, start: nil, increment: 2, rest: 90,
             knee: .moderate, alternatives: ["boxSquat", "hipThrust"], cue: "Only as deep as is pain-free."),
        lift("legCurl", "Leg curl machine", .accessory, "Machine", warm: nil, start: nil, increment: 2.5, rest: 60, knee: .low,
             alternatives: ["romanianDeadlift", "gluteBridge"]),
        lift("cableKickback", "Cable glute kickback", .accessory, "Cable", warm: nil, start: nil, increment: 2.5, rest: 45,
             knee: .low, unit: .repsEachSide, alternatives: ["hipThrust", "gluteBridge"]),
        lift("deadBug", "Dead bug", .core, "Bodyweight", warm: nil, start: nil, increment: 0, sets: 3, reps: 10, minReps: 8,
             rest: 45, unit: .repsEachSide, alternatives: ["plank", "cableCrunch"], cue: "Lower back stays pressed into the floor."),
        lift("wallSit", "Shallow wall sit", .rehab, "Bodyweight", warm: nil, start: nil, increment: 0, sets: 3, reps: 30,
             minReps: 20, rest: 45, knee: .low, unit: .seconds, alternatives: ["stepDown", "gluteBridge"],
             cue: "Only as deep as is pain-free; a shallow angle is fine."),
        lift("clamshell", "Banded clamshell", .rehab, "Resistance band", warm: nil, start: nil, increment: 0, sets: 3, reps: 15,
             minReps: 12, rest: 30, unit: .repsEachSide, alternatives: ["sideLyingAbduction", "bandedLateralWalk"]),
    ]
    // swiftlint:enable function_parameter_count

    static let byID: [String: Exercise] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func exercise(_ id: String) -> Exercise? { byID[id] }
}
