import SwiftUI

/// The start and finish positions of an exercise, from the public-domain Free Exercise DB, bundled in the app.
enum FormDemo {
    static func frames(for exerciseID: String) -> [UIImage] {
        (0...1).compactMap { index in
            Bundle.main.url(forResource: "form-\(exerciseID)-\(index)", withExtension: "jpg")
                .flatMap { UIImage(contentsOfFile: $0.path) }
        }
    }

    static func hasFrames(_ exerciseID: String) -> Bool { frames(for: exerciseID).count == 2 }

    /// Exercises the photo set doesn't cover: the knee rehab moves keep their physio video, and swimming needs none.
    static let noFrames: Set<String> = ["stepDown", "singleLegBalance", "sideLyingAbduction", "wallSit", "clamshell", "swim"]

    /// Seconds on each position; a full loop is twice this.
    static let hold: Double = 1.2
}

/// A short form loop: the start and finish positions crossfading back and forth (2.4 seconds a loop).
/// With Reduce Motion on, both positions are shown side by side instead.
struct FormLoopCard: View {
    let exerciseID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let frames = FormDemo.frames(for: exerciseID)
        Group {
            if frames.count == 2 {
                if reduceMotion {
                    HStack(spacing: 2) {
                        frameView(frames[0])
                        frameView(frames[1])
                    }
                } else {
                    TimelineView(.periodic(from: .now, by: FormDemo.hold)) { context in
                        let tick = Int(context.date.timeIntervalSinceReferenceDate / FormDemo.hold)
                        ZStack {
                            frameView(frames[0])
                            frameView(frames[1])
                                .opacity(tick % 2 == 0 ? 0 : 1)
                                .animation(.easeInOut(duration: 0.45), value: tick)
                        }
                    }
                }
            } else {
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "figure.mixed.cardio")
                        .font(.title)
                        .foregroundStyle(Palette.textTertiary)
                    Text("Follow the steps below")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.inset)
            }
        }
        .aspectRatio(3 / 2, contentMode: .fit)
        .clipShape(shape)
        .overlay(alignment: .bottomLeading) {
            if frames.count == 2 {
                Label("Form loop", systemImage: "repeat")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(Spacing.xs)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(frames.count == 2 ? "Form demonstration: start and finish positions" : "No demonstration")
    }

    private func frameView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
    }
}

/// How to do an exercise, and what to do instead. During a session, a swap replaces the current exercise.
struct ExerciseInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    /// Swaps you can make right now (knee-checked); nil when just browsing.
    var swapOptions: [Exercise]? = nil
    var onSwap: ((Exercise) -> Void)? = nil
    var onLater: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                FormLoopCard(exerciseID: exercise.id)

                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(exercise.name)
                        .font(.display(28))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    ChipFlow().callAsFunction {
                        Chip(text: exercise.equipment, symbol: "dumbbell.fill")
                        Chip(text: "\(exercise.sets) × \(exercise.targetReps) \(exercise.unit.label)", symbol: "repeat")
                        Chip(text: KneeText.title(exercise.kneeLoad), symbol: "figure.walk",
                             tint: KneeText.tint(exercise.kneeLoad), fill: KneeText.tint(exercise.kneeLoad).opacity(0.14))
                    }
                    if let cue = exercise.cue {
                        HStack(alignment: .top, spacing: Spacing.s) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(Palette.accent)
                                .accessibilityHidden(true)
                            Text(cue)
                                .font(.subheadline)
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Spacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    }
                    if let video = ExerciseVideos.videoID(for: exercise.id), let url = ExerciseVideos.watchURL(video) {
                        Link(destination: url) {
                            Label("Full video on YouTube", systemImage: "arrow.up.right.square")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    if FormDemo.hasFrames(exercise.id) {
                        Text("Form photos: Free Exercise DB (public domain).")
                            .font(.caption2)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    CardHeader(title: "Can't do it?", symbol: "arrow.left.arrow.right", tint: Palette.frost,
                               subtitle: swapOptions == nil ? "Swap it during the session" : "Busy, sore or no kit: swap it")
                    let alternatives = exercise.alternatives.compactMap(ExerciseLibrary.exercise)
                    ForEach(alternatives.indices, id: \.self) { index in
                        SwapRow(exercise: alternatives[index], allowed: isAllowed(alternatives[index]),
                                browsing: swapOptions == nil, onSwap: performSwap)
                        if index < alternatives.count - 1 { RowDivider() }
                    }
                    if let onLater {
                        Button {
                            onLater()
                            dismiss()
                        } label: {
                            Label("Do it later in the session", systemImage: "arrow.down.to.line")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, Spacing.xs)
                    }
                }
                .surface()
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle("How to")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private func isAllowed(_ alternative: Exercise) -> Bool {
        guard let swapOptions else { return true }
        return swapOptions.contains { $0.id == alternative.id }
    }

    private func performSwap(_ alternative: Exercise) {
        onSwap?(alternative)
        dismiss()
    }
}

/// An alternative: its demo one tap away, and a Swap button during a session.
private struct SwapRow: View {
    let exercise: Exercise
    let allowed: Bool
    let browsing: Bool
    let onSwap: (Exercise) -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            NavigationLink {
                ExerciseInfoView(exercise: exercise)
            } label: {
                HStack(spacing: Spacing.s) {
                    IconTile(symbol: "play.fill", tint: Palette.frost, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(allowed ? "\(exercise.equipment) · \(KneeText.title(exercise.kneeLoad).lowercased())" : "Not while the knee is settling")
                            .font(.caption)
                            .foregroundStyle(allowed ? Palette.textTertiary : Palette.warning)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !browsing && allowed {
                Button("Swap") { onSwap(exercise) }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, Spacing.m)
                    .frame(minHeight: 36)
                    .background(Palette.frost, in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 56)
    }
}

enum KneeText {
    static func title(_ load: KneeLoad) -> String {
        switch load {
        case .none: "No knee load"
        case .low: "Easy on the knee"
        case .moderate: "Some knee load"
        case .high: "Heavy knee load"
        }
    }

    static func tint(_ load: KneeLoad) -> Color {
        switch load {
        case .none, .low: Palette.success
        case .moderate: Palette.warning
        case .high: Palette.error
        }
    }
}
