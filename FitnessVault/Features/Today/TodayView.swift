import SwiftUI

/// Today (N2): one dominant current action, what's next, what's still due, and what's at stake.
/// Never the whole backlog or the whole week.
struct TodayView: View {
    @Environment(CoachModel.self) private var coach
    @Environment(AppModel.self) private var model
    @Environment(TrainingModel.self) private var training
    @Binding var showingSettings: Bool
    var openCoach: () -> Void
    @State private var showingAdd = false
    @State private var showingWorkout = false
    @State private var workoutCommitment: Commitment?
    @State private var showingKneeCheck = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header

                    ForEach(coach.needsVerification, id: \.id) { item in
                        VerifyCard(item: item)
                    }

                    if training.isActive {
                        Button {
                            showingWorkout = true
                        } label: {
                            NoticeBanner(symbol: "dumbbell.fill", title: "Workout in progress",
                                         message: "Tap to carry on where you left off.", tint: Palette.accent)
                        }
                        .buttonStyle(CardButtonStyle())
                    }

                    if training.needsNextDayKneeCheck {
                        Button {
                            showingKneeCheck = true
                        } label: {
                            NoticeBanner(symbol: "figure.walk", title: "How's the knee this morning?",
                                         message: "Pain can show up the day after. Ten seconds to log it.", tint: Palette.accent)
                        }
                        .buttonStyle(CardButtonStyle())
                    }

                    if coach.shouldOfferBriefing {
                        Button {
                            coach.send("I'm ready")
                            openCoach()
                        } label: {
                            NoticeBanner(symbol: "sunrise", title: "I'm ready",
                                         message: "Finish your morning routine first. Then tap here and I'll take you through today, one thing at a time.",
                                         tint: Palette.accent)
                        }
                        .buttonStyle(CardButtonStyle())
                    }

                    if let current = coach.currentAction {
                        CurrentActionCard(item: current, openCoach: openCoach) {
                            workoutCommitment = current
                            showingWorkout = true
                        }
                    } else {
                        NothingNowCard(openCoach: openCoach)
                    }

                    // One suggestion at a time (B3).
                    if let proposal = coach.proposals.first {
                        ProposalCard(item: proposal)
                    }

                    if let error = coach.lastError {
                        NoticeBanner(symbol: "exclamationmark.circle", title: "Nothing changed", message: error)
                    }

                    if coach.routines().allSatisfy({ !$0.isEnabled }) && !coach.routines().isEmpty {
                        NavigationLink {
                            RoutinesView()
                        } label: {
                            NoticeBanner(symbol: "repeat", title: "Agree your daily routines",
                                         message: "Routines you agree to count each day without asking. Nothing counts until you choose.",
                                         tint: Palette.accent)
                        }
                        .buttonStyle(CardButtonStyle())
                    }

                    ComingUpCard()

                    DinnerCard()

                    if !coach.essentialsDue.isEmpty {
                        EssentialsCard(items: coach.essentialsDue)
                    }

                    AccountabilityCard()
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.xl)
                .animation(.snappy, value: coach.commitments.map(\.stateRaw))
            }
            .pageBackground()
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add a commitment")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton(isPresented: $showingSettings)
                }
            }
            .refreshable {
                await coach.refresh()
                await model.syncHealth()
            }
            .sheet(isPresented: $showingAdd) {
                AddCommitmentView()
            }
            .fullScreenCover(isPresented: $showingWorkout) {
                WorkoutFlowView(commitment: workoutCommitment)
            }
            .sheet(isPresented: $showingKneeCheck) {
                NavigationStack {
                    KneeCheckView(timing: .nextDay) { pain, swelling, sharp in
                        training.logSymptom(timing: .nextDay, pain: pain, swelling: swelling, sharp: sharp)
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.background)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            if coach.workLocation != .unknown {
                Text("·")
                Text(coach.workLocation.title)
            } else if coach.isOnLeave {
                Text("·")
                Text("Day off")
            }
        }
        .font(.subheadline)
        .foregroundStyle(Palette.textSecondary)
    }
}

