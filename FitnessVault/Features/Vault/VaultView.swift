import SwiftUI

struct VaultView: View {
    @Environment(AppModel.self) private var model
    @Binding var showingSettings: Bool
    @State private var confirmingSettlement = false
    @State private var confirmingTopUp = false
    @State private var checkingPayments = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VaultHeroCard(summary: model.vault)

                    if let pending = model.payments.first(where: { $0.status.isUnresolved }) {
                        PendingPaymentCard(payment: pending, checking: $checkingPayments)
                    } else {
                        PayoutStatusLine().surface()
                    }

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Where your money is")
                        MoneyFlowCard(flow: model.flow)
                    }

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Starling")
                        StarlingCard(showingSettings: $showingSettings, confirmingTopUp: $confirmingTopUp)
                    }

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Payments to Monzo")
                        PaymentHistory(payments: model.payments)
                    }

                    if !model.monthHistory.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SectionHeader("Previous months")
                            VStack(spacing: 0) {
                                ForEach(model.monthHistory, id: \.month) { summary in
                                    MonthHistoryRow(summary: summary)
                                    if summary.month != model.monthHistory.last?.month { Divider().overlay(Palette.border) }
                                }
                            }
                            .surface()
                        }
                    }

                    HowMoneyMoves()
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.xl)
            }
            .pageBackground()
            .navigationTitle("Vault")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Check Payment Status", systemImage: "arrow.clockwise") {
                            Task { await model.checkPayments() }
                        }
                        Button("Release and Pay Now", systemImage: "arrow.right.circle") {
                            confirmingSettlement = true
                        }
                        .disabled(!model.isBankConfigured || !model.network.isOnline)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .accessibilityLabel("Vault actions")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton(isPresented: $showingSettings)
                }
            }
            .refreshable {
                await model.refreshBank()
                await model.checkPayments()
            }
            .task { await model.refreshBank() }
            .confirmationDialog("Prepare a payment now?", isPresented: $confirmingSettlement, titleVisibility: .visible) {
                Button("Release and Prepare Payment") { Task { await model.settleIfDue(force: true) } }
            } message: {
                Text("Earned money moves from your Savings Space to your Starling balance, and one payment to Monzo is created for finished, synced days. You'll approve it in the Starling app.")
            }
            .confirmationDialog("Top up your Savings Space?", isPresented: $confirmingTopUp, titleVisibility: .visible) {
                Button("Move \(model.fundingPlan?.topUpRequired.formatted() ?? "") into Space") {
                    Task { await model.topUpSpace() }
                }
            } message: {
                Text("Only the shortfall for this month's allocation is moved. Unearned money already in the Space stays where it is.")
            }
        }
    }
}

struct PendingPaymentCard: View {
    @Environment(AppModel.self) private var model
    let payment: PaymentOrder
    @Binding var checking: Bool
    @State private var confirmingNotSent = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                MoneyText(amount: payment.amount, font: .title2, weight: .medium)
                Spacer()
                StatusBadge(status: payment.status)
            }
            Text(payment.status.explanation)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = payment.lastStatusDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            HStack(spacing: Spacing.s) {
                Button {
                    checking = true
                    Task {
                        await model.checkPayments()
                        checking = false
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        if checking { ProgressView().controlSize(.small).tint(Palette.onAccent) }
                        Text("Check Status")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, Spacing.m)
                    .frame(minHeight: 44)
                    .background(Palette.accent, in: Capsule())
                }
                .disabled(checking || !model.network.isOnline)

                if payment.status == .reconciliationRequired {
                    Button("It wasn't sent") { confirmingNotSent = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minHeight: 44)
                }
            }
        }
        .surface()
        .sensoryFeedback(.success, trigger: payment.status == .paid)
        .confirmationDialog("Confirm this payment wasn't made", isPresented: $confirmingNotSent, titleVisibility: .visible) {
            Button("I've checked Starling. It wasn't sent.", role: .destructive) {
                model.confirmPaymentNotSent(payment)
            }
        } message: {
            Text("Only do this after checking your Starling payments. The earnings will be included in the next payment.")
        }
    }
}

struct MoneyFlowCard: View {
    let flow: MoneyFlow

    var body: some View {
        VStack(spacing: 0) {
            ValueRow(title: "Earned", value: flow.earned, detail: "Activity has qualified for a reward.", tint: Palette.accent)
            Divider().overlay(Palette.border)
            ValueRow(title: "Awaiting release", value: flow.awaitingRelease + flow.releasing,
                     detail: "Earned, still in your Savings Space.")
            Divider().overlay(Palette.border)
            ValueRow(title: "Released", value: flow.released, detail: "Moved to your Starling main balance.")
            Divider().overlay(Palette.border)
            ValueRow(title: "Awaiting approval", value: flow.awaitingApproval,
                     detail: "Payment created; approve it in Starling.", tint: flow.awaitingApproval.isPositive ? Palette.warning : Palette.textPrimary)
            if flow.processing.isPositive {
                Divider().overlay(Palette.border)
                ValueRow(title: "Processing", value: flow.processing, tint: Palette.warning)
            }
            if flow.needsChecking.isPositive {
                Divider().overlay(Palette.border)
                ValueRow(title: "Needs checking", value: flow.needsChecking, tint: Palette.warning)
            }
            Divider().overlay(Palette.border)
            ValueRow(title: "Paid to Monzo", value: flow.paid, detail: "Starling confirmed the payment.",
                     tint: flow.paid.isPositive ? Palette.success : Palette.textPrimary)
            if flow.failedOrRejected.isPositive {
                Divider().overlay(Palette.border)
                ValueRow(title: "Failed or rejected", value: flow.failedOrRejected,
                         detail: "Still in your Starling balance; included in the next payment.", tint: Palette.error)
            }
        }
        .surface()
    }
}

