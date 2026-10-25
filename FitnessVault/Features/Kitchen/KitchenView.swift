import SwiftUI

/// The Kitchen tab: today's food, the 8-week lunch and breakfast cycle, and the weekly Aldi lists.
/// Nothing here affects earnings.
enum KitchenSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case cycle = "Cycle"
    case shopping = "Shopping"
    case teas = "Teas"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .today: "fork.knife"
        case .cycle: "arrow.triangle.2.circlepath"
        case .shopping: "cart.fill"
        case .teas: "frying.pan.fill"
        }
    }
}

struct KitchenView: View {
    @Environment(KitchenModel.self) private var kitchen
    @Binding var showingSettings: Bool
    @State var section: KitchenSection = .today

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PillTabs(items: KitchenSection.allCases, selection: $section, tint: Palette.kitchen, stacked: true,
                         title: { $0.rawValue }, symbol: { $0.symbol })
                switch section {
                case .today: FoodTodaySection()
                case .cycle: CycleSection()
                case .shopping: CycleShoppingSection()
                case .teas: TeasSection()
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle("Kitchen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton(isPresented: $showingSettings)
            }
        }
        .refreshable { kitchen.refresh() }
        .onAppear { kitchen.refresh() }
    }
}

/// Tints for the two cycle meals.
extension CycleSlot {
    var tint: Color { self == .breakfast ? Palette.fresh : Palette.kitchen }
    var symbol: String { self == .breakfast ? "sunrise.fill" : "takeoutbag.and.cup.and.straw.fill" }
}

/// One macro: a big rounded number over its name, in a tinted tile.
struct MacroTile: View {
    let value: Double
    let unit: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(value.rounded()))")
                .font(.display(22))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit == "kcal" ? unit : "g \(unit)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Calories, protein, carbs and fat as four tiles.
struct MacroRow: View {
    let macros: Macros

    var body: some View {
        HStack(spacing: Spacing.xs) {
            MacroTile(value: macros.kcal, unit: "kcal", tint: Palette.kitchen)
            MacroTile(value: macros.protein, unit: "protein", tint: Palette.accent)
            MacroTile(value: macros.carbs, unit: "carbs", tint: Palette.frost)
            MacroTile(value: macros.fat, unit: "fat", tint: Palette.rose)
        }
    }
}

// MARK: - Cycle

struct CycleSection: View {
    @Environment(KitchenModel.self) private var kitchen

    var body: some View {
        let current = kitchen.currentWeek
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Week \(current)")
                        .font(.display(36))
                        .foregroundStyle(Palette.textPrimary)
                    Text("of \(MealCycle.weeks)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Menu {
                        ForEach(1...MealCycle.weeks, id: \.self) { week in
                            Button("Make this week \(week)") { kitchen.setCurrentWeek(week) }
                        }
                    } label: {
                        RoundIconLabel(symbol: "slider.horizontal.3", size: 40, tint: Palette.kitchen,
                                       fill: Palette.kitchen.opacity(0.16))
                    }
                    .accessibilityLabel("Change the cycle week")
                }
                SegmentedProgress(total: MealCycle.weeks, done: current - 1, tint: Palette.kitchen)
                Text("Same breakfast every day and the same batch-cooked lunch Monday to Friday, for a week. Eight weeks, then round again.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .heroCard(tint: Palette.kitchen, symbol: "arrow.triangle.2.circlepath")

            ForEach(1...MealCycle.weeks, id: \.self) { week in
                CycleWeekCard(week: week, isCurrent: week == current)
            }
            Footnote("Numbers are per portion, calculated from typical UK values for the Aldi products, so they're close estimates.")
        }
    }
}

private struct CycleWeekCard: View {
    let week: Int
    let isCurrent: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("WEEK \(week)")
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(isCurrent ? Palette.kitchen : Palette.textTertiary)
                Spacer()
                if isCurrent {
                    Chip(text: "This week", tint: Palette.onAccent, fill: Palette.kitchen)
                }
            }
            ForEach(CycleSlot.allCases) { slot in
                let meal = MealCycle.meal(slot, week: week)
                NavigationLink {
                    CycleMealDetailView(meal: meal)
                } label: {
                    TileRow(title: meal.title, subtitle: subtitle(meal), symbol: slot.symbol, tint: slot.tint) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .surface()
        .overlay { shape.strokeBorder(isCurrent ? Palette.kitchen.opacity(0.6) : Color.clear, lineWidth: 1.5) }
    }

    private func subtitle(_ meal: CycleMeal) -> String {
        let macros = meal.macros
        return "\(meal.slot.title) · \(Int(macros.kcal.rounded())) kcal · \(Int(macros.protein.rounded())) g protein"
    }
}

struct CycleMealDetailView: View {
    let meal: CycleMeal
    @State private var batch = true