// MARK: - Current action

struct CurrentActionCard: View {
    @Environment(CoachModel.self) private var coach
    let item: Commitment
    var openCoach: () -> Void
    /// Opens the workout logger for gym commitments.
    var startWorkout: (() -> Void)? = nil
    @State private var feedback = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Label(item.kind.title, systemImage: item.kind.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text(timeLabel)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(isOverdue ? Palette.warning : Palette.textSecondary)
            }

            Text(item.title)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let note = item.note, !note.isEmpty {
                Text("Where you got to: \(note)")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            } else if let reason = item.reason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if item.kind == .workout, let startWorkout {
                    startWorkout()
                    return
                }
                if item.state == .inProgress {
                    coach.transition(item, .complete)
                } else {
                    coach.transition(item, .start)
                }
                feedback += 1
            } label: {
                Text(item.kind == .workout && startWorkout != nil ? (item.state == .inProgress ? "Back to workout" : "Start workout")
                     : (item.state == .inProgress ? "Done" : "Start"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .foregroundStyle(Palette.onAccent)

            HStack(spacing: Spacing.xs) {
                if item.state != .inProgress {
                    SmallActionButton(title: "Done", symbol: "checkmark") {
                        coach.transition(item, .complete)
                        feedback += 1
                    }
                }
                Menu {
                    ForEach(laterOptions, id: \.title) { option in
                        Button(option.title) { coach.reschedule(item, to: option.date) }
                    }
                } label: {
                    SmallActionLabel(title: "Not now", symbol: "clock.arrow.circlepath")
                }
                Menu {
                    Menu("Move to tomorrow") {
                        ForEach(ExcuseReason.allCases) { reason in
                            Button(reason.title) { coach.reschedule(item, to: tomorrowSameTime, reason: reason) }
                        }
                    }
                    Menu("Not today") {
                        ForEach(ExcuseReason.allCases) { reason in
                            Button(reason.title) { coach.transition(item, .excuse(reason), reason: reason.title) }
                        }
                    }
                } label: {
                    SmallActionLabel(title: "Change plan", symbol: "arrow.triangle.branch")
                }
            }

            HStack(spacing: Spacing.xs) {
                Menu {
                    ForEach(ExcuseReason.allCases) { reason in
                        Button(reason.title) { coach.transition(item, .excuse(reason), reason: reason.title) }
                    }
                    Divider()
                    Button("I just don't fancy it") {
                        coach.send("I don't fancy it")
                        openCoach()
                    }
                } label: {
                    SmallActionLabel(title: "Something's blocking me", symbol: "hand.raised")
                }
                SmallActionButton(title: "Talk to coach", symbol: "bubble.left") { openCoach() }
            }
        }
        .surface(radius: Radius.hero, padding: Spacing.l)
        .sensoryFeedback(.success, trigger: feedback)
    }

    private var isOverdue: Bool {
        guard let start = item.scheduledStart, item.state == .approved else { return false }
        return start.addingTimeInterval(15 * 60) < coach.now()
    }

    private var timeLabel: String {
        if item.state == .inProgress { return "In progress" }
        guard let start = item.scheduledStart else { return "Any time today" }
        if isOverdue { return "Was due \(start.formatted(date: .omitted, time: .shortened))" }
        return start <= coach.now() ? "Now" : start.formatted(date: .omitted, time: .shortened)
    }

    private struct LaterOption {
        var title: String
        var date: Date
    }

    private var laterOptions: [LaterOption] {
        let now = coach.now()
        var options = [LaterOption(title: "In 30 minutes", date: now.addingTimeInterval(30 * 60)),
                       LaterOption(title: "In an hour", date: now.addingTimeInterval(60 * 60))]
        let evening = coach.today.startDate(calendar: coach.calendar)
            .addingTimeInterval(TimeInterval(max(coach.coach.workEndMinute + 60, 18 * 60) * 60))
        if evening > now.addingTimeInterval(60 * 60) { options.append(LaterOption(title: "This evening", date: evening)) }
        return options
    }

    private var tomorrowSameTime: Date {
        let tomorrow = coach.today.adding(days: 1, calendar: coach.calendar).startDate(calendar: coach.calendar)
        guard let start = item.scheduledStart else { return tomorrow.addingTimeInterval(12 * 3_600) }
        return tomorrow.addingTimeInterval(start.timeIntervalSince(coach.today.startDate(calendar: coach.calendar)))
    }
}

