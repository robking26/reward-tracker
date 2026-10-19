import Foundation

/// The facts, goals and backlog from the Vaultality 2.0 brief, loaded once into memory so the coach never
/// has to ask for them (C1). Everything is marked as coming from the brief and can be edited or deleted (M4).
enum SeedProfile {
    struct Fact {
        var store: MemoryStore
        var key: String
        var value: String
        var sensitivity: Sensitivity = .general
    }

    struct RoutineSeed {
        var title: String
        var kind: CommitmentKind
        var weekdays: Set<Int>
        var minuteOfDay: Int?
        var durationMinutes: Int
        var reason: String
    }

    struct TaskSeed {
        var title: String
        var minutes: Int
        var priority: Int
        var subtasks: [(String, Int)] = []
    }

    static let facts: [Fact] = [
        // Profile
        Fact(store: .profile, key: "About", value: "32, UK-based senior product designer."),
        Fact(store: .profile, key: "ADHD", value: "Diagnosed ADHD. Struggles to start tasks; once going, focuses for long stretches and loses track of time. Restarting after interruptions is hard. Big lists and rigid schedules overwhelm; likes structure but not repetitive days.", sensitivity: .medical),
        Fact(store: .profile, key: "Motivation", value: "Responds to tangible, visible results (fitness and appearance) and to the risk of losing money. Wants firm, direct, consistent coaching and autonomy, not micromanagement."),
        Fact(store: .profile, key: "75 Hard", value: "Completed 75 Hard; a broken streak on holiday collapsed motivation afterwards. No unbroken-streak mechanics."),
        Fact(store: .profile, key: "Wife", value: "Becky. Part of life context only: never coached, monitored, assigned tasks or scored.", sensitivity: .relationship),
        Fact(store: .profile, key: "Screens", value: "Wants less screen time outside work and protected evenings. Often forgets evening self-care."),

        // Goals
        Fact(store: .objective, key: "Body composition", value: "From about 95.3 kg (15 st) and about 30% body fat towards 10–12%, safely and sustainably. Readings are trends, not truths.", sensitivity: .medical),
        Fact(store: .objective, key: "Training", value: "Build to 4 gym sessions a week (2 upper, 2 lower, 45–60 min including warm-up and rehab) plus 1 swim attached to a gym visit."),
        Fact(store: .objective, key: "Steps", value: "Start around 7,000 a day (check the real Health baseline first), building gradually towards 12,500 within knee tolerance."),
        Fact(store: .objective, key: "Five-a-side", value: "Return to casual five-a-side with friends by October 2027, only if functionally ready. The date is not medical clearance.", sensitivity: .medical),
        Fact(store: .objective, key: "Home move", value: "Prepare the house for sale around Jan/Feb 2027; aim to move within about six months, to a home suited to family life."),
        Fact(store: .objective, key: "Lifestyle", value: "Less automatic drinking, little or no social vaping, gambling not automatic when socialising, more varied time with friends, more time with Becky, spontaneous outings, protected evenings, self-care."),
        Fact(store: .objective, key: "Swimming", value: "Rebuild towards Darwen Masters (60–90 minute sessions) within 12 months. Low pressure."),

        // Work
        Fact(store: .work, key: "Hours", value: "Prefers 08:00–16:00, finishing at 16:00. Peak design focus about 13:00–16:00. Office days vary; read them from the calendar."),
        Fact(store: .work, key: "Personal projects", value: "Personal projects never displace employment work. Workday time is only borrowed with explicit approval when workload genuinely allows."),

        // Preferences
        Fact(store: .preference, key: "Morning", value: "Wakes about 05:55 on weekdays. Does own routine first (weigh-in, shower, teeth, dressed), then says \"I'm ready\" for the briefing."),
        Fact(store: .preference, key: "Gym", value: "Nuffield Health Bolton. Prefers quieter times."),
        Fact(store: .preference, key: "Walking", value: "Enjoys walking, ideally at lunchtime. Wants 5 minutes to get ready. Dislikes walking in rain. Podcasts sometimes, quiet walks sometimes (no forced mindfulness)."),
        Fact(store: .preference, key: "Strength progression", value: "3 sets, usually 10 reps (8–10 acceptable; some lifts 3×8). Move up one increment after hitting the target in three consecutive relevant sessions; hold if technique or symptoms say so."),
        Fact(store: .preference, key: "Rehab timing", value: "More likely to skip rehab at the end of a session, so default it to the start after the warm-up (ask each session)."),
        Fact(store: .preference, key: "Notifications", value: "Dislikes constant interruptions. Discreet prompts in the office, no voice there."),

        // Knee
        Fact(store: .rehab, key: "History", value: "Right lateral knee pain since March 2025, reinjured playing football. Two physio assessments pointed to IT-band-related problems. Running and changing direction provoke symptoms; pain can be delayed to the next day. A previous reinjury caused sharp pain and prolonged swelling. Normal walking is generally fine. Left leg currently stronger.", sensitivity: .medical),
        Fact(store: .rehab, key: "Previous exercises", value: "Hip, glute and single-leg strength and control; physio recommended them daily.", sensitivity: .medical),
        Fact(store: .rehab, key: "KT tape", value: "Changes when symptoms start but doesn't guarantee the knee tolerates more.", sensitivity: .medical),

        // Food
        Fact(store: .nutrition, key: "Safety", value: "History of binge and secret eating: no fasting or big deficits by default, no moralising food, no compensatory exercise. Food is never fined.", sensitivity: .medical),
        Fact(store: .nutrition, key: "Never", value: "Mushrooms, courgette, cauliflower."),
        Fact(store: .nutrition, key: "Dinner", value: "Shared with Becky, two identical portions, about 19:00, plenty of variety. Friday can be a fakeaway, cooking or eating out."),
        Fact(store: .nutrition, key: "Lunch", value: "Same lunch Monday–Friday is fine, 4-week rotation, cheap, high protein, microwave at work. Chicken, turkey mince, pork, rice, vegetables, varied sauces."),
        Fact(store: .nutrition, key: "Kitchen", value: "Air fryer, oven, microwave, slow cooker, hob. No dishwasher: 5–10 minutes of washing up at most. One-pot, one-pan, tray bakes. Slow-cooker prep only on work-from-home mornings."),
        Fact(store: .nutrition, key: "Batch cooking", value: "One hour at most: five lunches plus extra freezer dinners where they fit."),
        Fact(store: .nutrition, key: "Shopping", value: "Aldi first, Co-op as a fallback. £400 a month household ceiling (groceries, toiletries, cleaning, top-ups, food-budget takeaways and meals out). A ceiling, not a target.", sensitivity: .financial),

        // Social
        Fact(store: .social, key: "Drinking", value: "Social drinking ranges from about 4 to 10 pints, usually the lower end. Goal: less automatic drinking, not necessarily abstinence. Recovery after heavy nights takes 48–72 hours.", sensitivity: .medical),
        Fact(store: .social, key: "Alternatives", value: "Golf (range or casual), five-a-side when ready, walking, days out and dates with Becky."),
        Fact(store: .social, key: "Gambling", value: "Never suggest gambling or link drinking to gambling."),
    ]

