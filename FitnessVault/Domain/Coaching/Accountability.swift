import Foundation

// Phase 5 accountability: month close, statements, a simulated transfer and the trial review.
// Pure and deterministic. Nothing here can move money: a transfer plan is a description, not an instruction to a bank.

/// When a month's record is frozen (D-029). The last day of a month can be confirmed on the 1st and is assumed
/// missed after that (D-014), so a month closes on the 3rd of the next month.
enum MonthCloseRule {
    static let closeDayOfNextMonth = 3

    static func closesOn(_ month: MonthKey) -> DayKey {
        let next = month.month == 12 ? MonthKey(year: month.year + 1, month: 1) : MonthKey(year: month.year, month: month.month + 1)
        return DayKey(year: next.year, month: next.month, day: closeDayOfNextMonth)
    }

    static func canClose(_ month: MonthKey, today: DayKey) -> Bool {
        today >= closesOn(month)
    }
}

/// One change to a day's fine, for the append-only ledger (A8: audit trail).
struct FineChange: Hashable, Sendable {
    var before: Pence
    var after: Pence
    var reason: String
}

enum FineLedger {
    /// The change to record when a day is reconciled or recalculated, or nil when nothing changed.
    /// A day's first reconciliation is always recorded, even at £0, so every scored day has an entry.
    static func change(wasFinalised: Bool, before: Pence, after: Pence, scorePercent: Int?) -> FineChange? {
        let score = scorePercent.map { "\($0)%" } ?? "no score"
        if !wasFinalised {
            return FineChange(before: .zero, after: after, reason: "Day reconciled at \(score)")
        }
        guard before != after else { return nil }
        return FineChange(before: before, after: after, reason: "Recalculated at \(score) after a correction")
    }
}

/// A finished day as the statement and review need it.
struct ScoredDay: Hashable, Sendable {
    var day: DayKey
    var scorePercent: Int?
    var fine: Pence
    var uncappedFine: Pence
}

/// The month's numbers once it closes (A3: £500 minus confirmed fines; fines stay in Starling).
struct MonthStatementSummary: Hashable, Sendable {
    var month: MonthKey
    var allocation: Pence
    var fines: Pence
    var daysScored: Int
    var daysWithFines: Int
    var averageScore: Int?
    /// Fines that the cap stopped.
    var capSaved: Pence

    var transferable: Pence { (allocation - fines).nonNegative }

    init(month: MonthKey, days: [ScoredDay], allocation: Pence, schedule: FineSchedule) {
        self.month = month
        self.allocation = allocation
        let scored = days.filter { $0.scorePercent != nil }
        // Recorded fines were capped as they happened; cap the total again so a bad record can never exceed it.
        let total = days.sum(\.fine)
        fines = Swift.min(total, Swift.min(schedule.monthlyCap, allocation)).nonNegative
        daysScored = scored.count
        daysWithFines = days.filter { $0.fine.isPositive }.count
        averageScore = scored.isEmpty ? nil : scored.compactMap(\.scorePercent).reduce(0, +) / scored.count
        capSaved = (days.sum(\.uncappedFine) - fines).nonNegative
    }
}

enum TransferMode: String, Codable, Sendable {
    /// The trial: nothing is sent to any bank.
    case simulated
    /// The user moves the money themselves and confirms it here (brief §22 fallback).
    case manual
}

/// What would move at month end, described for the user. Executing it is deliberately not implemented (A7, D-030).
struct TransferPlan: Hashable, Sendable {
    var month: MonthKey
    var amount: Pence
    var mode: TransferMode
    /// The same key for the same month, so a later real integration could never pay a month twice.
    var idempotencyKey: String
    var reference: String

    init(month: MonthKey, amount: Pence, mode: TransferMode) {
        self.month = month
        self.amount = amount.nonNegative
        self.mode = mode
        idempotencyKey = "vaultality-month-\(month.description)"
        reference = "Vaultality \(month.description)"
    }

