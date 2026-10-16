import Foundation

/// In-memory broker for demo mode and tests. Fills orders immediately; can never trade for real.
actor MockBrokerState {
    var cash: Pence
    var orders: [Int64: (ticker: String, quantity: Decimal)] = [:]
    var nextID: Int64 = 1

    init(cash: Pence) { self.cash = cash }

    func deposit(_ amount: Pence) { cash = cash + amount }

    func buy(ticker: String, quantity: Decimal, pricePence: Decimal) throws -> Int64 {
        let cost = OrderSizing.pence(fromPounds: quantity * pricePence / 100)
        guard cost <= cash else { throw InvestingError.rejected("Insufficient funds.") }
        cash = cash - cost
        let id = nextID
        nextID += 1
        orders[id] = (ticker, quantity)
        return id
    }

    func order(_ id: Int64) -> (ticker: String, quantity: Decimal)? { orders[id] }
}

struct MockInvestingService: InvestingService {
    let state: MockBrokerState
    /// Demo price: 3,500p a share, a plausible GBX gold ETC price.
    static let demoPricePence: Decimal = 3_500

    var environment: TradingEnvironment { .demo }
    var placesRealOrders: Bool { false }

    init(state: MockBrokerState = MockBrokerState(cash: .zero)) { self.state = state }

    func accountCurrency() async throws -> String { "GBP" }
    func freeCash() async throws -> Pence { await state.cash }

    func instruments() async throws -> [BrokerInstrument] {
        [BrokerInstrument(ticker: "DEMOGOLD_EQ", name: "Physical Gold ETC (demo)", isin: nil, type: "ETF",
                          currencyCode: "GBX", minTradeQuantity: Decimal(string: "0.01")!)]
    }

    func heldPrice(ticker: String) async throws -> Decimal? { Self.demoPricePence }

    func placeMarketBuy(ticker: String, quantity: Decimal) async throws -> Int64 {
        try await state.buy(ticker: ticker, quantity: quantity, pricePence: Self.demoPricePence)
    }

    func orderState(id: Int64, ticker: String) async throws -> BrokerOrderState {
        guard let order = await state.order(id) else { return .notFound }
        return .filled(quantity: order.quantity, valuePounds: order.quantity * Self.demoPricePence / 100)
    }

    func recentOrders(ticker: String) async throws -> [BrokerOrderSummary] { [] }
}
