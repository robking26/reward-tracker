import Foundation

/// What the dashboard and vault show for one month.
struct VaultSummary: Equatable, Sendable {
    var month: MonthKey
    var allocation: Pence
    var earned: Pence

    var remainingToUnlock: Pence { (allocation - earned).nonNegative }
    var progress: Double { earned.fraction(of: allocation) }
    var isFullyUnlocked: Bool { allocation.isPositive && earned >= allocation }
    var percentUnlocked: Int { Int((progress * 100).rounded(.down)) }

    static func empty(_ month: MonthKey, allocation: Pence) -> VaultSummary {
        VaultSummary(month: month, allocation: allocation, earned: .zero)
    }
}
