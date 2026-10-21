import PhotosUI
import SwiftUI

/// The £400 household ceiling and receipts (I1, I3). Spending is information, never a fine.
struct SpendingSection: View {
    @Environment(KitchenModel.self) private var kitchen
    @State private var capturing = false
    @State private var addingManually = false

    var body: some View {
        let budget = kitchen.budget
        let month = MonthKey(kitchen.now(), calendar: kitchen.calendar).description
        let receipts = kitchen.receipts.filter { $0.month == month }
        let ceiling = Double(HouseholdBudget.ceiling.value)
        let progress = ceiling > 0 ? Double(budget.spent.value) / ceiling : 0
        let budgetTint: Color = budget.isOver ? Palette.warning : Palette.kitchen
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.l) {
                    ZStack {
                        RingGauge(progress: progress, tint: budgetTint, lineWidth: 14)
                        VStack(spacing: 0) {
                            Text("\(Int((progress * 100).rounded()))%")
                                .font(.display(26))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textPrimary)
                            Text("of £400")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .frame(width: 124, height: 124)
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        BudgetFigure(label: "Spent", amount: budget.spent, tint: Palette.textPrimary)
                        BudgetFigure(label: "Left", amount: budget.remaining, tint: budgetTint)
                        BudgetFigure(label: "Even pace today", amount: budget.evenPace, tint: Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                Text(budget.summary)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .heroCard(tint: budgetTint, symbol: "sterlingsign")

            HStack(spacing: Spacing.s) {
                Button {
                    capturing = true
                } label: {
                    Label("Scan a receipt", systemImage: "doc.text.viewfinder")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Palette.kitchen, fill: Palette.kitchen.opacity(0.14)))
                Button {
                    addingManually = true
                } label: {
                    Label("No receipt", systemImage: "square.and.pencil")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if !receipts.isEmpty {
                SectionTitle(title: "This month", detail: receipts.count == 1 ? "1 receipt" : "\(receipts.count) receipts")
                VStack(spacing: 0) {
                    ForEach(receipts.indices, id: \.self) { index in
                        let receipt = receipts[index]
                        NavigationLink {
                            ReceiptDetailView(receipt: receipt)
                        } label: {
                            TileRow(title: receipt.merchant.title,
                                    subtitle: receipt.needsReview ? "Check this one" : receipt.date.formatted(.dateTime.weekday(.abbreviated).day().month()),
                                    symbol: merchantSymbol(receipt.merchant), tint: merchantTint(receipt.merchant)) {
                                Text(receipt.total.formatted())
                                    .font(.body.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.textPrimary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < receipts.count - 1 { RowDivider() }
                    }
                }
                .surface()
            }
            Footnote("Groceries, toiletries, cleaning, Co-op top-ups, and takeaways or meals out. It's a ceiling, not a target, and never a fine.")
        }
        .sheet(isPresented: $capturing) {
            ReceiptCaptureView().presentationBackground(Palette.background)
        }
        .sheet(isPresented: $addingManually) {
            NavigationStack {
                ReceiptReviewForm(parsed: ParsedReceipt(merchant: .aldi, date: kitchen.now(), lines: [], totalPence: nil, needsReview: false),
                                  manual: true)
            }
            .presentationBackground(Palette.background)
        }
    }
}

extension SpendingSection {
    fileprivate func merchantSymbol(_ merchant: Merchant) -> String {
        switch merchant {
        case .aldi: "cart.fill"
        case .coop: "basket.fill"
        case .takeaway: "takeoutbag.and.cup.and.straw.fill"
        case .other: "bag.fill"
        }
    }

    fileprivate func merchantTint(_ merchant: Merchant) -> Color {
        switch merchant {
        case .aldi: Palette.frost
        case .coop: Palette.fresh
        case .takeaway: Palette.rose
        case .other: Palette.rehab
        }
    }
}

/// A label over an amount, for the budget hero.
private struct BudgetFigure: View {
    let label: String
    let amount: Pence
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
            Text(amount.formatted())
                .font(.display(20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText(value: Double(amount.value)))
        }
        .accessibilityElement(children: .combine)
    }
}

struct ReceiptCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var parsed: ParsedReceipt?
    @State private var scanning = false
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let parsed {
                    ReceiptReviewForm(parsed: parsed, manual: false)
                } else {
                    Form {
                        Section {
                            if DocumentScanner.isAvailable {
                                Button("Scan with the camera", systemImage: "camera") { scanning = true }
                            }
                            PhotosPicker(selection: $photo, matching: .images) {
                                Label("Photo or screenshot", systemImage: "photo")
                            }
                        } footer: {
                            Text("Aldi, Co-op and takeaway receipts. Read on your iPhone; nothing is uploaded.")
                        }
                        if reading { Section { HStack { ProgressView(); Text("Reading…") } } }
                        if failed {
                            Section { Text("Couldn't read any text. Try again in better light, or add it without a receipt.") }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .pageBackground()
                    .navigationTitle("Receipt")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                read { await TextRecognition.text(in: images) }
            } onCancel: {
                scanning = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            read {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return "" }
                return await TextRecognition.text(in: image)
            }
        }
    }

    private func read(_ work: @escaping () async -> String) {
        reading = true
        failed = false
        Task {
            let text = await work()
            reading = false
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                failed = true
            } else {
                parsed = ReceiptParser.parse(text)
            }
        }
    }
}

/// Review before saving: uncertain lines are flagged and the total can be corrected (I3).
struct ReceiptReviewForm: View {
    @Environment(KitchenModel.self) private var kitchen
    @Environment(\.dismiss) private var dismiss
    let manual: Bool
    @State private var merchant: Merchant
    @State private var date: Date
    @State private var totalText: String
    @State private var lines: [ReceiptLine]
    @State private var duplicate = false
    private let needsReview: Bool

    init(parsed: ParsedReceipt, manual: Bool) {
        self.manual = manual
        needsReview = parsed.needsReview
        _merchant = State(initialValue: parsed.merchant == .other ? .aldi : parsed.merchant)
        _date = State(initialValue: parsed.date ?? .now)
        _totalText = State(initialValue: parsed.totalPence.map { String(format: "%.2f", Double($0) / 100) } ?? "")
        _lines = State(initialValue: parsed.lines)
    }

    var body: some View {
        Form {
            Section {
                Picker("Shop", selection: $merchant) {
                    ForEach(Merchant.allCases) { Text($0.title).tag($0) }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                HStack {
                    Text("Total £")
                    TextField("0.00", text: $totalText).keyboardType(.decimalPad)
                }
            } footer: {
                if needsReview && !manual {
                    Text("Some of this was hard to read or doesn't add up. Check the total before saving.")
                }
            }
            if !lines.isEmpty {
                Section("Items") {
                    ForEach(lines) { line in
                        HStack {
                            Text(line.quantity > 1 ? "\(line.quantity) × \(line.name)" : line.name)
                                .foregroundStyle(line.uncertain ? Palette.warning : Palette.textPrimary)
                            Spacer()
                            Text(Pence(line.pricePence).formatted()).monospacedDigit()
                        }
                    }
                    .onDelete { lines.remove(atOffsets: $0) }
                }
            }
            Section {
                Button("Save") { save() }
                    .disabled(totalPence == nil)
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(manual ? "Add spending" : "Check the receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .alert("Already saved", isPresented: $duplicate) {
            Button("OK") { dismiss() }
        } message: {
            Text("A \(merchant.title) receipt for the same amount on the same day is already here, so it wasn't added twice.")
        }
    }

    private var totalPence: Int? {
        let cleaned = totalText.replacingOccurrences(of: "£", with: "").replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return Int((value * 100).rounded())
    }

    private func save() {
        guard let totalPence else { return }
        let result = kitchen.saveReceipt(merchant: merchant, date: date, totalPence: totalPence, lines: lines,
                                         needsReview: false, manual: manual)
        if result == .duplicate { duplicate = true } else { dismiss() }
    }
}

struct ReceiptDetailView: View {
    @Environment(KitchenModel.self) private var kitchen
    @Environment(\.dismiss) private var dismiss
    let receipt: ReceiptRecord

    var body: some View {
        List {
            Section {
                LabeledContent("Shop", value: receipt.merchant.title)
                LabeledContent("Date", value: receipt.date.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Total", value: receipt.total.formatted())
                if receipt.needsReview {
                    Button("Looks right") { kitchen.markReviewed(receipt, lines: receipt.lines, totalPence: receipt.totalPence) }
                }
            }
            if !receipt.lines.isEmpty {
                Section("Items") {
                    ForEach(receipt.lines) { line in
                        HStack {
                            Text(line.name).foregroundStyle(line.uncertain ? Palette.warning : Palette.textPrimary)
                            Spacer()
                            Text(Pence(line.pricePence).formatted()).monospacedDigit()
                        }
                    }
                }
            }
            Section {
                Button("Delete", role: .destructive) {
                    kitchen.delete(receipt)
                    dismiss()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Receipt")
        .navigationBarTitleDisplayMode(.inline)
    }
}
