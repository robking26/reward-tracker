import Foundation

/// Where a month's forfeited spending is on its way to becoming gold.
/// Allocated money and invested money are never the same state.
enum InvestmentStatus: String, Codable, CaseIterable, Sendable {
    /// Unearned at month-end and set aside. Still in the Starling Savings Space.
    case forfeited
    /// Waiting to be sent from Starling to Trading 212.
    case awaitingFunding
    /// A transfer to Trading 212 has started (Starling approval or bank processing).
    case fundingProcessing
    /// Trading 212 shows enough free cash; ready to buy.
    case cashAvailable
    /// A buy order was accepted by Trading 212 and hasn't filled yet.
    case orderSubmitted
    case partiallyFilled
    /// Trading 212 reports the order filled.
    case purchased
    case failed
    /// The outcome of an order request is unknown. Nothing else is sent until it's checked.
    case reconciliationRequired

    var title: String {
        switch self {
        case .forfeited: "Forfeited from spending"
        case .awaitingFunding: "Awaiting funding"
        case .fundingProcessing: "Funding processing"
        case .cashAvailable: "Cash available"
        case .orderSubmitted: "Order submitted"
        case .partiallyFilled: "Partially filled"
        case .purchased: "Purchased"
        case .failed: "Failed"
        case .reconciliationRequired: "Needs checking"
        }
    }

    var explanation: String {
        switch self {
        case .forfeited, .awaitingFunding:
            "Set aside for gold. The money is still in your Starling Savings Space; nothing has been invested yet."
        case .fundingProcessing:
            "On its way to Trading 212. If a Starling payment was created, approve it in the Starling app."
        case .cashAvailable:
            "The cash is in Trading 212. No gold has been bought yet."
        case .orderSubmitted:
            "Trading 212 accepted the buy order. It isn't complete until it fills."
        case .partiallyFilled:
            "Part of the order has filled. The rest is still open."
        case .purchased:
            "Trading 212 confirmed the purchase. Any uninvested remainder stays as cash in Trading 212."
        case .failed:
            "This step didn't complete. Nothing was bought; you can try again."
        case .reconciliationRequired:
            "We couldn't confirm whether an order was placed. Check before anything else is sent."
        }
    }

    var symbol: String {
        switch self {
        case .forfeited, .awaitingFunding: "tray.and.arrow.down"
        case .fundingProcessing: "arrow.right.circle"
        case .cashAvailable: "sterlingsign.circle"
        case .orderSubmitted, .partiallyFilled: "clock"
        case .purchased: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .reconciliationRequired: "exclamationmark.triangle.fill"
        }
    }

    /// While an order may exist, no new order can be placed for any allocation.
    var blocksNewOrders: Bool {
        self == .orderSubmitted || self == .partiallyFilled || self == .reconciliationRequired
    }

    /// Money is still sitting in the Savings Space and must not count towards a future allowance.
    var isStillInSpace: Bool { self == .forfeited || self == .awaitingFunding }

    var isFinished: Bool { self == .purchased }
}

/// Month-end rules. Unearned allowance is set aside for investment, never rolled into the next month.
enum MonthEnd {
    /// `max(0, allowance − final earnings)`.
    static func forfeited(allocation: Pence, finalEarned: Pence) -> Pence {
        (allocation - finalEarned).nonNegative
    }

    /// A month closes once the 2nd of the next month has started and Apple Health has synced
    /// since then, so late-arriving activity is counted first.
    static func isReadyToClose(_ month: MonthKey, now: Date, lastSuccessfulSync: Date?, calendar: Calendar = .current) -> Bool {
        let closeFrom = month.next.firstDay.adding(days: 1, calendar: calendar).startDate(calendar: calendar)
        guard let lastSuccessfulSync else { return false }
        return now >= closeFrom && lastSuccessfulSync >= closeFrom
    }
}

/// Converts cash into a share quantity. Trading 212 market orders take a quantity, not a £ value.
enum OrderSizing {
    /// Kept back for price movement, spread and fees between pricing and filling.
    static let defaultBuffer = Decimal(string: "0.02")!
    /// Fractional shares are rounded down to this many decimal places.
    static let quantityScale: Int16 = 2

    /// The price of one share in pence, or nil for currencies the app won't trade (to avoid FX conversion).
    static func pricePerSharePence(_ price: Decimal, currencyCode: String) -> Decimal? {
        switch currencyCode.uppercased() {
        case "GBP": return price * 100
        case "GBX": return price
        default: return nil
        }
    }

    /// The largest quantity affordable within `cash` after the buffer, rounded down, or nil if
    /// below the instrument's minimum or the price can't be used.
    static func quantity(cash: Pence, price: Decimal, currencyCode: String, minQuantity: Decimal,
                         buffer: Decimal = defaultBuffer) -> Decimal? {
        guard cash.isPositive, price > 0,
              let pencePerShare = pricePerSharePence(price, currencyCode: currencyCode), pencePerShare > 0
        else { return nil }
        let budget = Decimal(cash.value) * (1 - buffer)
        var raw = budget / pencePerShare
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, Int(quantityScale), .down)
        return rounded > 0 && rounded >= minQuantity ? rounded : nil
    }

    /// Converts a broker amount in pounds (e.g. 132.4567) to whole pence, rounding down.
    static func pence(fromPounds amount: Decimal) -> Pence {
        var scaled = amount * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .down)
        return Pence(NSDecimalNumber(decimal: rounded).intValue)
    }
}