struct SmallActionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Spacing.s)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

struct SmallActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SmallActionLabel(title: title, symbol: symbol)
        }
        .buttonStyle(CardButtonStyle())
    }
}

struct NothingNowCard: View {
    @Environment(CoachModel.self) private var coach
    var openCoach: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Nothing agreed right now")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.xs) {
                SmallActionButton(title: "I'm ready", symbol: "sunrise") {
                    coach.send("I'm ready")
                    openCoach()
                }
                SmallActionButton(title: "What's next?", symbol: "arrow.forward") {
                    coach.send("What's next?")
                    openCoach()
                }
            }
        }
        .surface(radius: Radius.hero, padding: Spacing.l)
    }

    private var message: String {
        if let window = coach.nextOpportunity {
            return "You've got \(DurationFormat.text(minutes: window.minutes)) from \(window.interval.start.formatted(date: .omitted, time: .shortened)). Rest is allowed too."
        }
        return "Protect your evening."
    }
}

// MARK: - Verification, proposals

/// "Did you do this?" for earlier commitments (D-014). Never assumes silence means a miss.
struct VerifyCard: View {
    @Environment(CoachModel.self) private var coach
    let item: Commitment

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("\(dayLabel): did you do this?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            Label(item.title, systemImage: item.kind.symbol)
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
            HStack(spacing: Spacing.xs) {
                SmallActionButton(title: "Yes, done", symbol: "checkmark") { coach.transition(item, .complete) }
                SmallActionButton(title: "No", symbol: "xmark") { coach.transition(item, .markMissed) }
                Menu {
                    ForEach(ExcuseReason.allCases) { reason in
                        Button(reason.title) { coach.transition(item, .excuse(reason), reason: reason.title) }
                    }
                } label: {
                    SmallActionLabel(title: "Couldn't", symbol: "questionmark")
                }
            }
            Text("Unanswered by the end of today counts as missed. You can still correct it until the month closes.")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .surface()
    }

    private var dayLabel: String {
        guard let day = item.dayKey else { return "Earlier" }
        if day == coach.today.adding(days: -1, calendar: coach.calendar) { return "Yesterday" }
        return day.startDate(calendar: coach.calendar).formatted(.dateTime.weekday(.wide))
    }
}

