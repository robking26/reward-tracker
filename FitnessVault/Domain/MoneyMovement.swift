import Foundation

/// Internal Savings Space → Starling main balance transfer status.
enum TransferStatus: String, Codable, CaseIterable, Sendable {
    /// Recorded locally; the bank has not yet confirmed it.
    case requested
    /// Starling confirmed the transfer.
    case confirmed
    /// Starling rejected it. Safe to request again with a new identifier.
    case failed

    /// Counted as money that is on its way out of the Space (or already out).
    var reservesFunds: Bool { self != .failed }
}

/// External Starling → Monzo payment status.
enum PaymentStatus: String, Codable, CaseIterable, Sendable {
    /// Recorded locally, not yet sent to Starling.
    case awaitingInitiation
    /// Starling accepted the order and is waiting for you to approve it in the Starling app.
    case awaitingApproval
    /// Approved and being processed by Starling.
    case processing
    /// Starling confirmed the payment completed.
    case paid
    /// The payment was rejected or declined in Starling.
    case rejected
    /// Starling reported a failure.
    case failed
    /// The outcome is unknown (for example the connection dropped mid-request).
    /// Must be checked before anything else is sent.
    case reconciliationRequired

    var title: String {
        switch self {
        case .awaitingInitiation: "Awaiting initiation"
        case .awaitingApproval: "Awaiting Starling approval"
        case .processing: "Processing"
        case .paid: "Paid to Monzo"
        case .rejected: "Rejected"
        case .failed: "Failed"
        case .reconciliationRequired: "Needs checking"
        }
    }

    var explanation: String {
        switch self {
        case .awaitingInitiation: "This payment hasn't been sent to Starling yet."
        case .awaitingApproval: "Open the Starling app to approve this payment. Nothing has been paid yet."
        case .processing: "Approved in Starling and on its way to Monzo."
        case .paid: "Starling confirmed this payment arrived with your Monzo payee."
        case .rejected: "This payment was declined in Starling. The money is still in your Starling balance."
        case .failed: "Starling couldn't complete this payment. The money is still in your Starling balance."
        case .reconciliationRequired: "We couldn't confirm what happened. Check the status before trying again."
        }
    }

    /// Whether the payment still covers the earnings it was created for.
    /// Unresolved payments always do, which prevents a second payment for the same money.
    var coversEarnings: Bool {
        switch self {
        case .awaitingInitiation, .awaitingApproval, .processing, .paid, .reconciliationRequired: true
        case .rejected, .failed: false
        }
    }

    var isUnresolved: Bool {
        switch self {
        case .awaitingInitiation, .awaitingApproval, .processing, .reconciliationRequired: true
        case .paid, .rejected, .failed: false
        }
    }

    var symbol: String {
        switch self {
        case .awaitingInitiation: "clock"
        case .awaitingApproval: "hand.raised.fill"
        case .processing: "arrow.triangle.2.circlepath"
        case .paid: "checkmark.circle.fill"
        case .rejected, .failed: "xmark.circle.fill"
        case .reconciliationRequired: "exclamationmark.triangle.fill"
        }
    }
}

/// How earned money moves: Earned → Released (Space → main balance) → Paid (main → Monzo).
struct MoneyFlow: Equatable, Sendable {
    var earned: Pence
    var released: Pence
    var releasing: Pence
    var awaitingApproval: Pence
    var processing: Pence
    var paid: Pence
    var needsChecking: Pence
    var failedOrRejected: Pence

    /// Earned but not yet moved out of the Savings Space.
    var awaitingRelease: Pence { (earned - released - releasing).nonNegative }

    init(earned: Pence, transfers: [(amount: Pence, status: TransferStatus)], payments: [(amount: Pence, status: PaymentStatus)]) {
        self.earned = earned
        released = transfers.filter { $0.status == .confirmed }.sum { $0.amount }
        releasing = transfers.filter { $0.status == .requested }.sum { $0.amount }
        awaitingApproval = payments.filter { $0.status == .awaitingApproval || $0.status == .awaitingInitiation }.sum { $0.amount }
        processing = payments.filter { $0.status == .processing }.sum { $0.amount }
        paid = payments.filter { $0.status == .paid }.sum { $0.amount }
        needsChecking = payments.filter { $0.status == .reconciliationRequired }.sum { $0.amount }
        failedOrRejected = payments.filter { $0.status == .failed || $0.status == .rejected }.sum { $0.amount }
    }
}

/// Decides how much may move, and when. Every rule errs towards moving less.
enum SettlementPlanner {
    /// Internal releases are batched to avoid a bank transfer for every Health sample.
    static let minimumRelease: Pence = 100

    /// The amount to move from the Savings Space to the main balance now.
    /// - Parameters:
    ///   - earned: total ledger earnings to date.
    ///   - transfers: every internal transfer recorded.
    ///   - spaceBalance: the Savings Space balance as last reported by Starling.
    ///   - force: release any positive amount (used at settlement time) rather than waiting for a full batch.
    static func releaseAmount(
        earned: Pence,
        transfers: [(amount: Pence, status: TransferStatus)],
        spaceBalance: Pence,
        force: Bool
    ) -> Pence {
        let reserved = transfers.filter { $0.status.reservesFunds }.sum { $0.amount }
        let outstanding = (earned - reserved).nonNegative
        let amount = min(outstanding, spaceBalance.nonNegative)
        if force { return amount }
        return amount >= minimumRelease ? amount : .zero
    }

    enum PaymentDecision: Equatable, Sendable {
        case pay(Pence)
        /// A previous payment hasn't resolved; nothing new is sent until it does.
        case blockedByUnresolvedPayment
        case nothingToPay
    }

    /// The single consolidated Monzo payment to initiate at settlement time.
    /// - Parameters:
    ///   - settleableEarned: earnings from finalised, fully synced days only.
    ///   - releasedConfirmed: money Starling has confirmed is in the main balance.
    ///   - payments: every payment recorded.
    ///   - mainBalance: Starling's current effective main balance.
    static func paymentDecision(
        settleableEarned: Pence,
        releasedConfirmed: Pence,
        payments: [(amount: Pence, status: PaymentStatus)],
        mainBalance: Pence
    ) -> PaymentDecision {
        if payments.contains(where: { $0.status.isUnresolved }) { return .blockedByUnresolvedPayment }
        let covered = payments.filter { $0.status.coversEarnings }.sum { $0.amount }
        let eligible = min(settleableEarned, releasedConfirmed)
        let amount = min((eligible - covered).nonNegative, mainBalance.nonNegative)
        return amount.isPositive ? .pay(amount) : .nothingToPay
    }
}

/// Monthly funding of the Savings Space. Unearned money stays put and counts towards
/// the next allocation, so only the shortfall is ever topped up.
enum VaultFunding {
    struct Plan: Equatable, Sendable {
        /// Unearned money already in the Space that forms part of this month's allocation.
        var carriedForward: Pence
        /// The additional amount to move into the Space.
        var topUpRequired: Pence
        /// Money in the Space above this month's allocation. Never offered as rewards.
        var heldBeyondAllocation: Pence
    }

    static func plan(allocation: Pence, spaceBalance: Pence, reservedForPendingReleases: Pence = .zero) -> Plan {
        let available = (spaceBalance - reservedForPendingReleases).nonNegative
        let carried = min(available, allocation)
        return Plan(
            carriedForward: carried,
            topUpRequired: (allocation - available).nonNegative,
            heldBeyondAllocation: (available - allocation).nonNegative)
    }
}