    var instruction: String {
        switch mode {
        case .simulated:
            return amount.isPositive
                ? "Trial: no money moves. If this were live, \(amount.formatted()) would go from Starling to Monzo with the reference \"\(reference)\". The fines stay in Starling."
                : "Trial: no money moves. Fines reached the full allocation, so nothing would transfer this month."
        case .manual:
            return amount.isPositive
                ? "Move \(amount.formatted()) from Starling to Monzo yourself, with the reference \"\(reference)\", then confirm it here. The rest stays in Starling."
                : "Nothing to move this month."
        }
    }
}

/// A plain summary of the trial so the rules can be reviewed with real data (A7). Observations, never pressure.
struct TrialReview: Hashable, Sendable {
    var daysScored: Int
    var averageScore: Int?
    struct BandCount: Hashable, Sendable {
        var label: String
        var days: Int
    }

    struct KindCount: Hashable, Sendable {
        var kind: CommitmentKind
        var count: Int
    }

    /// Days per fine band, highest band first: "80–100%", "60–79%", ….
    var bandCounts: [BandCount]
    var simulatedFines: Pence
    var capSaved: Pence
    var missedByKind: [KindCount]
    var assumedMissed: Int
    var excused: Int
    var observations: [String]

    /// Enough scored days to say anything useful.
    static let minimumDays = 14

    var isReady: Bool { daysScored >= Self.minimumDays }

    struct Outcome: Hashable, Sendable {
        var kind: CommitmentKind
        var state: CommitmentState
        var assumedMissed: Bool
    }

    init(days: [ScoredDay], outcomes: [Outcome], schedule: FineSchedule) {
        let scored = days.filter { $0.scorePercent != nil }
        daysScored = scored.count
        averageScore = scored.isEmpty ? nil : scored.compactMap(\.scorePercent).reduce(0, +) / scored.count
        let bands = schedule.bands.sorted { $0.minimumPercent > $1.minimumPercent }
        var counts: [BandCount] = []
        var upper = 100
        for band in bands {
            let label = band.minimumPercent == 0 ? "Below \(upper + 1)%" : "\(band.minimumPercent)–\(upper)%"
            let count = scored.filter { day in
                guard let score = day.scorePercent else { return false }
                return score >= band.minimumPercent && score <= upper
            }.count
            counts.append(BandCount(label: label, days: count))
            upper = band.minimumPercent - 1
        }
        bandCounts = counts
        simulatedFines = days.sum(\.fine)
        capSaved = (days.sum(\.uncappedFine) - simulatedFines).nonNegative
        let missed = outcomes.filter { $0.state == .missed }
        let grouped = Dictionary(grouping: missed, by: \.kind).map { KindCount(kind: $0.key, count: $0.value.count) }
        missedByKind = grouped.sorted { $0.count != $1.count ? $0.count > $1.count : $0.kind.rawValue < $1.kind.rawValue }
        assumedMissed = missed.filter(\.assumedMissed).count
        excused = outcomes.filter { $0.state == .excused }.count

        var notes: [String] = []
        if missed.count > 0, assumedMissed * 2 >= missed.count {
            notes.append("Half or more of the misses were never answered rather than actually missed. Answering \"Did you do this?\" each morning would make the score more accurate.")
        }
        if let top = missedByKind.first, top.count >= 3 {
            notes.append("\(top.kind.title) was missed most (\(top.count) times). It may need a different time, a smaller version, or fewer days.")
        }
        if let average = averageScore, average < 60 {
            notes.append("The average day was \(average)%. Agreeing to fewer things may be more realistic than raising the stakes.")
        }
        if capSaved.isPositive {
            notes.append("The monthly cap stopped \(capSaved.formatted()) of fines.")
        }
        if notes.isEmpty, daysScored > 0 {
            notes.append("No pattern stands out yet.")
        }
        observations = notes
    }
}
