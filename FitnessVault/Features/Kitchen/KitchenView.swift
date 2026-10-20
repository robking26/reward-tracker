import SwiftUI

/// The kitchen (Phase 4): this week's meals, the Aldi list, what's probably in, recipes and the £400 ceiling.
/// Opened from Today; never part of the daily score.
enum KitchenSection: String, CaseIterable, Identifiable {
    case plan = "Meals"
    case list = "List"
    case stock = "In stock"
    case recipes = "Recipes"
    case spending = "Spend"

    var id: String { rawValue }
}

struct KitchenView: View {
    @Environment(KitchenModel.self) private var kitchen
    @State var section: KitchenSection = .plan

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Picker("Section", selection: $section) {
                    ForEach(KitchenSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch section {
                case .plan: MealPlanSection()
                case .list: ShoppingSection()
                case .stock: InventorySection()
                case .recipes: RecipeLibrarySection()
                case .spending: SpendingSection()
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle("Kitchen")
        .onAppear { kitchen.refresh() }
    }
}

// MARK: - Meal plan

struct MealPlanSection: View {
    @Environment(KitchenModel.self) private var kitchen

    var body: some View {
        let days = upcomingDays
        VStack(alignment: .leading, spacing: Spacing.m) {
            BatchCookCard()
            ForEach(days, id: \.self) { day in
                DayMealsCard(day: day, entries: kitchen.entries(on: day))
            }
            Button {
                kitchen.replan()
            } label: {
                SmallActionLabel(title: "Replan the rest of the week", symbol: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(CardButtonStyle())
            Text("Dinners are two identical portions. Lunches come from one batch cook, on a four-week rotation. Nothing here affects your score.")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var upcomingDays: [DayKey] {
        let today = kitchen.today
        let planned = Set(kitchen.plan.compactMap(\.dayKey).filter { $0 >= today })
        return planned.sorted()
    }
}

struct DayMealsCard: View {
    @Environment(KitchenModel.self) private var kitchen
    let day: DayKey
    let entries: [MealPlanEntry]
    @State private var swapping: MealPlanEntry?
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(day == kitchen.today ? Palette.accent : Palette.textSecondary)
            ForEach(entries, id: \.id) { entry in
                MealRow(entry: entry, onSwap: { swapping = entry }, onCooked: { note = kitchen.markCooked(entry) })
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(Palette.success)
            }
        }
        .surface()
        .sheet(item: $swapping) { entry in
            NavigationStack {
                RecipePickerView(slot: entry.slot) { recipe in
                    kitchen.swap(entry, to: recipe)
                    swapping = nil
                } onFreezer: { meal in
                    kitchen.useFreezer(entry, meal: meal)
                    swapping = nil
                }
            }
            .presentationBackground(Palette.background)
        }
    }

    private var title: String {
        let date = day.startDate(calendar: kitchen.calendar)
        if day == kitchen.today { return "Today" }
        if day == kitchen.today.adding(days: 1, calendar: kitchen.calendar) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }
}

struct MealRow: View {
    @Environment(KitchenModel.self) private var kitchen
    let entry: MealPlanEntry
    var onSwap: () -> Void
    var onCooked: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: entry.slot == .lunch ? "takeoutbag.and.cup.and.straw" : (entry.fromFreezer ? "snowflake" : "fork.knife"))
                .foregroundStyle(entry.cooked ? Palette.success : Palette.textTertiary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body)
                    .foregroundStyle(Palette.textPrimary)
                    .strikethrough(entry.cooked)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if entry.portions > 0 && !entry.cooked {
                Menu {
                    Button("Eaten", systemImage: "checkmark", action: onCooked)
                    if entry.fromFreezer && !entry.defrosted {
                        Button("Moved to the fridge", systemImage: "snowflake") { kitchen.markDefrosted(entry) }
                    }
                    Button("Swap", systemImage: "arrow.left.arrow.right", action: onSwap)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Options for \(entry.title)")
            }
        }
    }

    private var detail: String {
        var parts: [String] = []
        if entry.slot == .lunch { parts.append("Lunch") } else if entry.portions > 0 { parts.append("Dinner for two") }
        if let recipe = kitchen.recipe(entry.recipeID), !entry.fromFreezer {
            parts.append("\(recipe.prepMinutes + recipe.cookMinutes) min")
            parts.append("≈ \(Int(recipe.protein.rounded())) g protein")
        }
        if entry.fromFreezer { parts.append(entry.defrosted ? "Defrosting in the fridge" : "Defrost the night before") }
        if let note = entry.note, !entry.fromFreezer, entry.slot == .dinner { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

struct RecipePickerView: View {
    @Environment(KitchenModel.self) private var kitchen
    @Environment(\.dismiss) private var dismiss
    let slot: MealSlot
    var onPick: (Recipe) -> Void
    var onFreezer: (FreezerMeal) -> Void

    var body: some View {
        List {
            let freezer = kitchen.freezerMeals().filter { $0.portions >= (slot == .dinner ? 2 : 1) }
            if !freezer.isEmpty {
                Section("From the freezer") {
                    ForEach(freezer, id: \.title) { meal in
                        Button("\(meal.title) (\(meal.portions) left)") { onFreezer(meal) }
                    }
                }
            }
            Section(slot == .dinner ? "Dinners" : "Lunches") {
                ForEach(recipes, id: \.id) { recipe in
                    Button {
                        onPick(recipe)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.title).foregroundStyle(Palette.textPrimary)
                            Text("\(recipe.prepMinutes + recipe.cookMinutes) min · \(recipe.washUpMinutes) min washing up")
                                .font(.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Swap")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private var recipes: [Recipe] {
        kitchen.activeRecipes.filter { recipe in
            recipe.excludedIngredient == nil && (slot == .dinner ? recipe.role.suitsDinner : recipe.role.suitsLunch)
        }
    }
}

struct BatchCookCard: View {
    @Environment(KitchenModel.self) private var kitchen
    @State private var recorded = false

    var body: some View {
        let batch = kitchen.batchPlan
        if !batch.items.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text("Batch cook")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("about \(batch.minutes) min")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(batch.fits ? Palette.textSecondary : Palette.warning)
                }
                ForEach(batch.items, id: \.self) { item in
                    Label("\(item.title) × \(item.portions)\(item.forFreezer ? " for the freezer" : "")",
                          systemImage: item.forFreezer ? "snowflake" : "takeoutbag.and.cup.and.straw")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textPrimary)
                }
                ForEach(batch.adjustments, id: \.self) { line in
                    Text(line).font(.caption).foregroundStyle(Palette.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
                if recorded {
                    Text("Logged. Lunches are in the fridge; extras are in the freezer.")
                        .font(.caption)
                        .foregroundStyle(Palette.success)
                } else {
                    SmallActionButton(title: "Done the batch cook", symbol: "checkmark") {
                        kitchen.recordBatchCook(batch)
                        recorded = true
                    }
                }
            }
            .surface()
        }
    }
}

// MARK: - Shopping list

struct ShoppingSection: View {
    @Environment(KitchenModel.self) private var kitchen
    @State private var newItem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                SmallActionButton(title: "Build from meals", symbol: "list.bullet.rectangle") { kitchen.generateShoppingList() }
                SmallActionButton(title: "Clear ticked", symbol: "checkmark.circle") { kitchen.clearTicked() }
            }
            if let warning = kitchen.budget.warning(forList: kitchen.listEstimate) {
                NoticeBanner(symbol: "sterlingsign.circle", title: "Over the £400 ceiling", message: warning)
            }
            HStack {
                TextField("Add something", text: $newItem)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit(add)
                Button("Add", action: add).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .surface(padding: Spacing.s)

            if kitchen.shopping.isEmpty {
                Text("Nothing on the list. Build it from this week's meals, or add things as you run out.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(departments) { department in
                    DepartmentCard(department: department, items: items(in: department))
                }
                HStack {
                    Text("Estimate for what's left")
                    Spacer()
                    Text(kitchen.listEstimate.formatted()).monospacedDigit()
                }
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                Text("Aldi order, Co-op for top-ups. Prices are typical, not live. Things marked \"check first\" might already be in.")
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var departments: [AisleDepartment] {
        AisleDepartment.allCases.filter { department in kitchen.shopping.contains { $0.department == department } }
    }

    private func items(in department: AisleDepartment) -> [ShoppingItem] {
        kitchen.shopping.filter { $0.department == department }.sorted { ($0.ticked ? 1 : 0, $0.name) < ($1.ticked ? 1 : 0, $1.name) }
    }

    private func add() {
        let text = newItem.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        kitchen.addToShopping(text)
        newItem = ""
    }
}

struct DepartmentCard: View {
    @Environment(KitchenModel.self) private var kitchen
    let department: AisleDepartment
    let items: [ShoppingItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(department.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            ForEach(items, id: \.key) { item in
                Button {
                    kitchen.toggle(item)
                } label: {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: item.ticked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.ticked ? Palette.success : Palette.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .foregroundStyle(item.ticked ? Palette.textTertiary : Palette.textPrimary)
                                .strikethrough(item.ticked)
                            if !item.quantityText.isEmpty || item.checkFirst {
                                Text(item.checkFirst ? "\(item.quantityText) · check first" : item.quantityText)
                                    .font(.caption)
                                    .foregroundStyle(item.checkFirst ? Palette.warning : Palette.textTertiary)
                            }
                        }
                        Spacer()
                        if let pence = item.estimatePence {
                            Text(Pence(pence).formatted())
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: item.ticked)
                .accessibilityLabel("\(item.name), \(item.ticked ? "in the trolley" : "to buy")")
            }
        }
        .surface()
    }
}

// MARK: - Inventory

struct InventorySection: View {
    @Environment(KitchenModel.self) private var kitchen
    @State private var newItem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            FreezerCard()
            HStack {
                TextField("Tell me what's in, e.g. eggs", text: $newItem)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit(add)
                Button("Add", action: add).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .surface(padding: Spacing.s)
            ForEach(locations, id: \.self) { location in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(location.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    ForEach(items(at: location), id: \.key) { item in
                        InventoryRow(item: item)
                    }
                }
                .surface()
            }
            Text("These are estimates from receipts, your list and what you tell me. A receipt only says something was bought, not that it's still there. Say \"we've run out of milk\" to the coach any time.")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stock: [InventoryItem] { kitchen.inventory.filter { !$0.key.hasPrefix("meal:") } }

    private var locations: [StorageLocation] {
        StorageLocation.allCases.filter { location in stock.contains { $0.location == location } }
    }

    private func items(at location: StorageLocation) -> [InventoryItem] {
        stock.filter { $0.location == location }
    }

    private func add() {
        let text = newItem.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        kitchen.confirm(text, portions: nil)
        newItem = ""
    }
}

struct InventoryRow: View {
    @Environment(KitchenModel.self) private var kitchen
    let item: InventoryItem

    var body: some View {
        let presence = item.presence(now: kitchen.now())
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).foregroundStyle(Palette.textPrimary)
                Text(presence.title).font(.caption).foregroundStyle(tint(presence))
            }
            Spacer()
            Menu {
                Button("It's in", systemImage: "checkmark") { kitchen.confirm(item.name, portions: nil) }
                Button("Run out", systemImage: "xmark") { kitchen.markOut(item.name) }
                Button("Add to the list", systemImage: "cart") { kitchen.addToShopping(item.name) }
                Button("Stop tracking", systemImage: "trash", role: .destructive) { kitchen.remove(item) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Palette.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Options for \(item.name)")
        }
    }

    private func tint(_ presence: Presence) -> Color {
        switch presence {
        case .have, .probably: Palette.success
        case .maybe: Palette.warning
        case .probablyNot, .out: Palette.textTertiary
        }
    }
}

struct FreezerCard: View {
    @Environment(KitchenModel.self) private var kitchen

    var body: some View {
        let meals = kitchen.freezerMeals()
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Freezer meals")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            if meals.isEmpty {
                Text("None yet. Freezable dinners add their spare portions when you mark them eaten, and the batch cook adds more.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(meals, id: \.title) { meal in
                    Stepper(value: Binding(get: { meal.portions }, set: { kitchen.confirm(meal.title, portions: $0) }), in: 0...20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.title).foregroundStyle(Palette.textPrimary)
                            Text(DefrostPlanner.portionsText(meal.portions)).font(.caption).foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
            if meals.count < 2 {
                Text("Aim for two or three favourites in here for difficult days.")
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .surface()
    }
}
