import SwiftUI

/// The consolidated calendar (N4): external calendars read-only, plus the coach's own commitments and
/// the free windows the coach can see. A blank slot isn't automatically free time.
struct CalendarTabView: View {
    @Environment(CoachModel.self) private var coach
    @Binding var showingSettings: Bool
    @State private var mode: Mode = .day
    @State private var offset = 0

    enum Mode: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    accessNotices

                    switch mode {
                    case .day:
                        dayNavigator
                        DayTimeline(day: selectedDay)
                    case .week:
                        ForEach(0..<7, id: \.self) { index in
                            let day = coach.today.adding(days: index, calendar: coach.calendar)
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(dayTitle(day))
                                    .font(.headline)
                                    .foregroundStyle(Palette.textPrimary)
                                DayTimeline(day: day, compact: true)
                            }
                        }
                    }

                    CalendarLegend()
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.xl)
            }
            .pageBackground()
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton(isPresented: $showingSettings)
                }
            }
            .refreshable { await coach.refresh() }
        }
    }

    private var selectedDay: DayKey { coach.today.adding(days: offset, calendar: coach.calendar) }

    private var dayNavigator: some View {
        HStack {
            Button {
                offset -= 1
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous day")
            Spacer()
            Text(dayTitle(selectedDay))
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Button {
                offset += 1
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next day")
        }
        .foregroundStyle(Palette.textSecondary)
    }

    @ViewBuilder
    private var accessNotices: some View {
        switch coach.calendarAccess {
        case .notDetermined:
            NoticeBanner(symbol: "calendar.badge.plus", title: "Let the coach see your calendars",
                         message: "Read-only. Vaultality never adds, moves or deletes events. Your work calendar is used to protect meetings and focus time.",
                         tint: Palette.accent, actionTitle: "Allow Calendar Access") {
                Task { await coach.requestCalendarAccess() }
            }
        case .denied, .restricted, .writeOnly:
            NoticeBanner(symbol: "calendar.badge.exclamationmark", title: "Calendars not visible",
                         message: "Without calendar access the coach treats 8 to 4 on weekdays as work and can't see your plans. Allow full access in Settings › Privacy & Security › Calendars › Vaultality.")
        case .granted:
            if coach.availableCalendars.contains(where: { coach.calendarRoles[$0.id] == nil }) {
                NavigationLink {
                    CalendarsSettingsView()
                } label: {
                    NoticeBanner(symbol: "tag", title: "Label your calendars",
                                 message: "Tell the coach which calendar is work, which is yours and which is shared with Becky. Unlabelled calendars are ignored.",
                                 tint: Palette.accent)
                }
                .buttonStyle(CardButtonStyle())
            } else if coach.hasNoWorkCalendar {
                NoticeBanner(symbol: "briefcase", title: "No work calendar",
                             message: "If your Outlook work calendar isn't in the iPhone Calendar app, the coach can't see meetings, so it treats 8 to 4 on weekdays as protected work time.")
            }
        }
    }

    private func dayTitle(_ day: DayKey) -> String {
        if day == coach.today { return "Today" }
        if day == coach.today.adding(days: 1, calendar: coach.calendar) { return "Tomorrow" }
        if day == coach.today.adding(days: -1, calendar: coach.calendar) { return "Yesterday" }
        return day.startDate(calendar: coach.calendar).formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

/// One day: all-day items, then events, agreed commitments and free windows in time order.
struct DayTimeline: View {
    @Environment(CoachModel.self) private var coach
    let day: DayKey
    var compact = false

    var body: some View {
        let entries = self.entries
        if entries.isEmpty {
            Text("Nothing scheduled")
                .font(.subheadline)
                .foregroundStyle(Palette.textTertiary)
                .surface()
        } else {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    TimelineRow(entry: entry)
                    if entry.id != entries.last?.id { Divider().overlay(Palette.border) }
                }
            }
            .surface(padding: Spacing.m)
        }
    }

    private var entries: [TimelineEntry] {
        let events = coach.classifiedEvents(on: day)
        let commitments = coach.commitments(on: day).filter { $0.state != .cancelled && $0.state != .rescheduled }
        var result: [TimelineEntry] = events.map { item in
            TimelineEntry(id: "e-" + item.id, start: item.event.start, end: item.event.end, isAllDay: item.event.isAllDay,
                          title: item.event.title, style: .event(item.kind))
        }
        result += commitments.map { item in
            TimelineEntry(id: "c-" + item.id.uuidString, start: item.scheduledStart, end: item.scheduledEnd, isAllDay: false,
                          title: item.title, style: item.state == .proposed ? .suggestion : .commitment(item.state))
        }
        if !compact {
            let isToday = day == coach.today
            let isWorkday = coach.coach.isWorkday(day, calendar: coach.calendar) && !CalendarClassifier.isOnLeave(events)
            let windows = Availability.windows(on: day, shape: coach.coach.shape(isWorkday: isWorkday),
                                               blocks: coach.busyBlocks(on: day, events: events, commitments: commitments),
                                               notBefore: isToday ? coach.now() : nil, calendar: coach.calendar)
            result += windows.filter { $0.kind != .workGap && $0.minutes >= 20 }.map { window in
                TimelineEntry(id: "w-\(window.interval.start.timeIntervalSince1970)", start: window.interval.start,
                              end: window.interval.end, isAllDay: false,
                              title: window.kind == .lunch ? "Lunch break" : "Free", style: .opportunity)
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return (lhs.start ?? .distantFuture) < (rhs.start ?? .distantFuture)
        }
    }
}

struct TimelineEntry: Identifiable {
    enum Style: Equatable {
        case event(BlockKind)
        case commitment(CommitmentState)
        case suggestion
        case opportunity
    }

    var id: String
    var start: Date?
    var end: Date?
    var isAllDay: Bool
    var title: String
    var style: Style
}

struct TimelineRow: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.style.colour)
                .frame(width: 4)
                .opacity(entry.style == .opportunity ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(entry.style == .opportunity ? .regular : .medium))
                    .foregroundStyle(entry.style == .opportunity ? Palette.textSecondary : Palette.textPrimary)
                    .strikethrough(entry.style == .commitment(.completed))
                Text(entry.style.label)
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            Text(timeText)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        if entry.isAllDay { return "All day" }
        guard let start = entry.start else { return "Any time" }
        let from = start.formatted(date: .omitted, time: .shortened)
        guard let end = entry.end else { return from }
        return "\(from)–\(end.formatted(date: .omitted, time: .shortened))"
    }
}

