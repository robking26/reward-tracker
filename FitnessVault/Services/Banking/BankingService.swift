import Foundation

struct BankAccount: Hashable, Sendable, Identifiable {
    var id: String { accountUID }
    let accountUID: String
    let defaultCategoryUID: String
    let name: String
}

struct SavingsSpace: Hashable, Sendable, Identifiable {
    var id: String { uid }
    let uid: String
    let name: String
    let balance: Pence
}

struct PayeeAccount: Hashable, Sendable, Identifiable {
    var id: String { payeeAccountUID }
    let payeeUID: String
    let payeeAccountUID: String
    let payeeName: String
    let description: String
}

struct BankSnapshot: Equatable, Sendable {
    var mainBalance: Pence
    var spaceBalance: Pence
    var spaceName: String
    var fetchedAt: Date
}

enum PaymentInitiationResult: Equatable, Sendable {
    /// Starling accepted the order. It still needs your approval in the Starling app.
    case accepted(paymentOrderUID: String)
    /// The request was rejected outright; nothing was created.
    case rejected(String)
}

enum BankingError: LocalizedError, Equatable {
    case notConnected
    case incompleteSetup
    case liveTransfersNotConfirmed
    case offline
    case unauthorised
    case http(Int, String?)
    /// The request may or may not have reached Starling. The outcome must be checked, not retried blindly.
    case outcomeUnknown(String)
    case unreadableResponse

    var errorDescription: String? {
        switch self {
        case .notConnected: "Starling isn't connected."
        case .incompleteSetup: "Choose your account, Savings Space and Monzo payee in Settings."
        case .liveTransfersNotConfirmed: "Live transfers are switched off. Confirm them in Settings first."
        case .offline: "You're offline. Banking actions will resume when you reconnect."
        case .unauthorised: "Starling rejected the access token. Reconnect in Settings."
        case .http(let code, let message): message ?? "Starling returned an error (\(code))."
        case .outcomeUnknown(let detail): "We couldn't confirm the result: \(detail)"
        case .unreadableResponse: "Starling returned an unexpected response."
        }
    }
}

/// Everything the app needs from a bank. Mockable so no test or preview can move real money.
protocol BankingService: Sendable {
    var isSandbox: Bool { get }
    var movesRealMoney: Bool { get }

    func accounts() async throws -> [BankAccount]
    func savingsSpaces(accountUID: String) async throws -> [SavingsSpace]
    func payeeAccounts() async throws -> [PayeeAccount]
    func snapshot() async throws -> BankSnapshot
    /// Moves money from the Savings Space to the main balance. `transferID` makes retries idempotent.
    func releaseFromSpace(amount: Pence, transferID: UUID) async throws
    /// Moves money into the Savings Space. Used for the monthly top-up.
    func addToSpace(amount: Pence, transferID: UUID) async throws
    /// Creates one payment to the existing Monzo payee. It still needs approval in the Starling app.
    func initiatePayment(amount: Pence, externalID: UUID, reference: String) async throws -> PaymentInitiationResult
    func paymentStatus(paymentOrderUID: String) async throws -> PaymentStatus
}
