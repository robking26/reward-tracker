import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library

struct RecipeLibrarySection: View {
    @Environment(KitchenModel.self) private var kitchen
    @State private var importing = false
    @State private var filter: RecipeFilter = .all

    private let columns = [GridItem(.flexible(), spacing: Spacing.s), GridItem(.flexible(), spacing: Spacing.s)]

    var body: some View {
        let recipes = kitchen.activeRecipes.filter { filter.includes($0) }
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(RecipeFilter.allCases) { option in
                            FilterChip(title: option.title, selected: option == filter) {
                                withAnimation(.snappy) { filter = option }
                            }
                        }
                    }
                }
                .scrollClipDisabled()
                Button {
                    importing = true
                } label: {
                    RoundIconLabel(symbol: "plus", size: 40, tint: Palette.onAccent, fill: Palette.kitchen)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a recipe")
            }
            if recipes.isEmpty {
                Text("No recipes here yet.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.s) {
                    ForEach(recipes, id: \.id) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            RecipeTile(recipe: recipe)
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
            }
            Footnote("Nutrition is estimated from typical UK values per portion. Imported recipes are kept for your own use.")
        }
        .sheet(isPresented: $importing) {
            RecipeImportView()
                .presentationBackground(Palette.background)
        }
    }
}

enum RecipeFilter: String, CaseIterable, Identifiable {
    case all, favourites, dinner, lunch, freezable, quick

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .favourites: "Favourites"
        case .dinner: "Dinners"
        case .lunch: "Lunches"
        case .freezable: "Freezes well"
        case .quick: "Under 30 min"
        }
    }

    func includes(_ recipe: Recipe) -> Bool {
        switch self {
        case .all: true
        case .favourites: recipe.favourite
        case .dinner: recipe.role.suitsDinner
        case .lunch: recipe.role.suitsLunch
        case .freezable: recipe.freezable
        case .quick: recipe.prepMinutes + recipe.cookMinutes <= 30
        }
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    var tint: Color = Palette.kitchen
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Palette.onAccent : Palette.textSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(selected ? tint : Palette.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A recipe card: gradient artwork, title and the two numbers that matter.
struct RecipeTile: View {
    let recipe: Recipe

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                DishArtwork(title: recipe.title, symbol: MealStyle.symbol(role: recipe.role, slowCooker: recipe.usesSlowCooker),
                            height: 104)
                if recipe.favourite {
                    Image(systemName: "star.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.kitchen)
                        .frame(width: 28, height: 28)
                        .background(Palette.background.opacity(0.7), in: Circle())
                        .padding(Spacing.xs)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(recipe.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                if let excluded = recipe.excludedIngredient {
                    Text("Contains \(excluded)")
                        .font(.caption)
                        .foregroundStyle(Palette.warning)
                        .lineLimit(1)
                } else {
                    HStack(spacing: Spacing.xs) {
                        Label("\(recipe.prepMinutes + recipe.cookMinutes)′", systemImage: "clock")
                        Label("\(Int(recipe.protein.rounded()))g", systemImage: "bolt.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
                    .labelStyle(CompactLabelStyle())
                }
            }
            .padding(Spacing.s)
        }
        .background(Palette.surface)
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityHint("\(recipe.prepMinutes + recipe.cookMinutes) minutes, \(Int(recipe.protein.rounded())) grams of protein")
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.caption2.weight(.bold))
            configuration.title
        }
    }
}

// MARK: - Detail

struct RecipeDetailView: View {
    @Environment(KitchenModel.self) private var kitchen
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State private var pendingTweak: MacroTweak?
    @State private var correcting = false

    var body: some View {
        let tweaks = MacroTweaks.suggest(recipe.ingredients, servings: recipe.servings)
        let unmatched = NutritionEstimator.estimate(recipe.ingredients, servings: recipe.servings).unmatched
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                DishArtwork(title: recipe.title, symbol: MealStyle.symbol(role: recipe.role, slowCooker: recipe.usesSlowCooker),
                            height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Radius2.hero, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(recipe.title)
                        .font(.display(30))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    ChipFlow().callAsFunction {
                        Chip(text: recipe.role.title, symbol: "fork.knife")
                        Chip(text: "Serves \(recipe.servings)", symbol: "person.2.fill")
                        Chip(text: "\(recipe.prepMinutes + recipe.cookMinutes) min", symbol: "clock.fill")
                        Chip(text: "\(recipe.washUpMinutes) min wash-up", symbol: "drop.fill")
                        if recipe.freezable {
                            Chip(text: "Freezes well", symbol: "snowflake", tint: Palette.frost, fill: Palette.frost.opacity(0.14))
                        }
                        if recipe.usesSlowCooker {
                            Chip(text: "Slow cooker", symbol: "flame.fill", tint: Palette.kitchen, fill: Palette.kitchen.opacity(0.14))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        Text("Per portion")
                            .font(.headline)
                            .foregroundStyle(Palette.textPrimary)
                        Spacer()
                        Text(recipe.confidence.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    HStack(spacing: Spacing.xs) {
                        MacroTile(value: Int(recipe.kcal.rounded()), unit: "kcal", tint: Palette.kitchen)
                        MacroTile(value: Int(recipe.protein.rounded()), unit: "protein", tint: Palette.accent)
                        MacroTile(value: Int(recipe.carbs.rounded()), unit: "carbs", tint: Palette.frost)
                        MacroTile(value: Int(recipe.fat.rounded()), unit: "fat", tint: Palette.rose)
                    }
                    if !unmatched.isEmpty && recipe.confidence != .confirmed {
                        Footnote("Not counted: \(unmatched.joined(separator: ", ")).")
                    }
                    Button("Correct these numbers") { correcting = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.kitchen)
                }

                if !tweaks.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        CardHeader(title: "Better macros, same dish", symbol: "wand.and.stars", tint: Palette.accent,
                                   subtitle: "Anything that changes the flavour asks first")
                        ForEach(tweaks) { tweak in
                            Button {
                                if tweak.changesFlavour { pendingTweak = tweak } else { kitchen.apply(tweak, to: recipe) }
                            } label: {
                                TileRow(title: tweak.title, subtitle: tweak.detail, symbol: "arrow.triangle.swap", tint: Palette.accent) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Palette.accent)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .surface()
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    CardHeader(title: "Ingredients", symbol: "basket.fill", tint: Palette.fresh,
                               subtitle: "\(recipe.ingredients.count) items")
                    ForEach(recipe.ingredients) { ingredient in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Circle().fill(Palette.fresh).frame(width: 6, height: 6)
                            Text(ingredient.original)
                                .font(.subheadline)
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .surface()

                VStack(alignment: .leading, spacing: Spacing.m) {
                    CardHeader(title: "Method", symbol: "list.number", tint: Palette.kitchen,
                               subtitle: "\(recipe.steps.count) steps")
                    ForEach(recipe.steps.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: Spacing.s) {
                            Text("\(index + 1)")
                                .font(.footnote.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.onAccent)
                                .frame(width: 26, height: 26)
                                .background(Palette.kitchen, in: Circle())
                            Text(recipe.steps[index])
                                .font(.subheadline)
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .surface()

                VStack(spacing: 0) {
                    Toggle("Freezes well", isOn: Binding(get: { recipe.freezable }, set: { recipe.freezable = $0; kitchen.save(); kitchen.reload() }))
                        .frame(minHeight: 48)
                    RowDivider(inset: 0)
                    Toggle("Fakeaway", isOn: Binding(get: { recipe.isFakeaway }, set: { recipe.isFakeaway = $0; kitchen.save(); kitchen.reload() }))
                        .frame(minHeight: 48)
                    RowDivider(inset: 0)
                    LabeledContent("Use for") {
                        Picker("Use for", selection: Binding(get: { recipe.role }, set: { recipe.role = $0; kitchen.save(); kitchen.reload() })) {
                            ForEach(MealRole.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    .frame(minHeight: 48)
                }
                .tint(Palette.kitchen)
                .foregroundStyle(Palette.textPrimary)
                .surface(padding: Spacing.m)

                Button(role: .destructive) {
                    kitchen.archive(recipe)
                    dismiss()
                } label: {
                    Label("Remove from the library", systemImage: "trash")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Palette.error))
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    kitchen.toggleFavourite(recipe)
                } label: {
                    Image(systemName: recipe.favourite ? "star.fill" : "star")
                        .foregroundStyle(Palette.kitchen)
                }
                .accessibilityLabel(recipe.favourite ? "Remove from favourites" : "Add to favourites")
            }
        }
        .confirmationDialog("This changes the flavour a little", isPresented: Binding(get: { pendingTweak != nil }, set: { if !$0 { pendingTweak = nil } }),
                            titleVisibility: .visible, presenting: pendingTweak) { tweak in
            Button("Change it") { kitchen.apply(tweak, to: recipe) }
            Button("Keep it as it is", role: .cancel) {}
        } message: { tweak in
            Text(tweak.detail)
        }
        .sheet(isPresented: $correcting) {
            NutritionCorrectionView(recipe: recipe)
                .presentationDetents([.medium])
                .presentationBackground(Palette.background)
        }
    }
}

/// One macro: a big rounded number over its name, in a tinted tile.
private struct MacroTile: View {
    let value: Int
    let unit: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
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

struct NutritionCorrectionView: View {
    @Environment(KitchenModel.self) private var kitchen
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State private var kcal = ""
    @State private var protein = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Calories per portion", text: $kcal).keyboardType(.numberPad)
                    TextField("Protein per portion (g)", text: $protein).keyboardType(.decimalPad)
                } footer: {
                    Text("Use the figures from the pack or the recipe if you have them.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Your figures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        kitchen.correctNutrition(recipe, kcal: Double(kcal) ?? recipe.kcal,
                                                 protein: Double(protein.replacingOccurrences(of: ",", with: ".")) ?? recipe.protein)
                        dismiss()
                    }
                }
            }
            .onAppear {
                kcal = String(Int(recipe.kcal.rounded()))
                protein = String(Int(recipe.protein.rounded()))
            }
        }
    }
}

// MARK: - Import (F7)

struct RecipeImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var source: RecipeSource = .manual
    @State private var draft: RecipeDraft?
    @State private var scanning = false
    @State private var choosingFile = false
    @State private var photo: PhotosPickerItem?
    @State private var reading = false

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    RecipeDraftEditor(draft: draft, source: source) { dismiss() }
                } else {
                    chooser
                }
            }
            .navigationTitle(draft == nil ? "Add a recipe" : "Check it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                read(.camera) { await TextRecognition.text(in: images) }
            } onCancel: {
                scanning = false
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.pdf, .image, .plainText]) { result in
            guard case .success(let url) = result else { return }
            read(url.pathExtension.lowercased() == "pdf" ? .pdf : .file) { await TextRecognition.text(inFile: url) }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            read(.screenshot) {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return "" }
                return await TextRecognition.text(in: image)
            }
        }
    }

    private var chooser: some View {
        Form {
            Section {
                if DocumentScanner.isAvailable {
                    Button("Scan with the camera", systemImage: "camera") { scanning = true }
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Photo or screenshot", systemImage: "photo")
                }
                Button("PDF or file", systemImage: "doc") { choosingFile = true }
            } footer: {
                Text("Text is read on your iPhone. Nothing is uploaded.")
            }
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 180)
                Button("Read this") {
                    source = .manual
                    draft = RecipeParser.parse(text)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Or paste or type it")
            } footer: {
                Text("A title, an \"Ingredients\" list with amounts, then the method works best.")
            }
            if reading {
                Section { HStack { ProgressView(); Text("Reading…") } }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
    }

    private func read(_ kind: RecipeSource, _ work: @escaping () async -> String) {
        reading = true
        Task {
            let result = await work()
            reading = false
            source = kind
            if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = ""
            } else {
                draft = RecipeParser.parse(result)
            }
        }
    }
}

