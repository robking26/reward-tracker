import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library

struct RecipeLibrarySection: View {
    @Environment(KitchenModel.self) private var kitchen
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SmallActionButton(title: "Add a recipe", symbol: "plus") { importing = true }
            ForEach([MealRole.lunch, .dinner, .both, .breakfast]) { role in
                let recipes = kitchen.activeRecipes.filter { $0.role == role }
                if !recipes.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(role.title + "s")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                        ForEach(recipes, id: \.id) { recipe in
                            NavigationLink {
                                RecipeDetailView(recipe: recipe)
                            } label: {
                                RecipeRow(recipe: recipe)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .surface()
                }
            }
            Text("Nutrition is estimated from typical UK values and always shown as an estimate. Imported recipes are kept for your own use.")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $importing) {
            RecipeImportView()
                .presentationBackground(Palette.background)
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xxs) {
                    Text(recipe.title).foregroundStyle(Palette.textPrimary)
                    if recipe.favourite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(Palette.accent)
                    }
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(recipe.excludedIngredient == nil ? Palette.textTertiary : Palette.warning)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var summary: String {
        if let excluded = recipe.excludedIngredient { return "Contains \(excluded), so it's never suggested" }
        return "≈ \(Int(recipe.kcal.rounded())) kcal · \(Int(recipe.protein.rounded())) g protein · \(recipe.prepMinutes + recipe.cookMinutes) min"
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
        List {
            Section {
                LabeledContent("Per portion", value: "≈ \(Int(recipe.kcal.rounded())) kcal")
                LabeledContent("Protein", value: "≈ \(Int(recipe.protein.rounded())) g")
                LabeledContent("Carbs · fat", value: "≈ \(Int(recipe.carbs.rounded())) g · \(Int(recipe.fat.rounded())) g")
                LabeledContent("How sure", value: recipe.confidence.title)
                Button("Correct these numbers") { correcting = true }
            } header: {
                Text("Nutrition (estimate)")
            } footer: {
                let unmatched = NutritionEstimator.estimate(recipe.ingredients, servings: recipe.servings).unmatched
                if !unmatched.isEmpty && recipe.confidence != .confirmed {
                    Text("Not counted: \(unmatched.joined(separator: ", ")).")
                }
            }
            Section("Time") {
                LabeledContent("Prep", value: "\(recipe.prepMinutes) min")
                LabeledContent("Cook", value: "\(recipe.cookMinutes) min")
                LabeledContent("Washing up", value: "about \(recipe.washUpMinutes) min")
                LabeledContent("Serves", value: "\(recipe.servings)")
            }
            if !tweaks.isEmpty {
                Section {
                    ForEach(tweaks) { tweak in
                        Button {
                            if tweak.changesFlavour { pendingTweak = tweak } else { kitchen.apply(tweak, to: recipe) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tweak.title).foregroundStyle(Palette.textPrimary)
                                Text(tweak.detail).font(.caption).foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                } header: {
                    Text("Better macros, same dish")
                } footer: {
                    Text("Anything that changes the flavour asks first.")
                }
            }
            Section("Ingredients") {
                ForEach(recipe.ingredients) { ingredient in
                    Text(ingredient.original)
                }
            }
            Section("Method") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { item in
                    Text("\(item.offset + 1). \(item.element)")
                }
            }
            Section {
                Toggle("Freezes well", isOn: Binding(get: { recipe.freezable }, set: { recipe.freezable = $0; kitchen.save(); kitchen.reload() }))
                Toggle("Fakeaway", isOn: Binding(get: { recipe.isFakeaway }, set: { recipe.isFakeaway = $0; kitchen.save(); kitchen.reload() }))
                Picker("Use for", selection: Binding(get: { recipe.role }, set: { recipe.role = $0; kitchen.save(); kitchen.reload() })) {
                    ForEach(MealRole.allCases) { Text($0.title).tag($0) }
                }
                Button("Remove from the library", role: .destructive) {
                    kitchen.archive(recipe)
                    dismiss()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    kitchen.toggleFavourite(recipe)
                } label: {
                    Image(systemName: recipe.favourite ? "star.fill" : "star")
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
