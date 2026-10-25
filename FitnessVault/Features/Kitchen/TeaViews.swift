import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Kitchen section

/// Teas: this week's plan, planning the next one by swiping, and the recipe bank.
struct TeasSection: View {
    @Environment(TeaModel.self) private var teas
    @State private var planning = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let week = teas.currentWeek, !week.meals.isEmpty {
                ThisWeeksTeas(week: week)
            } else {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    CardHeader(title: "This week's teas", symbol: "fork.knife", tint: Palette.kitchen,
                               subtitle: "Pick together on Saturday morning")
                    Text(teas.onTarget.isEmpty
                         ? "Add recipes from your books first; then you each swipe and the matches fill the week."
                         : "Say who's eating each night, then you each swipe through \(teas.onTarget.count) recipes. Matches fill the week; Monday to Thursday get quick ones (30 minutes or less).")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .surface()
            }

            Button {
                if teas.currentWeek == nil { teas.startWeek() }
                planning = true
            } label: {
                Label(teas.currentWeek == nil ? "Plan this week's teas" : "Carry on planning", systemImage: "hand.draw.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Palette.kitchen))
            .disabled(teas.onTarget.isEmpty)

            RecipeBankCard()
        }
        .sheet(isPresented: $planning) {
            TeaPlanFlow()
                .presentationBackground(Palette.background)
        }
    }
}

private struct ThisWeeksTeas: View {
    @Environment(TeaModel.self) private var teas
    let week: TeaWeek

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            CardHeader(title: "This week's teas", symbol: "fork.knife", tint: Palette.kitchen,
                       subtitle: "\(teas.matches.count) you both liked")
            ForEach(teas.nights, id: \.self) { night in
                let diner = teas.diner(on: night)
                if diner != .notCooking {
                    NightRow(night: night, diner: diner, recipe: teas.recipe(week.meals[night.description]))
                }
            }
        }
        .surface()
    }
}

private struct NightRow: View {
    @Environment(TeaModel.self) private var teas
    let night: DayKey
    let diner: TeaDiner
    let recipe: TeaRecipe?

    var body: some View {
        let date = night.startDate(calendar: teas.calendar)
        let content = HStack(spacing: Spacing.s) {
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.kitchen)
                Text(date.formatted(.dateTime.day()))
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe?.title ?? "Nothing matched yet")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(recipe == nil ? Palette.textTertiary : Palette.textPrimary)
                HStack(spacing: 6) {
                    Label(diner.title, systemImage: diner.symbol)
                    if TeaPlanner.needsQuick(night, calendar: teas.calendar) {
                        Label("Quick", systemImage: "bolt.fill")
                    }
                    if let recipe {
                        Text("\(Int(recipe.portionKcal)) kcal · \(Int(recipe.portionProtein)) g protein")
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 52)
        if let recipe {
            NavigationLink { TeaRecipeDetail(recipe: recipe) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - Planning

/// Who's eating which night, Rob's swipes, Becky's swipes, then the plan.
struct TeaPlanFlow: View {
    @Environment(TeaModel.self) private var teas
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .nights

    enum Step { case nights, swipe(TeaSwiper), handover, plan }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .nights: nightsStep
                case .swipe(let swiper): SwipeDeck(swiper: swiper) { finished(swiper) }
                case .handover: handover
                case .plan: planStep
                }
            }
            .pageBackground()
            .navigationTitle("Teas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private var nightsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Who's eating a home-cooked tea?")
                    .font(.display(26))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(teas.nights, id: \.self) { night in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(night.startDate(calendar: teas.calendar).formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Palette.textPrimary)
                                if TeaPlanner.needsQuick(night, calendar: teas.calendar) {
                                    Label("Quick meals, 30 min or less", systemImage: "bolt.fill")
                                        .font(.caption)
                                        .foregroundStyle(Palette.kitchen)
                                }
                            }
                            Spacer()
                            Picker("Who", selection: Binding(get: { teas.diner(on: night) },
                                                             set: { teas.setDiner($0, on: night) })) {
                                ForEach(TeaDiner.allCases) { Text($0.title).tag($0) }
                            }
                            .tint(Palette.kitchen)
                        }
                        .frame(minHeight: 56)
                        RowDivider(inset: 0)
                    }
                }
                .surface()
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                Button("Start swiping") { step = teas.needs(.rob) ? .swipe(.rob) : (teas.needs(.becky) ? .swipe(.becky) : .plan) }
                    .buttonStyle(PrimaryButtonStyle(tint: Palette.kitchen))
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
    }

    private var summary: String {
        let diners = teas.nights.map { teas.diner(on: $0) }
        let together = diners.filter { $0 == .together }.count
        let rob = diners.filter { $0 == .rob }.count
        let becky = diners.filter { $0 == .becky }.count
        return "\(together) together, \(rob) just you, \(becky) just Becky. Every meal is 600–700 kcal with 50 g+ protein."
    }

    private var handover: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Palette.rose)
            Text("Pass the phone to Becky")
                .font(.display(28))
                .foregroundStyle(Palette.textPrimary)
            Text("Rob's picks stay hidden. Matches show at the end.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Button("Becky's turn") { step = .swipe(.becky) }
                .buttonStyle(PrimaryButtonStyle(tint: Palette.rose))
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity)
    }

    private var planStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Your week")
                    .font(.display(28))
                    .foregroundStyle(Palette.textPrimary)
                Text("\(teas.matches.count) recipes you both liked.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                VStack(spacing: 0) {
                    ForEach(teas.nights, id: \.self) { night in
                        let diner = teas.diner(on: night)
                        if diner != .notCooking {
                            HStack {
                                NightRow(night: night, diner: diner, recipe: teas.recipe(teas.week?.meals[night.description]))
                                Menu {
                                    ForEach(teas.options(for: night)) { option in
                                        Button(option.title) { teas.setMeal(option, on: night) }
                                    }
                                } label: {
                                    RoundIconLabel(symbol: "arrow.triangle.2.circlepath", size: 34)
                                }
                                .accessibilityLabel("Change")
                            }
                            RowDivider(inset: 0)
                        }
                    }
                }
                .surface()
                HStack(spacing: Spacing.s) {
                    Button("Swipe again") {
                        teas.resetSwipes()
                        step = .nights
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Done") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle(tint: Palette.kitchen))
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .onAppear { teas.makePlan() }
    }

    private func finished(_ swiper: TeaSwiper) {
        withAnimation {
            if swiper == .rob && teas.needs(.becky) {
                step = .handover
            } else {
                step = .plan
            }
        }
    }
}

