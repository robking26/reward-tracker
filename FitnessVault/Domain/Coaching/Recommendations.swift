import Foundation

/// One suggestion the coach can make, with its reasoning (E4). Becomes a *proposed* commitment;
/// it only counts once the user agrees.
struct Recommendation: Hashable, Sendable {
    var title: String
    var kind: CommitmentKind
    var start: Date?
    var durationMinutes: Int
    var weight: Int
    var objective: Objective
    /// Why this, why now. Shown on Today and said in the briefing.
    var reason: String
    /// What the coach would offer instead if the answer is no.
    var alternative: String?
    /// How the coach asks the question, e.g. "Shall we train then?"
    var question: String
}

/// Everything the morning briefing needs to know, already gathered by the app (S1).
struct RecommendationInput: Sendable {
    var day: DayKey
    var now: Date
    var calendar: Calendar
    var settings: CoachSettings
    var isWorkday: Bool
    /// Free windows from the availability engine (after `now`).
    var windows: [OpportunityWindow]
    /// Today's classified calendar events.
    var events: [ClassifiedEvent]
    /// Kinds already proposed or agreed today, so nothing is suggested twice.
    var existingKinds: Set<CommitmentKind>
    /// Workouts completed or agreed earlier this week (Monday–yesterday).
    var workoutsThisWeek: Int
    /// Consecutive days with a completed workout, ending yesterday.
    var consecutiveWorkoutDays: Int
    /// True if the last completed workout was an upper-body session.
    var lastWorkoutWasUpper: Bool?
    /// The highest-priority house task that can be done now: title and minutes.
    var houseTask: HouseTaskSuggestion?

    // Phase 6 context. The defaults keep the morning plan as it was when nothing is known.
    /// Hourly forecast; empty when weather is off or unavailable (never guessed).
    var forecast: [HourlyWeather] = []
    var recovery: RecoveryStatus = .clear
    /// One-way gym travel to plan with, when a live estimate is available.
    var gymTravelMinutes: Int? = nil
    var busyness: [BusynessReport] = []
    /// A social plan this evening: physical suggestions finish an hour before it.
    var socialEveningStart: Date? = nil
}

struct HouseTaskSuggestion: Hashable, Sendable {
    var title: String
    var minutes: Int
}

/// Deterministic morning suggestions (B3, S1). The language model only words them.
enum RecommendationEngine {
    /// The project starts on 19 October 2026; gym sessions ramp up from there (O-A).
    static let projectStart = DayKey(year: 2026, month: 10, day: 19)

