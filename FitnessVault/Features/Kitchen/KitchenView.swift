import SwiftUI

/// The Kitchen tab: tonight's dinner, this week's meals, the Aldi list, what's probably in, recipes and the
/// £400 household ceiling. Nothing here affects earnings.
enum KitchenSection: String, CaseIterable, Identifiable {
    case plan = "Meals"
    case list = "List"
    case stock = "In stock"
    case recipes = "Recipes"
    case spending = "Spend"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .plan: "calendar"
        case .list: "checklist"
        case .stock: "refrigerator.fill"
        case .recipes: "book.closed.fill"
        case .spending: "sterlingsign.circle.fill"
        }
    }
}

struct KitchenView: View {
    @Environment(KitchenModel.self) private var kitchen
    @Binding var showingSettings: Bool
    @State var section: KitchenSection = .plan

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                DinnerCard()
                PillTabs(items: KitchenSection.allCases, selection: $section, tint: Palette.kitchen,
                         title: { $0.rawValue }, symbol: { $0.symbol })
                    .padding(.vertical, Spacing.xxs)
                Group {
                    switch section {
                    case .plan: MealPlanSection()
                    case .list: ShoppingSection()
                    case .stock: InventorySection()
                    case .recipes: RecipeLibrarySection()
                    case .spending: SpendingSection()
                    }
                }
                .transition(.opacity)
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

/// Symbols and hues for meals, shared by the plan, recipes and tonight's card.
enum MealStyle {
    static func symbol(slot: MealSlot, fromFreezer: Bool) -> String {
        if fromFreezer { return "snowflake" }
        return slot == .lunch ? "takeoutbag.and.cup.and.straw.fill" : "fork.knife"
    }

    static func tint(slot: MealSlot, fromFreezer: Bool) -> Color {
        if fromFreezer { return Palette.frost }
        return slot == .lunch ? Palette.fresh : Palette.kitchen
    }

    static func symbol(role: MealRole, slowCooker: Bool) -> String {
        if slowCooker { return "flame.fill" }
        switch role {
        case .lunch: return "takeoutbag.and.cup.and.straw.fill"
        case .dinner: return "fork.knife"
        case .both: return "frying.pan.fill"
        case .breakfast: return "cup.and.saucer.fill"
        }
    }
}

/// A capsule text field with a round add button.
struct AddField: View {
    let placeholder: String
    @Binding var text: String
    var tint: Color = Palette.kitchen
    let add: () -> Void

    var body: some View {
        let empty = text.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: Spacing.xs) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Palette.textTertiary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit(add)
            Button(action: add) {
                RoundIconLabel(symbol: "arrow.up", size: 34, tint: Palette.onAccent, fill: empty ? Palette.elevated : tint)
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .accessibilityLabel("Add")
        }
        .padding(.leading, Spacing.m)
        .padding(.trailing, 6)
        .frame(minHeight: 48)
        .background(Palette.surface, in: Capsule())
    }
}

// MARK: - Meal plan

struct MealPlanSection: View {
    @Environment(KitchenModel.self) private var kitchen
    @State private var selected: DayKey?

