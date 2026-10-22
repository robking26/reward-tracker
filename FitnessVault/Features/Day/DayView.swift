import SwiftUI

/// The Day tab: your calendar, work Outlook and Becky's calendar in one timeline, with suggestions fitted into the
/// free time: the gym, a swim, the Aldi shop, the batch cook, runs and walks.
struct DayView: View {
    @Environment(AppModel.self) private var model
    @Environment(TrainingModel.self) private var training
    @Environment(KitchenModel.self) private var kitchen
    @Environment(PlannerModel.self) private var planner
    @Binding var showingSettings: Bool
    @State private var selected: DayKey?
    @State private var showingDaySettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    DayStrip(days: planner.days, selected: day, pictures: planner.pictures, calendar: planner.calendar) {
                        selected = $0
                    }

                    if let picture = planner.picture(for: day) {
                        DayHero(picture: picture, isToday: day == planner.today, calendar: planner.calendar)
                    }

                    if !planner.isSetUp {
                        SetupCard { showingDaySettings = true }
                    }

                    if !planner.needsConfirming.isEmpty {
                        BeckyInbox(events: planner.needsConfirming)
                    }

                    if planner.isSetUp && !planner.missingPlaces.isEmpty {
                        NoticeBanner(symbol: "mappin.and.ellipse", title: "Add your places",
                                     message: "Save \(missingText) so drive times and suggestions can include them.",
                                     tint: Palette.frost, actionTitle: "Add places") { showingDaySettings = true }
                    }

                    if let picture = planner.picture(for: day) {
                        Timeline(picture: picture)
                    }

                    Footnote("Drive times from Apple Maps (traffic-aware where Apple has it), plus parking. Directions open in Google Maps. Forecast from Open-Meteo.")
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.xl)
            }
            .pageBackground()
            .navigationTitle("Day")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingDaySettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .accessibilityLabel("Day settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton(isPresented: $showingSettings)
                }
            }
            .refreshable { await reload() }
            .task { await reload() }
            .sheet(isPresented: $showingDaySettings, onDismiss: { Task { await planner.refresh() } }) {
                DaySettingsView()
            }
            .overlay(alignment: .bottom) {
                if let message = planner.message {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, Spacing.s)
                        .background(Palette.elevated, in: Capsule())
                        .padding(.bottom, Spacing.m)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: message) {
                            try? await Task.sleep(for: .seconds(2.5))
                            withAnimation { planner.message = nil }
                        }
                }
            }
        }
    }

    private var day: DayKey { selected.flatMap { planner.days.contains($0) ? $0 : nil } ?? planner.today }

    private var missingText: String {
        let names = planner.missingPlaces.map { $0.title.lowercased() }
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    private func reload() async {
        let swims = (try? await model.health.swims(since: Date.now.addingTimeInterval(-14 * 86_400))) ?? []
        planner.update(training: training, kitchen: kitchen, swims: swims)
        await planner.refresh()
    }
}

// MARK: - Day strip

