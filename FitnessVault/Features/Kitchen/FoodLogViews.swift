import SwiftUI
import VisionKit

// MARK: - Today

/// Today's food: the totals, then each meal. Planned meals (the cycle's breakfast and lunch Monday to Friday, and
/// tonight's tea) are one tap; a meal with nothing planned gets a placeholder to scan or add by hand. Extras have their
/// own card.
struct FoodTodaySection: View {
    @Environment(KitchenModel.self) private var kitchen
    @Environment(TeaModel.self) private var teas
    @State private var sheet: FoodSheet?

    var body: some View {
        let day = kitchen.today
        let nutrition = kitchen.nutrition(on: day)
        let logged = kitchen.entries(on: day)
        let weekday = kitchen.isCycleDay(day)
        VStack(alignment: .leading, spacing: Spacing.m) {
            DayTotalsCard(nutrition: nutrition, count: logged.count)

            if weekday {
                CycleTodayCard(slot: .breakfast, day: day)
                CycleTodayCard(slot: .lunch, day: day)
            } else {
                UnplannedMealCard(meal: .breakfast, reason: "Nothing planned at the weekend", logged: logged, sheet: $sheet)
                UnplannedMealCard(meal: .lunch, reason: "Nothing planned at the weekend", logged: logged, sheet: $sheet)
            }
            if let tea = teas.plannedTea(on: day) {
                TeaTodayCard(recipe: tea, day: day)
            } else {
                UnplannedMealCard(meal: .evening, reason: "No tea planned tonight", logged: logged, sheet: $sheet)
            }

            ExtrasCard(sheet: $sheet)

            if !logged.isEmpty {
                SectionTitle(title: "Logged today", detail: logged.count == 1 ? "1 item" : "\(logged.count) items")
                VStack(spacing: 0) {
                    ForEach(logged.indices, id: \.self) { index in
                        FoodEntryRow(entry: logged[index])
                        if index < logged.count - 1 { RowDivider() }
                    }
                }
                .surface()
            }
            Footnote("Barcodes are looked up on Open Food Facts, a free food database; only the barcode is sent. Nothing here affects your earnings.")
        }
        .sheet(item: $sheet) { item in
            NavigationStack {
                switch item {
                case .scan(let meal): ScanFlowView(meal: meal) { sheet = nil }
                case .manual(let meal): ManualFoodView(preset: meal) { sheet = nil }
                case .product(let product, let meal): ProductAmountView(product: product, preset: meal) { sheet = nil }
                }
            }
            .presentationBackground(Palette.background)
        }
    }
}

enum FoodSheet: Identifiable {
    /// The meal it's for, or nil to go by the time of day.
    case scan(FoodMeal?), manual(FoodMeal?), product(FoodProduct, FoodMeal?)

    var id: String {
        switch self {
        case .scan(let meal): "scan-\(meal?.rawValue ?? "")"
        case .manual(let meal): "manual-\(meal?.rawValue ?? "")"
        case .product(let product, let meal): "product-\(product.barcode)-\(meal?.rawValue ?? "")"
        }
    }
}

/// A meal with nothing planned: a placeholder to scan or add by hand, which shows what you logged once you have.
private struct UnplannedMealCard: View {
    let meal: FoodMeal
    let reason: String
    let logged: [FoodLogEntry]
    @Binding var sheet: FoodSheet?

