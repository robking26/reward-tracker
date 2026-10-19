import SwiftUI

// The single-page earnings dashboard was replaced by the Today, Coach, Calendar and Progress tabs (D-004).
// Movement tiles now live in Progress.

enum DayLabel {
    @MainActor
    static func text(_ day: DayKey, model: AppModel) -> String {
        if day == model.today { return "Today" }
        if day == model.today.adding(days: -1, calendar: model.calendar) { return "Yesterday" }
        return day.startDate(calendar: model.calendar).formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}
