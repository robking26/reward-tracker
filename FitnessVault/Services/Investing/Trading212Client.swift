import Foundation

/// Trading 212 Public API (v0, beta) client. Docs: https://docs.trading212.com/api
///
/// - Demo and live are separate hosts; the key belongs to one of them.
/// - Market orders take a share quantity (positive buys) and are not idempotent, so an order
///   request that times out is reported as `outcomeUnknown` and must be reconciled, never resent.
/// - Response shapes are read leniently because the API is in beta; verify against demo first.
struct Trading212Client: InvestingService {
    let environment: TradingEnvironment
    let apiKey: String
    let apiSecret: String?
    let liveTradingConfirmed: Bool
    var session: URLSession = .shared

    var placesRealOrders: Bool { environment == .live }

    // MARK: Account

    func accountCurrency() async throws -> String {
        let json = try await object("GET", "/equity/account/info")
        guard let code = json["currencyCode"] as? String else { throw InvestingError.unreadableResponse }
        return code
    }

    func freeCash() async throws -> Pence {
        let json = try await object("GET", "/equity/account/cash")
        guard let free = Self.decimal(json["free"]) else { throw InvestingError.unreadableResponse }
        return OrderSizing.pence(fromPounds: free)
    }

    func instruments() async throws -> [BrokerInstrument] {
        let data = try await send("GET", "/equity/metadata/instruments")
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw InvestingError.unreadableResponse
        }
        return list.compactMap { item in
            guard let ticker = item["ticker"] as? String else { return nil }
            return BrokerInstrument(
                ticker: ticker,
                name: (item["name"] as? String) ?? (item["shortName"] as? String) ?? ticker,
                isin: item["isin"] as? String,
                type: (item["type"] as? String) ?? "",
                currencyCode: (item["currencyCode"] as? String) ?? "",
                minTradeQuantity: Self.decimal(item["minTradeQuantity"]) ?? 0)
        }
    }

    func heldPrice(ticker: String) async throws -> Decimal? {
        do {
            let json = try await object("GET", "/equity/portfolio/\(ticker)")
            return Self.decimal(json["currentPrice"])
        } catch InvestingError.rejected {
            return nil // Not held.
        }
    }

    // MARK: Orders

    func placeMarketBuy(ticker: String, quantity: Decimal) async throws -> Int64 {
        if environment == .live && !liveTradingConfirmed { throw InvestingError.liveTradingNotConfirmed }
        guard quantity > 0 else { throw InvestingError.rejected("The order quantity must be positive.") }
        let body: [String: Any] = ["ticker": ticker, "quantity": NSDecimalNumber(decimal: quantity)]
        let data = try await send("POST", "/equity/orders/market", body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = Self.int64(json["id"])
        else {
            // Accepted but unreadable: an order may exist, so treat the outcome as unknown.
            throw InvestingError.outcomeUnknown("Trading 212 accepted the request but its reply couldn't be read.")
        }
        return id
    }

    func orderState(id: Int64, ticker: String) async throws -> BrokerOrderState {
        // An order still open is listed under pending orders.
        do {
            let json = try await object("GET", "/equity/orders/\(id)")
            return Self.state(from: json) ?? .open(filledQuantity: Self.decimal(json["filledQuantity"]) ?? 0)
        } catch InvestingError.rejected {
            // Not pending any more: look in order history.
        }
        for item in try await history(ticker: ticker) where Self.int64(Self.field("id", in: item)) == id {
            if let state = Self.state(from: item) { return state }
        }
        return .notFound
    }

    func recentOrders(ticker: String) async throws -> [BrokerOrderSummary] {
        var summaries: [BrokerOrderSummary] = []
        if let pending = try? await send("GET", "/equity/orders"),
           let list = try? JSONSerialization.jsonObject(with: pending) as? [[String: Any]] {
            summaries += list.compactMap(Self.summary)
        }
        summaries += try await history(ticker: ticker).compactMap(Self.summary)
        return summaries.filter { $0.ticker == ticker }
    }

    private func history(ticker: String) async throws -> [[String: Any]] {
        let json = try await object("GET", "/equity/history/orders?ticker=\(ticker)&limit=50")
        return json["items"] as? [[String: Any]] ?? []
    }

    // MARK: Parsing

    /// Reads a field from a flat order or one nested under "order"/"fill" (newer response shape).
    private static func field(_ key: String, in item: [String: Any]) -> Any? {
        if let value = item[key] { return value }
        if let order = item["order"] as? [String: Any], let value = order[key] { return value }
        if let fill = item["fill"] as? [String: Any], let value = fill[key] { return value }
        return nil
    }

    private static func state(from item: [String: Any]) -> BrokerOrderState? {
        let status = (field("status", in: item) as? String)?.uppercased() ?? ""
        let filled = decimal(field("filledQuantity", in: item)) ?? 0
        switch status {
        case "FILLED":
            return .filled(quantity: filled, valuePounds: decimal(field("filledValue", in: item)))
        case "CANCELLED", "REJECTED":
            return .cancelled(status.capitalized)
        case "PARTIALLY_FILLED":
            return .open(filledQuantity: filled)
        case "":
            return nil
        default:
            return .open(filledQuantity: filled)
        }
    }

    private static func summary(_ item: [String: Any]) -> BrokerOrderSummary? {
        guard let id = int64(field("id", in: item)), let ticker = field("ticker", in: item) as? String else { return nil }
        let created = (field("dateCreated", in: item) as? String ?? field("createdAt", in: item) as? String)
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        return BrokerOrderSummary(id: id, ticker: ticker,
                                  quantity: decimal(field("quantity", in: item)) ?? decimal(field("orderedQuantity", in: item)),
                                  createdAt: created)
    }

    static func decimal(_ value: Any?) -> Decimal? {
        switch value {
        case let number as NSNumber: return Decimal(string: number.stringValue)
        case let string as String: return Decimal(string: string)
        default: return nil
        }
    }

    static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber: return number.int64Value
        case let string as String: return Int64(string)
        default: return nil
        }
    }

    // MARK: Transport

    private func object(_ method: String, _ path: String) async throws -> [String: Any] {
        let data = try await send(method, path)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InvestingError.unreadableResponse
        }
        return json
    }

    private func send(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Data {
        guard !apiKey.isEmpty, let url = URL(string: environment.baseURL.absoluteString + path) else {
            throw InvestingError.notConnected
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiSecret, !apiSecret.isEmpty {
            let credentials = Data("\(apiKey):\(apiSecret)".utf8).base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if method == "GET" || error.code == .notConnectedToInternet { throw InvestingError.offline }
            throw InvestingError.outcomeUnknown(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw InvestingError.unreadableResponse }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw InvestingError.unauthorised
        case 403:
            throw InvestingError.missingPermission
        case 429:
            throw InvestingError.rateLimited
        case 500...:
            if method == "GET" { throw InvestingError.rejected("Trading 212 returned an error (\(http.statusCode)).") }
            throw InvestingError.outcomeUnknown("Trading 212 returned \(http.statusCode).")
        default:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["message"] as? String) ?? ($0["code"] as? String) }
            throw InvestingError.rejected(message ?? "Trading 212 declined the request (\(http.statusCode)).")
        }
    }
}