extension TimelineEntry.Style {
    var colour: Color {
        switch self {
        case .event(let kind):
            switch kind {
            case .workMeeting: Color(hex: 0x7FA7E8)
            case .workFocus: Color(hex: 0x4E6FA8)
            case .personal: Color(hex: 0xC59BE8)
            case .sharedInfo: Color(hex: 0xE8A3C1)
            case .allDayInfo: Palette.textTertiary
            case .coachCommitment, .travel: Palette.accent
            }
        case .commitment(let state): state == .completed ? Palette.success : Palette.accent
        case .suggestion: Palette.warning
        case .opportunity: Palette.textTertiary
        }
    }

    var label: String {
        switch self {
        case .event(let kind): kind.label
        case .commitment(let state): "Commitment · \(state.title)"
        case .suggestion: "Coach suggestion"
        case .opportunity: "Flexible opportunity"
        }
    }
}

struct CalendarLegend: View {
    var body: some View {
        let items: [TimelineEntry.Style] = [.event(.workMeeting), .event(.workFocus), .event(.personal),
                                            .event(.sharedInfo), .commitment(.approved), .suggestion, .opportunity]
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: Spacing.xs) {
                    Circle().fill(items[index].colour).frame(width: 8, height: 8)
                    Text(items[index].legendTitle).font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            Text("External calendars are read-only. The coach never changes them.")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
                .padding(.top, Spacing.xxs)
        }
    }
}

extension TimelineEntry.Style {
    var legendTitle: String {
        switch self {
        case .event(.workMeeting): "Work meeting"
        case .event(.workFocus): "Focus time (protected)"
        case .event(.personal): "Personal"
        case .event(.sharedInfo): "Shared with Becky (doesn't make you busy)"
        case .commitment: "Your commitment"
        case .suggestion: "Coach suggestion"
        case .opportunity: "Flexible opportunity"
        default: label
        }
    }
}
