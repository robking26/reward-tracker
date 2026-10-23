import Foundation
import SwiftUI

// What the Day and battery widgets show, saved by the app through the app group. The widget can't read calendars
// or Apple Health itself, so it draws what the app last worked out.

struct DayWidgetItem: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case mine, work, becky, suggestion, routine
    }

    var id: String
    var title: String
    var start: Date
    var end: Date
    var kind: Kind
    /// 0xRRGGBB, so the widget matches the app's colours.
    var colour: UInt32

    var color: Color {
        Color(.sRGB, red: Double((colour >> 16) & 0xFF) / 255, green: Double((colour >> 8) & 0xFF) / 255,
              blue: Double(colour & 0xFF) / 255, opacity: 1)
    }
}

struct DayWidgetSnapshot: Codable, Hashable, Sendable {
    /// yyyy-MM-dd.
    var day: String
    /// "Office day", "Home day", "Day off", "Annual leave".
    var headline: String
    var items: [DayWidgetItem]
    var updatedAt: Date

    static let placeholder: DayWidgetSnapshot = {
        let start = Calendar.current.startOfDay(for: .now)
        func at(_ hour: Double) -> Date { start.addingTimeInterval(hour * 3_600) }
        return DayWidgetSnapshot(day: WidgetSnapshot.dayString(for: .now), headline: "Home day", items: [
            DayWidgetItem(id: "1", title: "Stand-up", start: at(9.5), end: at(9.75), kind: .work, colour: 0x8CCBFF),
            DayWidgetItem(id: "2", title: "Design review", start: at(11), end: at(12), kind: .work, colour: 0x8CCBFF),
            DayWidgetItem(id: "3", title: "Gym · PureGym", start: at(17.75), end: at(19.25), kind: .suggestion, colour: 0xC5F277),
            DayWidgetItem(id: "4", title: "Night routine", start: at(21), end: at(21.5), kind: .routine, colour: 0xB8A5FF),
        ], updatedAt: .now)
    }()
}

struct BatteryWidgetSnapshot: Codable, Hashable, Sendable {
    /// 0 to 400 quarter-percents.
    var quarters: Int
    var thisWeekQuarters: Int
    var daysLeft: Int
    var chargedToday: Bool
    var updatedAt: Date

    var percent: Double { Double(quarters) / 4 }
    static let placeholder = BatteryWidgetSnapshot(quarters: 25, thisWeekQuarters: 5, daysLeft: 305, chargedToday: true,
                                                   updatedAt: .now)
}

enum PlannerWidgetStore {
    static let dayKind = "FitnessVaultDay"
    static let batteryKind = "FitnessVaultBattery"
    private static let dayKey = "widget.day.v1"
    private static let batteryKey = "widget.battery.v1"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshotStore.appGroup) }

    static func loadDay() -> DayWidgetSnapshot? { load(dayKey) }
    static func loadBattery() -> BatteryWidgetSnapshot? { load(batteryKey) }

    /// Saves and reports whether anything changed, so the widget is only reloaded when it needs to be.
    @discardableResult
    static func save(_ snapshot: DayWidgetSnapshot) -> Bool { save(snapshot, key: dayKey, same: { $0.day == snapshot.day && $0.headline == snapshot.headline && $0.items == snapshot.items }) }

    @discardableResult
    static func save(_ snapshot: BatteryWidgetSnapshot) -> Bool {
        save(snapshot, key: batteryKey, same: { (old: BatteryWidgetSnapshot) in
            old.quarters == snapshot.quarters && old.thisWeekQuarters == snapshot.thisWeekQuarters
                && old.daysLeft == snapshot.daysLeft && old.chargedToday == snapshot.chargedToday
        })
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Codable>(_ snapshot: T, key: String, same: (T) -> Bool) -> Bool {
        if let old: T = load(key), same(old) { return false }
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults?.set(data, forKey: key)
        return true
    }
}
