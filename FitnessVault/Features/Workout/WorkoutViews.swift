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
        case .rehab: "Rehab only"
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

    private var plan: WorkoutPlan {
        switch choice {
        case .rehab: training.makeRehabPlan()
        case .upper: training.makePlan(focus: .upper, variant: variant, availableMinutes: minutes, rehabFirst: rehabFirst)
        case .lower: training.makePlan(focus: .lower, variant: variant, availableMinutes: minutes, rehabFirst: rehabFirst)
        }
    }

    var body: some View {
        let plan = self.plan
        List {
            Section {
                Picker("Session", selection: $choice) {
                    ForEach(SessionChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if choice != .rehab {
                    Stepper("\(minutes) minutes in the gym", value: $minutes, in: 30...90, step: 5)
                    Toggle(isOn: $rehabFirst) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Knee rehab first")
                            Text("Recommended: straight after your warm-up, so it doesn't get skipped at the end.")
                                .font(.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
            if training.kneeStatus != .settled {
                Section {
                    Label("Knee: \(training.kneeStatus.title.lowercased()). Lower-body loads are held and heavy knee work is swapped.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Palette.warning)
                }
            }
            Section("\(plan.title) · about \(plan.estimatedMinutes) min") {
                ForEach(plan.exercises) { item in
                    PlannedRow(item: item)
                }
            }
            if !plan.notes.isEmpty {
                Section {
                    ForEach(plan.notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(Palette.textSecondary) }
                }
            }
            Section {
                Text("Weights marked \"check\" are starting estimates from your brief or a new exercise. Log what you actually lift; that's what progression uses.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") { training.start(plan) }.fontWeight(.semibold)
            }
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

struct PlannedRow: View {
    let item: PlannedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(item.exercise?.name ?? item.exerciseID)
                    .foregroundStyle(Palette.textPrimary)
                if item.isRehab {
                    Text("Rehab").font(.caption2.weight(.semibold)).foregroundStyle(Palette.accent)
                }
                if item.isOptional {
                    Text("Optional").font(.caption2).foregroundStyle(Palette.textTertiary)
                }
            }
            Text(prescription)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
            if let note = item.note {
                Text(note).font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var prescription: String {
        let unit = item.exercise?.unit.label ?? "reps"
        var text = "\(item.sets) × \(item.targetReps) \(unit)"
        if let kg = item.weightKg {
            text += " · \(WeightFormat.text(kg, perSide: item.exercise?.perSide ?? false))"
            if item.isValidation { text += " (check)" }
        }
        if item.supersetWithNext { text += " · superset" }
        return text
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
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let advice = training.lastAdvice {
                    NoticeBanner(symbol: "cross.case", title: "Knee", message: advice)
                }
                if let current = training.current {
                    if training.awaitingReady {
                        nextUp
                    } else {
                        exerciseCard(current)
                    }
                    restBanner
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("That's everything").font(.title2.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                        Text("Good session. End it to save.").foregroundStyle(Palette.textSecondary)
                    }
                    .surface(radius: Radius.hero, padding: Spacing.l)
                }
                remaining
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .navigationTitle(training.plan?.title ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("End") { confirmEnd = true }
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

    private func exerciseCard(_ item: PlannedExercise) -> some View {
        let exercise = item.exercise
        let step = (exercise?.incrementKg ?? 0) > 0 ? exercise!.incrementKg : 1
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text(item.isRehab ? "Rehab" : (exercise?.equipment ?? ""))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.isRehab ? Palette.accent : Palette.textSecondary)
                Spacer()
                Text("Set \(min(training.setsDone + 1, item.sets)) of \(item.sets)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(exercise?.name ?? item.exerciseID)
                .font(.title.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            if let cue = exercise?.cue {
                Text(cue).font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
            if let note = item.note {
                Text(note).font(.footnote).foregroundStyle(Palette.textTertiary)
            }

            if training.needsWarmUp, let warm = item.warmUpKg {
                HStack {
                    Text("Warm-up: \(WeightFormat.text(warm, perSide: exercise?.perSide ?? false)) × \(item.targetReps)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Button("Done") { training.logWarmUp(weight: warm, reps: item.targetReps) }
                        .buttonStyle(.bordered)
                }
                .padding(Spacing.s)
                .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }

            if exercise?.usesWeight ?? false {
                Stepper(value: $weight, in: 0...400, step: step) {
                    Text(weight > 0 ? WeightFormat.text(weight, perSide: exercise?.perSide ?? false) : "Set the weight")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            Stepper(value: $reps, in: 0...100) {
                Text("\(reps) \(exercise?.unit.label ?? "reps")")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
            }

            Button {
                training.logSet(weight: (exercise?.usesWeight ?? false) && weight > 0 ? weight : nil, reps: reps)
                logged += 1
            } label: {
                Text("Log set")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .foregroundStyle(Palette.onAccent)
        }
        .surface(radius: Radius.hero, padding: Spacing.l)
    }

    @ViewBuilder
    private var restBanner: some View {
        if let end = training.restEndsAt, end > Date.now {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.system(.largeTitle, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Button("Skip") { training.skipRest() }.buttonStyle(.bordered)
            }
            .surface()
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var nextUp: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let next = training.upNext {
                Text("Next up").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                Text(next.exercise?.name ?? next.exerciseID)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                PlannedRow(item: next)
                Button {
                    training.ready()
                } label: {
                    Text("Ready")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .foregroundStyle(Palette.onAccent)
            } else {
                Text("That's everything").font(.title2.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                Button {
                    onEnd(training.end())
                } label: {
                    Text("End and save").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .foregroundStyle(Palette.onAccent)
            }
        }
        .surface(radius: Radius.hero, padding: Spacing.l)
    }

    @ViewBuilder
    private var remaining: some View {
        if let plan = training.plan, training.currentIndex + 1 < plan.exercises.count {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Still to come")
                VStack(spacing: Spacing.xs) {
                    ForEach(Array(plan.exercises.dropFirst(training.currentIndex + 1))) { item in
                        PlannedRow(item: item)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
        Form {
            Section {
                VStack(alignment: .leading) {
                    Text("Pain: \(Int(pain)) out of 10").monospacedDigit()
                    Slider(value: $pain, in: 0...10, step: 1)
                        .accessibilityValue("\(Int(pain)) out of 10")
                }
                Toggle("Swelling", isOn: $swelling)
                Toggle("Sharp pain", isOn: $sharp)
            } header: {
                Text(timing == .nextDay ? "How's the knee this morning?" : "How's the knee?")
            } footer: {
                Text("Pain can show up the next day, so the morning check matters too.")
            }
            if let advice {
                Section {
                    Text(advice).foregroundStyle(Palette.textPrimary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Knee check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(advice == nil ? "Cancel" : "Close") { dismiss() } }
            if advice == nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { advice = save(Int(pain), swelling, sharp) }.fontWeight(.semibold)
                }
            }
        }
    }
}
