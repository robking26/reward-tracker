import SwiftUI

struct InvestmentBadge: View {
    let status: InvestmentStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, Spacing.xs + 2)
            .padding(.vertical, Spacing.xxs + 1)
            .background(Palette.elevated, in: Capsule())
            .accessibilityLabel("Status: \(status.title)")
    }
}

/// The list of month-end gold allocations shown in Money & Vault.
struct GoldSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if model.goldAllocations.isEmpty {
                ContentUnavailableView("Nothing set aside yet", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("When a month ends, whatever wasn't earned is set aside here for a gold ETC in Trading 212."))
                    .foregroundStyle(Palette.textSecondary)
                    .surface()
            } else {
                VStack(spacing: 0) {
                    ForEach(model.goldAllocations) { allocation in
                        NavigationLink {
                            GoldAllocationView(allocation: allocation)
                        } label: {
                            HStack(spacing: Spacing.s) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(allocation.monthKey?.title() ?? allocation.month)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Palette.textPrimary)
                                    Text(allocation.allocated.formatted())
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.textSecondary)
                                }
                                Spacer()
                                InvestmentBadge(status: allocation.status)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            .padding(.vertical, Spacing.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if allocation.id != model.goldAllocations.last?.id { Divider().overlay(Palette.border) }
                    }
                }
                .surface()
            }
            HStack {
                let invested = model.goldAllocations.filter { $0.status == .purchased }.sum { Pence($0.filledValuePence ?? 0) }
                let waiting = model.goldAllocations.filter { $0.status != .purchased }.sum(\.allocated)
                ValueRow(title: "Invested in gold", value: invested, detail: "Confirmed purchases", tint: invested.isPositive ? Palette.success : Palette.textPrimary)
                Divider().frame(height: 32).overlay(Palette.border)
                ValueRow(title: "Allocated, not yet invested", value: waiting, detail: "Awaiting funding or purchase")
            }
            .surface()
            if let error = model.goldError {
                Text(error).font(.footnote).foregroundStyle(Palette.error)
            }
        }
    }
}

/// One month's forfeited spending and every step on its way into gold.
struct GoldAllocationView: View {
    @Environment(AppModel.self) private var model
    let allocation: GoldAllocation
    @State private var working = false
    @State private var manualPrice = ""
    @State private var orderError: String?
    @State private var confirmingOrder = false
    @State private var confirmingNotPlaced = false

    private var instrument: GoldInstrument? { model.settings.trading212.instrument }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack(alignment: .firstTextBaseline) {
                        MoneyText(amount: allocation.allocated, font: .largeTitle, weight: .medium)
                        Spacer()
                        InvestmentBadge(status: allocation.status)
                    }
                    Text("Forfeited from \(allocation.monthKey?.title() ?? allocation.month) spending")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                    Text(allocation.status.explanation)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = allocation.lastDetail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .surface(radius: Radius.hero, padding: Spacing.l)

                steps

                actions

