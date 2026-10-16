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

/// What the app shares with its widget. Written by the app after each sync; the widget only reads it.
struct WidgetSnapshot: Codable, Hashable, Sendable {
    /// The local calendar day the numbers belong to, `yyyy-MM-dd`.
    var day: String
    var earnedTodayPence: Int
    var steps: Int
    var rings: ActivityRingsSnapshot?
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
