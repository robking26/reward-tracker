import SwiftUI
import WebKit

/// A YouTube video played inline. YouTube needs to know which app is embedding it, so the page is loaded with the
/// app's identifier as its origin; the privacy-enhanced domain sets no cookies until you press play.
struct YouTubePlayer: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loaded != videoID else { return }
        context.coordinator.loaded = videoID
        let source = "https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1"
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style>
        </head><body><iframe src="\(source)" allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
        allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://com.robking.fitnessvault"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loaded: String?
    }
}

/// The demo video in a 16:9 card, or a placeholder when there isn't one.
struct ExerciseVideoCard: View {
    let exerciseID: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Group {
            if let video = ExerciseVideos.videoID(for: exerciseID) {
                YouTubePlayer(videoID: video)
            } else {
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "play.slash.fill")
                        .font(.title)
                        .foregroundStyle(Palette.textTertiary)
                    Text("No demo for this one yet")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.inset)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(shape)
        .accessibilityLabel("Demo video")
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
                ExerciseVideoCard(exerciseID: exercise.id)

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
                            Label("Open in YouTube", systemImage: "arrow.up.right.square")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.textSecondary)
                        }
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
