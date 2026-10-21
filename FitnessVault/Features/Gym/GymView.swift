import SwiftUI

/// The Gym tab: the week at a glance, the next session, knee rehab, and progress.
/// Money comes from Apple Health, so a logged session earns through its strength minutes, not here.
struct GymView: View {
    @Environment(AppModel.self) private var model
    @Environment(TrainingModel.self) private var training
    @Binding var showingSettings: Bool
    @State private var showingWorkout = false
    @State private var rehabOnly = false
    @State private var kneeTiming: SymptomTiming?
    @State private var bodySamples: [BodySample] = []
    @State private var swims: [SwimSample] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    GymWeekStrip()

                    if training.isActive {
                        ResumeHero { open(rehab: false) }
                    } else {
                        NextSessionHero { open(rehab: false) }
                    }

                    if training.needsNextDayKneeCheck {
                        KneeMorningPrompt { kneeTiming = .nextDay }
                    }

                    if let summary = training.lastSummary, !training.isActive {
                        SavedSessionNote(summary: summary)
                    }

                    HStack(spacing: Spacing.s) {
                        QuickTile(title: "Knee rehab", subtitle: rehabSubtitle, symbol: "figure.cooldown", tint: Palette.rehab) {
                            open(rehab: true)
                        }
                        .disabled(training.isActive)
                        QuickTile(title: "Knee check", subtitle: training.kneeStatus.title, symbol: "waveform.path.ecg",
                                  tint: kneeTint) {
                            kneeTiming = .general
                        }
                    }

                    GymStatsRow()

                    SectionTitle(title: "Progress")
                    StrengthCard()
                    WorkoutsPerWeekCard()
                    KneeCard()
                    WalkingCard()
                    BodyTrendCard(samples: bodySamples)
                    SwimCard(swims: swims)
                    PhotosCard()
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.xl)
            }
            .pageBackground()
            .navigationTitle("Gym")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton(isPresented: $showingSettings)
                }
            }
            .refreshable { await loadHealthTrends() }
            .task { await loadHealthTrends() }
            .fullScreenCover(isPresented: $showingWorkout) {
                WorkoutFlowView(rehabOnly: rehabOnly)
            }
            .sheet(item: $kneeTiming) { timing in
                NavigationStack {
                    KneeCheckView(timing: timing) { pain, swelling, sharp in
                        training.logSymptom(timing: timing, pain: pain, swelling: swelling, sharp: sharp)
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.background)
            }
        }
    }

    private var rehabSubtitle: String {
        let plan = training.makeRehabPlan()
        return "\(plan.exercises.count) moves · \(plan.estimatedMinutes) min"
    }

    private var kneeTint: Color {
        training.kneeStatus == .settled ? Palette.success : Palette.warning
    }

    private func open(rehab: Bool) {
        rehabOnly = rehab
        showingWorkout = true
    }

    /// Body measurements and swims for the last 90 days, read from Apple Health.
    private func loadHealthTrends() async {
        let since = Date.now.addingTimeInterval(-90 * 86_400)
        bodySamples = (try? await model.health.bodySamples(since: since)) ?? []
        swims = (try? await model.health.swims(since: since)) ?? []
    }
}

extension SymptomTiming: Identifiable {
    var id: String { rawValue }
}

// MARK: - Week strip

/// Monday to Sunday, with a lime disc on the days you trained and a ring around today.
private struct GymWeekStrip: View {
    @Environment(AppModel.self) private var model
    @Environment(TrainingModel.self) private var training

    var body: some View {
        let days = weekDays
        let trained = trainedDays
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                WeekDayDot(day: day, isToday: day == model.today, trained: trained.contains(day.description),
                           isFuture: day > model.today, calendar: model.calendar)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Spacing.xs)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(trained.count) gym sessions")
    }

    private var weekDays: [DayKey] {
        let calendar = model.calendar
        let weekday = calendar.component(.weekday, from: model.today.startDate(calendar: calendar))
        let monday = model.today.adding(days: -((weekday + 5) % 7), calendar: calendar)
        return (0..<7).map { monday.adding(days: $0, calendar: calendar) }
    }

    private var trainedDays: Set<String> {
        Set(training.sessions().filter { $0.endedAt != nil }.map(\.day))
    }
}

private struct WeekDayDot: View {
    let day: DayKey
    let isToday: Bool
    let trained: Bool
    let isFuture: Bool
    let calendar: Calendar

    var body: some View {
        let date = day.startDate(calendar: calendar)
        let letter = date.formatted(.dateTime.weekday(.narrow))
        let number = date.formatted(.dateTime.day())
        let fill: Color = trained ? Palette.accent : Palette.elevated.opacity(isFuture ? 0.4 : 1)
        let ink: Color = trained ? Palette.onAccent : (isFuture ? Palette.textTertiary : Palette.textPrimary)
        VStack(spacing: 6) {
            Text(letter)
                .font(.caption2.weight(.bold))
                .foregroundStyle(isToday ? Palette.accent : Palette.textTertiary)
            ZStack {
                Circle().fill(fill)
                if isToday && !trained {
                    Circle().strokeBorder(Palette.accent, lineWidth: 2)
                }
                if trained {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ink)
                } else {
                    Text(number)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                }
            }
            .frame(width: 38, height: 38)
        }
    }
}

// MARK: - Heroes

/// The suggested next session with a single big Start button.
private struct NextSessionHero: View {
    @Environment(TrainingModel.self) private var training
    let start: () -> Void