struct ProposalCard: View {
    @Environment(CoachModel.self) private var coach
    let item: Commitment

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Suggestion")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.accent)
            Text(item.title + (item.scheduledStart.map { " at \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
            if let reason = item.reason {
                Text(reason).font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
            HStack(spacing: Spacing.xs) {
                SmallActionButton(title: "Agree", symbol: "checkmark") { coach.transition(item, .approve) }
                SmallActionButton(title: "Not today", symbol: "xmark") { coach.transition(item, .cancel, reason: "Declined") }
            }
        }
        .surface()
    }
}

// MARK: - Coming up, essentials, accountability

struct ComingUpCard: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        let rows = self.rows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Coming up")
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        let row = rows[index]
                        HStack(spacing: Spacing.s) {
                            Image(systemName: row.symbol)
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title).font(.subheadline).foregroundStyle(Palette.textPrimary)
                                Text(row.detail).font(.caption).foregroundStyle(Palette.textTertiary)
                            }
                            Spacer()
                            Text(row.time)
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .padding(.vertical, Spacing.xs)
                        .accessibilityElement(children: .combine)
                        if index < rows.count - 1 { Divider().overlay(Palette.border) }
                    }
                }
                .surface(padding: Spacing.m)
            }
        }
    }

    private struct Row {
        var symbol: String
        var title: String
        var detail: String
        var time: String
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let next = coach.nextCommitment, let start = next.scheduledStart {
            rows.append(Row(symbol: next.kind.symbol, title: next.title, detail: "Agreed", time: start.formatted(date: .omitted, time: .shortened)))
        }
        if let event = coach.upcomingEvent {
            rows.append(Row(symbol: "calendar", title: event.event.title, detail: event.kind.label,
                            time: event.event.start.formatted(date: .omitted, time: .shortened)))
        }
        if let window = coach.nextOpportunity {
            rows.append(Row(symbol: "sparkles", title: "Free time",
                            detail: DurationFormat.text(minutes: window.minutes) + (window.kind == .lunch ? " · lunch" : ""),
                            time: window.interval.start.formatted(date: .omitted, time: .shortened)))
        }
        return rows
    }
}

struct EssentialsCard: View {
    @Environment(CoachModel.self) private var coach
    let items: [Commitment]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader("Still due today")
            VStack(spacing: 0) {
                ForEach(items, id: \.id) { item in
                    HStack(spacing: Spacing.s) {
                        Image(systemName: item.kind.symbol)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline).foregroundStyle(Palette.textPrimary)
                            Text(item.scheduledStart.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Any time")
                                .font(.caption).foregroundStyle(Palette.textTertiary)
                        }
                        Spacer()
                        Button {
                            coach.transition(item, .complete)
                        } label: {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                                .foregroundStyle(Palette.accent)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Mark \(item.title) done")
                    }
                    if item.id != items.last?.id { Divider().overlay(Palette.border) }
                }
            }
            .surface(padding: Spacing.m)
        }
    }
}

/// What's at stake today, honestly (A5): never 100% while anything is still due.
struct AccountabilityCard: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        let projection = coach.projection
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("Today's commitments")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                if coach.coach.finesAreSimulated {
                    Text("Trial · no real money")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Palette.elevated, in: Capsule())
                }
            }
            if let confirmed = projection.score.confirmedPercent, let possible = projection.score.possiblePercent {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text("\(confirmed)%")
                        .font(.largeTitle.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText(value: Double(confirmed)))
                    Text(projection.score.isSettled ? "done" : "done · up to \(possible)% if you finish")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(stakeText(projection))
                    .font(.subheadline)
                    .foregroundStyle(projection.worstCaseFine.isPositive ? Palette.warning : Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Nothing agreed today, so nothing is at stake.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            Divider().overlay(Palette.border)
            HStack {
                Text("This month")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("\(coach.monthFines.formatted()) fines · \(projection.transferEstimate.formatted()) to keep")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .surface()
        .accessibilityElement(children: .combine)
    }

    private func stakeText(_ projection: DayProjection) -> String {
        if !projection.worstCaseFine.isPositive { return "Nothing at stake today." }
        if projection.bestCaseFine == projection.worstCaseFine {
            return "\(projection.worstCaseFine.formatted()) at stake today."
        }
        let best = projection.bestCaseFine.isPositive ? projection.bestCaseFine.formatted() : "nothing"
        return "Finish the rest and it costs \(best). Stop now and it's \(projection.worstCaseFine.formatted())."
    }
}

enum DurationFormat {
    static func text(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

extension BlockKind {
    var label: String {
        switch self {
        case .workMeeting: "Work meeting"
        case .workFocus: "Focus time · protected"
        case .personal: "Personal"
        case .sharedInfo: "Becky"
        case .allDayInfo: "All day"
        case .coachCommitment: "Agreed"
        case .travel: "Travel"
        }
    }
}
