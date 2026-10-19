import Foundation

/// One band of the daily fine table: a score at or above `minimumPercent` costs `fine`.
struct FineBand: Codable, Hashable, Sendable {
    var minimumPercent: Int
    var fine: Pence
}

/// The experimental fine structure (A2). Configurable; reviewed after the trial month.
struct FineSchedule: Codable, Hashable, Sendable {
    /// Highest threshold first.
    var bands: [FineBand]
    var monthlyCap: Pence

    static let trial = FineSchedule(
        bands: [
            FineBand(minimumPercent: 80, fine: .zero),
            FineBand(minimumPercent: 60, fine: .pounds(5)),
            FineBand(minimumPercent: 40, fine: .pounds(10)),
            FineBand(minimumPercent: 0, fine: .pounds(15)),
        ],
        monthlyCap: .pounds(100))

    /// The fine for a whole-number score, before the monthly cap. Never negative.
    func fine(forPercent percent: Int) -> Pence {
        let sorted = bands.sorted { $0.minimumPercent > $1.minimumPercent }
        for band in sorted where percent >= band.minimumPercent {
            return band.fine.nonNegative
        }
        return sorted.last?.fine.nonNegative ?? .zero
    }

    /// The fine actually recorded once earlier fines this month are taken into account (A6):
    /// never above the monthly cap, never above the allocation, never negative.
    func cappedFine(_ fine: Pence, monthToDate: Pence, allocation: Pence) -> Pence {
        let ceiling = Swift.min(monthlyCap, allocation)
        let room = (ceiling - monthToDate).nonNegative
        return Swift.min(fine.nonNegative, room)
    }
}

/// The minimum a commitment needs for scoring. Deliberately has no field for food, weight or calories (A6).
struct ScoredCommitment: Hashable, Sendable {
    var state: CommitmentState
    var weight: Int
}

/// A day's weighted completion, as far as it's known right now (A5).
struct DayScore: Hashable, Sendable {
    var applicableWeight: Int
    var completedWeight: Int
    /// Approved, in progress or awaiting verification: can still be done.
    var openWeight: Int
    var missedWeight: Int

    init(_ commitments: [ScoredCommitment]) {
        var applicable = 0, completed = 0, open = 0, missed = 0
        for item in commitments where item.state.isApplicable {
            let weight = CommitmentRules.clampedWeight(item.weight)
            applicable += weight
            switch item.state {
            case .completed: completed += weight
            case .missed: missed += weight
            default: if item.state.isOpen { open += weight }
            }
        }
        applicableWeight = applicable
        completedWeight = completed
        openWeight = open
        missedWeight = missed
    }

    /// Nothing agreed today, so there's nothing to score and nothing to fine.
    var isEmpty: Bool { applicableWeight == 0 }
    var isSettled: Bool { openWeight == 0 }

    /// Completed so far, rounded down so it never flatters (scenario J).
    var confirmedPercent: Int? {
        guard !isEmpty else { return nil }
        return completedWeight * 100 / applicableWeight
    }

    /// The best the day can still finish at if every open commitment gets done.
    var possiblePercent: Int? {
        guard !isEmpty else { return nil }
        return (completedWeight + openWeight) * 100 / applicableWeight
    }
}

/// Live financial projection for one day (A5).
struct DayProjection: Hashable, Sendable {
    var score: DayScore
    /// The fine if nothing else gets done today (after the monthly cap).
    var worstCaseFine: Pence
    /// The fine if every remaining commitment gets done (after the monthly cap).
    var bestCaseFine: Pence
    var monthToDateFines: Pence
    var allocation: Pence

    init(score: DayScore, schedule: FineSchedule, monthToDateFines: Pence, allocation: Pence) {
        self.score = score
        self.monthToDateFines = monthToDateFines
        self.allocation = allocation
        if let confirmed = score.confirmedPercent, let possible = score.possiblePercent {
            worstCaseFine = schedule.cappedFine(schedule.fine(forPercent: confirmed),
                                                monthToDate: monthToDateFines, allocation: allocation)
            bestCaseFine = schedule.cappedFine(schedule.fine(forPercent: possible),
                                               monthToDate: monthToDateFines, allocation: allocation)
        } else {
            worstCaseFine = .zero
            bestCaseFine = .zero
        }
    }

    /// What would transfer at month end if today ended at its best case.
    var transferEstimate: Pence { (allocation - monthToDateFines - bestCaseFine).nonNegative }
}

/// Turns a finished day into its final fine (A4–A6).
enum DayReconciliation {
    struct Outcome: Hashable, Sendable {
        var scorePercent: Int?
        var uncappedFine: Pence
        var fine: Pence
        var explanation: String
    }

    /// Only call once no commitment is open. Open items must first become pending verification,
    /// then completed, missed or excused (D-014).
    static func finalise(_ commitments: [ScoredCommitment], schedule: FineSchedule,
                         monthToDateFines: Pence, allocation: Pence) -> Outcome {
        let score = DayScore(commitments)
        guard let percent = score.confirmedPercent else {
            return Outcome(scorePercent: nil, uncappedFine: .zero, fine: .zero,
                           explanation: "Nothing was agreed for this day, so there's no score and no fine.")
        }
        let uncapped = schedule.fine(forPercent: percent)
        let fine = schedule.cappedFine(uncapped, monthToDate: monthToDateFines, allocation: allocation)
        var explanation = "\(percent)% of agreed commitments done (\(score.completedWeight) of \(score.applicableWeight) points)."
        if fine.isPositive {
            explanation += " That's in the \(uncapped.formatted(wholePounds: true)) band."
        } else if uncapped.isPositive {
            explanation += " The \(schedule.monthlyCap.formatted(wholePounds: true)) monthly cap has been reached, so no further fine."
        } else {
            explanation += " No fine."
        }
        if fine.isPositive && fine < uncapped {
            explanation += " Reduced to \(fine.formatted()) by the monthly cap."
        }
        return Outcome(scorePercent: percent, uncappedFine: uncapped, fine: fine, explanation: explanation)
    }
}
