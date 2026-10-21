import SwiftUI

/// Tonight's dinner at the top of the Kitchen, with the defrost prompt and a way out when it isn't happening.
struct DinnerCard: View {
    @Environment(KitchenModel.self) private var kitchen
    @State private var rescuing = false
    @State private var forgotDefrost = false
    @State private var choosingFromMenu = false

    var body: some View {
        let dinner = kitchen.tonight
        let tint: Color = dinner?.fromFreezer == true ? Palette.frost : Palette.kitchen
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Chip(text: "TONIGHT", symbol: "moon.stars.fill", tint: Palette.onAccent, fill: tint)
                Spacer()
                if let dinner, dinner.cooked {
                    Chip(text: "Eaten", symbol: "checkmark", tint: Palette.success, fill: Palette.success.opacity(0.15))
                }
            }

            if let dinner, dinner.portions == 0 {
                Text("Eating out")
                    .font(.display(32))
                    .foregroundStyle(Palette.textPrimary)
                Button {
                    choosingFromMenu = true
                } label: {
                    Label("Help me pick from the menu", systemImage: "menucard.fill")
                }
                .buttonStyle(PrimaryButtonStyle(tint: tint))
            } else if let dinner {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(dinner.title)
                        .font(.display(30))
                        .foregroundStyle(dinner.cooked ? Palette.textTertiary : Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    ChipFlow().callAsFunction {
                        ForEach(chips(dinner), id: \.text) { chip in
                            Chip(text: chip.text, symbol: chip.symbol, tint: Palette.textPrimary, fill: Palette.background.opacity(0.35))
                        }
                    }
                    if let note = note(dinner) {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                actions(dinner, tint: tint)
            } else {
                Text("Nothing planned")
                    .font(.display(30))
                    .foregroundStyle(Palette.textPrimary)
                Text("Two or three easy options from what's probably in.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                Button {
                    forgotDefrost = false
                    rescuing = true
                } label: {
                    Label("Easy options", systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle(tint: tint))
            }

            if let tomorrow = tomorrowToDefrost {
                HStack(alignment: .center, spacing: Spacing.s) {
                    IconTile(symbol: "snowflake", tint: Palette.frost, size: 38)
                    Text("Tomorrow is \(tomorrow.title). Move \(DefrostPlanner.portionsText(tomorrow.portions)) to the fridge tonight.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Done") { kitchen.markDefrosted(tomorrow) }
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.frost)
                        .padding(.horizontal, Spacing.s)
                        .frame(minHeight: 36)
                        .background(Palette.frost.opacity(0.15), in: Capsule())
                }
                .padding(Spacing.s)
                .background(Palette.background.opacity(0.35), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }
        }
        .heroCard(tint: tint, symbol: dinner?.fromFreezer == true ? "snowflake" : "fork.knife")
        .sheet(isPresented: $choosingFromMenu) {
            MenuHelperView().presentationBackground(Palette.background)
        }
        .sheet(isPresented: $rescuing) {
            DinnerRescueView(defrostForgotten: forgotDefrost)
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.background)
        }
    }

    @ViewBuilder
    private func actions(_ dinner: MealPlanEntry, tint: Color) -> some View {
        if kitchen.tonightNeedsDefrosting {
            HStack(spacing: Spacing.s) {
                Button {
                    kitchen.markDefrosted(dinner)
                } label: {
                    Label("It's defrosted", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle(tint: tint))
                Button {
                    forgotDefrost = true
                    rescuing = true
                } label: {
                    Text("Forgot")
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(width: 110)
            }
        } else if !dinner.cooked && dinner.portions > 0 {
            let canCook = kitchen.cooking != dinner.id && !dinner.fromFreezer && kitchen.recipe(dinner.recipeID) != nil
            VStack(spacing: Spacing.s) {
                if canCook {
                    Button {
                        kitchen.startCooking(dinner)
                    } label: {
                        Label("Start cooking", systemImage: "flame.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: tint))
                }
                HStack(spacing: Spacing.s) {
                    if canCook {
                        Button {
                            kitchen.markCooked(dinner)
                        } label: {
                            Label("Eaten", systemImage: "checkmark")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button {
                            kitchen.markCooked(dinner)
                        } label: {
                            Label("Eaten", systemImage: "checkmark")
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: tint))
                    }
                    Button {
                        forgotDefrost = false
                        rescuing = true
                    } label: {
                        Label("Not happening", systemImage: "arrow.uturn.left")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private struct DinnerChip {
        var text: String
        var symbol: String
    }

    private func chips(_ dinner: MealPlanEntry) -> [DinnerChip] {
        var result = [DinnerChip(text: "For two", symbol: "person.2.fill")]
        if dinner.fromFreezer {
            result.append(DinnerChip(text: "From the freezer", symbol: "snowflake"))
            return result
        }
        guard let recipe = kitchen.recipe(dinner.recipeID) else { return result }
        result.append(DinnerChip(text: "\(recipe.prepMinutes + recipe.cookMinutes) min", symbol: "clock.fill"))
        result.append(DinnerChip(text: "\(Int(recipe.protein.rounded())) g protein", symbol: "bolt.fill"))
        result.append(DinnerChip(text: "\(Int(recipe.kcal.rounded())) kcal", symbol: "flame.fill"))
        result.append(DinnerChip(text: "\(recipe.washUpMinutes) min wash-up", symbol: "drop.fill"))
        return result
    }

    private func note(_ dinner: MealPlanEntry) -> String? {
        if dinner.cooked { return nil }
        if dinner.fromFreezer {
            return dinner.defrosted ? "Defrosting in the fridge. Reheat until piping hot." : nil
        }
        return kitchen.recipe(dinner.recipeID) == nil ? dinner.note : nil
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
                        TileRow(title: option.title, subtitle: option.detail, symbol: symbol(option.kind),
                                tint: option.kind == .freezer ? Palette.frost : Palette.kitchen)
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