/// One card at a time: right for yes, left for no. Buttons do the same.
private struct SwipeDeck: View {
    @Environment(TeaModel.self) private var teas
    let swiper: TeaSwiper
    let onFinished: () -> Void
    @State private var drag: CGSize = .zero

    var body: some View {
        let deck = teas.deck(for: swiper)
        VStack(spacing: Spacing.m) {
            HStack {
                Text("\(swiper.name)'s turn")
                    .font(.headline)
                    .foregroundStyle(swiper == .rob ? Palette.kitchen : Palette.rose)
                Spacer()
                Text("\(deck.count) left")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
            }
            ZStack {
                if deck.isEmpty {
                    VStack(spacing: Spacing.s) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Palette.success)
                        Text("That's all of them")
                            .font(.headline)
                            .foregroundStyle(Palette.textPrimary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                let top = Array(deck.prefix(2))
                ForEach(top.reversed()) { recipe in
                    let isTop = recipe.id == top.first?.id
                    TeaCard(recipe: recipe, verdict: isTop ? drag.width : 0)
                        .offset(isTop ? drag : .zero)
                        .rotationEffect(.degrees(isTop ? Double(drag.width / 18) : 0))
                        .scaleEffect(isTop ? 1 : 0.96)
                        .gesture(dragGesture(recipe))
                        .allowsHitTesting(isTop)
                }
            }
            .frame(maxHeight: .infinity)
            if let top = deck.first {
                HStack(spacing: Spacing.xl) {
                    Button { decide(top, liked: false) } label: {
                        RoundIconLabel(symbol: "xmark", size: 64, tint: Palette.textSecondary)
                    }
                    .accessibilityLabel("Not this one")
                    Button { decide(top, liked: true) } label: {
                        RoundIconLabel(symbol: "heart.fill", size: 64, tint: Palette.onAccent, fill: Palette.kitchen)
                    }
                    .accessibilityLabel("Yes please")
                }
            } else {
                Button("Next", action: onFinished)
                    .buttonStyle(PrimaryButtonStyle(tint: Palette.kitchen))
            }
        }
        .padding(.horizontal, Spacing.page)
        .padding(.bottom, Spacing.l)
    }

    private func dragGesture(_ recipe: TeaRecipe) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > 110 {
                    decide(recipe, liked: value.translation.width > 0)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { drag = .zero }
                }
            }
    }

    private func decide(_ recipe: TeaRecipe, liked: Bool) {
        withAnimation(.easeOut(duration: 0.22)) { drag = CGSize(width: liked ? 500 : -500, height: 40) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            teas.swipe(recipe, liked: liked, by: swiper)
            drag = .zero
        }
    }
}

