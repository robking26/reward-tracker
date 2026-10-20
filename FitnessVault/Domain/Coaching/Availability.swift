import Foundation

/// What an entry in the consolidated calendar means for the user's time (N4).
enum BlockKind: String, Codable, Sendable, CaseIterable {
    case workMeeting
    case workFocus
    case personal
    /// Becky's events on the shared calendar: context, never "busy" by themselves.
    case sharedInfo
    case allDayInfo
    case coachCommitment
    case travel

    /// Whether this block stops the user doing something else.
    var blocksUser: Bool {
        switch self {
        case .workMeeting, .workFocus, .personal, .coachCommitment, .travel: true
        case .sharedInfo, .allDayInfo: false
        }
    }
}

struct BusyBlock: Hashable, Sendable {
    var interval: DateInterval
    var kind: BlockKind
    var title: String = ""
}

enum Workload: String, Codable, CaseIterable, Sendable {
    case light, normal, heavy

    var title: String { rawValue.capitalized }
}

/// The shape of one day (D-010). Minutes are minutes after local midnight.
struct DayShape: Hashable, Sendable {
    var wakeMinute = 5 * 60 + 55
    var bedtimeMinute = 22 * 60 + 30
    var isWorkday = true
    var workStartMinute = 8 * 60
    var workEndMinute = 16 * 60
    var lunchStartMinute = 12 * 60
    var lunchEndMinute = 13 * 60
}

/// A stretch of time something could happen in.
enum WindowKind: String, Hashable, Sendable {
    /// Personal time outside work.
    case free
    /// The lunch break.
    case lunch
    /// Inside working hours with no meeting or focus block. Only for short tasks the user confirms (scenario F);
    /// never for discretionary activities without explicit approval (S2).
    case workGap
}

struct OpportunityWindow: Hashable, Sendable {
    var interval: DateInterval
    var kind: WindowKind

    var minutes: Int { Int(interval.duration / 60) }
}

/// What an activity needs, door to door (L1).
struct ActivityNeed: Hashable, Sendable {
    var activeMinutes: Int
    var travelMinutesEachWay = 0
    var preparationMinutes = 0
    var allowedKinds: Set<WindowKind> = [.free]

    var totalMinutes: Int { activeMinutes + preparationMinutes + travelMinutesEachWay * 2 }
}

/// Deterministic availability (S1–S2). A blank calendar slot isn't automatically free time.
enum Availability {
    /// Work gaps can only hold tasks this short (D-011).
    static let workGapLimitMinutes = 15
    static let minimumWindowMinutes = 5

    static func windows(on day: DayKey, shape: DayShape, blocks: [BusyBlock], notBefore now: Date? = nil,
                        calendar: Calendar = .current) -> [OpportunityWindow] {
        func at(_ minute: Int) -> Date {
            day.date(atMinute: minute, calendar: calendar)
        }

        var segments: [(DateInterval, WindowKind)] = []
        func add(_ start: Int, _ end: Int, _ kind: WindowKind) {
            let lower = max(start, shape.wakeMinute), upper = min(end, shape.bedtimeMinute)
            guard upper > lower else { return }
            segments.append((DateInterval(start: at(lower), end: at(upper)), kind))
        }

        if shape.isWorkday {
            add(shape.wakeMinute, shape.workStartMinute, .free)
            add(shape.workStartMinute, shape.lunchStartMinute, .workGap)
            add(shape.lunchStartMinute, shape.lunchEndMinute, .lunch)
            add(shape.lunchEndMinute, shape.workEndMinute, .workGap)
            add(shape.workEndMinute, shape.bedtimeMinute, .free)
        } else {
            add(shape.wakeMinute, shape.bedtimeMinute, .free)
        }

        let busy = blocks.filter { $0.kind.blocksUser }.map(\.interval)
        var result: [OpportunityWindow] = []
        for (segment, kind) in segments {
            for piece in subtract(busy, from: segment) {
                var piece = piece
                if let now {
                    guard piece.end > now else { continue }
                    if piece.start < now { piece = DateInterval(start: now, end: piece.end) }
                }
                guard piece.duration >= TimeInterval(minimumWindowMinutes * 60) else { continue }
                result.append(OpportunityWindow(interval: piece, kind: kind))
            }
        }
        return result.sorted { $0.interval.start < $1.interval.start }
    }

    /// The first window that fits the whole door-to-door need, if any.
    static func firstFit(_ need: ActivityNeed, in windows: [OpportunityWindow]) -> OpportunityWindow? {
        windows.first { window in
            guard need.allowedKinds.contains(window.kind) else { return false }
            if window.kind == .workGap && need.totalMinutes > workGapLimitMinutes { return false }
            return window.minutes >= need.totalMinutes
        }
    }

    /// Every window that fits.
    static func fits(_ need: ActivityNeed, in windows: [OpportunityWindow]) -> [OpportunityWindow] {
        windows.filter { firstFit(need, in: [$0]) != nil }
    }

    /// `interval` minus every busy interval, in order.
    static func subtract(_ busy: [DateInterval], from interval: DateInterval) -> [DateInterval] {
        var pieces = [interval]
        for block in busy.sorted(by: { $0.start < $1.start }) {
            var next: [DateInterval] = []
            for piece in pieces {
                guard block.start < piece.end && block.end > piece.start else {
                    next.append(piece)
                    continue
                }
                if block.start > piece.start {
                    next.append(DateInterval(start: piece.start, end: block.start))
                }
                if block.end < piece.end {
                    next.append(DateInterval(start: block.end, end: piece.end))
                }
            }
            pieces = next
        }
        return pieces
    }
}
