import SwiftUI

/// Setup, then the live set logger. Presented full screen from the Gym tab.
struct WorkoutFlowView: View {
    @Environment(TrainingModel.self) private var training
    @Environment(\.dismiss) private var dismiss
    /// Opens on the rehab-only session.
    var rehabOnly = false

    var body: some View {
        NavigationStack {
            Group {
                if training.isActive {
                    ActiveWorkoutView { _ in dismiss() }
                } else {
                    WorkoutSetupView(startWithRehab: rehabOnly) { dismiss() }
                }
            }
            .pageBackground()
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Setup

/// Upper body, lower body, or knee rehab on its own.
enum SessionChoice: String, CaseIterable, Identifiable {
    case upper, lower, rehab

    var id: String { rawValue }
    var title: String {
        switch self {
        case .upper: "Upper"
        case .lower: "Lower"
        case .rehab: "Rehab"
        }
    }
    var subtitle: String {
        switch self {
        case .upper: "Push, pull"
        case .lower: "Legs"
        case .rehab: "Knee only"
        }
    }
    var symbol: String {
        switch self {
        case .upper: "figure.strengthtraining.traditional"
        case .lower: "figure.step.training"
        case .rehab: "figure.cooldown"
        }
    }
    var tint: Color {
        switch self {
        case .upper: Palette.accent
        case .lower: Palette.frost
        case .rehab: Palette.rehab
        }
    }
}

struct WorkoutSetupView: View {
    @Environment(TrainingModel.self) private var training
    var startWithRehab = false
    var onCancel: () -> Void
    @State private var choice: SessionChoice = .upper
    @State private var variant = 0
    @State private var minutes = 60
    @State private var rehabFirst = true
    @State private var loaded = false

    private static let durations = [30, 45, 60, 75, 90]

    private var plan: WorkoutPlan {
        switch choice {
        case .rehab: training.makeRehabPlan()
        case .upper: training.makePlan(focus: .upper, variant: variant, availableMinutes: minutes, rehabFirst: rehabFirst)
        case .lower: training.makePlan(focus: .lower, variant: variant, availableMinutes: minutes, rehabFirst: rehabFirst)
        }
    }

    var body: some View {
        let plan = self.plan
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .top, spacing: Spacing.s) {
                    ForEach(SessionChoice.allCases) { option in
                        SessionOptionCard(option: option, selected: option == choice) {
                            withAnimation(.snappy) { choice = option }
                        }
                    }
                }

                if choice != .rehab {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Time in the gym")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                        HStack(spacing: 6) {
                            ForEach(Self.durations, id: \.self) { value in
                                DurationChip(minutes: value, selected: value == minutes, tint: choice.tint) {
                                    withAnimation(.snappy) { minutes = value }
                                }
                            }
                        }
                        Toggle(isOn: $rehabFirst) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Knee rehab first")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.textPrimary)
                                Text("Straight after the warm-up, so it doesn't get skipped.")
                                    .font(.caption)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                        }
                        .tint(Palette.rehab)
                        .surface()
                    }
                }