/// Lets the user correct what was read before it's saved (F7: corrections and uncertainty).
struct RecipeDraftEditor: View {
    @Environment(KitchenModel.self) private var kitchen
    let source: RecipeSource
    var onSaved: () -> Void
    @State private var title: String
    @State private var servings: Int
    @State private var role: MealRole = .dinner
    @State private var freezable = false
    @State private var fakeaway = false
    @State private var ingredientsText: String
    @State private var stepsText: String
    @State private var prep: Int
    @State private var cook: Int

    init(draft: RecipeDraft, source: RecipeSource, onSaved: @escaping () -> Void) {
        self.source = source
        self.onSaved = onSaved
        _title = State(initialValue: draft.title)
        _servings = State(initialValue: draft.servings)
        _ingredientsText = State(initialValue: draft.ingredients.map(\.original).joined(separator: "\n"))
        _stepsText = State(initialValue: draft.steps.joined(separator: "\n"))
        _prep = State(initialValue: draft.prepMinutes ?? 15)
        _cook = State(initialValue: draft.cookMinutes ?? 25)
    }

    var body: some View {
        let current = draft
        Form {
            Section {
                TextField("Name", text: $title)
                Stepper("Serves \(servings)", value: $servings, in: 1...12)
                Picker("Use for", selection: $role) {
                    ForEach(MealRole.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Freezes well", isOn: $freezable)
                Toggle("Fakeaway", isOn: $fakeaway)
                Stepper("Prep \(prep) min", value: $prep, in: 0...180, step: 5)
                Stepper("Cook \(cook) min", value: $cook, in: 0...600, step: 5)
            }
            Section {
                Text(current.nutrition.summary)
                Text("Washing up about \(current.washUpMinutes) min\(current.isOnePan ? ", one pan" : "")")
                if !current.nutrition.unmatched.isEmpty {
                    Text("Not counted: \(current.nutrition.unmatched.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Palette.warning)
                }
                if !current.excluded.isEmpty {
                    Text("Contains \(current.excluded.joined(separator: " and ")). It'll be saved but never suggested.")
                        .font(.caption)
                        .foregroundStyle(Palette.warning)
                }
            } header: {
                Text("Per portion (estimate)")
            }
            Section {
                TextEditor(text: $ingredientsText).frame(minHeight: 160)
            } header: {
                Text("Ingredients, one per line")
            } footer: {
                Text("Fix anything misread; amounts like \"400 g\" or \"2 tbsp\" make the estimate closer.")
            }
            Section("Method, one step per line") {
                TextEditor(text: $stepsText).frame(minHeight: 160)
            }
            Section {
                Button("Save recipe") {
                    kitchen.save(current, role: role, source: source, freezable: freezable, fakeaway: fakeaway)
                    onSaved()
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("Kept on this iPhone for your own use.")
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
    }

    private var draft: RecipeDraft {
        let ingredients = ingredientsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map(IngredientParser.parse)
        let steps = stepsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let washUp = WashUpEstimator.estimate(steps.joined(separator: " "))
        let everything = ([title] + ingredients.map(\.original)).joined(separator: " ").lowercased()
        return RecipeDraft(title: title.trimmingCharacters(in: .whitespaces), servings: servings, servingsWasRead: true,
                           ingredients: ingredients, steps: steps, prepMinutes: prep, cookMinutes: cook,
                           washUpMinutes: washUp.minutes, cookware: washUp.cookware,
                           excluded: FoodExclusions.words.filter { everything.contains($0) },
                           nutrition: NutritionEstimator.estimate(ingredients, servings: servings))
    }
}