    var body: some View {
        let mine = logged.filter { $0.meal == meal }
        let kcal = mine.reduce(0) { $0 + $1.macros.kcal }
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                IconTile(symbol: meal.symbol, tint: Palette.textTertiary, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.textTertiary)
                    Text(mine.isEmpty ? reason : mine.map(\.name).joined(separator: ", "))
                        .font(.headline)
                        .foregroundStyle(mine.isEmpty ? Palette.textSecondary : Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !mine.isEmpty {
                        Text("\(Int(kcal.rounded())) kcal")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: Spacing.s) {
                Button {
                    sheet = .scan(meal)
                } label: {
                    Label("Scan", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    sheet = .manual(meal)
                } label: {
                    Label("By hand", systemImage: "square.and.pencil")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.surface.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Palette.textTertiary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

/// Tonight's tea from the Teas plan, with one tap to log your portion.
private struct TeaTodayCard: View {
    @Environment(KitchenModel.self) private var kitchen
    let recipe: TeaRecipe
    let day: DayKey

    var body: some View {
        let logged = kitchen.hasLoggedPlanned(recipe.title, on: day)
        VStack(alignment: .leading, spacing: Spacing.s) {
            NavigationLink {
                TeaRecipeDetail(recipe: recipe)
            } label: {
                HStack(spacing: Spacing.s) {
                    IconTile(symbol: "frying.pan.fill", tint: Palette.rehab, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TEA")
                            .font(.caption.weight(.bold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.rehab)
                        Text(recipe.title)
                            .font(.headline)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(Int(recipe.portionKcal)) kcal · \(Int(recipe.portionProtein)) g protein · \(Int(recipe.portionFat)) g fat")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if logged {
                Label("Logged", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.success)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Palette.success.opacity(0.12), in: Capsule())
            } else {
                Button {
                    kitchen.logPlanned(recipe.title, meal: .evening,
                                       macros: Macros(kcal: recipe.portionKcal, protein: recipe.portionProtein,
                                                      carbs: recipe.portionCarbs, fat: recipe.portionFat),
                                       amountText: "Your portion", on: day)
                } label: {
                    Label("Had it", systemImage: "checkmark")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Palette.rehab, fill: Palette.rehab.opacity(0.14)))
            }
        }
        .surface()
    }
}

/// Snacks and anything else: by barcode or by hand, with recent products one tap away.
private struct ExtrasCard: View {
    @Environment(KitchenModel.self) private var kitchen
    @Binding var sheet: FoodSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            CardHeader(title: "Extras", symbol: "carrot.fill", tint: Palette.kitchen,
                       subtitle: "Snacks and anything else: scan the barcode, or add it by hand")
            Button {
                sheet = .scan(.snack)
            } label: {
                Label("Scan a barcode", systemImage: "barcode.viewfinder")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Palette.kitchen))
            Button {
                sheet = .manual(.snack)
            } label: {
                Label("Add by hand", systemImage: "square.and.pencil")
            }
            .buttonStyle(SecondaryButtonStyle())
            if !kitchen.recentProducts.isEmpty {
                Text("Recent")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(kitchen.recentProducts, id: \.barcode) { saved in
                            Button {
                                sheet = .product(saved.product, nil)
                            } label: {
                                Chip(text: saved.name, symbol: "arrow.counterclockwise", tint: Palette.textPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
        .surface()
    }
}

private struct DayTotalsCard: View {
    let nutrition: DayNutrition
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(nutrition.total.kcal.rounded()))")
                    .font(.display(48))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText())
                Text("kcal today")
                    .font(.headline)
                    .foregroundStyle(Palette.textSecondary)
            }
            HStack(spacing: Spacing.s) {
                ForEach(FoodMeal.allCases) { meal in
                    MealDot(meal: meal, kcal: nutrition.byMeal[meal]?.kcal ?? 0)
                }
            }
            MacroRow(macros: nutrition.total)
        }
        .heroCard(tint: Palette.kitchen, symbol: "flame.fill")
        .animation(.snappy, value: nutrition.total.kcal)
    }
}

private struct MealDot: View {
    let meal: FoodMeal
    let kcal: Double

    var body: some View {
        let done = kcal > 0
        VStack(spacing: 4) {
            Image(systemName: meal.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(done ? Palette.onAccent : Palette.textTertiary)
                .frame(width: 34, height: 34)
                .background(done ? Palette.kitchen : Palette.elevated, in: Circle())
            Text(done ? "\(Int(kcal.rounded()))" : "–")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(done ? Palette.textPrimary : Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meal.title): \(done ? "\(Int(kcal.rounded())) kcal" : "nothing yet")")
    }
}

/// This week's breakfast or lunch, with one tap to log it.
private struct CycleTodayCard: View {
    @Environment(KitchenModel.self) private var kitchen
    let slot: CycleSlot
    let day: DayKey

    var body: some View {
        let meal = kitchen.meal(slot, on: day)
        let macros = meal.macros
        let logged = kitchen.hasLoggedCycle(slot, on: day)
        VStack(alignment: .leading, spacing: Spacing.s) {
            NavigationLink {
                CycleMealDetailView(meal: meal)
            } label: {
                HStack(spacing: Spacing.s) {
                    IconTile(symbol: slot.symbol, tint: slot.tint, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.title.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(0.6)
                            .foregroundStyle(slot.tint)
                        Text(meal.title)
                            .font(.headline)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(Int(macros.kcal.rounded())) kcal · \(Int(macros.protein.rounded())) g protein · \(Int(macros.fat.rounded())) g fat")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if logged {
                Label("Logged", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.success)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Palette.success.opacity(0.12), in: Capsule())
            } else {
                Button {
                    kitchen.logCycle(slot, on: day)
                } label: {
                    Label("Had it", systemImage: "checkmark")
                }
                .buttonStyle(SecondaryButtonStyle(tint: slot.tint, fill: slot.tint.opacity(0.14)))
            }
        }
        .surface()
    }
}

private struct FoodEntryRow: View {
    @Environment(KitchenModel.self) private var kitchen
    let entry: FoodLogEntry

    var body: some View {
        TileRow(title: entry.name, subtitle: subtitle, symbol: entry.meal.symbol, tint: tint) {
            Menu {
                Button("Remove", systemImage: "trash", role: .destructive) { kitchen.delete(entry) }
            } label: {
                RoundIconLabel(symbol: "ellipsis", size: 34, tint: Palette.textSecondary)
            }
            .accessibilityLabel("Options for \(entry.name)")
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !entry.amountText.isEmpty { parts.append(entry.amountText) }
        parts.append("\(Int(entry.kcal.rounded())) kcal")
        parts.append("\(Int(entry.protein.rounded())) g protein")
        return parts.joined(separator: " · ")
    }

    private var tint: Color {
        switch entry.meal {
        case .breakfast: Palette.fresh
        case .lunch: Palette.kitchen
        case .evening: Palette.rehab
        case .snack: Palette.rose
        }
    }
}

// MARK: - Scanning

/// Scan, look the barcode up, then choose how much. A barcode can also be typed.
struct ScanFlowView: View {
    @Environment(KitchenModel.self) private var kitchen
    /// The meal it's for, or nil to go by the time of day.
    var meal: FoodMeal? = nil
    let done: () -> Void
    @State private var typed = ""
    @State private var looking = false
    @State private var found: FoodProduct?
    @State private var failure: String?
    @State private var lastBarcode = ""
    @State private var addingByHand = false

    var body: some View {
        Group {
            if let found {
                ProductAmountView(product: found, preset: meal, done: done)
            } else if addingByHand {
                ManualFoodView(preset: meal, done: done)
            } else {
                scanner
            }
        }
    }

    private var scanner: some View {
        VStack(spacing: Spacing.m) {
            ZStack {
                if BarcodeScanner.isAvailable {
                    BarcodeScanner { code in lookUp(code) }
                } else {
                    VStack(spacing: Spacing.s) {
                        Image(systemName: "camera.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Palette.textTertiary)
                        Text("The camera scanner isn't available here. Type the numbers under the barcode instead.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Spacing.l)
                }
                if looking {
                    ProgressView("Looking it up…")
                        .padding(Spacing.l)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius2.hero, style: .continuous))

            if let failure {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        addingByHand = true
                    } label: {
                        Label("Add it by hand", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .surface(fill: Palette.warning.opacity(0.10))
            }

            AddField(placeholder: "Or type the barcode number", text: $typed, tint: Palette.kitchen) {
                lookUp(typed)
            }
            .keyboardType(.numberPad)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, Spacing.s)
        .pageBackground()
        .navigationTitle("Scan a barcode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: done) }
        }
    }

    private func lookUp(_ code: String) {
        let digits = code.filter(\.isNumber)
        guard digits.count >= 8, !looking, digits != lastBarcode || failure != nil else { return }
        lastBarcode = digits
        looking = true
        failure = nil
        Task {
            let result = await kitchen.lookUp(barcode: digits)
            looking = false
            switch result {
            case .success(let product):
                found = product
            case .failure(.notFound):
                failure = "\(digits) isn't in Open Food Facts yet."
            case .failure(.noNutrition):
                failure = "Found it, but it has no nutrition information."
            case .failure(.unreadable):
                failure = "Couldn't look it up. Check your connection and try again."
            }
        }
    }
}

/// The camera barcode reader (VisionKit). Reports each new code once.
struct BarcodeScanner: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    @MainActor static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
                                                qualityLevel: .balanced, recognizesMultipleItems: false,
                                                isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onFound = onFound
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onFound: (String) -> Void

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    onFound(value)
                    return
                }
            }
        }
    }
}

// MARK: - Amount

/// How much of a product, and for which meal, with the numbers updating as you type.
struct ProductAmountView: View {
    @Environment(KitchenModel.self) private var kitchen
    let product: FoodProduct
    var preset: FoodMeal? = nil
    let done: () -> Void
    @State private var gramsText = ""
    @State private var meal: FoodMeal = .evening

    private var grams: Double { Double(gramsText.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        let macros = product.macros(grams: grams)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let brand = product.brand {
                        Text(brand.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.kitchen)
                    }
                    Text(product.name)
                        .font(.display(28))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Per 100 g: \(Int(product.per100.kcal.rounded())) kcal · \(oneDecimal(product.per100.protein)) g protein · \(oneDecimal(product.per100.fat)) g fat")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("How much?")
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    HStack(spacing: Spacing.s) {
                        TextField("Grams", text: $gramsText)
                            .keyboardType(.decimalPad)
                            .font(.display(28))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                            .padding(.horizontal, Spacing.m)
                            .frame(minHeight: 60)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        Text("g")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    ChipFlow().callAsFunction {
                        if let serving = product.servingGrams {
                            AmountChip(title: product.servingText.map { "1 serving (\($0))" } ?? "1 serving") {
                                gramsText = clean(serving)
                            }
                            AmountChip(title: "2 servings") { gramsText = clean(serving * 2) }
                        }
                        AmountChip(title: "100 g") { gramsText = "100" }
                        AmountChip(title: "200 g") { gramsText = "200" }
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("For")
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    Picker("Meal", selection: $meal) {
                        ForEach(FoodMeal.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                MacroRow(macros: macros)
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xl)
        }
        .safeAreaInset(edge: .bottom) {
            BottomAction {
                Button {
                    kitchen.log(product, grams: grams, amountText: "\(clean(grams)) g", meal: meal)
                    done()
                } label: {
                    Label("Log it", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle(tint: Palette.kitchen))
                .disabled(grams <= 0)
            }
        }
        .pageBackground()
        .navigationTitle("Add food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: done) }
        }
        .onAppear {
            if gramsText.isEmpty { gramsText = clean(product.servingGrams ?? 100) }
            meal = preset ?? FoodMeal.likely(hour: kitchen.calendar.component(.hour, from: kitchen.now()))
        }
    }

    private func clean(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func oneDecimal(_ value: Double) -> String { String(format: "%.1f", value) }
}

private struct AmountChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Chip(text: title, tint: Palette.kitchen, fill: Palette.kitchen.opacity(0.14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - By hand

struct ManualFoodView: View {
    @Environment(KitchenModel.self) private var kitchen
    var preset: FoodMeal? = nil
    let done: () -> Void
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var meal: FoodMeal = .evening

    private func number(_ text: String) -> Double { Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        let macros = Macros(kcal: number(kcal), protein: number(protein), carbs: number(carbs), fat: number(fat))
        Form {
            Section {
                TextField("What was it?", text: $name)
                Picker("Meal", selection: $meal) {
                    ForEach(FoodMeal.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                NumberField(title: "Calories", unit: "kcal", text: $kcal)
                NumberField(title: "Protein", unit: "g", text: $protein)
                NumberField(title: "Carbs", unit: "g", text: $carbs)
                NumberField(title: "Fat", unit: "g", text: $fat)
            } header: {
                Text("For what you ate")
            } footer: {
                Text("Only calories are needed; leave the rest blank if you don't know.")
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Add by hand")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: done) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Log") {
                    kitchen.logManual(name: name, macros: macros, meal: meal)
                    done()
                }
                .fontWeight(.semibold)
                .disabled(macros.kcal <= 0)
            }
        }
        .onAppear { meal = preset ?? FoodMeal.likely(hour: kitchen.calendar.component(.hour, from: kitchen.now())) }
    }
}

private struct NumberField: View {
    let title: String
    let unit: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 120)
            Text(unit)
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 34, alignment: .leading)
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
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.textTertiary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit(add)
            Button(action: add) {
                RoundIconLabel(symbol: "arrow.right", size: 34, tint: Palette.onAccent, fill: empty ? Palette.elevated : tint)
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .accessibilityLabel("Look up")
        }
        .padding(.leading, Spacing.m)
        .padding(.trailing, 6)
        .frame(minHeight: 48)
        .background(Palette.surface, in: Capsule())
    }
}