private struct DayStrip: View {
    let days: [DayKey]
    let selected: DayKey
    let pictures: [DayPicture]
    let calendar: Calendar
    let onSelect: (DayKey) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                Button {
                    onSelect(day)
                } label: {
                    dayLabel(day)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(day.startDate(calendar: calendar).formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .accessibilityAddTraits(day == selected ? .isSelected : [])
            }
        }
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Spacing.xs)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func dayLabel(_ day: DayKey) -> some View {
        let date = day.startDate(calendar: calendar)
        let isSelected = day == selected
        let picture = pictures.first { $0.day == day }
        let tint = DayStyle.tint(picture?.location ?? .dayOff)
        return VStack(spacing: 6) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? tint : Palette.textTertiary)
            Text(date.formatted(.dateTime.day()))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Palette.onAccent : Palette.textPrimary)
                .frame(width: 36, height: 36)
                .background(isSelected ? tint : Palette.elevated, in: Circle())
            HStack(spacing: 2) {
                ForEach((picture?.suggestions ?? []).prefix(3)) { item in
                    Circle()
                        .fill(DayStyle.tint(item.kind))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Hero

private struct DayHero: View {
    let picture: DayPicture
    let isToday: Bool
    let calendar: Calendar

    var body: some View {
        let tint = DayStyle.tint(picture.location)
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(isToday ? "Today" : picture.day.startDate(calendar: calendar).formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(tint)
            Text(picture.location.title)
                .font(.display(32))
                .foregroundStyle(Palette.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ChipFlow().callAsFunction {
                Chip(text: picture.weather ?? "No forecast yet", symbol: WeatherAdvisor.symbol(for: picture.weather))
                Chip(text: "\(PlannerFormat.minutes(picture.freeMinutes)) free", symbol: "clock")
                if !picture.suggestions.isEmpty {
                    Chip(text: "\(picture.suggestions.count) to fit in", symbol: "sparkles", tint: tint,
                         fill: tint.opacity(0.14))
                }
            }
        }
        .heroCard(tint: tint, symbol: DayStyle.symbol(picture.location))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        switch picture.location {
        case .office: "Office focus at 9 am. Evenings start from the office."
        case .home: "Home focus at 9 am."
        case .unknown: "No office or home focus at 9 am in Outlook, so home is assumed."
        case .dayOff: "Nothing from work today."
        }
    }
}

// MARK: - Becky

private struct BeckyInbox: View {
    @Environment(PlannerModel.self) private var planner
    let events: [CalendarEventInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            CardHeader(title: "Becky's new events", symbol: "person.2.fill", tint: Palette.rose,
                       subtitle: "Shared ones join your day")
            ForEach(events.prefix(4)) { event in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(event.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(when(event))
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                    BeckyButtons(event: event)
                }
                .padding(.vertical, Spacing.xxs)
                if event.id != events.prefix(4).last?.id { RowDivider(inset: 0) }
            }
            if events.count > 4 {
                Footnote("\(events.count - 4) more after these. Anything you don't mark stays just so you know.")
            } else {
                Footnote("Anything you don't mark stays just so you know.")
            }
        }
        .surface()
    }

    private func when(_ event: CalendarEventInfo) -> String {
        let date = event.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        if event.isAllDay { return "\(date), all day" }
        return "\(date), \(PlannerFormat.range(event.start, event.end, planner.calendar))"
    }
}

private struct BeckyButtons: View {
    @Environment(PlannerModel.self) private var planner
    let event: CalendarEventInfo

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Button {
                withAnimation { planner.confirm(event, shared: true) }
            } label: {
                Label("Shared", systemImage: "checkmark")
                    .compactPill(ink: Palette.onAccent, fill: Palette.rose)
            }
            Button {
                withAnimation { planner.confirm(event, shared: false) }
            } label: {
                Label("Hers only", systemImage: "eye")
                    .compactPill(ink: Palette.textPrimary, fill: Palette.elevated)
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timeline

private enum TimelineEntry: Identifiable {
    case event(DayEvent)
    case suggestion(Suggestion)

    var id: String {
        switch self {
        case .event(let item): "e-\(item.id)"
        case .suggestion(let item): "s-\(item.id)"
        }
    }

    var start: Date {
        switch self {
        case .event(let item): item.event.start
        case .suggestion(let item): item.leaveAt
        }
    }
}

private struct Timeline: View {
    @Environment(PlannerModel.self) private var planner
    let picture: DayPicture

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionTitle(title: "Plan", detail: picture.suggestions.isEmpty ? nil : "Suggestions are dashed")
            if !picture.allDayEvents.isEmpty {
                ChipFlow().callAsFunction {
                    ForEach(picture.allDayEvents) { item in
                        Chip(text: item.event.title, symbol: "sun.max", tint: DayStyle.tint(item.source),
                             fill: DayStyle.tint(item.source).opacity(0.12))
                    }
                }
            }
            if entries.isEmpty {
                Text(planner.isSetUp ? "Nothing in the diary and nothing left to fit in." : "Set up your calendars to see your day.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surface()
            }
            ForEach(entries) { entry in
                switch entry {
                case .event(let item): EventRow(item: item)
                case .suggestion(let item): SuggestionCard(suggestion: item)
                }
            }
        }
    }

    private var entries: [TimelineEntry] {
        let events = picture.timedEvents.map(TimelineEntry.event)
        let suggestions = picture.suggestions.map(TimelineEntry.suggestion)
        return (events + suggestions).sorted { $0.start < $1.start }
    }
}

private struct EventRow: View {
    @Environment(PlannerModel.self) private var planner
    let item: DayEvent

    var body: some View {
        let tint = DayStyle.tint(item.source)
        let faded = item.source == .beckyVisible
        HStack(alignment: .top, spacing: Spacing.s) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(PlannerFormat.time(item.event.start, planner.calendar))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(PlannerFormat.time(item.event.end, planner.calendar))
                    .font(.caption2)
                    .foregroundStyle(Palette.textTertiary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 70, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.event.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(DayStyle.label(item.source))
                        .foregroundStyle(tint)
                    if let location = item.event.location, !location.isEmpty {
                        Text("· \(location)")
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                .font(.caption.weight(.semibold))
                if item.source == .beckyUnconfirmed {
                    BeckyButtons(event: item.event)
                        .padding(.top, Spacing.xxs)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s)
        .background(Palette.surface.opacity(faded ? 0.5 : 1), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .opacity(faded ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}

private struct SuggestionCard: View {
    @Environment(PlannerModel.self) private var planner
    @Environment(\.openURL) private var openURL
    let suggestion: Suggestion

    var body: some View {
        let tint = DayStyle.tint(suggestion.kind)
        let calendar = planner.calendar
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                IconTile(symbol: suggestion.kind.symbol, tint: tint, size: 44, filled: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(timing(calendar))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
                Spacer(minLength: 0)
                Menu {
                    if suggestion.kind == .aldiShop || suggestion.kind == .batchCook {
                        Button("Done for this week", systemImage: "checkmark") { withAnimation { planner.markDone(suggestion) } }
                    }
                    Button("Not this day", systemImage: "xmark") { withAnimation { planner.dismiss(suggestion) } }
                } label: {
                    RoundIconLabel(symbol: "ellipsis", size: 36)
                }
                .accessibilityLabel("More options")
            }
            ChipFlow().callAsFunction {
                Chip(text: PlannerFormat.minutes(suggestion.minutes), symbol: "timer")
                if suggestion.travelThere > 0 || suggestion.travelBack > 0 {
                    Chip(text: travelText, symbol: "car.fill")
                }
                if suggestion.kind.isOutdoor {
                    Chip(text: "Dry", symbol: "sun.max.fill", tint: Palette.fresh, fill: Palette.fresh.opacity(0.12))
                }
            }
            Text(suggestion.detail)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
            HStack(spacing: Spacing.xs) {
                Button {
                    withAnimation { planner.accept(suggestion) }
                } label: {
                    Label("Add to calendar", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Palette.onAccent, fill: tint))
                .disabled(planner.ownCalendarIDs.isEmpty)
                if let place = venue, let url = GoogleMapsLink.directions(to: place) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(Spacing.m)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
    }

    private var venue: SavedPlace? {
        guard let id = suggestion.kind.venue, id != .home else { return nil }
        return planner.settings.places[id]
    }

    private var title: String {
        if let name = suggestion.venueName, suggestion.kind != .batchCook { return "\(suggestion.kind.title) · \(name)" }
        return suggestion.kind.title
    }

    private func timing(_ calendar: Calendar) -> String {
        if suggestion.travelThere > 0 {
            return "Leave \(PlannerFormat.time(suggestion.leaveAt, calendar)) · back \(PlannerFormat.time(suggestion.backAt, calendar))"
        }
        return PlannerFormat.range(suggestion.start, suggestion.end, calendar)
    }

    private var travelText: String {
        let from = suggestion.origin == .current ? "from where you are" : "from \(suggestion.origin.title.lowercased())"
        let estimate = suggestion.travelIsEstimate ? " (estimate)" : ""
        if suggestion.travelThere == suggestion.travelBack {
            return "\(suggestion.travelThere) min each way \(from)\(estimate)"
        }
        return "\(suggestion.travelThere) min there \(from), \(suggestion.travelBack) back\(estimate)"
    }
}

// MARK: - Setup

private struct SetupCard: View {
    @Environment(PlannerModel.self) private var planner
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            CardHeader(title: "Bring your calendars together", symbol: "calendar", tint: Palette.frost,
                       subtitle: "Your Apple calendar, work Outlook and Becky's, read on this iPhone.")
            TileRow(title: "Allow calendar access", subtitle: planner.access.title, symbol: "lock.open.fill",
                    tint: Palette.frost, done: planner.access == .granted)
            TileRow(title: "Say which calendar is which", subtitle: "Mine, Becky's and work", symbol: "list.bullet",
                    tint: Palette.frost, done: planner.isSetUp)
            if planner.access == .granted {
                Button("Label calendars", action: openSettings)
                    .buttonStyle(PrimaryButtonStyle(tint: Palette.frost))
            } else {
                Button("Allow calendar access") {
                    Task { await planner.requestCalendarAccess() }
                }
                .buttonStyle(PrimaryButtonStyle(tint: Palette.frost))
            }
        }
        .surface()
    }
}

// MARK: - Style

enum DayStyle {
    static func tint(_ location: WorkLocation) -> Color {
        switch location {
        case .office: Palette.frost
        case .home: Palette.fresh
        case .unknown: Palette.warning
        case .dayOff: Palette.accent
        }
    }

    static func symbol(_ location: WorkLocation) -> String {
        switch location {
        case .office: "building.2.fill"
        case .home: "house.fill"
        case .unknown: "briefcase.fill"
        case .dayOff: "sun.max.fill"
        }
    }

    static func tint(_ source: EventSource) -> Color {
        switch source {
        case .mine: Palette.accent
        case .work: Palette.frost
        case .beckyShared: Palette.rose
        case .beckyVisible, .beckyUnconfirmed: Palette.textTertiary
        }
    }

    static func label(_ source: EventSource) -> String {
        switch source {
        case .mine: "You"
        case .work: "Work"
        case .beckyShared: "With Becky"
        case .beckyVisible: "Becky · just so you know"
        case .beckyUnconfirmed: "Becky · shared with you?"
        }
    }

    static func tint(_ kind: ActivityKind) -> Color {
        switch kind {
        case .gym: Palette.accent
        case .swim: Palette.frost
        case .aldiShop, .batchCook: Palette.kitchen
        case .run: Palette.rose
        case .walk: Palette.fresh
        }
    }
}

private extension View {
    /// A small capsule for quick answers inside a card.
    func compactPill(ink: Color, fill: Color) -> some View {
        font(.footnote.weight(.semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: 36)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
    }
}