    /// Two sessions a week for the first fortnight, three for the next two weeks, then four.
    static func weeklyWorkoutTarget(on day: DayKey, calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: projectStart.startDate(calendar: calendar),
                                           to: day.startDate(calendar: calendar)).day ?? 0
        switch max(0, days) / 7 {
        case 0, 1: return 2
        case 2, 3: return 3
        default: return 4
        }
    }

    static func morning(_ input: RecommendationInput) -> [Recommendation] {
        var windows = protectEvenings(input.windows, day: input.day, settings: input.settings, calendar: input.calendar)
        if let social = input.socialEveningStart {
            windows = clip(windows, before: social.addingTimeInterval(-60 * 60))
        }
        switch input.recovery {
        case .recovering(let feeling):
            return recoveryDay(input, windows: windows, feeling: feeling)
        case .restarting:
            return restartDay(input, windows: windows)
        case .clear:
            break
        }
        var result: [Recommendation] = []

        func reserve(_ start: Date, minutes: Int) {
            let block = DateInterval(start: start, duration: TimeInterval(minutes * 60))
            windows = windows.flatMap { window in
                Availability.subtract([block], from: window.interval).compactMap { piece in
                    piece.duration >= TimeInterval(Availability.minimumWindowMinutes * 60)
                        ? OpportunityWindow(interval: piece, kind: window.kind) : nil
                }
            }
        }

        // 1. Gym, if the week's target isn't met and recovery allows.
        var gymPlanned = false
        let target = weeklyWorkoutTarget(on: input.day, calendar: input.calendar)
        if !input.existingKinds.contains(.workout), input.workoutsThisWeek < target, input.consecutiveWorkoutDays < 2,
           let gym = gymRecommendation(input, windows: windows) {
            result.append(gym)
            if let start = gym.start { reserve(start, minutes: gym.durationMinutes) }
            gymPlanned = true
        }

        // 2. Walk: lunchtime on workdays, otherwise a daytime gap.
        if !input.existingKinds.contains(.walk), let walk = walkRecommendation(input, windows: windows) {
            result.append(walk)
            if let start = walk.start { reserve(start, minutes: walk.durationMinutes) }
        }

        // 3. Knee rehab: inside the gym session when there is one, otherwise on its own.
        if !input.existingKinds.contains(.rehab) && !gymPlanned {
            result.append(Recommendation(
                title: "Knee rehab exercises", kind: .rehab, start: nil, durationMinutes: 15, weight: 3, objective: .knee,
                reason: "Your physio recommended hip, glute and single-leg work daily.",
                alternative: "Even five minutes of glute bridges counts for something.",
                question: "Fit your knee exercises in today?"))
        }

        // 4. A house-sale task on days off, if there's a sensible gap.
        if !input.isWorkday, let task = input.houseTask, let window = windows.first(where: { window in
            window.kind == .free && window.minutes >= task.minutes + 10 && hour(of: window.interval.start, input) < 17
        }) {
            let start = window.interval.start
            result.append(Recommendation(
                title: task.title, kind: .household, start: start, durationMinutes: task.minutes, weight: 1,
                objective: .homeMove, reason: "One step closer to the sale. It's the next job on the list.",
                alternative: "Or pick something smaller from the list.",
                question: "\(task.title) at \(time(start, input))?"))
            reserve(start, minutes: task.minutes)
        }

        // 5. Evening self-care at wind-down.
        result += selfCare(input)

        return result.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    // MARK: Recovery (SO3)

    /// Recovering: nothing demanding. A gentle walk only once the user feels up to it, and the usual self-care.
    private static func recoveryDay(_ input: RecommendationInput, windows: [OpportunityWindow],
                                    feeling: RecoveryFeeling) -> [Recommendation] {
        var result: [Recommendation] = []
        if feeling == .gettingThere, !input.existingKinds.contains(.walk),
           let window = walkWindow(input, windows: windows, minutes: 20) {
            result.append(Recommendation(
                title: "Gentle walk", kind: .walk, start: window, durationMinutes: 20, weight: 1, objective: .health,
                reason: "Fresh air helps. Only if you feel up to it.", alternative: "Or rest. That's fine too.",
                question: "A short, easy walk at \(time(window, input))?"))
        }
        result += selfCare(input)
        return result
    }

    /// The first day back: one manageable action, and make the gym easy to attend (SO3).
    private static func restartDay(_ input: RecommendationInput, windows: [OpportunityWindow]) -> [Recommendation] {
        var result: [Recommendation] = []
        if !input.existingKinds.contains(.workout),
           input.workoutsThisWeek < weeklyWorkoutTarget(on: input.day, calendar: input.calendar),
           var gym = gymRecommendation(input, windows: windows, activeMinutes: 40) {
            let first: String = gym.title.prefix(1).lowercased()
            let rest = String(gym.title.dropFirst())
            gym.title = "Easy \(first)\(rest)"
            gym.weight = 3
            gym.reason = "First day back. Lighter weights, 40 minutes, then home. Just turning up is the win."
            result.append(gym)
        } else if !input.existingKinds.contains(.walk), let start = walkWindow(input, windows: windows, minutes: 30) {
            result.append(Recommendation(
                title: "Walk", kind: .walk, start: start, durationMinutes: 30, weight: 2, objective: .health,
                reason: "One easy thing to get going again.", alternative: "Ten minutes still counts.",
                question: "Walk at \(time(start, input))?"))
        }
        result += selfCare(input)
        return result
    }

    private static func selfCare(_ input: RecommendationInput) -> [Recommendation] {
        guard !input.existingKinds.contains(.selfCare) else { return [] }
        let start = at(input.settings.windDownMinute, input)
        guard start > input.now else { return [] }
        return [Recommendation(
            title: "Evening self-care", kind: .selfCare, start: start, durationMinutes: 15, weight: 2,
            objective: .lifestyle, reason: "Phone down, teeth, ready for bed. It protects your sleep.",
            alternative: nil, question: "Self-care at \(time(start, input)) tonight?")]
    }

    /// A dry daytime start for a walk, or any daytime start when there's no forecast.
    private static func walkWindow(_ input: RecommendationInput, windows: [OpportunityWindow], minutes: Int) -> Date? {
        let daytime = windows.filter { window in
            window.kind != .workGap && window.minutes >= minutes && (9..<18).contains(hour(of: window.interval.start, input))
        }
        if !input.forecast.isEmpty {
            return WeatherAdvisor.firstDryStart(in: daytime, minutes: minutes, forecast: input.forecast, notBefore: input.now)?.start
        }
        return daytime.first.map { max($0.interval.start, input.now) }
    }

    private static func clip(_ windows: [OpportunityWindow], before end: Date) -> [OpportunityWindow] {
        windows.compactMap { window in
            guard window.interval.start < end else { return nil }
            let clipped = DateInterval(start: window.interval.start, end: min(window.interval.end, end))
            return clipped.duration >= TimeInterval(Availability.minimumWindowMinutes * 60)
                ? OpportunityWindow(interval: clipped, kind: window.kind) : nil
        }
    }

    // MARK: Pieces

    private static func gymRecommendation(_ input: RecommendationInput, windows: [OpportunityWindow],
                                          activeMinutes: Int = 60) -> Recommendation? {
        let travel = input.gymTravelMinutes ?? input.settings.gymTravelMinutes
        let need = ActivityNeed(activeMinutes: activeMinutes, travelMinutesEachWay: travel, preparationMinutes: 10, allowedKinds: [.free])
        let fits = Availability.fits(need, in: windows)
        guard !fits.isEmpty else { return nil }

        // Prefer a gap while Becky is busy, then after work, then whatever fits.
        let beckyBusy = input.events.filter { $0.kind == .sharedInfo && !$0.event.isAllDay }
        let workEnd = at(input.settings.workEndMinute, input)
        var reasonLead = ""
        let chosen: OpportunityWindow
        if let pair = fits.lazy.compactMap({ window in
            beckyBusy.first(where: { $0.event.start >= window.interval.start && $0.event.start < window.interval.end }).map { (window, $0) }
        }).first {
            chosen = pair.0
            reasonLead = "Becky's at \(pair.1.event.title.lowercased()) at \(time(pair.1.event.start, input)). "
        } else if let quiet = quietest(fits, input: input) {
            // The user's own busy/quiet reports, labelled as such (L3).
            chosen = quiet.window
            reasonLead = quiet.estimate.label + ". "
        } else if let after = fits.first(where: { $0.interval.end > workEnd && $0.interval.start >= workEnd.addingTimeInterval(-60 * 60) }) {
            chosen = after
        } else {
            chosen = fits[0]
        }

        // Line the session up with Becky's event if there is one (as late as still fits), otherwise start of the gap.
        var start = chosen.interval.start
        if let event = beckyBusy.first(where: { chosen.interval.contains($0.event.start) }) {
            let desired = event.event.start.addingTimeInterval(-TimeInterval((travel + 10) * 60))
            let latest = chosen.interval.end.addingTimeInterval(-TimeInterval(need.totalMinutes * 60))
            start = max(chosen.interval.start, min(desired, latest))
        }
        let upper = !(input.lastWorkoutWasUpper ?? false)
        let focus = upper ? "Upper body" : "Lower body"
        let rehab = upper ? "Brief knee work after your warm-up." : "Knee rehab goes first, after your warm-up."
        return Recommendation(
            title: "\(focus) at Nuffield", kind: .workout, start: start, durationMinutes: need.totalMinutes, weight: 4,
            objective: .health,
            reason: "\(reasonLead)You've got time for the full trip (\(need.totalMinutes) min door to door). \(rehab)",
            alternative: "If not, a 30-minute walk keeps you moving.",
            question: "Shall we train at \(time(start, input))?")
    }

    /// The fitting window with the quietest estimate, when the reports clearly prefer one.
    private static func quietest(_ fits: [OpportunityWindow], input: RecommendationInput)
        -> (window: OpportunityWindow, estimate: BusynessEstimate)? {
        let rated = fits.compactMap { window -> (window: OpportunityWindow, estimate: BusynessEstimate)? in
            GymBusynessEstimator.estimate(at: window.interval.start, reports: input.busyness, calendar: input.calendar)
                .map { (window: window, estimate: $0) }
        }
        guard let best = rated.min(by: { $0.estimate.level.score < $1.estimate.level.score }),
              best.estimate.level != .busy else { return nil }
        return best
    }

    private static func walkRecommendation(_ input: RecommendationInput, windows: [OpportunityWindow]) -> Recommendation? {
        if input.isWorkday {
            guard let lunch = windows.first(where: { $0.kind == .lunch && $0.minutes >= 35 }) else { return nil }
            // Five minutes to get ready first (K2).
            let start = lunch.interval.start.addingTimeInterval(5 * 60)
            // Avoid walking in the rain (K2): find a dry slot later, or skip the walk rather than nag.
            if WeatherAdvisor.isDry(DateInterval(start: start, duration: 30 * 60), forecast: input.forecast) == false {
                let later = windows.filter { $0.kind != .workGap && $0.interval.start > start }
                guard let dry = WeatherAdvisor.firstDryStart(in: later, minutes: 30, forecast: input.forecast, notBefore: start),
                      hour(of: dry.start, input) < 18 else { return nil }
                return Recommendation(
                    title: "Walk", kind: .walk, start: dry.start, durationMinutes: 30, weight: 2, objective: .health,
                    reason: "Rain's forecast at lunch, but it should be dry at \(time(dry.start, input)).",
                    alternative: "Ten minutes round the block still counts.",
                    question: "Walk at \(time(dry.start, input)) instead?")
            }
            return Recommendation(
                title: "Lunchtime walk", kind: .walk, start: start, durationMinutes: 30, weight: 2, objective: .health,
                reason: "Lunch is clear. Getting outside keeps your steps building.",
                alternative: "Ten minutes round the block still counts.",
                question: "Walk at \(time(start, input))?")
        }
        let daytime = windows.filter { window in
            window.kind == .free && window.minutes >= 40 && (9..<17).contains(hour(of: window.interval.start, input))
        }
        let start: Date
        if !input.forecast.isEmpty {
            guard let dry = WeatherAdvisor.firstDryStart(in: daytime, minutes: 40, forecast: input.forecast, notBefore: input.now)
            else { return nil }
            start = dry.start
        } else {
            guard let window = daytime.first else { return nil }
            start = window.interval.start
        }
        return Recommendation(
            title: "Walk", kind: .walk, start: start, durationMinutes: 40, weight: 2, objective: .health,
            reason: "A clear stretch of daylight. Get outside.",
            alternative: "Or a shorter one later.", question: "Walk at \(time(start, input))?")
    }

    /// Physical suggestions stop at wind-down and keep clear of dinner (S3: protect dinner, self-care and sleep).
    static func protectEvenings(_ windows: [OpportunityWindow], day: DayKey, settings: CoachSettings,
                                calendar: Calendar) -> [OpportunityWindow] {
        let dinner = DateInterval(start: day.date(atMinute: settings.dinnerMinute, calendar: calendar), duration: 60 * 60)
        let windDown = day.date(atMinute: settings.windDownMinute, calendar: calendar)
        return windows.flatMap { window -> [OpportunityWindow] in
            guard window.interval.start < windDown else { return [] }
            let clipped = DateInterval(start: window.interval.start, end: min(window.interval.end, windDown))
            return Availability.subtract([dinner], from: clipped).compactMap { piece in
                piece.duration >= TimeInterval(Availability.minimumWindowMinutes * 60)
                    ? OpportunityWindow(interval: piece, kind: window.kind) : nil
            }
        }
    }

    private static func at(_ minute: Int, _ input: RecommendationInput) -> Date {
        input.day.date(atMinute: minute, calendar: input.calendar)
    }

    private static func hour(of date: Date, _ input: RecommendationInput) -> Int {
        input.calendar.component(.hour, from: date)
    }

    private static func time(_ date: Date, _ input: RecommendationInput) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = input.calendar.timeZone
        return date.formatted(style)
    }
}