    var body: some View {
        let days = upcomingDays
        let day = selected.flatMap { days.contains($0) ? $0 : nil } ?? days.first
        VStack(alignment: .leading, spacing: Spacing.m) {
            if !days.isEmpty {
                DayStrip(days: days, selected: day) { picked in
                    withAnimation(.snappy) { selected = picked }
                }
            }
            if let day {
                DayMealsCard(day: day, entries: kitchen.entries(on: day))
                    .id(day)
            }
            BatchCookCard()
            HomeDaysCard()
            Button {
                kitchen.replan()
            } label: {
                Label("Replan the rest of the week", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(SecondaryButtonStyle())
            Footnote("Dinners are two identical portions. Lunches come from one batch cook, on a four-week rotation. Nothing here affects your earnings.")
        }
    }

    private var upcomingDays: [DayKey] {
        let today = kitchen.today
        let planned = Set(kitchen.plan.compactMap(\.dayKey).filter { $0 >= today })
        return planned.sorted()
    }
}

/// The week as tappable day pills: weekday, date and a dot for a freezer or slow-cooker night.
private struct DayStrip: View {
    @Environment(KitchenModel.self) private var kitchen
    let days: [DayKey]
    let selected: DayKey?
    let pick: (DayKey) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(days, id: \.self) { day in
                    DayPill(day: day, selected: day == selected, isToday: day == kitchen.today,
                            marker: marker(for: day), calendar: kitchen.calendar) { pick(day) }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func marker(for day: DayKey) -> Color? {
        guard let dinner = kitchen.dinner(on: day) else { return nil }
        if dinner.cooked { return Palette.success }
        if dinner.fromFreezer { return Palette.frost }
        if dinner.portions == 0 { return Palette.rose }
        return nil
    }
}

private struct DayPill: View {
    let day: DayKey
    let selected: Bool
    let isToday: Bool
    let marker: Color?
    let calendar: Calendar
    let action: () -> Void

    var body: some View {
        let date = day.startDate(calendar: calendar)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let ink: Color = selected ? Palette.onAccent : Palette.textPrimary
        let soft: Color = selected ? Palette.onAccent.opacity(0.7) : Palette.textTertiary
        Button(action: action) {
            VStack(spacing: 4) {
                Text(isToday ? "Today" : date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(soft)
                Text(date.formatted(.dateTime.day()))
                    .font(.display(22))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                Circle()
                    .fill(marker ?? Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 58, height: 76)
            .background(selected ? Palette.kitchen : Palette.surface, in: shape)
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month()))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct DayMealsCard: View {
    @Environment(KitchenModel.self) private var kitchen
    let day: DayKey
    let entries: [MealPlanEntry]
    @State private var swapping: MealPlanEntry?
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(day.startDate(calendar: kitchen.calendar).formatted(.dateTime.weekday(.wide).day().month()))
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.bottom, Spacing.xxs)
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                MealRow(entry: entry, onSwap: { swapping = entry }, onCooked: { note = kitchen.markCooked(entry) })
                if index < entries.count - 1 { RowDivider() }
            }
            if let note {
                Label(note, systemImage: "snowflake")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.frost)
                    .padding(.top, Spacing.xxs)
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
        if day == kitchen.today { return "Today" }
        if day == kitchen.today.adding(days: 1, calendar: kitchen.calendar) { return "Tomorrow" }
        return day.startDate(calendar: kitchen.calendar).formatted(.dateTime.weekday(.wide))
    }
}

struct MealRow: View {
    @Environment(KitchenModel.self) private var kitchen
    let entry: MealPlanEntry
    var onSwap: () -> Void
    var onCooked: () -> Void

    var body: some View {
        TileRow(title: entry.title, subtitle: detail,
                symbol: MealStyle.symbol(slot: entry.slot, fromFreezer: entry.fromFreezer),
                tint: MealStyle.tint(slot: entry.slot, fromFreezer: entry.fromFreezer), done: entry.cooked) {
            if entry.portions > 0 && !entry.cooked {
                Menu {
                    Button("Eaten", systemImage: "checkmark", action: onCooked)
                    if entry.fromFreezer && !entry.defrosted {
                        Button("Moved to the fridge", systemImage: "snowflake") { kitchen.markDefrosted(entry) }
                    }
                    Button("Swap", systemImage: "arrow.left.arrow.right", action: onSwap)
                } label: {
                    RoundIconLabel(symbol: "ellipsis", size: 36, tint: Palette.textSecondary)
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
            parts.append("\(Int(recipe.protein.rounded())) g protein")
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
        let freezer = kitchen.freezerMeals().filter { $0.portions >= (slot == .dinner ? 2 : 1) }
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if !freezer.isEmpty {
                    SectionTitle(title: "From the freezer")
                    VStack(spacing: 0) {
                        ForEach(freezer.indices, id: \.self) { index in
                            let meal = freezer[index]
                            Button {
                                onFreezer(meal)
                            } label: {
                                TileRow(title: meal.title, subtitle: DefrostPlanner.portionsText(meal.portions) + " left",
                                        symbol: "snowflake", tint: Palette.frost)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < freezer.count - 1 { RowDivider() }
                        }
                    }
                    .surface()
                }
                SectionTitle(title: slot == .dinner ? "Dinners" : "Lunches")
                VStack(spacing: 0) {
                    ForEach(recipes.indices, id: \.self) { index in
                        let recipe = recipes[index]
                        Button {
                            onPick(recipe)
                        } label: {
                            TileRow(title: recipe.title,
                                    subtitle: "\(recipe.prepMinutes + recipe.cookMinutes) min · \(recipe.washUpMinutes) min washing up",
                                    symbol: MealStyle.symbol(role: recipe.role, slowCooker: recipe.usesSlowCooker),
                                    tint: MealStyle.tint(slot: slot, fromFreezer: false))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < recipes.count - 1 { RowDivider() }
                    }
                }
                .surface()
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle("Swap")
        .navigationBarTitleDisplayMode(.inline)
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

/// Which weekdays you work from home: slow-cooker meals are only planned for those (no morning prep on office days).
struct HomeDaysCard: View {
    @Environment(KitchenModel.self) private var kitchen
    private let weekdays = [1, 2, 3, 4, 5]
    private let letters = ["M", "T", "W", "T", "F"]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            CardHeader(title: "Working from home", symbol: "house.fill", tint: Palette.kitchen,
                       subtitle: "Slow-cooker days, 07:10 reminder")
            HStack(spacing: Spacing.xs) {
                ForEach(weekdays, id: \.self) { weekday in
                    let atHome: Bool = kitchen.homeWorkdays.contains(weekday)
                    let fill: Color = atHome ? Palette.kitchen : Palette.elevated
                    let ink: Color = atHome ? Palette.onAccent : Palette.textSecondary
                    Button {
                        kitchen.setHomeWorkday(weekday, !atHome)
                    } label: {
                        VStack(spacing: 2) {
                            Text(letters[weekday - 1])
                                .font(.headline)
                            Image(systemName: atHome ? "house.fill" : "building.2")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(fill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[weekday % 7])
                    .accessibilityValue(atHome ? "Working from home" : "In the office")
                }
            }
        }
        .surface()
    }
}

struct BatchCookCard: View {
    @Environment(KitchenModel.self) private var kitchen
    @State private var recorded = false

    var body: some View {
        let batch = kitchen.batchPlan
        if !batch.items.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                CardHeader(title: "Batch cook", symbol: "frying.pan.fill", tint: Palette.fresh, subtitle: "Once a week") {
                    Chip(text: "≈ \(batch.minutes) min", symbol: "clock",
                         tint: batch.fits ? Palette.fresh : Palette.warning,
                         fill: (batch.fits ? Palette.fresh : Palette.warning).opacity(0.14))
                }
                VStack(spacing: 0) {
                    ForEach(batch.items, id: \.self) { item in
                        HStack(spacing: Spacing.s) {
                            Image(systemName: item.forFreezer ? "snowflake" : "takeoutbag.and.cup.and.straw.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(item.forFreezer ? Palette.frost : Palette.fresh)
                                .frame(width: 24)
                            Text(item.title)
                                .font(.subheadline)
                                .foregroundStyle(Palette.textPrimary)
                            Spacer()
                            Text("× \(item.portions)")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .frame(minHeight: 36)
                    }
                }
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xxs)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                ForEach(batch.adjustments, id: \.self) { line in
                    Footnote(line)
                }
                if recorded {
                    Label("Logged. Lunches are in the fridge; extras are in the freezer.", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.success)
                } else {
                    Button {
                        kitchen.recordBatchCook(batch)
                        recorded = true
                    } label: {
                        Label("Done the batch cook", systemImage: "checkmark")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Palette.fresh, fill: Palette.fresh.opacity(0.14)))
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
        let total = kitchen.shopping.count
        let ticked = kitchen.shopping.filter(\.ticked).count
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                ZStack {
                    RingGauge(progress: total == 0 ? 0 : Double(ticked) / Double(total), tint: Palette.kitchen, lineWidth: 9)
                    VStack(spacing: 0) {
                        Text("\(ticked)")
                            .font(.display(22))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                        Text("of \(total)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(total - ticked == 1 ? "1 thing to buy" : "\(total - ticked) things to buy")
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    Text("≈ \(kitchen.listEstimate.formatted()) at Aldi")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                    Text("Co-op for top-ups")
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .heroCard(tint: Palette.kitchen, symbol: "cart.fill")

            HStack(spacing: Spacing.s) {
                Button {
                    kitchen.generateShoppingList()
                } label: {
                    Label("Build from meals", systemImage: "wand.and.stars")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Palette.kitchen, fill: Palette.kitchen.opacity(0.14)))
                Button {
                    kitchen.clearTicked()
                } label: {
                    Label("Clear ticked", systemImage: "checkmark.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            if let warning = kitchen.budget.warning(forList: kitchen.listEstimate) {
                NoticeBanner(symbol: "sterlingsign.circle", title: "Over the £400 ceiling", message: warning)
            }
            AddField(placeholder: "Add something", text: $newItem, add: add)

            if kitchen.shopping.isEmpty {
                VStack(spacing: Spacing.s) {
                    IconTile(symbol: "cart", tint: Palette.kitchen, size: 52)
                    Text("Nothing on the list")
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Build it from this week's meals, or add things as you run out.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.l)
                .surface()
            } else {
                ForEach(departments) { department in
                    DepartmentCard(department: department, items: items(in: department))
                }
                Footnote("Prices are typical, not live. Things marked \"check first\" might already be in.")
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
        let left = items.filter { !$0.ticked }.count
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack {
                Text(department.title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                Text(left == 0 ? "Done" : "\(left) left")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(left == 0 ? Palette.success : Palette.textTertiary)
            }
            .padding(.bottom, Spacing.xxs)
            ForEach(items.indices, id: \.self) { index in
                ShoppingRow(item: items[index]) { kitchen.toggle(items[index]) }
                if index < items.count - 1 { RowDivider(inset: 40) }
            }
        }
        .surface()
    }
}

private struct ShoppingRow: View {
    let item: ShoppingItem
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.s) {
                ZStack {
                    Circle()
                        .strokeBorder(item.ticked ? Palette.kitchen : Palette.textTertiary, lineWidth: 2)
                    if item.ticked {
                        Circle().fill(Palette.kitchen)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Palette.onAccent)
                    }
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body)
                        .foregroundStyle(item.ticked ? Palette.textTertiary : Palette.textPrimary)
                        .strikethrough(item.ticked, color: Palette.textTertiary)
                    if !item.quantityText.isEmpty || item.checkFirst {
                        Text(item.checkFirst ? "\(item.quantityText) · check first" : item.quantityText)
                            .font(.caption)
                            .foregroundStyle(item.checkFirst ? Palette.warning : Palette.textTertiary)
                    }
                }
                Spacer()
                if let pence = item.estimatePence {
                    Text(Pence(pence).formatted())
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: item.ticked)
        .sensoryFeedback(.impact(weight: .light), trigger: item.ticked)
        .accessibilityLabel("\(item.name), \(item.ticked ? "in the trolley" : "to buy")")
    }
}

// MARK: - Inventory

struct InventorySection: View {
    @Environment(KitchenModel.self) private var kitchen
    @State private var newItem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            FreezerCard()
            AddField(placeholder: "Tell me what's in, e.g. eggs", text: $newItem, tint: Palette.fresh, add: add)
            ForEach(locations, id: \.self) { location in
                let rows = items(at: location)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    CardHeader(title: location.title, symbol: symbol(location), tint: tint(location),
                               subtitle: rows.count == 1 ? "1 item" : "\(rows.count) items")
                    ForEach(rows.indices, id: \.self) { index in
                        InventoryRow(item: rows[index])
                        if index < rows.count - 1 { RowDivider(inset: 0) }
                    }
                }
                .surface()
            }
            Footnote("These are estimates from receipts, your list and what you tell me. A receipt only says something was bought, not that it's still there.")
        }
    }

    private var stock: [InventoryItem] { kitchen.inventory.filter { !$0.key.hasPrefix("meal:") } }

    private var locations: [StorageLocation] {
        StorageLocation.allCases.filter { location in stock.contains { $0.location == location } }
    }

    private func items(at location: StorageLocation) -> [InventoryItem] {
        stock.filter { $0.location == location }
    }

    private func symbol(_ location: StorageLocation) -> String {
        switch location {
        case .fridge: "refrigerator.fill"
        case .freezer: "snowflake"
        case .cupboard: "cabinet.fill"
        case .bathroom: "shower.fill"
        case .underSink: "spray.sparkle.fill"
        }
    }

    private func tint(_ location: StorageLocation) -> Color {
        switch location {
        case .fridge: Palette.fresh
        case .freezer: Palette.frost
        case .cupboard: Palette.kitchen
        case .bathroom, .underSink: Palette.rehab
        }
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
        let color = tint(presence)
        HStack(spacing: Spacing.s) {
            Text(item.name)
                .font(.body)
                .foregroundStyle(presence <= .probablyNot ? Palette.textTertiary : Palette.textPrimary)
            Spacer()
            Chip(text: presence.title, tint: color, fill: color.opacity(0.14))
            Menu {
                Button("It's in", systemImage: "checkmark") { kitchen.confirm(item.name, portions: nil) }
                Button("Run out", systemImage: "xmark") { kitchen.markOut(item.name) }
                Button("Add to the list", systemImage: "cart") { kitchen.addToShopping(item.name) }
                Button("Stop tracking", systemImage: "trash", role: .destructive) { kitchen.remove(item) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(item.name)")
        }
        .frame(minHeight: 48)
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
        let portions = meals.reduce(0) { $0 + $1.portions }
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Freezer")
                        .font(.headline)
                        .foregroundStyle(Palette.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(portions)")
                            .font(.display(40))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                        Text(portions == 1 ? "portion" : "portions")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer()
                IconTile(symbol: "snowflake", tint: Palette.frost, size: 44)
            }
            if meals.isEmpty {
                Text("None yet. Freezable dinners add their spare portions when you mark them eaten, and the batch cook adds more.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(meals.indices, id: \.self) { index in
                        FreezerMealRow(meal: meals[index])
                        if index < meals.count - 1 { RowDivider(inset: 0) }
                    }
                }
                .padding(.horizontal, Spacing.s)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }
            if meals.count < 2 {
                Footnote("Aim for two or three favourites in here for difficult days.")
            }
        }
        .heroCard(tint: Palette.frost)
    }
}

private struct FreezerMealRow: View {
    @Environment(KitchenModel.self) private var kitchen
    let meal: FreezerMeal

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(meal.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.xs)
            Button {
                kitchen.confirm(meal.title, portions: max(0, meal.portions - 1))
            } label: {
                RoundIconLabel(symbol: "minus", size: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("One fewer portion of \(meal.title)")
            Text("\(meal.portions)")
                .font(.display(20))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: 26)
                .contentTransition(.numericText())
            Button {
                kitchen.confirm(meal.title, portions: min(20, meal.portions + 1))
            } label: {
                RoundIconLabel(symbol: "plus", size: 32, tint: Palette.onAccent, fill: Palette.frost)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("One more portion of \(meal.title)")
        }
        .frame(minHeight: 52)
    }
}
