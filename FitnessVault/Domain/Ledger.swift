import Foundation

/// An immutable reward ledger line. Corrections are appended as new lines, never edits,
/// so the ledger is an audit trail.
struct LedgerLine: Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        /// Money earned for newly recorded activity.
        case accrual
        /// A reduction after Apple Health corrected or deleted samples.
        case correction
    }

    /// Stable identifier: `month/day/category/sequence`. Re-running a sync with the
    /// same data yields the same identifiers, so inserts are idempotent.
    let id: String
    let day: DayKey
    let category: RewardCategory
    let amount: Pence
    let kind: Kind

    static func makeID(day: DayKey, category: RewardCategory, sequence: Int) -> String {
        "\(day.monthKey)/\(day)/\(category.rawValue)/\(sequence)"
    }
}

/// Brings a month's ledger in line with freshly calculated rewards without ever
/// exceeding the month's allocation or touching locked days.
enum LedgerReconciler {
    struct Result: Equatable, Sendable {
        var newLines: [LedgerLine]
        /// Rewards that qualified but could not be paid because the vault is fully unlocked.
        var cappedAmount: Pence
    }

    /// - Parameters:
    ///   - existing: every ledger line already recorded for the month.
    ///   - calculated: the latest reward totals per day and category for the month.
    ///   - lockedDays: days whose rewards are final and must not change, even if rates or data change.
    ///   - allocation: the month's vault allocation, which total earnings can never exceed.
    static func reconcile(
        existing: [LedgerLine],
        calculated: [DayKey: [RewardCategory: Pence]],
        lockedDays: Set<DayKey>,
        allocation: Pence
    ) -> Result {
        var recorded: [Key: Pence] = [:]
        var sequence: [Key: Int] = [:]
        for line in existing {
            let key = Key(day: line.day, category: line.category)
            recorded[key, default: .zero] = recorded[key, default: .zero] + line.amount
            sequence[key, default: 0] += 1
        }
        var monthTotal = existing.sum(\.amount)

        var reductions: [(Key, Pence)] = []
        var increases: [(Key, Pence)] = []
        let orderedDays = calculated.keys.sorted()
        for day in orderedDays where !lockedDays.contains(day) {
            for category in RewardCategory.allCases {
                let key = Key(day: day, category: category)
                let target = (calculated[day]?[category] ?? .zero).nonNegative
                let delta = target - recorded[key, default: .zero]
                if delta < .zero { reductions.append((key, delta)) }
                if delta > .zero { increases.append((key, delta)) }
            }
        }

        var lines: [LedgerLine] = []
        func append(_ key: Key, _ amount: Pence, _ kind: LedgerLine.Kind) {
            let next = sequence[key, default: 0]
            sequence[key] = next + 1
            lines.append(LedgerLine(
                id: LedgerLine.makeID(day: key.day, category: key.category, sequence: next),
                day: key.day, category: key.category, amount: amount, kind: kind))
        }

        // Reductions first, so freed allocation is available to later qualifying activity.
        for (key, delta) in reductions {
            append(key, delta, .correction)
            monthTotal = monthTotal + delta
        }

        var capped = Pence.zero
        for (key, delta) in increases {
            let available = (allocation - monthTotal).nonNegative
            let granted = min(delta, available)
            capped = capped + (delta - granted)
            guard granted.isPositive else { continue }
            append(key, granted, .accrual)
            monthTotal = monthTotal + granted
        }
        return Result(newLines: lines, cappedAmount: capped)
    }

    private struct Key: Hashable {
        let day: DayKey
        let category: RewardCategory
    }
}
