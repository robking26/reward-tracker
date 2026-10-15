import SwiftData
import SwiftUI

struct NutritionView: View {
    @Environment(AppModel.self) private var model
    @Binding var showingSettings: Bool
    @State private var capturing = false
    @State private var choosingFromLibrary = false

    var body: some View {
        NavigationStack {
            MealsJournalList(header: AnyView(captureHeader))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        SettingsToolbarButton(isPresented: $showingSettings)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            choosingFromLibrary = true
                        } label: {
                            Image(systemName: "photo.on.rectangle")
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .accessibilityLabel("Choose a meal photo from your library")
                    }
                }
                .mealCapture(isPresented: $capturing, libraryPresented: $choosingFromLibrary)
        }
    }

    private var captureHeader: some View {
        let today = model.todayMetrics
        let limit = model.settings.rates.maxRewardedMealPhotosPerDay
        let left = max(0, limit - today.rewardEligibleMeals)
        return VStack(spacing: Spacing.m) {
            Button {
                capturing = true
            } label: {
                VStack(spacing: Spacing.s) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 80, height: 80)
                        .background(Palette.accent, in: Circle())
                    Text("Photograph a meal")
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    Text(left > 0
                         ? "\(left) of \(limit) photo rewards left today · \(model.settings.rates.pencePerMealPhoto.formatted()) each"
                         : "Today's photo rewards are used. Keep logging for your nutrition totals.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, Spacing.l)
                .frame(maxWidth: .infinity)
                .surface(radius: Radius.hero)
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityLabel("Photograph a meal. \(left) photo rewards left today.")

            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Today")
                NutritionGrid()
            }
            .padding(.top, Spacing.s)
        }
    }
}

/// The chronological meal journal, grouped by day.
struct MealsJournalList: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Meal.loggedAt, order: .reverse) private var meals: [Meal]
    var header: AnyView? = nil
    @State private var pendingDeletion: Meal?

    var body: some View {
        List {
            if let header {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.page, bottom: Spacing.xs, trailing: Spacing.page))
            }

            if meals.isEmpty {
                ContentUnavailableView("No meals yet", systemImage: "fork.knife",
                                       description: Text("Photograph a meal and confirm the estimate to see it here."))
                    .foregroundStyle(Palette.textSecondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(groupedDays, id: \.self) { day in
                Section {
                    ForEach(meals.filter { $0.day == day }) { meal in
                        MealRow(meal: meal, rewardAmount: model.settings.rates.pencePerMealPhoto)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = meal }
                            }
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = meal }
                            }
                    }
                } header: {
                    Text(DayKey(string: day).map { "Meals · " + DayLabel.text($0, model: model) } ?? day)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .textCase(nil)
                }
                .listRowBackground(Palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Nutrition")
        .confirmationDialog("Delete this meal?", isPresented: .init(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
            Button("Delete Meal", role: .destructive) {
                if let meal = pendingDeletion { Task { await model.deleteMeal(meal) } }
                pendingDeletion = nil
            }
        } message: {
            Text("Its nutrition and any photo reward for it will be removed.")
        }
    }

    private var groupedDays: [String] {
        var seen = Set<String>()
        return meals.compactMap { seen.insert($0.day).inserted ? $0.day : nil }
    }
}

struct MealRow: View {
    let meal: Meal
    let rewardAmount: Pence

    var body: some View {
        HStack(spacing: Spacing.s) {
            thumbnail
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meal.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: Spacing.xs)
                    Text(meal.loggedAt, format: .dateTime.hour().minute())
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                }
                Text("\(meal.kilocalories) kcal · P \(meal.proteinGrams) g · C \(meal.carbohydrateGrams) g · F \(meal.fatGrams) g")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                Text(meal.isRewardEligible ? "+\(rewardAmount.formatted())" : "No photo reward")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(meal.isRewardEligible ? Palette.accent : Palette.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = meal.thumbnailJPEG, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "fork.knife")
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 56, height: 56)
                .background(Palette.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}