// MARK: - Replanning (S3, scenario B)

/// A commitment that now clashes with something in the calendar.
struct ScheduleConflict: Hashable, Sendable {
    var commitmentID: UUID
    var eventTitle: String
    var eventStart: Date
}

struct ScheduledItem: Hashable, Sendable {
    var id: UUID
    var interval: DateInterval
}

enum Replanner {
    /// Agreed or proposed commitments still ahead that overlap a meeting, focus block or personal event.
    /// Becky's events and all-day markers never clash.
    static func conflicts(_ items: [ScheduledItem], events: [ClassifiedEvent], now: Date) -> [ScheduleConflict] {
        let blocking = events.filter { $0.kind.blocksUser && $0.event.end > $0.event.start }
        return items.compactMap { item in
            guard item.interval.start > now else { return nil }
            guard let clash = blocking.first(where: {
                DateInterval(start: $0.event.start, end: $0.event.end).intersection(with: item.interval).map { $0.duration > 0 } ?? false
            }) else { return nil }
            return ScheduleConflict(commitmentID: item.id, eventTitle: clash.event.title, eventStart: clash.event.start)
        }
    }

    /// The first window that fits the whole activity, after `notBefore`.
    static func alternative(for need: ActivityNeed, in windows: [OpportunityWindow], notBefore: Date) -> Date? {
        windows.first { window in
            window.interval.end > notBefore && Availability.firstFit(need, in: [window]) != nil
        }.map { max($0.interval.start, notBefore) }
    }
}

// MARK: - Launch mode (C3)

/// Tiny first steps for starting, by kind. Once the user is going, the coach backs off.
enum LaunchSteps {
    static func steps(for kind: CommitmentKind) -> [String] {
        switch kind {
        case .workout: ["Kit on.", "Bottle filled, bag by the door.", "Keys. Out the door."]
        case .swim: ["Swim bag: trunks, goggles, towel.", "Bag by the door.", "Out the door."]
        case .walk: ["Trainers on.", "Phone and keys.", "Out the door. Podcast optional."]
        case .rehab: ["Find a clear bit of floor.", "Ten glute bridges.", "Next exercise, slowly."]
        case .selfCare: ["Phone on charge, out of the bedroom.", "Teeth.", "Skin care, then bed."]
        case .household: ["Put one thing away.", "Then the next.", "Keep going for five minutes."]
        case .meal: ["Pan out.", "Ingredients on the side.", "Start the first step of the recipe."]
        case .work: ["Open the file.", "Find where you left off.", "Do the next small bit."]
        case .social, .other: ["Do the very first bit.", "Then the next.", "Keep going."]
        }
    }
}
