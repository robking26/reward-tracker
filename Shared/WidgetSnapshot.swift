import Foundation

/// Progress on one Activity ring, as recorded in Apple Health.
struct RingProgress: Codable, Hashable, Sendable {
    var value: Double
    var goal: Double

    var fraction: Double { goal > 0 ? max(0, value / goal) : 0 }
}

/// Today's Move, Exercise and Stand rings.
struct ActivityRingsSnapshot: Codable, Hashable, Sendable {
    var move: RingProgress
    var exercise: RingProgress
    var stand: RingProgress
    /// "kcal", or "min" when Move is set to Move Time.
    var moveUnit: String
}

/// One reward input's contribution today, e.g. Exercise · 32 min · £1.92.
struct WidgetCategoryLine: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var symbol: String
    /// The measurement, already formatted, e.g. "8,412 steps" or "32 min".
    var detail: String
    var earnedPence: Int
}

/// One Apple Health measurement for today, e.g. Exercise · 32 min.
struct WidgetMetric: Codable, Hashable, Sendable, Identifiable {
    /// The reward category it belongs to, so the widget can show what it earned.
    var id: String
    var title: String
    var symbol: String
    /// Already formatted, e.g. "8,412".
    var value: String
    var unit: String
}

/// What the app shares with its widget. Written by the app after each sync; the widget only reads it.
struct WidgetSnapshot: Codable, Hashable, Sendable {
    /// The local calendar day the numbers belong to, `yyyy-MM-dd`.
    var day: String
    var earnedTodayPence: Int
    var steps: Int
    /// Every input that earned money today, highest first. Optional so older saved snapshots still load.
    var breakdown: [WidgetCategoryLine]?
    var rings: ActivityRingsSnapshot?
    /// Today's headline Health numbers, whether or not they earned anything. Optional so older snapshots still load.
    var metrics: [WidgetMetric]?
    var monthEarnedPence: Int
    var monthAllocationPence: Int
    var isDemo: Bool
    /// When Apple Health was last read, so the widget can say how fresh the numbers are.
    var updatedAt: Date

    func isForToday(_ now: Date = .now, calendar: Calendar = .current) -> Bool {
        day == Self.dayString(for: now, calendar: calendar)
    }

    static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// True when everything except the timestamp matches, so unchanged data doesn't spend the widget's refresh budget.
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        var a = self, b = other
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        return a == b
    }
}

/// Shared storage between the app and the widget, through the app group.
enum WidgetSnapshotStore {
    static let appGroup = "group.com.robking.FitnessVault"
    static let widgetKind = "FitnessVaultToday"
    static let weekWidgetKind = "FitnessVaultWeek"
    private static let key = "widget.snapshot.v1"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }
}

/// Money formatting for the widget, which can't use the app's `Pence` type.
enum WidgetMoney {
    static func format(pence: Int, wholePounds: Bool = false) -> String {
        let style = Decimal.FormatStyle.Currency(code: "GBP", locale: Locale(identifier: "en_GB"))
        let amount = Decimal(pence) / 100
        return wholePounds
            ? amount.formatted(style.precision(.fractionLength(0)))
            : amount.formatted(style)
    }
}

/// What the coach shares with the widget: the next action and today's commitment count.
/// Sensitive commitments (e.g. knee rehab) are flagged so the Lock Screen can stay discreet (WG1).
struct CoachWidgetSnapshot: Codable, Hashable, Sendable {
    var day: String
    var nextTitle: String?
    var nextSymbol: String?
    var nextStart: Date?
    var nextIsSensitive: Bool
    var nextInProgress: Bool
    /// Up to three other things still due today, non-sensitive titles only.
    var stillDue: [String]
    var done: Int
    var total: Int
    var updatedAt: Date
    // Phase 7. Optional so snapshots saved by earlier versions still load.
    /// The current commitment, for the widget's Done button. Nil when there's nothing to mark.
    var nextID: String? = nil
    /// "workout" or "swim" adds a Start workout link.
    var nextKind: String? = nil
    /// The morning "I'm ready" hasn't happened yet.
    var briefingPending: Bool? = nil
    /// The last seven finished days, oldest first: a score, or nil for no score. Never money (WG1).
    var week: [Int?]? = nil
    var workoutsThisWeek: Int? = nil
    var workoutTarget: Int? = nil

    func isForToday(_ now: Date = .now, calendar: Calendar = .current) -> Bool {
        day == WidgetSnapshot.dayString(for: now, calendar: calendar)
    }

    func hasSameContent(as other: CoachWidgetSnapshot) -> Bool {
        var a = self, b = other
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        return a == b
    }
}

enum CoachWidgetStore {
    private static let key = "widget.coach.v1"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshotStore.appGroup) }

    static func load() -> CoachWidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CoachWidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: CoachWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }
}
