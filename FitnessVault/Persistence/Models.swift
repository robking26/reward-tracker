import Foundation
import SwiftData

// SwiftData entities. Money is always stored as integer pence.

@Model
final class MonthlyVault {
    @Attribute(.unique) var month: String
    var allocationPence: Int
    /// Space balance reported by Starling when the month was opened, if known.
    var openingSpaceBalancePence: Int?
    var carriedForwardPence: Int
    var topUpRequiredPence: Int
    var createdAt: Date
    /// Set once month-end settlement has run. Optional so stores from earlier versions open cleanly.
    var closedAt: Date?
    var finalEarnedPence: Int?
    /// Unearned allowance at month-end, set aside for the gold investment.
    var forfeitedPence: Int?

    init(month: MonthKey, allocation: Pence, openingSpaceBalance: Pence?, plan: VaultFunding.Plan?) {
        self.month = month.description
        allocationPence = allocation.value
        openingSpaceBalancePence = openingSpaceBalance?.value
        carriedForwardPence = plan?.carriedForward.value ?? 0
        topUpRequiredPence = plan?.topUpRequired.value ?? 0
        createdAt = .now
    }

    var monthKey: MonthKey? { MonthKey(string: month) }
    var allocation: Pence { Pence(allocationPence) }
}

@Model
final class DailyActivity {
    @Attribute(.unique) var day: String
    var steps: Int
    var swimmingMetres: Int
    /// Added later; optional so stores from earlier versions open without migration.
    var runningMetres: Int?
    var strengthSeconds: Int
    var exerciseSeconds: Int
    var activeKilocalories: Int
    var flightsClimbed: Int
    /// Apple Health workout UUIDs counted towards strength, so a workout is never counted twice.
    var strengthWorkoutIDs: [String]
    var updatedAt: Date

    init(day: DayKey) {
        self.day = day.description
        steps = 0
        swimmingMetres = 0
        strengthSeconds = 0
        exerciseSeconds = 0
        activeKilocalories = 0
        flightsClimbed = 0
        strengthWorkoutIDs = []
        updatedAt = .now
    }

    var dayKey: DayKey? { DayKey(string: day) }
}

@Model
final class RewardLedgerEntry {
    @Attribute(.unique) var id: String
    var day: String
    var month: String
    var categoryRaw: String
    var amountPence: Int
    var kindRaw: String
    var createdAt: Date

    init(line: LedgerLine) {
        id = line.id
        day = line.day.description
        month = line.day.monthKey.description
        categoryRaw = line.category.rawValue
        amountPence = line.amount.value
        kindRaw = line.kind.rawValue
        createdAt = .now
    }

    var amount: Pence { Pence(amountPence) }
    var category: RewardCategory? { RewardCategory(rawValue: categoryRaw) }

    var line: LedgerLine? {
        guard let dayKey = DayKey(string: day), let category else { return nil }
        return LedgerLine(id: id, day: dayKey, category: category, amount: amount,
                          kind: LedgerLine.Kind(rawValue: kindRaw) ?? .accrual)
    }
}

/// Retired: nutrition is no longer part of the app. The model stays in the schema only so stores
/// created by earlier versions keep opening without a migration. Nothing reads or writes it.
@Model
final class Meal {
    @Attribute(.unique) var id: UUID
    var loggedAt: Date
    var day: String
    var name: String
    var items: [String]
    var kilocalories: Int
    var proteinGrams: Int
    var carbohydrateGrams: Int
    var fatGrams: Int
    var confidenceRaw: String
    var isRewardEligible: Bool
    var imageHash: Int64
    @Attribute(.externalStorage) var thumbnailJPEG: Data?
    var savedToHealth: Bool

    init(id: UUID = UUID(), loggedAt: Date, name: String) {
        self.id = id
        self.loggedAt = loggedAt
        day = DayKey(loggedAt).description
        self.name = name
        items = []
        kilocalories = 0
        proteinGrams = 0
        carbohydrateGrams = 0
        fatGrams = 0
        confidenceRaw = "low"
        isRewardEligible = false
        imageHash = 0
        thumbnailJPEG = nil
        savedToHealth = false
    }
}

@Model
final class HealthSyncState {
    @Attribute(.unique) var key: String
    var lastSuccessfulSync: Date?
    var lastAttempt: Date?
    var lastError: String?
    /// The latest day whose rewards are final (`yyyy-MM-dd`).
    var finalisedThrough: String?

    init() { key = "default" }
}

@Model
final class BankTransfer {
    /// Also sent to Starling as the transfer UID, which makes retries idempotent.
    @Attribute(.unique) var id: UUID
    var amountPence: Int
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var isSandbox: Bool
    var note: String?
    /// nil for releases of earned money; "gold" when moving forfeited money out for investment.
    var purpose: String?