                if let orderError {
                    Text(orderError).font(.footnote).foregroundStyle(Palette.error)
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle("Gold allocation")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshGold(allocation) ; model.reload() }
        .confirmationDialog("Buy gold now?", isPresented: $confirmingOrder, titleVisibility: .visible) {
            Button(model.settings.trading212.environment == .live ? "Place Live Order" : "Place Demo Order") {
                Task { await placeOrder() }
            }
        } message: {
            Text("A market buy for \(instrument?.name ?? "your gold ETC") using up to \(allocation.allocated.formatted()), rounded down to whole hundredths of a share. Prices move, so the final cost can differ slightly; any remainder stays as cash in Trading 212.")
        }
        .confirmationDialog("Confirm no order was placed", isPresented: $confirmingNotPlaced, titleVisibility: .visible) {
            Button("I've checked Trading 212. There's no order.", role: .destructive) {
                model.confirmGoldOrderNotPlaced(allocation)
            }
        } message: {
            Text("Only do this after checking the Trading 212 app. The cash will be available to try again.")
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepRow("Set aside at month-end", done: true)
            stepRow("Sent to Trading 212", done: [.cashAvailable, .orderSubmitted, .partiallyFilled, .purchased].contains(allocation.status),
                    active: allocation.status == .fundingProcessing)
            stepRow("Cash confirmed in Trading 212", done: [.orderSubmitted, .partiallyFilled, .purchased].contains(allocation.status) || allocation.status == .cashAvailable)
            stepRow("Buy order", done: allocation.status == .purchased,
                    active: [.orderSubmitted, .partiallyFilled, .reconciliationRequired].contains(allocation.status))
            if let quantity = allocation.filledQuantity ?? allocation.orderQuantity, let ticker = allocation.ticker {
                Divider().overlay(Palette.border)
                HStack {
                    Text(allocation.status == .purchased ? "Bought" : "Ordered")
                    Spacer()
                    Text("\(quantity) \(ticker)").monospacedDigit()
                }
                .font(.subheadline)
                .padding(.vertical, Spacing.s)
            }
            if let residual = allocation.residual {
                ValueRow(title: "Left as cash in Trading 212", value: residual)
            }
        }
        .surface()
    }

    private func stepRow(_ title: String, done: Bool, active: Bool = false) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: done ? "checkmark.circle.fill" : (active ? "circle.dotted" : "circle"))
                .foregroundStyle(done ? Palette.success : (active ? Palette.warning : Palette.textTertiary))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(done || active ? Palette.textPrimary : Palette.textSecondary)
            Spacer()
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : (active ? "In progress" : "Not started"))
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            switch allocation.status {
            case .forfeited, .awaitingFunding, .failed:
                primaryButton("Send to Trading 212") { await model.fundGold(allocation) }
                Button("I've sent it myself") { model.markGoldFundedManually(allocation) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(minHeight: 44)
                Text("Sending from Starling needs your approval in the Starling app. Vaultality never approves payments for you.")
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
            case .fundingProcessing:
                primaryButton("Check Trading 212 Cash") { await model.refreshGold(allocation); model.reload() }
            case .cashAvailable:
                if instrument?.confirmed != true {
                    NavigationLink("Choose your gold ETC") { Trading212ConnectionView() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                } else {
                    TextField("Share price, if you don't hold it yet (\(instrument?.currencyCode ?? ""))", text: $manualPrice)
                        .keyboardType(.decimalPad)
                        .font(.subheadline)
                        .padding(Spacing.s)
                        .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    primaryButton("Buy \(instrument?.name ?? "Gold")") { confirmingOrder = true }
                    if model.settings.trading212.environment == .live && !model.settings.trading212.liveTradingConfirmed {
                        Text("Live trading is switched off. Turn it on in Trading 212 settings to buy for real.")
                            .font(.caption)
                            .foregroundStyle(Palette.warning)
                    }
                }
            case .orderSubmitted, .partiallyFilled:
                primaryButton("Check Order") { await model.refreshGold(allocation); model.reload() }
            case .reconciliationRequired:
                primaryButton("Look for the Order") { await model.reconcileGold(allocation) }
                Button("It wasn't placed") { confirmingNotPlaced = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(minHeight: 44)
            case .purchased:
                EmptyView()
            }
        }
        .disabled(working || !model.network.isOnline)
    }

    private func primaryButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            working = true
            Task {
                await action()
                working = false
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                if working { ProgressView().controlSize(.small).tint(Palette.onAccent) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Palette.accent, in: Capsule())
        }
        .sensoryFeedback(.success, trigger: allocation.status == .purchased)
    }

    private func placeOrder() async {
        working = true
        defer { working = false }
        let price = Decimal(string: manualPrice.replacingOccurrences(of: ",", with: "."))
        do {
            try await model.placeGoldOrder(allocation, manualPrice: price)
            orderError = nil
        } catch {
            orderError = error.localizedDescription
        }
    }
}
