import Foundation

/// Starling Bank public API (v2) client using a personal access token.
///
/// Endpoints used (documented at developer.starlingbank.com):
/// - `GET  /api/v2/accounts`
/// - `GET  /api/v2/accounts/{accountUid}/balance`
/// - `GET  /api/v2/account/{accountUid}/savings-goals`
/// - `PUT  /api/v2/account/{accountUid}/savings-goals/{savingsGoalUid}/withdraw-money/{transferUid}`
/// - `PUT  /api/v2/account/{accountUid}/savings-goals/{savingsGoalUid}/add-money/{transferUid}`
/// - `GET  /api/v2/payees`
/// - `PUT  /api/v2/payments/local/account/{accountUid}/category/{categoryUid}`
/// - `GET  /api/v2/payments/local/payment-order/{paymentOrderUid}/payments`
///
/// Payments made with a personal access token must be approved by you in the Starling app.
/// This client never attempts to approve, and never treats an order as paid until Starling says so.
/// The payment request and status shapes must be verified against the sandbox before live use (Phase 5).
struct StarlingClient: BankingService {
    let environment: BankingEnvironment
    let token: String
    let configuration: StarlingConfiguration
    let liveTransfersConfirmed: Bool
    var session: URLSession = .shared

    var isSandbox: Bool { environment == .sandbox }
    var movesRealMoney: Bool { environment == .production }

    // MARK: Discovery

    func accounts() async throws -> [BankAccount] {
        struct Response: Decodable {
            struct Account: Decodable { let accountUid: String; let defaultCategory: String; let name: String?; let currency: String }
            let accounts: [Account]
        }
        let response: Response = try await send("GET", "/api/v2/accounts")
        return response.accounts.filter { $0.currency == "GBP" }
            .map { BankAccount(accountUID: $0.accountUid, defaultCategoryUID: $0.defaultCategory, name: $0.name ?? "Personal") }
    }

    func savingsSpaces(accountUID: String) async throws -> [SavingsSpace] {
        struct Response: Decodable {
            struct Goal: Decodable { let savingsGoalUid: String; let name: String; let totalSaved: Amount? }
            let savingsGoalList: [Goal]
        }
        let response: Response = try await send("GET", "/api/v2/account/\(accountUID)/savings-goals")
        return response.savingsGoalList.map {
            SavingsSpace(uid: $0.savingsGoalUid, name: $0.name, balance: $0.totalSaved?.pence ?? .zero)
        }
    }

    func payeeAccounts() async throws -> [PayeeAccount] {
        struct Response: Decodable {
            struct Payee: Decodable {
                struct Account: Decodable { let payeeAccountUid: String; let description: String?; let accountIdentifier: String? }
                let payeeUid: String
                let payeeName: String
                let accounts: [Account]?
            }
            let payees: [Payee]
        }
        let response: Response = try await send("GET", "/api/v2/payees")
        return response.payees.flatMap { payee in
            (payee.accounts ?? []).map { account in
                PayeeAccount(payeeUID: payee.payeeUid, payeeAccountUID: account.payeeAccountUid, payeeName: payee.payeeName,
                             description: [account.description, account.accountIdentifier.map { "••\($0.suffix(4))" }]
                                .compactMap { $0 }.joined(separator: " "))
            }
        }
    }

    func snapshot() async throws -> BankSnapshot {
        guard let accountUID = configuration.accountUID, let goalUID = configuration.savingsGoalUID else {
            throw BankingError.incompleteSetup
        }
        struct Balance: Decodable { let effectiveBalance: Amount }
        let balance: Balance = try await send("GET", "/api/v2/accounts/\(accountUID)/balance")
        let spaces = try await savingsSpaces(accountUID: accountUID)
        guard let space = spaces.first(where: { $0.uid == goalUID }) else { throw BankingError.incompleteSetup }
        return BankSnapshot(mainBalance: balance.effectiveBalance.pence, spaceBalance: space.balance,
                            spaceName: space.name, fetchedAt: .now)
    }

    // MARK: Money movement

    func releaseFromSpace(amount: Pence, transferID: UUID) async throws {
        try await moveWithinStarling("withdraw-money", amount: amount, transferID: transferID)
    }

    func addToSpace(amount: Pence, transferID: UUID) async throws {
        try await moveWithinStarling("add-money", amount: amount, transferID: transferID)
    }