    init(id: UUID = UUID(), amount: Pence, isSandbox: Bool) {
        self.id = id
        amountPence = amount.value
        statusRaw = TransferStatus.requested.rawValue
        createdAt = .now
        updatedAt = .now
        self.isSandbox = isSandbox
    }

    var amount: Pence { Pence(amountPence) }
    var status: TransferStatus {
        get { TransferStatus(rawValue: statusRaw) ?? .requested }
        set { statusRaw = newValue.rawValue; updatedAt = .now }
    }
}

@Model
final class PaymentOrder {
    /// Sent to Starling as the external identifier.
    @Attribute(.unique) var id: UUID
    var amountPence: Int
    var statusRaw: String
    var starlingPaymentOrderUID: String?
    var reference: String
    /// The last activity day whose earnings this payment covers.
    var coversThroughDay: String
    var createdAt: Date
    var updatedAt: Date
    var isSandbox: Bool
    var lastStatusDetail: String?
    /// nil for Monzo payouts of earnings; "goldFunding" for sending forfeited money to Trading 212.
    var purpose: String?

    init(id: UUID = UUID(), amount: Pence, reference: String, coversThrough: DayKey, isSandbox: Bool) {
        self.id = id
        amountPence = amount.value
        statusRaw = PaymentStatus.awaitingInitiation.rawValue
        self.reference = reference
        coversThroughDay = coversThrough.description
        createdAt = .now
        updatedAt = .now
        self.isSandbox = isSandbox
    }

    var amount: Pence { Pence(amountPence) }
    var status: PaymentStatus {
        get { PaymentStatus(rawValue: statusRaw) ?? .reconciliationRequired }
        set { statusRaw = newValue.rawValue; updatedAt = .now }
    }
}

/// A month's forfeited spending and its journey into a gold ETC. One per month, at most.
@Model
final class GoldAllocation {
    @Attribute(.unique) var month: String
    var id: UUID
    var allocatedPence: Int
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var lastDetail: String?
    /// Starling transfer out of the Space and payment to Trading 212, if the app made them.
    var fundingTransferID: UUID?
    var fundingPaymentID: UUID?
    var isDemoBroker: Bool?
    var ticker: String?
    /// Decimal strings, so quantities are stored exactly.
    var orderQuantity: String?
    var orderID: Int64?
    var orderPlacedAt: Date?
    var filledQuantity: String?
    var filledValuePence: Int?

    init(month: MonthKey, allocated: Pence) {
        self.month = month.description
        id = UUID()
        allocatedPence = allocated.value
        statusRaw = InvestmentStatus.awaitingFunding.rawValue
        createdAt = .now
        updatedAt = .now
    }

    var allocated: Pence { Pence(allocatedPence) }
    var monthKey: MonthKey? { MonthKey(string: month) }
    var status: InvestmentStatus {
        get { InvestmentStatus(rawValue: statusRaw) ?? .reconciliationRequired }
        set { statusRaw = newValue.rawValue; updatedAt = .now }
    }
    /// Uninvested remainder left as cash in Trading 212 after the purchase.
    var residual: Pence? { filledValuePence.map { (allocated - Pence($0)).nonNegative } }
}

/// Append-only audit trail for every financial event.
@Model
final class AuditEvent {
    var id: UUID
    var date: Date
    var kind: String
    var message: String
    var relatedID: String?

    init(kind: String, message: String, relatedID: String? = nil) {
        id = UUID()
        date = .now
        self.kind = kind
        self.message = message
        self.relatedID = relatedID
    }
}

enum Persistence {
    static let schema = Schema([
        MonthlyVault.self, DailyActivity.self, RewardLedgerEntry.self, Meal.self,
        HealthSyncState.self, BankTransfer.self, PaymentOrder.self, AuditEvent.self, GoldAllocation.self,
        // Gym and rehab
        WorkoutSession.self, SetLog.self, SymptomLog.self,
        // Kitchen
        Recipe.self, MealPlanEntry.self, InventoryItem.self, ReceiptRecord.self, ShoppingItem.self,
        // Retired 2.0 coaching data, kept so existing stores open (RetiredModels.swift)
        Commitment.self, CommitmentEvent.self, Routine.self, DayRecord.self, CoachMessage.self,
        MemoryRecord.self, TaskItem.self, FineLedgerEntry.self, MonthStatement.self,
        SocialPlan.self, RecoveryPeriod.self, GymBusynessRecord.self, OutingSuggestion.self,
        PlanFeedback.self, DayCheckIn.self, PlanAuditRecord.self,
    ])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the Vaultality store: \(error)")
        }
    }
}