    var body: some View {
        let macros = meal.macros
        let portions = meal.slot == .lunch && batch ? 5 : 1
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                DishArtwork(title: meal.title, symbol: meal.symbol, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Radius2.hero, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(meal.title)
                        .font(.display(30))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(meal.summary)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ChipFlow().callAsFunction {
                        Chip(text: "Week \(meal.week)", symbol: "arrow.triangle.2.circlepath", tint: meal.slot.tint,
                             fill: meal.slot.tint.opacity(0.14))
                        Chip(text: meal.slot == .lunch ? "Mon–Fri lunch" : "Every breakfast", symbol: meal.slot.symbol)
                        Chip(text: "\(meal.prepMinutes) min prep", symbol: "clock.fill")
                        if meal.cookMinutes > 0 {
                            Chip(text: "\(meal.cookMinutes) min cooking", symbol: "flame.fill")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Per portion")
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    MacroRow(macros: macros)
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    CardHeader(title: "Ingredients", symbol: "basket.fill", tint: Palette.fresh,
                               subtitle: portions == 1 ? "One portion" : "Batch of \(portions)") {
                        if meal.slot == .lunch {
                            Picker("Amounts", selection: $batch) {
                                Text("×1").tag(false)
                                Text("×5").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 104)
                        }
                    }
                    ForEach(meal.ingredients, id: \.foodID) { ingredient in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Circle().fill(Palette.fresh).frame(width: 6, height: 6)
                            Text(ingredient.text(portions: portions))
                                .font(.subheadline)
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .surface()

                VStack(alignment: .leading, spacing: Spacing.m) {
                    CardHeader(title: meal.slot == .lunch ? "Sunday batch cook" : "Method", symbol: "list.number",
                               tint: Palette.kitchen, subtitle: "\(meal.steps.count) steps")
                    ForEach(meal.steps.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: Spacing.s) {
                            Text("\(index + 1)")
                                .font(.footnote.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.onAccent)
                                .frame(width: 26, height: 26)
                                .background(Palette.kitchen, in: Circle())
                            Text(meal.steps[index])
                                .font(.subheadline)
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(alignment: .top, spacing: Spacing.s) {
                        Image(systemName: "refrigerator.fill")
                            .foregroundStyle(Palette.frost)
                            .accessibilityHidden(true)
                        Text(meal.storage)
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.frost.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
                .surface()
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle(meal.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shopping

struct CycleShoppingSection: View {
    @Environment(KitchenModel.self) private var kitchen
    @State private var nextWeek = false

    var body: some View {
        let monday = kitchen.shoppingMonday(next: nextWeek)
        let week = kitchen.week(of: monday)
        let start = monday.startDate(calendar: kitchen.calendar).formatted(.dateTime.weekday(.abbreviated).day().month())
        VStack(alignment: .leading, spacing: Spacing.m) {
            Picker("Week", selection: $nextWeek) {
                Text("This week").tag(false)
                Text("Next week").tag(true)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Week \(week) · from \(start)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                ShareLink(item: kitchen.shareText(weekStarting: monday), subject: Text("Aldi list"),
                          preview: SharePreview("Aldi list · week \(week)")) {
                    Label("Share list", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, Spacing.s)
                        .frame(minHeight: 36)
                        .background(Palette.kitchen, in: Capsule())
                }
                .accessibilityHint("Sends both lists as text, in Aldi walking order")
            }

            CycleListCard(slot: .lunch, monday: monday)
            CycleListCard(slot: .breakfast, monday: monday)
            Footnote("Aldi packs and typical prices, so totals are estimates. \"Check the cupboard\" items usually last more than a week, so they're left out of the total.")
        }
    }
}

private struct CycleListCard: View {
    @Environment(KitchenModel.self) private var kitchen
    let slot: CycleSlot
    let monday: DayKey

    var body: some View {
        let meal = MealCycle.meal(slot, week: kitchen.week(of: monday))
        let lines = kitchen.shoppingList(slot, weekStarting: monday)
        let left = lines.filter { !kitchen.isTicked($0, slot: slot, monday: monday) }
        VStack(alignment: .leading, spacing: Spacing.s) {
            CardHeader(title: slot == .lunch ? "Lunches" : "Breakfasts", symbol: slot.symbol, tint: slot.tint,
                       subtitle: "\(meal.title) × \(slot.portionsPerWeek)") {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("≈ \(CycleShopping.estimate(left).formatted())")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                    Text(left.isEmpty ? "All in" : "\(left.count) to get")
                        .font(.caption)
                        .foregroundStyle(left.isEmpty ? Palette.success : Palette.textTertiary)
                }
            }
            VStack(spacing: 0) {
                ForEach(lines.indices, id: \.self) { index in
                    let line = lines[index]
                    CycleListRow(line: line, ticked: kitchen.isTicked(line, slot: slot, monday: monday), tint: slot.tint) {
                        kitchen.toggle(line, slot: slot, monday: monday)
                    }
                    if index < lines.count - 1 { RowDivider(inset: 40) }
                }
            }
            if left.count < lines.count {
                Button("Untick all") { kitchen.clearTicks(slot: slot, monday: monday) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(slot.tint)
            }
        }
        .surface()
    }
}

private struct CycleListRow: View {
    let line: CycleShoppingLine
    let ticked: Bool
    let tint: Color
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.s) {
                ZStack {
                    Circle().strokeBorder(ticked ? tint : Palette.textTertiary, lineWidth: 2)
                    if ticked {
                        Circle().fill(tint)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Palette.onAccent)
                    }
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name)
                        .font(.body)
                        .foregroundStyle(ticked ? Palette.textTertiary : Palette.textPrimary)
                        .strikethrough(ticked, color: Palette.textTertiary)
                    Text(line.checkFirst ? "\(line.needed) · check the cupboard" : "\(line.needed) · \(line.packs)")
                        .font(.caption)
                        .foregroundStyle(line.checkFirst ? Palette.warning : Palette.textTertiary)
                }
                Spacer()
                Text(Pence(line.pricePence).formatted())
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: ticked)
        .accessibilityLabel("\(line.name), \(line.needed), \(ticked ? "in the trolley" : "to buy")")
    }
}