struct StarlingCard: View {
    @Environment(AppModel.self) private var model
    @Binding var showingSettings: Bool
    @Binding var confirmingTopUp: Bool

    var body: some View {
        if !model.isBankConfigured {
            ContentUnavailableView {
                Label("Starling not connected", systemImage: "building.columns")
            } description: {
                Text("Connect your Starling account, Savings Space and Monzo payee to receive what you earn.")
            } actions: {
                Button("Connect Starling") { showingSettings = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .foregroundStyle(Palette.onAccent)
            }
            .surface()
        } else if let snapshot = model.bankSnapshot {
            VStack(spacing: 0) {
                ValueRow(title: snapshot.spaceName, value: snapshot.spaceBalance, detail: "Savings Space")
                Divider().overlay(Palette.border)
                ValueRow(title: "Main balance", value: snapshot.mainBalance)
                if let plan = model.fundingPlan {
                    Divider().overlay(Palette.border)
                    ValueRow(title: "Carried forward", value: plan.carriedForward,
                             detail: "Unearned money already in the Space, counted towards this month.")
                    if plan.heldBeyondAllocation.isPositive {
                        Divider().overlay(Palette.border)
                        ValueRow(title: "Held beyond allocation", value: plan.heldBeyondAllocation,
                                 detail: "Stays in the Space. Never offered as rewards.")
                    }
                    if plan.topUpRequired.isPositive {
                        Divider().overlay(Palette.border)
                        HStack {
                            ValueRow(title: "Top-up needed", value: plan.topUpRequired,
                                     detail: "To fund the full \(model.settings.monthlyAllocation.formatted()).", tint: Palette.warning)
                        }
                        Button("Move into Space") { confirmingTopUp = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .disabled(!model.network.isOnline)
                    }
                }
                Text("\(model.settings.demoMode ? "Demo bank" : model.settings.bankingEnvironment.title) · Updated \(MeasureFormat.relative(snapshot.fetchedAt))")
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.xs)
            }
            .surface()
        } else if let error = model.bankError {
            NoticeBanner(symbol: "exclamationmark.triangle", title: "Couldn't reach Starling", message: error,
                         actionTitle: "Try Again") {
                Task { await model.refreshBank() }
            }
        } else {
            HStack {
                ProgressView().tint(Palette.textSecondary)
                Text("Loading balances…")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            .surface()
        }
    }
}

struct PaymentHistory: View {
    let payments: [PaymentOrder]

    var body: some View {
        if payments.isEmpty {
            ContentUnavailableView("No payments yet", systemImage: "arrow.left.arrow.right",
                                   description: Text("Each morning, finished days' earnings are prepared as one payment to Monzo."))
                .foregroundStyle(Palette.textSecondary)
                .surface()
        } else {
            VStack(spacing: 0) {
                ForEach(payments) { payment in
                    HStack(alignment: .center, spacing: Spacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(payment.amount.formatted())
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textPrimary)
                            Text(payment.createdAt.formatted(date: .abbreviated, time: .shortened) + (payment.isSandbox ? " · Sandbox" : ""))
                                .font(.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                        Spacer()
                        StatusBadge(status: payment.status)
                    }
                    .padding(.vertical, Spacing.s)
                    .accessibilityElement(children: .combine)
                    if payment.id != payments.last?.id { Divider().overlay(Palette.border) }
                }
            }
            .surface()
        }
    }
}

struct MonthHistoryRow: View {
    let summary: VaultSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(summary.month.title())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("\(summary.earned.formatted()) of \(summary.allocation.formatted())")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            ThinProgressBar(progress: summary.progress, height: 4)
            Text("\(summary.remainingToUnlock.formatted()) unearned, kept in Starling")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

struct HowMoneyMoves: View {
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.s) {
                step("1", "Earned", "Apple Health activity qualifies for a reward, up to your monthly allocation.")
                step("2", "Released", "Earned money moves from your Savings Space to your Starling balance.")
                step("3", "Awaiting approval", "Each morning one payment to Monzo is created. Starling asks you to approve it in their app. Nothing is sent until you do.")
                step("4", "Paid", "Shown only after Starling confirms the payment completed.")
                Text("Money you don't earn stays in Starling. It's never forfeited, and next month only the shortfall is topped up.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, Spacing.xs)
            }
            .padding(.top, Spacing.s)
        } label: {
            Text("How money moves")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
        }
        .tint(Palette.textSecondary)
        .surface()
    }

    private func step(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Text(number)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 22, height: 22)
                .background(Palette.elevated, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                Text(text).font(.footnote).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