                if training.kneeStatus != .settled {
                    HStack(alignment: .top, spacing: Spacing.s) {
                        IconTile(symbol: "exclamationmark.triangle.fill", tint: Palette.warning, size: 34)
                        Text("Knee \(training.kneeStatus.title.lowercased()): lower-body loads are held and heavy knee work is swapped.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .surface(fill: Palette.warning.opacity(0.12))
                }

                VStack(alignment: .leading, spacing: Spacing.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(plan.title)
                            .font(.display(30))
                            .foregroundStyle(Palette.textPrimary)
                        Spacer()
                        Chip(text: "≈ \(plan.estimatedMinutes) min", symbol: "clock", tint: choice.tint, fill: choice.tint.opacity(0.14))
                    }
                    VStack(spacing: 0) {
                        ForEach(plan.exercises.indices, id: \.self) { index in
                            TimelineExerciseRow(number: index + 1, item: plan.exercises[index],
                                                isLast: index == plan.exercises.count - 1, tint: choice.tint)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(plan.notes, id: \.self) { note in
                        Footnote(note)
                    }
                    Footnote("Weights marked \"check\" are starting estimates. Log what you actually lift; that's what progression uses.")
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xl)
        }
        .safeAreaInset(edge: .bottom) {
            BottomAction {
                Button {
                    training.start(plan)
                } label: {
                    Label("Start \(plan.title)", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(tint: choice.tint))
            }
        }
        .navigationTitle("New workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
        }
        .onChange(of: choice) { _, new in
            guard new != .rehab else { return }
            variant = training.suggestedFocus(for: new == .lower ? "lower" : "upper").1
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if startWithRehab {
                choice = .rehab
            } else {
                let suggested = training.suggestedFocus(for: nil)
                choice = suggested.0 == .lower ? .lower : .upper
                variant = suggested.1
            }
        }
    }
}

/// The pinned bottom action, on a fade so content scrolls underneath.
struct BottomAction<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xs)
            .background {
                LinearGradient(colors: [Palette.background.opacity(0), Palette.background, Palette.background],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
    }
}

private struct SessionOptionCard: View {
    let option: SessionChoice
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                IconTile(symbol: option.symbol, tint: option.tint, size: 40, filled: selected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(selected ? option.tint.opacity(0.14) : Palette.surface, in: shape)
            .overlay { shape.strokeBorder(selected ? option.tint : Color.clear, lineWidth: 2) }
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct DurationChip: View {
    let minutes: Int
    let selected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(minutes)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(selected ? Palette.onAccent : Palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? tint : Palette.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(minutes) minutes")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A numbered exercise on a vertical timeline.
private struct TimelineExerciseRow: View {
    let number: Int
    let item: PlannedExercise
    let isLast: Bool
    let tint: Color

    var body: some View {
        let rowTint: Color = item.isRehab ? Palette.rehab : tint
        HStack(alignment: .top, spacing: Spacing.s) {
            VStack(spacing: 0) {
                Text("\(number)")
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(rowTint)
                    .frame(width: 30, height: 30)
                    .background(rowTint.opacity(0.16), in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Palette.elevated)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.exercise?.name ?? item.exerciseID)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                PrescriptionChips(item: item)
                if let note = item.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : Spacing.m)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Sets × reps, weight and tags as chips.
struct PrescriptionChips: View {
    let item: PlannedExercise

    var body: some View {
        let unit = item.exercise?.unit.label ?? "reps"
        ChipFlow().callAsFunction {
            Chip(text: "\(item.sets) × \(item.targetReps) \(unit)")
            if let kg = item.weightKg {
                Chip(text: WeightFormat.text(kg, perSide: item.exercise?.perSide ?? false), symbol: "scalemass")
            }
            if item.isValidation {
                Chip(text: "Check weight", tint: Palette.warning, fill: Palette.warning.opacity(0.14))
            }
            if item.isRehab {
                Chip(text: "Rehab", tint: Palette.rehab, fill: Palette.rehab.opacity(0.14))
            }
            if item.supersetWithNext {
                Chip(text: "Superset", symbol: "link", tint: Palette.frost, fill: Palette.frost.opacity(0.14))
            }
            if item.isOptional {
                Chip(text: "Optional", tint: Palette.textTertiary)
            }
        }
    }
}

// MARK: - Active session

struct ActiveWorkoutView: View {
    @Environment(TrainingModel.self) private var training
    var onEnd: (TrainingModel.Summary?) -> Void
    @State private var weight: Double = 0
    @State private var reps = 10
    @State private var sheet: Sheet?
    @State private var confirmEnd = false
    @State private var restFinished = 0
    @State private var logged = 0

    enum Sheet: String, Identifiable {
        case busy, knee, reorder, add
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                progressHeader
                if let advice = training.lastAdvice {
                    HStack(alignment: .top, spacing: Spacing.s) {
                        IconTile(symbol: "cross.case.fill", tint: Palette.rehab, size: 34)
                        Text(advice)
                            .font(.footnote)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .surface(fill: Palette.rehab.opacity(0.12))
                }
                if let current = training.current {
                    if training.isResting {
                        RestRing(endsAt: training.restEndsAt ?? .now, totalSeconds: current.restSeconds) { training.skipRest() }
                    }
                    if training.awaitingReady {
                        nextUp
                    } else {
                        exerciseCard(current)
                    }
                } else {
                    finishedCard
                }
                remaining
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xl)
        }
        .safeAreaInset(edge: .bottom) { bottomAction }
        .navigationTitle(training.plan?.title ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("End") { confirmEnd = true }
                    .foregroundStyle(Palette.error)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { sheet = .busy } label: { Label("Equipment busy", systemImage: "person.2.slash") }
                    Button { sheet = .knee } label: { Label("My knee hurts", systemImage: "cross.case") }
                    Button { sheet = .reorder } label: { Label("Change the order", systemImage: "arrow.up.arrow.down") }
                    Button { sheet = .add } label: { Label("Add an exercise", systemImage: "plus") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Workout options")
            }
        }
        .confirmationDialog("End the workout? Everything you've logged is saved.", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Workout") { onEnd(training.end()) }
        }
        .sheet(item: $sheet) { sheet in
            NavigationStack {
                switch sheet {
                case .busy: BusyEquipmentSheet()
                case .knee:
                    KneeCheckView(timing: .during) { pain, swelling, sharp in
                        training.reportKneePain(pain: pain, swelling: swelling, sharp: sharp)
                    }
                case .reorder: ReorderSheet()
                case .add: AddExerciseSheet()
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Palette.background)
        }
        .onAppear(perform: resetInputs)
        .onChange(of: training.currentIndex) { resetInputs() }
        .onChange(of: training.plan?.exercises.map(\.exerciseID) ?? []) { resetInputs() }
        .task(id: training.restEndsAt) {
            guard let end = training.restEndsAt else { return }
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled { restFinished += 1 }
        }
        .sensoryFeedback(.warning, trigger: restFinished)
        .sensoryFeedback(.success, trigger: logged)
    }

    private var progressHeader: some View {
        let total = training.plan?.exercises.count ?? 0
        let index = min(training.currentIndex + 1, max(total, 1))
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            SegmentedProgress(total: total, done: training.currentIndex)
            Text(training.current == nil ? "All \(total) exercises done" : "Exercise \(index) of \(total)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func exerciseCard(_ item: PlannedExercise) -> some View {
        let exercise = item.exercise
        let step = (exercise?.incrementKg ?? 0) > 0 ? (exercise?.incrementKg ?? 1) : 1
        let perSide = exercise?.perSide ?? false
        let tint: Color = item.isRehab ? Palette.rehab : Palette.accent
        let done = training.setsDone
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Chip(text: item.isRehab ? "Rehab" : (exercise?.equipment ?? "Exercise"),
                     symbol: item.isRehab ? "cross.case.fill" : "dumbbell.fill", tint: tint, fill: tint.opacity(0.15))
                Spacer()
                SetDots(total: item.sets, done: done, tint: tint)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(exercise?.name ?? item.exerciseID)
                    .font(.display(30))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Set \(min(done + 1, item.sets)) of \(item.sets)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if let cue = exercise?.cue {
                    Text(cue)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = item.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if training.needsWarmUp, let warm = item.warmUpKg {
                HStack(spacing: Spacing.s) {
                    IconTile(symbol: "flame.fill", tint: Palette.kitchen, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Warm-up set")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text("\(WeightFormat.text(warm, perSide: perSide)) × \(item.targetReps)")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Button("Done") { training.logWarmUp(weight: warm, reps: item.targetReps) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.kitchen)
                        .padding(.horizontal, Spacing.m)
                        .frame(minHeight: 40)
                        .background(Palette.kitchen.opacity(0.15), in: Capsule())
                }
                .padding(Spacing.s)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }

            HStack(spacing: Spacing.s) {
                if exercise?.usesWeight ?? false {
                    NumberStepper(title: perSide ? "kg each" : "kg", value: weight > 0 ? WeightText.number(weight) : "–", tint: tint,
                                  onMinus: { weight = max(0, weight - step) }, onPlus: { weight = min(400, weight + step) })
                }
                NumberStepper(title: exercise?.unit.label ?? "reps", value: "\(reps)", tint: tint,
                              onMinus: { reps = max(0, reps - 1) }, onPlus: { reps = min(100, reps + 1) })
            }
        }
        .heroCard(tint: tint)
    }

    private var finishedCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            IconTile(symbol: "trophy.fill", tint: Palette.accent, size: 48, filled: true)
            Text("That's everything")
                .font(.display(30))
                .foregroundStyle(Palette.textPrimary)
            Text("Good session. End it to save.")
                .foregroundStyle(Palette.textSecondary)
        }
        .heroCard(tint: Palette.accent, symbol: "checkmark.seal.fill")
    }

    @ViewBuilder
    private var nextUp: some View {
        if let next = training.upNext {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Chip(text: "NEXT UP", symbol: "arrow.right", tint: Palette.onAccent, fill: Palette.accent)
                Text(next.exercise?.name ?? next.exerciseID)
                    .font(.display(30))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                PrescriptionChips(item: next)
                if let cue = next.exercise?.cue {
                    Text(cue)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .heroCard(tint: Palette.accent)
        } else {
            finishedCard
        }
    }

    @ViewBuilder
    private var bottomAction: some View {
        if let current = training.current {
            BottomAction {
                if training.awaitingReady && training.upNext != nil {
                    Button {
                        training.ready()
                    } label: {
                        Label("Ready", systemImage: "arrow.right")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else if training.awaitingReady {
                    Button {
                        onEnd(training.end())
                    } label: {
                        Label("End and save", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button {
                        let usesWeight = current.exercise?.usesWeight ?? false
                        training.logSet(weight: usesWeight && weight > 0 ? weight : nil, reps: reps)
                        logged += 1
                    } label: {
                        Label("Log set", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: current.isRehab ? Palette.rehab : Palette.accent))
                }
            }
        } else {
            BottomAction {
                Button {
                    onEnd(training.end())
                } label: {
                    Label("End and save", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var remaining: some View {
        let skip = training.awaitingReady ? 2 : 1
        if let plan = training.plan, training.currentIndex + skip < plan.exercises.count {
            let start = training.currentIndex + skip
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionTitle(title: "Still to come", detail: "\(plan.exercises.count - start)")
                VStack(spacing: 0) {
                    ForEach(start..<plan.exercises.count, id: \.self) { index in
                        TimelineExerciseRow(number: index + 1, item: plan.exercises[index],
                                            isLast: index == plan.exercises.count - 1, tint: Palette.textSecondary)
                    }
                }
                .surface()
            }
        }
    }

    private func resetInputs() {
        guard let item = training.current else { return }
        weight = item.weightKg ?? 0
        reps = item.targetReps
    }
}

enum WeightText {
    /// "22.5" or "20": the number alone, for big steppers.
    static func number(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(kg)) : String(format: "%.1f", kg)
    }
}

/// A big number between round minus and plus buttons.
private struct NumberStepper: View {
    let title: String
    let value: String
    let tint: Color
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.display(40))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
            HStack(spacing: Spacing.s) {
                Button(action: onMinus) { RoundIconLabel(symbol: "minus", size: 44) }
                    .accessibilityLabel("Less")
                Button(action: onPlus) { RoundIconLabel(symbol: "plus", size: 44, tint: Palette.onAccent, fill: tint) }
                    .accessibilityLabel("More")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Spacing.m)
        .frame(maxWidth: .infinity)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(value) \(title)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onPlus()
            case .decrement: onMinus()
            @unknown default: break
            }
        }
    }
}

/// One dot per set: filled once logged.
private struct SetDots: View {
    let total: Int
    let done: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index < done ? tint : Palette.elevated)
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(done) of \(total) sets done")
    }
}

/// The rest countdown as a ring that empties, with Skip.
private struct RestRing: View {
    let endsAt: Date
    let totalSeconds: Int
    let skip: () -> Void

    var body: some View {
        HStack(spacing: Spacing.l) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let left = max(0, endsAt.timeIntervalSince(context.date))
                let fraction = totalSeconds > 0 ? left / Double(totalSeconds) : 0
                ZStack {
                    Circle().stroke(Palette.accent.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: min(1, fraction))
                        .stroke(Palette.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: fraction)
                    Text(timerInterval: Date.now...max(endsAt, Date.now), countsDown: true)
                        .font(.display(26))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(width: 92)
                }
                .frame(width: 120, height: 120)
            }
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Rest")
                    .font(.display(26))
                    .foregroundStyle(Palette.textPrimary)
                Text("Breathe. Next set when the ring empties.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Skip rest", action: skip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, Spacing.m)
                    .frame(minHeight: 40)
                    .background(Palette.accent.opacity(0.15), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .surface(radius: Radius2.hero, padding: Spacing.l)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sheets

struct BusyEquipmentSheet: View {
    @Environment(TrainingModel.self) private var training
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Swap for") {
                let options = training.alternativesForCurrent()
                if options.isEmpty {
                    Text("No equivalent here. Do it later instead.").foregroundStyle(Palette.textSecondary)
                }
                ForEach(options) { exercise in
                    Button(exercise.name) {
                        training.swapCurrent(to: exercise)
                        dismiss()
                    }
                }
            }
            if training.setsDone == 0 && !training.isLastExercise {
                Section {
                    Button("Do it later") {
                        training.doCurrentLater()
                        dismiss()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Equipment busy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

struct ReorderSheet: View {
    @Environment(TrainingModel.self) private var training
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let offset = training.currentIndex + 1
        let upcoming = Array((training.plan?.exercises ?? []).dropFirst(offset))
        List {
            ForEach(upcoming) { item in
                Text(item.exercise?.name ?? item.exerciseID)
            }
            .onMove { source, destination in
                training.move(from: IndexSet(source.map { $0 + offset }), to: destination + offset)
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .navigationTitle("Change the order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

struct AddExerciseSheet: View {
    @Environment(TrainingModel.self) private var training
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let options = training.extensionOptions()
        List {
            if options.isEmpty {
                Text("Nothing suitable left to add today.")
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(options) { exercise in
                Button(exercise.name) {
                    training.add(exercise)
                    dismiss()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Add an exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

/// A knee check-in (R3). Advice never diagnoses; concerning answers point to the physio or GP.
struct KneeCheckView: View {
    @Environment(\.dismiss) private var dismiss
    let timing: SymptomTiming
    var save: (Int, Bool, Bool) -> String
    @State private var pain = 0.0
    @State private var swelling = false
    @State private var sharp = false
    @State private var advice: String?

    var body: some View {
        let level = Int(pain)
        let tint = Self.tint(for: level)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text(timing == .nextDay ? "How's the knee this morning?" : "How's the knee?")
                    .font(.display(26))
                    .foregroundStyle(Palette.textPrimary)

                VStack(spacing: Spacing.s) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(level)")
                            .font(.display(72))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .contentTransition(.numericText(value: pain))
                        Text("/ 10")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Text(Self.label(for: level))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Slider(value: $pain, in: 0...10, step: 1)
                        .tint(tint)
                        .accessibilityLabel("Pain")
                        .accessibilityValue("\(level) out of 10")
                    HStack {
                        Text("None")
                        Spacer()
                        Text("Worst")
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
                }
                .padding(Spacing.l)
                .frame(maxWidth: .infinity)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius2.hero, style: .continuous))
                .animation(.snappy, value: level)

                HStack(spacing: Spacing.s) {
                    SymptomToggle(title: "Swelling", symbol: "drop.fill", isOn: $swelling)
                    SymptomToggle(title: "Sharp pain", symbol: "bolt.fill", isOn: $sharp)
                }

                if let advice {
                    HStack(alignment: .top, spacing: Spacing.s) {
                        IconTile(symbol: "cross.case.fill", tint: Palette.rehab, size: 36)
                        Text(advice)
                            .font(.subheadline)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .surface(fill: Palette.rehab.opacity(0.12))
                } else {
                    Footnote("Pain can show up the next day, so the morning check matters too.")
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle("Knee check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(advice == nil ? "Cancel" : "Close") { dismiss() } }
            if advice == nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { advice = save(level, swelling, sharp) }.fontWeight(.semibold)
                }
            }
        }
    }

    static func tint(for level: Int) -> Color {
        if level >= 6 { return Palette.error }
        if level >= 3 { return Palette.warning }
        return Palette.success
    }

    static func label(for level: Int) -> String {
        switch level {
        case 0: "No pain"
        case 1...2: "Barely there"
        case 3...5: "Noticeable"
        case 6...7: "Painful"
        default: "Very painful"
        }
    }
}

/// A tappable symptom tile that fills in when it applies.
private struct SymptomToggle: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            HStack(spacing: Spacing.s) {
                IconTile(symbol: symbol, tint: Palette.warning, size: 36, filled: isOn)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Palette.warning : Palette.textTertiary)
            }
            .padding(14)
            .background(isOn ? Palette.warning.opacity(0.12) : Palette.surface, in: shape)
            .overlay { shape.strokeBorder(isOn ? Palette.warning : Color.clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}
