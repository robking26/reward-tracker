import Foundation
import WidgetKit

/// Saves what the Day and battery widgets draw, and asks iOS to redraw them only when something changed.
@MainActor
enum PlannerWidgetPublisher {
    static func publishDay(planner: PlannerModel, routines: RoutineModel) {
        guard let picture = planner.picture(for: planner.today) else { return }
        let calendar = planner.calendar
        var items: [DayWidgetItem] = picture.timedEvents
            .filter { $0.source != .beckyVisible && $0.source != .beckyUnconfirmed }
            .map { item in
                DayWidgetItem(id: item.id, title: item.event.title, start: item.event.start, end: item.event.end,
                              kind: kind(item.source), colour: colour(item.source))
            }
        for suggestion in picture.suggestions {
            var title = suggestion.kind.title
            if let venue = suggestion.venueName, suggestion.kind != .batchCook { title += " · \(venue)" }
            items.append(DayWidgetItem(id: suggestion.id, title: title, start: suggestion.leaveAt, end: suggestion.backAt,
                                       kind: .suggestion, colour: colour(suggestion.kind)))
        }
        if routines.isSetUp {
            for part in RoutinePart.allCases {
                let window = routines.window(part, on: picture.day)
                guard window.duration <= 4 * 3_600 else { continue }
                items.append(DayWidgetItem(id: "routine-\(part.rawValue)", title: part.title, start: window.start,
                                           end: window.end, kind: .routine, colour: 0xB8A5FF))
            }
        }
        let snapshot = DayWidgetSnapshot(day: WidgetSnapshot.dayString(for: planner.now(), calendar: calendar),
                                         headline: picture.location.title, items: items.sorted { $0.start < $1.start },
                                         updatedAt: planner.now())
        if PlannerWidgetStore.save(snapshot) { WidgetCenter.shared.reloadTimelines(ofKind: PlannerWidgetStore.dayKind) }
    }

    static func publishBattery(_ battery: LifeBatteryModel) {
        let result = battery.result
        let snapshot = BatteryWidgetSnapshot(quarters: result.quarters, thisWeekQuarters: Int((battery.thisWeek * 4).rounded()),
                                             daysLeft: battery.daysLeft,
                                             chargedToday: result.events.contains { $0.day == battery.today && $0.quarters > 0 },
                                             updatedAt: battery.now())
        if PlannerWidgetStore.save(snapshot) { WidgetCenter.shared.reloadTimelines(ofKind: PlannerWidgetStore.batteryKind) }
    }

    private static func kind(_ source: EventSource) -> DayWidgetItem.Kind {
        switch source {
        case .mine, .workFree: .mine
        case .work: .work
        case .beckyShared, .beckyVisible, .beckyUnconfirmed: .becky
        }
    }

    // The app's palette as hex, so the widget matches.
    private static func colour(_ source: EventSource) -> UInt32 {
        switch source {
        case .mine: 0xC5F277
        case .work: 0x8CCBFF
        case .beckyShared: 0xFF9AA8
        case .workFree: 0x7FE0C3
        case .beckyVisible, .beckyUnconfirmed: 0x7F8884
        }
    }

    private static func colour(_ kind: ActivityKind) -> UInt32 {
        switch kind {
        case .gym: 0xC5F277
        case .swim: 0x8CCBFF
        case .aldiShop, .batchCook: 0xFFB36B
        case .run: 0xFF9AA8
        case .walk: 0x7FE0C3
        }
    }
}