    /// Suggested routines, all **off** until the user agrees to them (A3).
    static let routines: [RoutineSeed] = [
        RoutineSeed(title: "Lunchtime walk", kind: .walk, weekdays: [1, 2, 3, 4, 5], minuteOfDay: 12 * 60 + 10,
                    durationMinutes: 30, reason: "Gets you outside daily and builds steps gradually."),
        RoutineSeed(title: "Knee rehab exercises", kind: .rehab, weekdays: [1, 2, 3, 4, 5, 6, 7], minuteOfDay: nil,
                    durationMinutes: 15, reason: "Your physio recommended daily hip, glute and single-leg work."),
        RoutineSeed(title: "Evening self-care", kind: .selfCare, weekdays: [1, 2, 3, 4, 5, 6, 7], minuteOfDay: 21 * 60 + 30,
                    durationMinutes: 15, reason: "The routine you most often forget; protects sleep and evenings."),
        RoutineSeed(title: "Wash up after dinner", kind: .household, weekdays: [1, 2, 3, 4, 5, 6, 7], minuteOfDay: 20 * 60,
                    durationMinutes: 10, reason: "No dishwasher, so ten minutes each night stops it piling up."),
    ]

    /// The house-sale backlog (H2), most important first. Subtasks show how big jobs break down.
    static let houseSale: [TaskSeed] = [
        TaskSeed(title: "Tidy and sort the attic", minutes: 120, priority: 4, subtasks: [
            ("Clear a space to sort into", 15), ("Sort one corner: keep, sell, tip", 30), ("Bag up tip items", 20),
            ("Book or plan a tip run", 5),
        ]),
        TaskSeed(title: "Tip runs for unwanted items", minutes: 60, priority: 3),
        TaskSeed(title: "Finish kitchen skirting boards", minutes: 180, priority: 4, subtasks: [
            ("Measure the missing sections", 15), ("List materials needed", 10), ("Buy skirting and adhesive", 45),
            ("Cut and fix the first piece", 30), ("Fill joints and caulk", 30), ("Paint", 45), ("Clean up", 15),
        ]),
        TaskSeed(title: "Finish office skirting boards", minutes: 150, priority: 3),
        TaskSeed(title: "Paint the main bedroom", minutes: 300, priority: 3),
        TaskSeed(title: "Touch up paintwork", minutes: 90, priority: 2),
        TaskSeed(title: "Clean the carpets", minutes: 180, priority: 2),
        TaskSeed(title: "Jet-wash the rear area", minutes: 120, priority: 2),
        TaskSeed(title: "Paint the rear walls", minutes: 240, priority: 2),
        TaskSeed(title: "Repair and repoint the front patio joints", minutes: 180, priority: 2),
        TaskSeed(title: "Final deep clean", minutes: 360, priority: 2),
        TaskSeed(title: "Contact estate agents", minutes: 45, priority: 3),
        TaskSeed(title: "Arrange valuation and photography", minutes: 30, priority: 2),
    ]

    /// Guesses the area for a task added in conversation. A guess is harmless here: the user can move it.
    static func area(forTask title: String) -> TaskArea {
        let lowered = title.lowercased()
        let houseSale = ["attic", "skirting", "paint", "carpet", "patio", "jet", "repoint", "estate agent", "valuation",
                         "tip run", "deep clean", "decorat", "caulk", "photograph"]
        let household = ["laundry", "washing", "hoover", "vacuum", "clean", "dishes", "wash up", "bins", "rubbish",
                         "bed linen", "bedding", "tidy", "iron", "dryer", "shopping", "defrost", "cook"]
        let work = ["figma", "betslip", "deck", "design review", "work"]
        if houseSale.contains(where: { lowered.contains($0) }) { return .houseSale }
        if household.contains(where: { lowered.contains($0) }) { return .household }
        if work.contains(where: { lowered.contains($0) }) { return .work }
        return .personal
    }
}