private struct TeaCard: View {
    let recipe: TeaRecipe
    /// How far it's being dragged: right fades in "Yes", left "No".
    let verdict: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Chip(text: PlannerFormat.minutes(recipe.totalMinutes), symbol: recipe.isQuick ? "bolt.fill" : "timer",
                     tint: recipe.isQuick ? Palette.kitchen : Palette.textSecondary)
                if let boost = recipe.portion?.boost {
                    Chip(text: "+\(Int(recipe.portion?.boostGrams ?? 0))g \(boost.name)", symbol: "plus.circle.fill",
                         tint: Palette.kitchen, fill: Palette.kitchen.opacity(0.14))
                } else if let scale = recipe.portion?.scale, abs(scale - 1) > 0.001 {
                    Chip(text: "×\(TeaFormat.scale(scale)) portion", symbol: "scalemass", tint: Palette.kitchen,
                         fill: Palette.kitchen.opacity(0.14))
                }
                Spacer()
            }
            Spacer(minLength: 0)
            Text(recipe.title)
                .font(.display(30))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let source = recipe.source {
                Text(source)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            HStack(spacing: Spacing.s) {
                MacroPill(value: recipe.portionKcal, unit: "kcal")
                MacroPill(value: recipe.portionProtein, unit: "g protein")
                MacroPill(value: recipe.portionCarbs, unit: "g carbs")
                MacroPill(value: recipe.portionFat, unit: "g fat")
            }
            if !recipe.ingredients.isEmpty {
                Text(recipe.ingredients.prefix(5).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(3)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: 460, alignment: .leading)
        .heroCard(tint: Palette.kitchen, symbol: "fork.knife")
        .overlay(alignment: .topTrailing) {
            Text("YES")
                .font(.headline.weight(.heavy))
                .foregroundStyle(Palette.success)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(Palette.success, lineWidth: 2))
                .rotationEffect(.degrees(12))
                .padding(Spacing.l)
                .opacity(Double(max(0, verdict) / 110))
        }
        .overlay(alignment: .topLeading) {
            Text("NO")
                .font(.headline.weight(.heavy))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(Palette.textSecondary, lineWidth: 2))
                .rotationEffect(.degrees(-12))
                .padding(Spacing.l)
                .opacity(Double(max(0, -verdict) / 110))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MacroPill: View {
    let value: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(Int(value.rounded()))")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Recipe

struct TeaRecipeDetail: View {
    @Environment(TeaModel.self) private var teas
    let recipe: TeaRecipe

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(recipe.title)
                        .font(.display(28))
                        .foregroundStyle(Palette.textPrimary)
                    if let source = recipe.source {
                        Text(source)
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    ChipFlow().callAsFunction {
                        Chip(text: "Prep \(current.prepMinutes) min", symbol: "clock")
                        Chip(text: "Cook \(current.cookMinutes) min", symbol: "flame")
                        if current.isQuick { Chip(text: "Quick: Monday to Thursday", symbol: "bolt.fill", tint: Palette.kitchen) }
                        Chip(text: "Serves \(recipe.servings)", symbol: "person.2")
                        if current.freezable { Chip(text: "Freezes", symbol: "snowflake", tint: Palette.frost) }
                        if !recipe.meetsTargets {
                            Chip(text: "Outside your targets", symbol: "exclamationmark.triangle", tint: Palette.warning)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(portionText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(recipe.meetsTargets ? Palette.kitchen : Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Spacing.s) {
                        MacroPill(value: recipe.portionKcal, unit: "kcal")
                        MacroPill(value: recipe.portionProtein, unit: "g protein")
                        MacroPill(value: recipe.portionCarbs, unit: "g carbs")
                        MacroPill(value: recipe.portionFat, unit: "g fat")
                    }
                    if let boost = recipe.portion?.boost {
                        Label(boost.how, systemImage: "plus.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .surface()
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Times are estimated from the method; correct them if they're off.")
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                    Stepper("Prep \(current.prepMinutes) min", value: Binding(
                        get: { current.prepMinutes },
                        set: { teas.setMinutes(prep: $0, cook: current.cookMinutes, for: current) }), in: 0...120, step: 5)
                    Stepper("Cook \(current.cookMinutes) min", value: Binding(
                        get: { current.cookMinutes },
                        set: { teas.setMinutes(prep: current.prepMinutes, cook: $0, for: current) }), in: 0...480, step: 5)
                    Toggle("Freezes", isOn: Binding(get: { current.freezable },
                                                    set: { teas.setFreezable($0, for: current) }))
                        .tint(Palette.frost)
                }
                .surface()
                if !recipe.ingredients.isEmpty {
                    SectionTitle(title: "Ingredients", detail: recipe.portionIngredients == recipe.ingredients ? nil : "For your portion")
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(recipe.portionIngredients, id: \.self) { line in
                            Text("• " + line)
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surface()
                }
                if !recipe.method.isEmpty {
                    SectionTitle(title: "Method")
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        ForEach(recipe.method.indices, id: \.self) { index in
                            HStack(alignment: .top, spacing: Spacing.s) {
                                Text("\(index + 1)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Palette.kitchen)
                                    .frame(width: 20)
                                Text(recipe.method[index])
                                    .foregroundStyle(Palette.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .surface()
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle("Recipe")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The live copy, so the times and freezes switch show what was saved.
    private var current: TeaRecipe { teas.recipe(recipe.id) ?? recipe }

    private var portionText: String {
        let printed = "\(Int(recipe.kcal)) kcal, \(Int(recipe.protein)) g protein as printed"
        guard let portion = recipe.portion else {
            return "As the book (\(printed)). It can't reach your targets, so it isn't offered."
        }
        let resized = abs(portion.scale - 1) > 0.001
        let share = "×\(TeaFormat.scale(portion.scale)) the book's portion"
        if let boost = portion.boost {
            return (resized ? share + " plus " : "The book's portion plus ") + "\(Int(portion.boostGrams))g \(boost.name) "
                + "(\(printed)) hits your targets. Amounts below are for your portion."
        }
        if !resized { return "As the book: on target." }
        return "\(share) (\(printed)) hits your targets. Gram and ml amounts below are scaled; for \(recipe.servings) people, scale the whole recipe."
    }
}

enum TeaFormat {
    static func scale(_ value: Double) -> String {
        let text = String(format: "%.2f", value)
        return text.hasSuffix("0") ? String(text.dropLast()) : text
    }
}

// MARK: - Recipe bank

private struct RecipeBankCard: View {
    @Environment(TeaModel.self) private var teas

    var body: some View {
        NavigationLink {
            RecipeBankView()
        } label: {
            HStack(spacing: Spacing.s) {
                IconTile(symbol: "books.vertical.fill", tint: Palette.kitchen, size: 44, filled: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recipe bank")
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    Text(teas.recipes.isEmpty ? "From your recipe books, via Claude"
                         : "\(teas.recipes.count) recipes · \(teas.onTarget.count) on target · \(teas.onTarget.filter(\.isQuick).count) quick")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .surface()
        }
        .buttonStyle(CardButtonStyle())
    }
}

struct RecipeBankView: View {
    @Environment(TeaModel.self) private var teas
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button {
                    importFrom(UIPasteboard.general.string.map { Data($0.utf8) })
                } label: {
                    Label("Paste recipes from Claude", systemImage: "doc.on.clipboard")
                }
                Button {
                    importing = true
                } label: {
                    Label("Import a file", systemImage: "square.and.arrow.down")
                }
                Button {
                    UIPasteboard.general.string = TeaPlanner.claudePrompt
                    message = "Prompt copied. Paste it into Claude with your photos or PDFs."
                } label: {
                    Label("Copy the prompt for Claude", systemImage: "text.quote")
                }
            } header: {
                Text("Add recipes")
            } footer: {
                Text(message ?? "Send Claude photos or PDFs from your recipe books with the prompt, then paste or import what it gives back. Each recipe's portion is resized, and topped up with lean protein where it's light, to land on 600–700 kcal with 50 g+ protein.")
            }

            Section("Recipes") {
                if teas.recipes.isEmpty {
                    Text("None yet")
                        .foregroundStyle(Palette.textTertiary)
                }
                ForEach(teas.recipes) { recipe in
                    NavigationLink {
                        TeaRecipeDetail(recipe: recipe)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.title)
                                .foregroundStyle(Palette.textPrimary)
                            Text(bankLine(recipe))
                                .font(.caption)
                                .foregroundStyle(recipe.meetsTargets ? Palette.textTertiary : Palette.warning)
                        }
                    }
                }
                .onDelete { offsets in
                    for recipe in offsets.map({ teas.recipes[$0] }) { teas.delete(recipe) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Recipe bank")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            importFrom(try? Data(contentsOf: url))
        }
    }

    private func bankLine(_ recipe: TeaRecipe) -> String {
        let quick = recipe.isQuick ? " · quick" : ""
        guard let portion = recipe.portion else {
            return "\(Int(recipe.kcal)) kcal · \(Int(recipe.protein)) g protein: can't reach your targets\(quick)"
        }
        let topUp = portion.boost.map { " + \(Int(portion.boostGrams))g \($0.name)" } ?? ""
        return "×\(TeaFormat.scale(portion.scale))\(topUp): \(Int(recipe.portionKcal)) kcal · \(Int(recipe.portionProtein)) g protein\(quick)"
    }

    private func importFrom(_ data: Data?) {
        guard let data else {
            message = "Nothing to import."
            return
        }
        do {
            let count = try teas.importRecipes(data)
            message = count == 1 ? "1 recipe added." : "\(count) recipes added."
        } catch {
            message = "That doesn't look like Claude's recipe list. Ask for JSON only, using the copied prompt."
        }
    }
}
