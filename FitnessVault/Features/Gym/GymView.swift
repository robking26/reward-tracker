import SwiftUI

/// The Gym tab: start a session or knee rehab, the next-morning knee check, and progress.
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
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if training.isActive {
                        Button {
                            rehabOnly = false
                            showingWorkout = true
                        } label: {
                            NoticeBanner(symbol: "dumbbell.fill", title: "Workout in progress",
                                         message: "Tap to carry on where you left off.", tint: Palette.accent)
                        }
                        .buttonStyle(CardButtonStyle())
                    } else {
                        HStack(spacing: Spacing.s) {
                            SmallActionButton(title: "Start workout", symbol: "dumbbell") {
                                rehabOnly = false
                                showingWorkout = true
                            }
                            SmallActionButton(title: "Knee rehab", symbol: "figure.cooldown") {
                                rehabOnly = true
                                showingWorkout = true
                            }
                        }
                    }

                    if training.needsNextDayKneeCheck {
                        Button {
                            kneeTiming = .nextDay
                        } label: {
                            NoticeBanner(symbol: "figure.walk", title: "How's the knee this morning?",
                                         message: "Pain can show up the day after. Ten seconds to log it.", tint: Palette.accent)
                        }
                        .buttonStyle(CardButtonStyle())
                    }

                    if let summary = training.lastSummary, !training.isActive {
                        Text("Saved: \(summary.workingSets) sets across \(summary.exercises) exercises in \(summary.minutes) minutes.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }

                    WorkoutsPerWeekCard()
                    StrengthCard()
                    KneeCard()
                    SmallActionButton(title: "Log how the knee feels", symbol: "square.and.pencil") { kneeTiming = .general }
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
