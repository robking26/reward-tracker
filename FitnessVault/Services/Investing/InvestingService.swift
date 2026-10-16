import Foundation

struct BrokerInstrument: Hashable, Sendable, Identifiable {
    var id: String { ticker }
    let ticker: String
    let name: String
    let isin: String?
    let type: String
    let currencyCode: String
    let minTradeQuantity: Decimal
}

enum BrokerOrderState: Equatable, Sendable {
    /// Still open at the broker, with the quantity filled so far.
    case open(filledQuantity: Decimal)
    case filled(quantity: Decimal, valuePounds: Decimal?)
    case cancelled(String)
    /// The broker doesn't (yet) report this order anywhere.
    case notFound
}

struct BrokerOrderSummary: Hashable, Sendable {
    let id: Int64
    let ticker: String
    let quantity: Decimal?
    let createdAt: Date?
}

enum InvestingError: LocalizedError, Equatable {
    case notConnected
    case offline
    case unauthorised
    case missingPermission
    case rateLimited
    case rejected(String)
    /// The order request may or may not have reached Trading 212. Check before retrying.
    case outcomeUnknown(String)
    case unreadableResponse
    case liveTradingNotConfirmed
    case accountCurrencyNotGBP(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Trading 212 isn't connected."
        case .offline: "You're offline."
        case .unauthorised: "Trading 212 rejected the API key. Check it in Settings."
        case .missingPermission: "The Trading 212 API key doesn't have permission for this. Orders need the 'orders execute' permission."
        case .rateLimited: "Trading 212 is limiting requests. Try again in a minute."
        case .rejected(let message): message
        case .outcomeUnknown(let detail): "We couldn't confirm the result: \(detail)"
        case .unreadableResponse: "Trading 212 returned an unexpected response."
        case .liveTradingNotConfirmed: "Live trading is switched off. Turn it on in Settings first."
        case .accountCurrencyNotGBP(let code): "Your Trading 212 account is in \(code). Vaultality only invests from a GBP account."
        }
    }
}

/// A broker that can hold cash and buy an ETC. Mockable so tests and demo mode never place real orders.
protocol InvestingService: Sendable {
    var environment: TradingEnvironment { get }
    var placesRealOrders: Bool { get }

    func accountCurrency() async throws -> String
    /// Free cash available to invest, in pence.
    func freeCash() async throws -> Pence
    func instruments() async throws -> [BrokerInstrument]
    /// The latest price per share from an existing holding, in the instrument's currency, if held.
    func heldPrice(ticker: String) async throws -> Decimal?
    /// Places a market buy. Not idempotent: never call twice for the same intent without reconciling first.
    func placeMarketBuy(ticker: String, quantity: Decimal) async throws -> Int64
    func orderState(id: Int64, ticker: String) async throws -> BrokerOrderState
    /// Recent orders for a ticker, used to find an order whose request outcome was unknown.
    func recentOrders(ticker: String) async throws -> [BrokerOrderSummary]
}
