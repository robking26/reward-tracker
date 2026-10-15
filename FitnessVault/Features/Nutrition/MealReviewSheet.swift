import SwiftUI

/// Analyses a meal photo and lets you confirm, edit or discard the estimate.
struct MealReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let takenAt: Date

    private enum Stage: Equatable {
        case analysing
        case review
        case failed(String)
    }

    @State private var stage: Stage = .analysing
    @State private var estimate = NutritionEstimate(name: "", items: [], portionDescription: "", kilocalories: 0,
                                                    proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0, confidence: .low)
    @State private var hash: UInt64 = 0
    @State private var thumbnail: Data?
    @State private var saving = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
                        .accessibilityLabel("Your meal photo")

                    switch stage {
                    case .analysing:
                        VStack(spacing: Spacing.s) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(Palette.textSecondary)
                            Text("Estimating nutrition…")
                                .font(.subheadline)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                    case .failed(let message):
                        ContentUnavailableView {
                            Label("Couldn't analyse this photo", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("Try Again") { Task { await analyse() } }
                                .buttonStyle(.borderedProminent)
                                .tint(Palette.accent)
                                .foregroundStyle(Palette.onAccent)
                        }
                    case .review:
                        reviewForm
                    }
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .pageBackground()
            .navigationTitle("Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { dismiss() }
                        .foregroundStyle(Palette.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { Task { await confirm() } }
                        .fontWeight(.semibold)
                        .disabled(stage != .review || saving || estimate.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
        .presentationDetents([.large])
        .presentationBackground(Palette.background)
        .presentationCornerRadius(Radius.hero)
        .interactiveDismissDisabled(saving)
        .task { await analyse() }
    }

    private var reviewForm: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                TextField("Meal name", text: $estimate.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .submitLabel(.done)
                if !estimate.items.isEmpty {
                    Text(estimate.items.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
                Label("\(estimate.confidence.title) confidence estimate. Photo estimates aren't precise measurements, so adjust anything that looks wrong.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
            }

            VStack(spacing: 0) {
                NutrientField(title: "Calories", unit: "kcal", value: $estimate.kilocalories)
                Divider().overlay(Palette.border)
                NutrientField(title: "Protein", unit: "g", value: $estimate.proteinGrams)
                Divider().overlay(Palette.border)
                NutrientField(title: "Carbohydrates", unit: "g", value: $estimate.carbohydrateGrams)
                Divider().overlay(Palette.border)
                NutrientField(title: "Fat", unit: "g", value: $estimate.fatGrams)
            }
            .surface(padding: Spacing.m)

            rewardNote
        }
    }

    private var rewardNote: some View {
        let note = rewardNoteContent(model.mealOutcome(for: hash, at: takenAt))
        return Label(note.text, systemImage: note.symbol)
            .font(.footnote)
            .foregroundStyle(note.tint)
            .surface()
    }

    private func rewardNoteContent(_ outcome: MealRewardPolicy.Outcome) -> (symbol: String, text: String, tint: Color) {
        let rates = model.settings.rates
        switch outcome {
        case .eligible:
            return ("sterlingsign.circle.fill", "This meal earns \(rates.pencePerMealPhoto.formatted()) when you confirm it.", Palette.accent)
        case .dailyLimitReached:
            return ("checkmark.circle", "You've had today's \(rates.maxRewardedMealPhotosPerDay) photo rewards. This meal still counts towards your nutrition.", Palette.textSecondary)
        case .duplicate:
            return ("square.on.square", "This looks like a meal you've already logged today, so it won't earn another photo reward.", Palette.warning)
        }
    }

    private func analyse() async {
        stage = .analysing
        guard let analyser = model.mealAnalyzer else {
            stage = .failed(MealAnalysisError.notConfigured.errorDescription ?? "")
            return
        }
        // Only a downsized copy without location metadata leaves the device.
        guard let upload = MealPhotoProcessing.jpeg(from: image, maxPixel: 1024) else {
            stage = .failed("The photo couldn't be prepared.")
            return
        }
        hash = ImageFingerprint.averageHash(of: upload) ?? 0
        thumbnail = MealPhotoProcessing.jpeg(from: image, maxPixel: 240, quality: 0.6)
        do {
            estimate = try await analyser.analyse(jpeg: upload)
            withAnimation(.snappy) { stage = .review }
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func confirm() async {
        saving = true
        await model.confirmMeal(estimate, photo: thumbnail, hash: hash, at: takenAt)
        saved = true
        saving = false
        dismiss()
    }
}

private struct NutrientField: View {
    let title: String
    let unit: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            TextField(title, value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: 100)
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 36, alignment: .leading)
        }
        .padding(.vertical, Spacing.s)
    }
}