    var body: some View {
        let suggested = training.suggestedFocus(for: nil)
        let plan = training.makePlan(focus: suggested.0, variant: suggested.1, availableMinutes: 60, rehabFirst: true)
        let rehabCount = plan.exercises.filter(\.isRehab).count
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Chip(text: "UP NEXT", symbol: "sparkles", tint: Palette.onAccent, fill: Palette.accent)
                Spacer()
                if training.kneeStatus != .settled {
                    Chip(text: "Knee \(training.kneeStatus.title.lowercased())", symbol: "exclamationmark.triangle.fill",
                         tint: Palette.warning, fill: Palette.warning.opacity(0.15))
                }
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(plan.title)
                    .font(.display(38))
                    .foregroundStyle(Palette.textPrimary)
                Text(firstExercises(plan))
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: Spacing.l) {
                HeroMetric(value: "\(plan.estimatedMinutes)", unit: "min", label: "Duration")
                HeroMetric(value: "\(plan.exercises.count)", unit: "", label: "Exercises")
                HeroMetric(value: "\(plan.exercises.reduce(0) { $0 + $1.sets })", unit: "", label: "Sets")
                if rehabCount > 0 {
                    HeroMetric(value: "\(rehabCount)", unit: "", label: "Rehab")
                }
            }
            Button(action: start) {
                Label("Start workout", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .heroCard(tint: Palette.accent, symbol: "dumbbell.fill")
    }

    private func firstExercises(_ plan: WorkoutPlan) -> String {
        let names = plan.exercises.filter { !$0.isRehab }.prefix(3).compactMap { $0.exercise?.name }
        return names.joined(separator: " · ")
    }
}

private struct HeroMetric: View {
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.display(24))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A session is running: how far through, and back in.
private struct ResumeHero: View {
    @Environment(TrainingModel.self) private var training
    let resume: () -> Void

    var body: some View {
        let total = training.plan?.exercises.count ?? 0
        let index = min(training.currentIndex + 1, max(total, 1))
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.xs) {
                Circle().fill(Palette.accent).frame(width: 8, height: 8)
                Text("IN PROGRESS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.accent)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(training.plan?.title ?? "Workout")
                    .font(.display(34))
                    .foregroundStyle(Palette.textPrimary)
                Text(nowText)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            SegmentedProgress(total: total, done: training.currentIndex)
            Text("Exercise \(index) of \(total)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.textTertiary)
            Button(action: resume) {
                Label("Carry on", systemImage: "arrow.right")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .heroCard(tint: Palette.accent, symbol: "timer")
    }

    private var nowText: String {
        guard let name = training.current?.exercise?.name else { return "All exercises done" }
        return "Now: \(name)"
    }
}

/// One capsule per exercise: lime for done, a brighter capsule for the current one.
struct SegmentedProgress: View {
    let total: Int
    let done: Int
    var tint: Color = Palette.accent

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(color(index))
                    .frame(height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(done) of \(total) exercises done")
    }

    private func color(_ index: Int) -> Color {
        if index < done { return tint }
        if index == done { return tint.opacity(0.45) }
        return Palette.elevated
    }
}

// MARK: - Small cards

private struct KneeMorningPrompt: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                IconTile(symbol: "sun.max.fill", tint: Palette.rehab, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("How's the knee this morning?")
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Pain can show up the day after. Ten seconds to log it.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .surface(fill: Palette.rehab.opacity(0.12))
        }
        .buttonStyle(CardButtonStyle())
    }
}

private struct SavedSessionNote: View {
    let summary: TrainingModel.Summary

    var body: some View {
        HStack(spacing: Spacing.s) {
            IconTile(symbol: "checkmark", tint: Palette.success, size: 36, filled: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Session saved")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("\(summary.workingSets) sets · \(summary.exercises) exercises · \(summary.minutes) min")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .surface()
        .accessibilityElement(children: .combine)
    }
}

/// A square shortcut with a tinted icon.
private struct QuickTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    IconTile(symbol: symbol, tint: tint, size: 40)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .surface()
        }
        .buttonStyle(CardButtonStyle())
    }
}

/// Sessions this week, over eight weeks, and sets logged this week.
private struct GymStatsRow: View {
    @Environment(AppModel.self) private var model
    @Environment(TrainingModel.self) private var training

    var body: some View {
        let calendar = model.calendar
        let weekday = calendar.component(.weekday, from: model.today.startDate(calendar: calendar))
        let monday = model.today.adding(days: -((weekday + 5) % 7), calendar: calendar)
        let eightWeeks = monday.adding(days: -49, calendar: calendar)
        let finished = training.sessions().filter { $0.endedAt != nil }
        let thisWeek = finished.filter { (DayKey(string: $0.day) ?? eightWeeks) >= monday }
        let recent = finished.filter { (DayKey(string: $0.day) ?? eightWeeks) >= eightWeeks }
        let sets = thisWeek.reduce(0) { total, session in
            total + training.logs(for: session).filter { !$0.isWarmUp }.count
        }
        HStack(spacing: Spacing.s) {
            StatTile(value: "\(thisWeek.count)", label: "This week", symbol: "calendar", tint: Palette.accent)
            StatTile(value: "\(recent.count)", label: "8 weeks", symbol: "chart.bar.fill", tint: Palette.frost)
            StatTile(value: "\(sets)", label: "Sets this week", symbol: "square.stack.3d.up.fill", tint: Palette.kitchen)
        }
    }
}
