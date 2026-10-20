import SwiftUI

/// Tonight's dinner at the top of the Kitchen, with the defrost prompt and a way out when it isn't happening.
struct DinnerCard: View {
    @Environment(KitchenModel.self) private var kitchen
    @State private var rescuing = false
    @State private var forgotDefrost = false
    @State private var choosingFromMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Tonight")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)

            if let dinner = kitchen.tonight, dinner.portions == 0 {
                Text("Eating out")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                SmallActionButton(title: "Help me pick from the menu", symbol: "menucard") { choosingFromMenu = true }
            } else if let dinner = kitchen.tonight {
                Text(dinner.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(dinner.cooked ? Palette.textTertiary : Palette.textPrimary)
                    .strikethrough(dinner.cooked)
                if let detail = detail(dinner) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if kitchen.tonightNeedsDefrosting {
                    HStack(spacing: Spacing.s) {
                        SmallActionButton(title: "It's defrosted", symbol: "checkmark") { kitchen.markDefrosted(dinner) }
                        SmallActionButton(title: "Forgot", symbol: "snowflake") {
                            forgotDefrost = true
                            rescuing = true
                        }
                    }
                } else if !dinner.cooked && dinner.portions > 0 {
                    HStack(spacing: Spacing.s) {
                        if kitchen.cooking != dinner.id, !dinner.fromFreezer, kitchen.recipe(dinner.recipeID) != nil {
                            SmallActionButton(title: "Start cooking", symbol: "flame") { kitchen.startCooking(dinner) }
                        }
                        SmallActionButton(title: "Eaten", symbol: "checkmark") { kitchen.markCooked(dinner) }
                        SmallActionButton(title: "Not happening", symbol: "arrow.uturn.left") {
                            forgotDefrost = false
                            rescuing = true
                        }
                    }
                }
            } else {
                Text("Nothing planned tonight.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                SmallActionButton(title: "Easy options", symbol: "fork.knife") {
                    forgotDefrost = false
                    rescuing = true
                }
            }

            if let tomorrow = tomorrowToDefrost {
                Divider().overlay(Palette.border)
                HStack(alignment: .top, spacing: Spacing.s) {
                    Image(systemName: "snowflake").foregroundStyle(Palette.accent).accessibilityHidden(true)
                    Text("Tomorrow is \(tomorrow.title). Move \(DefrostPlanner.portionsText(tomorrow.portions)) from the freezer to the fridge tonight.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SmallActionButton(title: "Done", symbol: "checkmark") { kitchen.markDefrosted(tomorrow) }
            }
        }
        .surface()
        .sheet(isPresented: $choosingFromMenu) {
            MenuHelperView().presentationBackground(Palette.background)
        }
        .sheet(isPresented: $rescuing) {
            DinnerRescueView(defrostForgotten: forgotDefrost)
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.background)
        }
    }

    private func detail(_ dinner: MealPlanEntry) -> String? {
        if dinner.cooked { return "Done." }
        if dinner.fromFreezer { return dinner.defrosted ? "From the freezer, defrosting in the fridge. Reheat until piping hot." : "From the freezer." }
        guard let recipe = kitchen.recipe(dinner.recipeID) else { return dinner.note }
        return "Two portions · about \(recipe.prepMinutes + recipe.cookMinutes) min · \(recipe.washUpMinutes) min washing up"
    }

    /// From 4pm, a reminder about tomorrow's freezer meal.
    private var tomorrowToDefrost: MealPlanEntry? {
        let hour = kitchen.calendar.component(.hour, from: kitchen.now())
        guard hour >= 16, let entry = kitchen.dinner(on: kitchen.today.adding(days: 1, calendar: kitchen.calendar)),
              entry.fromFreezer, !entry.defrosted else { return nil }
        return entry
    }
}

/// Scenario G: two or three low-effort options from what's probably in. No judgement, no fine.
struct DinnerRescueView: View {
    @Environment(KitchenModel.self) private var kitchen
    @Environment(\.dismiss) private var dismiss
    let defrostForgotten: Bool

    var body: some View {
        NavigationStack {
            List {
                if defrostForgotten, let dinner = kitchen.tonight, dinner.fromFreezer {
                    Section {
                        Text(DefrostPlanner.forgottenAdvice(dinner.title))
                            .font(.subheadline)
                    }
                }
                Section {
                    ForEach(kitchen.rescueOptions(defrostForgotten: defrostForgotten)) { option in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(option.title, systemImage: symbol(option.kind))
                                .foregroundStyle(Palette.textPrimary)
                            Text(option.detail)
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                } footer: {
                    Text("Based on what's probably in. Any of these is fine.")
                }
            }
            .scrollContentBackground(.hidden)
            .pageBackground()
            .navigationTitle("Easy dinner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func symbol(_ kind: RescueKind) -> String {
        switch kind {
        case .cupboard: "cabinet"
        case .freezer: "snowflake"
        case .topUp: "basket"
        case .takeaway: "takeoutbag.and.cup.and.straw"
        }
    }
}
