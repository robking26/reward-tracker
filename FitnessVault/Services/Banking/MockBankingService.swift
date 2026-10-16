import Foundation

/// In-memory bank for previews, tests and demo mode. It can never move real money.
actor MockBankState {
    var mainBalance: Pence
    var spaceBalance: Pence
    var paymentStatuses: [String: PaymentStatus] = [:]
    var seenTransferIDs: Set<UUID> = []

    init(mainBalance: Pence, spaceBalance: Pence) {
        self.mainBalance = mainBalance
        self.spaceBalance = spaceBalance
    }

    func move(_ amount: Pence, toMain: Bool, id: UUID) throws {
        guard seenTransferIDs.insert(id).inserted else { return }
        if toMain {
            guard amount <= spaceBalance else { throw BankingError.http(422, "Insufficient funds in the Savings Space.") }
            spaceBalance = spaceBalance - amount
            mainBalance = mainBalance + amount
        } else {
            guard amount <= mainBalance else { throw BankingError.http(422, "Insufficient funds.") }
            mainBalance = mainBalance - amount
            spaceBalance = spaceBalance + amount
        }
    }

    func createPayment(_ id: String) { paymentStatuses[id] = .awaitingApproval }
    func status(_ id: String) -> PaymentStatus { paymentStatuses[id] ?? .reconciliationRequired }
    func setStatus(_ status: PaymentStatus, for id: String) { paymentStatuses[id] = status }
}

struct MockBankingService: BankingService {
    let state: MockBankState
    var isSandbox: Bool { true }
    var movesRealMoney: Bool { false }

    init(state: MockBankState = MockBankState(mainBalance: .pounds(250), spaceBalance: .pounds(400))) {
        self.state = state
    }

    func accounts() async throws -> [BankAccount] {
        [BankAccount(accountUID: "mock-account", defaultCategoryUID: "mock-category", name: "Personal (demo)")]
    }

    func savingsSpaces(accountUID: String) async throws -> [SavingsSpace] {
        [SavingsSpace(uid: "mock-space", name: "Vaultality (demo)", balance: await state.spaceBalance)]
    }

    func payeeAccounts() async throws -> [PayeeAccount] {
        [PayeeAccount(payeeUID: "mock-payee", payeeAccountUID: "mock-payee-account", payeeName: "Monzo (demo)", description: "••1234")]
    }

    func snapshot() async throws -> BankSnapshot {
        BankSnapshot(mainBalance: await state.mainBalance, spaceBalance: await state.spaceBalance,
                     spaceName: "Vaultality (demo)", fetchedAt: .now)
    }

    func releaseFromSpace(amount: Pence, transferID: UUID) async throws {
        try await state.move(amount, toMain: true, id: transferID)
    }

    func addToSpace(amount: Pence, transferID: UUID) async throws {
        try await state.move(amount, toMain: false, id: transferID)
    }

    func initiatePayment(amount: Pence, externalID: UUID, reference: String, payeeAccountUID: String) async throws -> PaymentInitiationResult {
        let id = "mock-order-\(externalID.uuidString.prefix(8))"
        await state.createPayment(id)
        return .accepted(paymentOrderUID: id)
    }

    func paymentStatus(paymentOrderUID: String) async throws -> PaymentStatus {
        await state.status(paymentOrderUID)
    }
}