    private func moveWithinStarling(_ action: String, amount: Pence, transferID: UUID) async throws {
        try guardMoneyMovement()
        guard let accountUID = configuration.accountUID, let goalUID = configuration.savingsGoalUID else {
            throw BankingError.incompleteSetup
        }
        struct Body: Encodable { let amount: Amount }
        struct Response: Decodable { let success: Bool? }
        let path = "/api/v2/account/\(accountUID)/savings-goals/\(goalUID)/\(action)/\(transferID.uuidString.lowercased())"
        let response: Response = try await send("PUT", path, body: Body(amount: Amount(amount)))
        if response.success == false { throw BankingError.http(200, "Starling declined the Savings Space transfer.") }
    }

    func initiatePayment(amount: Pence, externalID: UUID, reference: String) async throws -> PaymentInitiationResult {
        try guardMoneyMovement()
        guard let accountUID = configuration.accountUID, let categoryUID = configuration.defaultCategoryUID,
              let payeeAccountUID = configuration.payeeAccountUID
        else { throw BankingError.incompleteSetup }

        struct Body: Encodable {
            let externalIdentifier: String
            let destinationPayeeAccountUid: String
            let reference: String
            let amount: Amount
        }
        struct Response: Decodable { let paymentOrderUid: String }
        do {
            let response: Response = try await send(
                "PUT", "/api/v2/payments/local/account/\(accountUID)/category/\(categoryUID)",
                body: Body(externalIdentifier: externalID.uuidString, destinationPayeeAccountUid: payeeAccountUID,
                           reference: String(reference.prefix(18)), amount: Amount(amount)))
            return .accepted(paymentOrderUID: response.paymentOrderUid)
        } catch BankingError.http(let code, let message) where (400..<500).contains(code) && code != 401 && code != 403 {
            return .rejected(message ?? "Starling rejected the payment (\(code)).")
        }
    }

    func paymentStatus(paymentOrderUID: String) async throws -> PaymentStatus {
        struct Response: Decodable {
            struct Payment: Decodable {
                struct Details: Decodable { let paymentStatus: String?; let description: String? }
                let completedAt: String?
                let rejectedAt: String?
                let paymentStatusDetails: Details?
            }
            let payments: [Payment]
        }
        let response: Response = try await send("GET", "/api/v2/payments/local/payment-order/\(paymentOrderUID)/payments")
        guard let payment = response.payments.last else {
            // The order exists but no payment has been made from it yet: you haven't approved it.
            return .awaitingApproval
        }
        switch payment.paymentStatusDetails?.paymentStatus?.uppercased() ?? "" {
        case "ACCEPTED" where payment.completedAt != nil: return .paid
        case "REJECTED": return .rejected
        case "PENDING", "ACCEPTED": return .processing
        default:
            if payment.rejectedAt != nil { return .rejected }
            if payment.completedAt != nil { return .paid }
            return .reconciliationRequired
        }
    }

    private func guardMoneyMovement() throws {
        if environment == .production && !liveTransfersConfirmed { throw BankingError.liveTransfersNotConfirmed }
    }

    // MARK: Transport

    private struct Empty: Encodable {}

    private func send<Response: Decodable>(_ method: String, _ path: String) async throws -> Response {
        try await send(method, path, body: Optional<Empty>.none)
    }

    private func send<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body?) async throws -> Response {
        guard !token.isEmpty else { throw BankingError.notConnected }
        var request = URLRequest(url: environment.baseURL.appending(path: path), timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            // A write may have reached Starling before the connection dropped, so its outcome is unknown.
            // Only a write that never left the device is safe to call "offline".
            if method == "GET" || error.code == .notConnectedToInternet { throw BankingError.offline }
            throw BankingError.outcomeUnknown(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw BankingError.unreadableResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw BankingError.unauthorised
        case 500...: throw method == "GET"
            ? BankingError.http(http.statusCode, nil)
            : BankingError.outcomeUnknown("Starling returned \(http.statusCode).")
        default:
            throw BankingError.http(http.statusCode, Self.errorMessage(from: data))
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw BankingError.unreadableResponse
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable {
            struct Item: Decodable { let message: String? }
            let errors: [Item]?
            let error_description: String?
        }
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data) else { return nil }
        return body.errors?.compactMap(\.message).first ?? body.error_description
    }
}

/// Starling's `CurrencyAndAmount`.
private struct Amount: Codable {
    let currency: String
    let minorUnits: Int

    init(_ pence: Pence) {
        currency = "GBP"
        minorUnits = pence.value
    }

    var pence: Pence { currency == "GBP" ? Pence(minorUnits) : .zero }
}
