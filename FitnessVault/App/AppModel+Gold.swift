import Foundation
import SwiftData

/// Month-end settlement and the gold investment workflow.
///
/// Forfeited spending moves through explicit, separate steps: allocated → funded (Starling → Trading 212,
/// approved by you in Starling) → cash confirmed in Trading 212 → order → filled. Nothing is marked as
/// invested until Trading 212 reports a fill, and no order is sent while another may exist.
extension AppModel {
    static let goldPurpose = "gold"
    static let goldFundingPurpose = "goldFunding"

    // MARK: Services

    var investing: InvestingService? {
        if settings.demoMode { return demoBroker }
        let environment = settings.trading212.environment
        guard let key = Keychain.read(.trading212Key(for: environment)), !key.isEmpty else { return nil }
        return Trading212Client(environment: environment, apiKey: key,
                                apiSecret: Keychain.read(.trading212Secret(for: environment)),
                                liveTradingConfirmed: settings.trading212.liveTradingConfirmed)
    }

    var isTrading212Connected: Bool { investing != nil }

    func goldAllocationRecords() -> [GoldAllocation] {
        (try? context.fetch(FetchDescriptor<GoldAllocation>(sortBy: [SortDescriptor(\.month, order: .reverse)]))) ?? []
    }

    func goldAllocation(for month: MonthKey) -> GoldAllocation? {
        let key = month.description
        return try? context.fetch(FetchDescriptor<GoldAllocation>(predicate: #Predicate { $0.month == key })).first
    }

    // MARK: Month-end

    /// Closes every finished month that hasn't been closed: locks its days, records final earnings and
    /// sets aside `max(0, allowance − earned)` for gold. Safe to call repeatedly; each month closes once.
    func closeFinishedMonths() {
        // Dormant since Vaultality 2.0: fines stay in Starling instead (D-005).
        guard settings.goldInvestingEnabled else { return }
        let state = syncState()
        for record in vaults() where record.closedAt == nil {
            guard let month = record.monthKey, month < currentMonth,
                  MonthEnd.isReadyToClose(month, now: now(), lastSuccessfulSync: state.lastSuccessfulSync, calendar: calendar)
            else { continue }

            // Lock the month so late Health changes or rate changes can't alter it after settlement.
            if let lastDay = month.days(calendar: calendar).last,
               state.finalisedThroughDay.map({ $0 < lastDay }) ?? true {
                state.finalisedThrough = lastDay.description
            }
            let earned = ledgerEntries(month: month).sum(\.amount)
            let forfeited = MonthEnd.forfeited(allocation: record.allocation, finalEarned: earned)
            record.closedAt = now()
            record.finalEarnedPence = earned.value
            record.forfeitedPence = forfeited.value
            audit("month-end", "\(month) closed: earned \(earned.formatted()) of \(record.allocation.formatted()); \(forfeited.formatted()) forfeited from spending.")

            if forfeited.isPositive, goldAllocation(for: month) == nil {
                let allocation = GoldAllocation(month: month, allocated: forfeited)
                context.insert(allocation)
                audit("gold", "Gold allocation of \(forfeited.formatted()) created for \(month).", allocation.id.uuidString)
            }
        }
        save()
    }

    // MARK: Funding

    /// Moves the allocation out of the Savings Space and, if a Trading 212 payee is set up in Starling,
    /// creates a payment for you to approve in the Starling app.
    func fundGold(_ allocation: GoldAllocation) async {
        guard allocation.status == .awaitingFunding || allocation.status == .forfeited || allocation.status == .failed,
              allocation.fundingPaymentID == nil || allocation.status == .failed
        else { return }
        guard let banking, isBankConfigured else {
            goldError = BankingError.notConnected.errorDescription
            return
        }
        goldError = nil

        // 1. Out of the Space (idempotent at Starling via the transfer UID).
        let transfer: BankTransfer
        if let id = allocation.fundingTransferID, let existing = allTransfers().first(where: { $0.id == id }), existing.status != .failed {
            transfer = existing
        } else {
            transfer = BankTransfer(amount: allocation.allocated, isSandbox: banking.isSandbox)
            transfer.purpose = Self.goldPurpose
            context.insert(transfer)
            allocation.fundingTransferID = transfer.id
            audit("gold", "Release of \(allocation.allocated.formatted()) from the Space for gold requested.", allocation.id.uuidString)
            save()
        }
        if transfer.status == .requested { await perform(transfer, using: banking) }
        guard transfer.status == .confirmed else {
            allocation.lastDetail = transfer.note ?? "Couldn't move the money out of the Savings Space yet."
            save()
            reload()
            return
        }

        // 2. To Trading 212.
        guard let payee = settings.trading212.fundingPayeeAccountUID ?? (settings.demoMode ? "mock-payee-account" : nil) else {
            allocation.status = .fundingProcessing
            allocation.lastDetail = "\(allocation.allocated.formatted()) is in your Starling balance. Send it to Trading 212 from the Starling app, then check again here."
            audit("gold", "Funding left to you: no Trading 212 payee configured.", allocation.id.uuidString)
            save()
            reload()
            return
        }
        let order = PaymentOrder(amount: allocation.allocated, reference: "Vaultality gold",
                                 coversThrough: allocation.monthKey?.firstDay ?? today, isSandbox: banking.isSandbox)
        order.purpose = Self.goldFundingPurpose
        context.insert(order)
        allocation.fundingPaymentID = order.id
        save()
        do {
            switch try await banking.initiatePayment(amount: order.amount, externalID: order.id, reference: order.reference,
                                                     payeeAccountUID: payee) {
            case .accepted(let uid):
                order.starlingPaymentOrderUID = uid
                order.status = .awaitingApproval
                allocation.status = .fundingProcessing
                allocation.lastDetail = "Approve the \(order.amount.formatted()) payment to Trading 212 in the Starling app."
                audit("gold", "Starling payment to Trading 212 created; awaiting your approval.", allocation.id.uuidString)
                if settings.notificationsEnabled { Notifier.awaitingApproval(order.amount) }
            case .rejected(let message):
                order.status = .rejected
                allocation.status = .failed
                allocation.lastDetail = message
            }
        } catch {
            order.status = .reconciliationRequired
            order.lastStatusDetail = error.localizedDescription
            allocation.status = .fundingProcessing
            allocation.lastDetail = "We couldn't confirm the Starling payment was created. Check the Starling app."
        }
        save()
        reload()
    }

    /// For when you've sent the money to Trading 212 yourself.
    func markGoldFundedManually(_ allocation: GoldAllocation) {
        guard allocation.status == .awaitingFunding || allocation.status == .forfeited else { return }
        allocation.status = .fundingProcessing
        allocation.lastDetail = "Waiting for the cash to show in Trading 212."
        audit("gold", "Marked as funded manually.", allocation.id.uuidString)
        save()
        reload()
    }

    // MARK: Progress

    /// Checks every unfinished allocation. Places an order by itself only when automation is on.
    func advanceGold() async {
        for allocation in goldAllocationRecords() where !allocation.status.isFinished {
            await refreshGold(allocation, allowAutomaticOrder: settings.trading212.automationEnabled)
        }
        save()
        reload()
    }

    func refreshGold(_ allocation: GoldAllocation, allowAutomaticOrder: Bool = false) async {
        guard let broker = investing else { return }
        do {
            switch allocation.status {
            case .fundingProcessing:
                if let paymentID = allocation.fundingPaymentID,
                   let payment = allPaymentOrders().first(where: { $0.id == paymentID }),
                   payment.status == .rejected || payment.status == .failed {
                    allocation.status = .awaitingFunding
                    allocation.lastDetail = "The Starling payment to Trading 212 wasn't made. Fund it again when ready."
                    allocation.fundingPaymentID = nil
                    break
                }
                let cash = try await broker.freeCash()
                if cash >= allocation.allocated {
                    allocation.status = .cashAvailable
                    allocation.lastDetail = "\(allocation.allocated.formatted()) is available in Trading 212."
                    audit("gold", "Cash confirmed in Trading 212 (\(cash.formatted()) free).", allocation.id.uuidString)
                } else {
                    allocation.lastDetail = "Waiting for \(allocation.allocated.formatted()) to arrive in Trading 212 (\(cash.formatted()) free so far)."
                }
            case .cashAvailable:
                if allowAutomaticOrder { try await placeGoldOrder(allocation, manualPrice: nil) }
            case .orderSubmitted, .partiallyFilled:
                try await updateOrderState(allocation, broker: broker)
            default:
                break
            }
            goldError = nil
        } catch {
            goldError = error.localizedDescription
        }
    }

    // MARK: Ordering

    enum GoldOrderError: LocalizedError {
        case instrumentNotConfirmed, notReady, anotherOrderOpen, needsPrice, cannotSize(String)
        var errorDescription: String? {
            switch self {
            case .instrumentNotConfirmed: "Choose and confirm your gold ETC in Trading 212 settings first."
            case .notReady: "This allocation isn't ready to buy yet."
            case .anotherOrderOpen: "Another gold order is still open or needs checking. Resolve it first."
            case .needsPrice: "Enter the current share price shown in Trading 212."
            case .cannotSize(let reason): reason
            }
        }
    }

    /// Buys the confirmed gold ETC with this allocation's cash. The intent is saved before the request,
    /// and an unclear outcome becomes "Needs checking" rather than a retry.
    func placeGoldOrder(_ allocation: GoldAllocation, manualPrice: Decimal?) async throws {
        guard let broker = investing else { throw InvestingError.notConnected }
        guard let instrument = settings.trading212.instrument, instrument.confirmed else { throw GoldOrderError.instrumentNotConfirmed }
        guard allocation.status == .cashAvailable else { throw GoldOrderError.notReady }
        guard !goldAllocationRecords().contains(where: { $0.status.blocksNewOrders }) else { throw GoldOrderError.anotherOrderOpen }

        let currency = try await broker.accountCurrency()
        guard currency.uppercased() == "GBP" else { throw InvestingError.accountCurrencyNotGBP(currency) }
        // Spend only this allocation's money, and never more than is actually free.
        let free = try await broker.freeCash()
        let budget = min(allocation.allocated, free)
        let heldPrice = try await broker.heldPrice(ticker: instrument.ticker)
        guard let price = heldPrice ?? manualPrice else { throw GoldOrderError.needsPrice }
        let minimum = Decimal(string: instrument.minTradeQuantity) ?? 0
        guard let quantity = OrderSizing.quantity(cash: budget, price: price, currencyCode: instrument.currencyCode, minQuantity: minimum) else {
            throw GoldOrderError.cannotSize(
                OrderSizing.pricePerSharePence(price, currencyCode: instrument.currencyCode) == nil
                    ? "\(instrument.name) is priced in \(instrument.currencyCode). Choose a gold ETC priced in GBP or GBX."
                    : "\(budget.formatted()) isn't enough for the minimum order of \(instrument.name).")
        }

        allocation.ticker = instrument.ticker
        allocation.orderQuantity = "\(quantity)"
        allocation.orderPlacedAt = .now
        allocation.isDemoBroker = !broker.placesRealOrders
        allocation.status = .reconciliationRequired
        allocation.lastDetail = "Sending a buy order for \(quantity) \(instrument.ticker)…"
        audit("gold", "Buy order for \(quantity) \(instrument.ticker) being sent (\(broker.environment.title)).", allocation.id.uuidString)
        save()

        do {
            let id = try await broker.placeMarketBuy(ticker: instrument.ticker, quantity: quantity)
            allocation.orderID = id
            allocation.status = .orderSubmitted
            allocation.lastDetail = "Order \(id) submitted for \(quantity) shares."
            audit("gold", "Trading 212 accepted order \(id).", allocation.id.uuidString)
            try? await updateOrderState(allocation, broker: broker)
        } catch InvestingError.outcomeUnknown(let detail) {
            allocation.lastDetail = "We couldn't confirm whether the order was placed: \(detail)"
            audit("gold", "Order outcome unknown: \(detail)", allocation.id.uuidString)
        } catch {
            // Rejected or never sent: nothing was created, so the cash is still available.
            allocation.status = .cashAvailable
            allocation.lastDetail = error.localizedDescription
            audit("gold", "Order not placed: \(error.localizedDescription)", allocation.id.uuidString)
        }
        save()
        reload()
    }

    private func updateOrderState(_ allocation: GoldAllocation, broker: InvestingService) async throws {
        guard let id = allocation.orderID, let ticker = allocation.ticker else { return }
        switch try await broker.orderState(id: id, ticker: ticker) {
        case .open(let filled):
            allocation.status = filled > 0 ? .partiallyFilled : .orderSubmitted
            allocation.filledQuantity = filled > 0 ? "\(filled)" : nil
        case .filled(let quantity, let value):
            allocation.status = .purchased
            allocation.filledQuantity = "\(quantity)"
            allocation.filledValuePence = value.map { OrderSizing.pence(fromPounds: $0).value }
            let residual = allocation.residual.map { " \($0.formatted()) stays as cash in Trading 212." } ?? ""
            allocation.lastDetail = "Bought \(quantity) \(ticker).\(residual)"
            audit("gold", "Order \(id) filled: \(quantity) \(ticker).", allocation.id.uuidString)
        case .cancelled(let reason):
            allocation.status = .failed
            allocation.lastDetail = "Trading 212 reports the order as \(reason.lowercased()). No gold was bought."
            audit("gold", "Order \(id) \(reason.lowercased()).", allocation.id.uuidString)
        case .notFound:
            allocation.lastDetail = "Trading 212 doesn't list order \(id) yet."
        }
        save()
    }

    // MARK: Reconciliation

    /// Looks for an order matching an unclear request. Adopts it if found; otherwise leaves it for you to confirm.
    func reconcileGold(_ allocation: GoldAllocation) async {
        guard allocation.status == .reconciliationRequired, let broker = investing, let ticker = allocation.ticker else { return }
        do {
            let placedAt = allocation.orderPlacedAt ?? allocation.updatedAt
            let quantity = allocation.orderQuantity.flatMap { Decimal(string: $0) }
            let match = try await broker.recentOrders(ticker: ticker).first { order in
                (order.createdAt.map { $0 >= placedAt.addingTimeInterval(-120) } ?? true)
                    && (quantity == nil || order.quantity == quantity)
            }
            if let match {
                allocation.orderID = match.id
                allocation.status = .orderSubmitted
                allocation.lastDetail = "Found order \(match.id) in Trading 212."
                audit("gold", "Reconciled: order \(match.id) found.", allocation.id.uuidString)
                try await updateOrderState(allocation, broker: broker)
            } else {
                allocation.lastDetail = "No matching order found in Trading 212. If the Trading 212 app shows no order either, mark it as not placed."
            }
            goldError = nil
        } catch {
            goldError = error.localizedDescription
        }
        save()
        reload()
    }

    /// After you've checked Trading 212 and no order exists, the cash can be used again. Never marks anything as bought.
    func confirmGoldOrderNotPlaced(_ allocation: GoldAllocation) {
        guard allocation.status == .reconciliationRequired || allocation.status == .failed else { return }
        allocation.status = .cashAvailable
        allocation.orderID = nil
        allocation.lastDetail = "Marked as not placed. The cash is available to try again."
        audit("gold", "Order marked as not placed after a manual check.", allocation.id.uuidString)
        save()
        reload()
    }
}
