import SwiftUI

/// The Day tab: your calendar, work Outlook and Becky's calendar in one timeline, with suggestions fitted into the
/// free time: the gym, a swim, the Aldi shop, the batch cook, runs and walks.
struct DayView: View {
    @Environment(AppModel.self) private var model
    @Environment(TrainingModel.self) private var training
    @Environment(KitchenModel.self) private var kitchen
    @Environment(PlannerModel.self) private var planner
    @Environment(RoutineModel.self) private var routines
    @Binding var showingSettings: Bool
    @State private var selected: DayKey?
    @State private var showingDaySettings = false
    @State private var block: DayBlock?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayStrip(days: planner.days, selected: day, pictures: planner.pictures, calendar: planner.calendar) {
                    selected = $0
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.xs)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            if let picture = planner.picture(for: day) {
                                DayHeader(picture: picture, isToday: day == planner.today, calendar: planner.calendar)
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

                            if day == planner.today {
                                RoutineCard()
                                JournalCard()
                            }

                            if let picture = planner.picture(for: day) {
                                HourCalendar(picture: picture, isToday: day == planner.today, selection: $block)
                            }

                            Footnote("Dashed blocks are suggestions; tap anything for details. Drive times from Apple Maps (traffic-aware where Apple has it), plus parking. Directions open in Google Maps. Forecast from Open-Meteo.")
                        }
                        .padding(.horizontal, Spacing.page)
                        .padding(.bottom, Spacing.xl)
                    }
                    .onAppear { scrollToNow(proxy, animated: false) }
                    .onChange(of: day) { scrollToNow(proxy, animated: true) }
                }
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
            .sheet(item: $block) { block in
                BlockDetail(block: block, day: day)
                    .presentationBackground(Palette.background)
            }
            .onChange(of: planner.revision) { PlannerWidgetPublisher.publishDay(planner: planner, routines: routines) }
            .onChange(of: routines.revision) { PlannerWidgetPublisher.publishDay(planner: planner, routines: routines) }
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

    /// Today opens at the hour before now; other days at their first event (or 8 am).
    private func scrollToNow(_ proxy: ScrollViewProxy, animated: Bool) {
        let calendar = planner.calendar
        var hour = 8
        if day == planner.today {
            hour = calendar.component(.hour, from: planner.now()) - 1
        } else if let first = planner.picture(for: day)?.timedEvents.first {
            hour = calendar.component(.hour, from: first.event.start)
        }
        let target = "hour-\(max(0, min(22, hour)))"
        if animated {
            withAnimation(.snappy) { proxy.scrollTo(target, anchor: .top) }
        } else {
            DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
        }
    }

    private func reload() async {
        let swims = (try? await model.health.swims(since: Date.now.addingTimeInterval(-14 * 86_400))) ?? []
        planner.update(training: training, kitchen: kitchen, swims: swims)
        await planner.refresh()
        routines.refreshSchedule()
        PlannerWidgetPublisher.publishDay(planner: planner, routines: routines)
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

// MARK: - Header

private struct DayHeader: View {
    let picture: DayPicture
    let isToday: Bool
    let calendar: Calendar

    var body: some View {
        let tint = DayStyle.tint(picture.location)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                IconTile(symbol: DayStyle.symbol(picture.location), tint: tint, size: 40, filled: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(isToday ? "Today" : picture.day.startDate(calendar: calendar).formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(tint)
                    Text(picture.location.title)
                        .font(.display(24))
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            ChipFlow().callAsFunction {
                Chip(text: picture.weather ?? "No forecast yet", symbol: WeatherAdvisor.symbol(for: picture.weather))
                Chip(text: "\(PlannerFormat.minutes(picture.freeMinutes)) free", symbol: "clock")
                if !picture.suggestions.isEmpty {
                    Chip(text: "\(picture.suggestions.count) to fit in", symbol: "sparkles", tint: tint, fill: tint.opacity(0.14))
                }
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        switch picture.location {
        case .office: "Office focus at 9 am. Evenings start from the office."
        case .home: "Home focus at 9 am."
        case .unknown: "No office or home focus at 9 am in Outlook, so home is assumed."
        case .dayOff: "Nothing from work today."
        case .leave: "Rob King AL in Outlook: no work today."
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

// MARK: - Hour by hour

/// One thing on the calendar: an event, a suggestion or a routine.
struct DayBlock: Identifiable {
    enum Target {
        case event(DayEvent)
        case suggestion(Suggestion)
        case routine(RoutinePart)
    }

    enum Look { case solid, dashed, faded }

    var id: String
    var title: String
    var subtitle: String
    var start: Date
    var end: Date
    var tint: Color
    var look: Look
    var target: Target
}

private struct HourCalendar: View {
    @Environment(PlannerModel.self) private var planner
    @Environment(RoutineModel.self) private var routines
    let picture: DayPicture
    let isToday: Bool
    @Binding var selection: DayBlock?

    static let hourHeight: CGFloat = 64
    static let gutter: CGFloat = 50

    var body: some View {
        let blocks = DayBlocks.make(picture: picture, routines: routines, calendar: planner.calendar)
        let columns = CalendarLayout.columns(blocks.map { CalendarSlot(id: $0.id, start: $0.start, end: $0.end) })
        let calendar = planner.calendar
        let dayStart = picture.day.startDate(calendar: calendar)
        VStack(alignment: .leading, spacing: Spacing.s) {
            if !picture.allDayEvents.isEmpty {
                ChipFlow().callAsFunction {
                    ForEach(picture.allDayEvents) { item in
                        Chip(text: item.event.title, symbol: "sun.max", tint: DayStyle.tint(item.source),
                             fill: DayStyle.tint(item.source).opacity(0.12))
                    }
                }
            }
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        HStack(alignment: .top, spacing: Spacing.xs) {
                            Text(hourLabel(hour, calendar: calendar))
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textTertiary)
                                .frame(width: Self.gutter - Spacing.xs, alignment: .trailing)
                                .offset(y: -7)
                            Rectangle()
                                .fill(Palette.border.opacity(0.6))
                                .frame(height: 0.5)
                        }
                        .frame(height: Self.hourHeight, alignment: .top)
                        .id("hour-\(hour)")
                    }
                }
                GeometryReader { proxy in
                    let width = proxy.size.width - Self.gutter
                    if let work = picture.work {
                        Rectangle()
                            .fill(DayStyle.tint(picture.location).opacity(0.05))
                            .frame(width: width, height: height(from: work.start, to: work.end, dayStart: dayStart))
                            .offset(x: Self.gutter, y: offset(work.start, dayStart: dayStart))
                    }
                    ForEach(blocks) { block in
                        let place = columns[block.id] ?? CalendarColumn(column: 0, count: 1)
                        let columnWidth = width / CGFloat(place.count)
                        Button {
                            selection = block
                        } label: {
                            BlockView(block: block, height: height(from: block.start, to: block.end, dayStart: dayStart),
                                      calendar: calendar)
                        }
                        .buttonStyle(.plain)
                        .frame(width: max(24, columnWidth - 3))
                        .offset(x: Self.gutter + CGFloat(place.column) * columnWidth, y: offset(block.start, dayStart: dayStart))
                    }
                    if isToday {
                        let y = offset(planner.now(), dayStart: dayStart)
                        HStack(spacing: 0) {
                            Circle().fill(Palette.error).frame(width: 9, height: 9)
                            Rectangle().fill(Palette.error).frame(height: 1.5)
                        }
                        .offset(x: Self.gutter - 4, y: y - 4.5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
            }
            .frame(height: Self.hourHeight * 24)
            if blocks.isEmpty {
                Text(planner.isSetUp ? "Nothing in the diary and nothing left to fit in." : "Set up your calendars to see your day.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func offset(_ date: Date, dayStart: Date) -> CGFloat {
        let hours = min(24, max(0, date.timeIntervalSince(dayStart) / 3_600))
        return CGFloat(hours) * Self.hourHeight
    }

    private func height(from start: Date, to end: Date, dayStart: Date) -> CGFloat {
        max(22, offset(end, dayStart: dayStart) - offset(start, dayStart: dayStart) - 2)
    }

    private func hourLabel(_ hour: Int, calendar: Calendar) -> String {
        guard hour > 0 else { return "" }
        let date = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15, hour: hour)) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

private struct BlockView: View {
    let block: DayBlock
    let height: CGFloat
    let calendar: Calendar

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(alignment: .leading, spacing: 1) {
            Text(block.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(height > 44 ? 2 : 1)
            if height > 34 {
                Text(block.subtitle)
                    .font(.caption2)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(block.tint.opacity(block.look == .dashed ? 0.08 : 0.22), in: shape)
        .overlay(alignment: .leading) {
            if block.look != .dashed {
                Rectangle().fill(block.tint).frame(width: 3)
            }
        }
        .overlay {
            if block.look == .dashed {
                shape.strokeBorder(block.tint.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            }
        }
        .clipShape(shape)
        .opacity(block.look == .faded ? 0.5 : 1)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.title), \(PlannerFormat.range(block.start, block.end, calendar)), \(block.subtitle)")
    }
}

/// Builds the calendar's blocks from the day's picture and routines.
@MainActor
enum DayBlocks {
    static func make(picture: DayPicture, routines: RoutineModel, calendar: Calendar) -> [DayBlock] {
        var blocks: [DayBlock] = picture.timedEvents.map { item in
            let look: DayBlock.Look
            switch item.source {
            case .beckyVisible, .beckyUnconfirmed: look = .faded
            case .workFree: look = .dashed
            default: look = .solid
            }
            return DayBlock(id: "e-\(item.id)", title: item.event.title, subtitle: DayStyle.label(item.source),
                            start: item.event.start, end: item.event.end, tint: DayStyle.tint(item.source), look: look,
                            target: .event(item))
        }
        for suggestion in picture.suggestions {
            var title = suggestion.kind.title
            if let venue = suggestion.venueName, suggestion.kind != .batchCook { title += " · \(venue)" }
            let subtitle = suggestion.travelThere > 0 ? "Leave \(PlannerFormat.time(suggestion.leaveAt, calendar))"
                : PlannerFormat.minutes(suggestion.minutes)
            blocks.append(DayBlock(id: "s-\(suggestion.id)", title: title, subtitle: subtitle, start: suggestion.leaveAt,
                                   end: suggestion.backAt, tint: DayStyle.tint(suggestion.kind), look: .dashed,
                                   target: .suggestion(suggestion)))
        }
        if routines.isSetUp {
            for part in RoutinePart.allCases {
                let window = routines.window(part, on: picture.day)
                // Nights away have no set time, so they aren't drawn as a block.
                if window.duration > 4 * 3_600 { continue }
                let items = routines.items(part, on: picture.day)
                let done = items.filter { routines.record(part, on: picture.day)?.ticked.contains($0.id) ?? false }.count
                blocks.append(DayBlock(id: "r-\(part.rawValue)", title: part.title,
                                       subtitle: "\(done) of \(items.count) · \(part.purpose.lowercased())",
                                       start: window.start, end: window.end, tint: Palette.rehab, look: .solid,
                                       target: .routine(part)))
            }
        }
        return blocks
    }
}

/// What a tapped block opens: the event, the suggestion with its actions, or the routine checklist.
private struct BlockDetail: View {
    @Environment(\.dismiss) private var dismiss
    let block: DayBlock
    let day: DayKey

    var body: some View {
        switch block.target {
        case .routine(let part):
            NavigationStack { RoutineChecklistView(part: part, day: day) }
        case .event(let item):
            NavigationStack {
                ScrollView {
                    EventRow(item: item)
                        .padding(.horizontal, Spacing.page)
                }
                .pageBackground()
                .navigationTitle(item.event.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
            .presentationDetents([.medium])
        case .suggestion(let suggestion):
            NavigationStack {
                ScrollView {
                    SuggestionCard(suggestion: suggestion)
                        .padding(.horizontal, Spacing.page)
                }
                .pageBackground()
                .navigationTitle(suggestion.kind.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
            .presentationDetents([.medium, .large])
        }
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
        case .dayOff, .leave: Palette.accent
        }
    }

    static func symbol(_ location: WorkLocation) -> String {
        switch location {
        case .office: "building.2.fill"
        case .home: "house.fill"
        case .unknown: "briefcase.fill"
        case .dayOff: "sun.max.fill"
        case .leave: "beach.umbrella.fill"
        }
    }

    static func tint(_ source: EventSource) -> Color {
        switch source {
        case .mine: Palette.accent
        case .work: Palette.frost
        case .beckyShared: Palette.rose
        case .beckyVisible, .beckyUnconfirmed: Palette.textTertiary
        case .workFree: Palette.fresh
        }
    }

    static func label(_ source: EventSource) -> String {
        switch source {
        case .mine: "You"
        case .work: "Work"
        case .beckyShared: "With Becky"
        case .beckyVisible: "Becky · just so you know"
        case .beckyUnconfirmed: "Becky · shared with you?"
        case .workFree: "Work · free for you"
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
