import SwiftUI

// MARK: - Card on the Day tab

/// The routine that matters right now, with progress, home or away, and what's at stake.
struct RoutineCard: View {
    @Environment(RoutineModel.self) private var routines
    @State private var showing: RoutinePart?
    @State private var showingQuestionnaire = false

    var body: some View {
        if routines.isSetUp {
            let part = routines.currentPart
            Button {
                showing = part
            } label: {
                RoutineSummary(part: part, day: routines.today)
            }
            .buttonStyle(CardButtonStyle())
            .sheet(item: $showing) { part in
                NavigationStack { RoutineChecklistView(part: part, day: routines.today) }
                    .presentationBackground(Palette.background)
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.s) {
                CardHeader(title: "Morning and night routines", symbol: "sunrise.fill", tint: Palette.rehab,
                           subtitle: "Self-care for today's you and tomorrow's you")
                Text("A short questionnaire sets up weekday and weekend versions, at home and away. Missing a home routine halves that day's earnings.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start the questionnaire") { showingQuestionnaire = true }
                    .buttonStyle(PrimaryButtonStyle(tint: Palette.rehab))
            }
            .surface()
            .sheet(isPresented: $showingQuestionnaire) {
                RoutineQuestionnaireView()
            }
        }
    }
}

private struct RoutineSummary: View {
    @Environment(RoutineModel.self) private var routines
    let part: RoutinePart
    let day: DayKey

    var body: some View {
        let items = routines.items(part, on: day)
        let record = routines.record(part, on: day)
        let done = items.filter { record?.ticked.contains($0.id) ?? false }.count
        let status = routines.status(part, on: day)
        let tint = RoutineStyle.tint(status)
        HStack(spacing: Spacing.m) {
            ZStack {
                RingGauge(progress: min(1, Double(done) / Double(max(routines.required(part, on: day), 1))), tint: tint,
                          lineWidth: 7)
                Image(systemName: part.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(part.title)
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Text(part.isWalk ? part.purpose : "\(part.purpose) · \(done) of \(items.count), \(routines.required(part, on: day)) needed")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                ScoreLine(part: part, day: day)
                Text(RoutineStyle.message(status, window: routines.window(part, on: day), calendar: routines.calendar, part: part,
                                         costs: routines.costs(part, on: day)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.textTertiary)
        }
        .surface()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Checklist

struct RoutineChecklistView: View {
    @Environment(RoutineModel.self) private var routines
    @Environment(PlannerModel.self) private var planner
    @Environment(\.dismiss) private var dismiss
    @State var part: RoutinePart
    let day: DayKey
    @State private var journalItem: RoutineItem?

    var body: some View {
        let items = routines.items(part, on: day)
        let record = routines.record(part, on: day)
        let status = routines.status(part, on: day)
        let closed = routines.isClosed(part, on: day)
        let place = routines.place(part, on: day)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Picker("Routine", selection: $part) {
                    ForEach(RoutinePart.allCases) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(part.purpose)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(RoutineStyle.tint(status))
                    Text(routines.key(part, on: day).title)
                        .font(.display(26))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(RoutineStyle.message(status, window: routines.window(part, on: day), calendar: routines.calendar, part: part,
                                         costs: routines.costs(part, on: day)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RoutineStyle.tint(status))
                    ScoreLine(part: part, day: day)
                        .padding(.top, 2)
                    if let finished = finishedLine(items: items, record: record) {
                        Label(finished, systemImage: "checkmark.seal.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.success)
                    }
                    if part == .evening, let tomorrow = tomorrowLine {
                        Label(tomorrow, systemImage: "calendar")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .heroCard(tint: RoutineStyle.tint(status), symbol: part.symbol)

                if !part.isWalk {
                    Picker("Where", selection: Binding(get: { place }, set: { routines.setPlace($0, part: part, on: day) })) {
                        ForEach(RoutinePlace.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(closed)
                }
                if routines.isAutoAway(part, on: day) {
                    Label("Away tonight: you weren't home by 8:30 pm.", systemImage: "moon.zzz.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.frost)
                }

                VStack(spacing: 0) {
                    let planned = routines.plannedTimes(part, on: day)
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        let ticked = record?.ticked.contains(item.id) ?? false
                        RoutineItemRow(item: item, ticked: ticked, tint: RoutineStyle.tint(status),
                                       opensJournal: RoutineCatalogue.journalPrompts[item.id] != nil,
                                       planned: index < planned.count ? PlannerFormat.time(planned[index], routines.calendar) : nil) {
                            // Journal items are ticked by writing the entry.
                            if RoutineCatalogue.journalPrompts[item.id] != nil && !ticked {
                                journalItem = item
                            } else {
                                routines.toggle(item, part: part, on: day)
                            }
                        }
                        .disabled(closed)
                        if index < items.count - 1 { RowDivider(inset: 48) }
                    }
                }
                .surface()

                Footnote(part.isWalk ? "Walks don't change your earnings. They keep the streak going, and they're good for you."
                         : place == .home
                         ? "At home, tick \(routines.required(part, on: day)) of \(items.count) (80%) by \(PlannerFormat.time(routines.window(part, on: day).end, routines.calendar)) or today keeps half its earnings. Morning and night together only ever halve a day once."
                         : "Away routines are for you; they never cost anything.")
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle(part.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .sheet(item: $journalItem) { item in
            NavigationStack {
                JournalComposer(prompt: RoutineCatalogue.journalPrompts[item.id], routineItemID: item.id) { _ in
                    routines.tick(item, part: part, on: day)
                }
            }
            .presentationBackground(Palette.background)
        }
    }

    /// "Finished at 7:21, 9 minutes inside the plan · Clean sweep" once it's done.
    private func finishedLine(items: [RoutineItem], record: RoutineRecord?) -> String? {
        guard let record, let finished = record.completedAt else { return nil }
        var text = "Finished at \(PlannerFormat.time(finished, routines.calendar))"
        let planned = routines.plannedTimes(part, on: day)
        if let lastStart = planned.last, let last = items.last {
            let plannedEnd = lastStart.addingTimeInterval(TimeInterval((last.minutes ?? 5) * 60))
            let spare = Int((plannedEnd.timeIntervalSince(finished) / 60).rounded())
            if spare >= 3 { text += ", \(spare) min inside the plan" }
        }
        if items.allSatisfy({ record.ticked.contains($0.id) }) { text += " · Clean sweep" }
        return text
    }

    /// Tomorrow's shape from the Day tab, so tonight's prep fits it.
    private var tomorrowLine: String? {
        let tomorrow = day.adding(days: 1, calendar: routines.calendar)
        guard let picture = planner.picture(for: tomorrow) else { return nil }
        var text = "Tomorrow: \(picture.location.title.lowercased())"
        if let first = picture.timedEvents.first(where: { $0.blocksTime }) {
            text += ", first up \(first.event.title) at \(PlannerFormat.time(first.event.start, routines.calendar))"
        }
        if let gym = picture.suggestions.first(where: { $0.kind == .gym }) {
            text += ", gym suggested at \(PlannerFormat.time(gym.start, routines.calendar))"
        }
        return text
    }
}

private struct RoutineItemRow: View {
    let item: RoutineItem
    let ticked: Bool
    let tint: Color
    var opensJournal = false
    var planned: String? = nil
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.s) {
                IconTile(symbol: item.symbol, tint: ticked ? tint : Palette.textTertiary, size: 36, filled: ticked)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(ticked ? Palette.textTertiary : Palette.textPrimary)
                        .strikethrough(ticked, color: Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = detail {
                        Text(detail)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                if opensJournal && !ticked {
                    Image(systemName: "square.and.pencil")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.textTertiary)
                }
                Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(ticked ? tint : Palette.textTertiary)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: ticked)
        .accessibilityLabel(item.title)
        .accessibilityValue(ticked ? "Done" : "Not done")
    }

    private var detail: String? {
        let minutes = item.minutes.map { "\($0) min" }
        switch (planned, minutes) {
        case let (planned?, minutes?): return "\(planned) · \(minutes)"
        case let (planned?, nil): return planned
        case let (nil, minutes?): return minutes
        default: return nil
        }
    }
}

// MARK: - Keeping score

/// Streak, the week as seven dots, and pace while it's open. Quiet, not a game show.
private struct ScoreLine: View {
    @Environment(RoutineModel.self) private var routines
    let part: RoutinePart
    let day: DayKey

    var body: some View {
        let streak = routines.streak(part)
        let best = routines.bestStreak(part)
        HStack(spacing: Spacing.s) {
            Label(streak == 1 ? "1 day" : "\(streak) days", systemImage: "flame.fill")
                .foregroundStyle(streak > 0 ? Palette.kitchen : Palette.textTertiary)
            if best > streak {
                Text("Best \(best)")
                    .foregroundStyle(Palette.textTertiary)
            }
            WeekDots(statuses: routines.week(part))
            if let pace = routines.pace(part, on: day) {
                Text(RoutineScore.paceText(pace))
                    .foregroundStyle(pace < -2 ? Palette.warning : Palette.success)
            }
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// The last seven days, oldest first: filled when done, red when missed, outlined while it's still to come.
struct WeekDots: View {
    let statuses: [RoutineStatus]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(statuses.indices, id: \.self) { index in
                let status = statuses[index]
                Circle()
                    .fill(fill(status))
                    .overlay { Circle().strokeBorder(stroke(status), lineWidth: 1) }
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(statuses.filter { $0 == .done || $0 == .awayDone }.count) of the last 7 days done")
    }

    private func fill(_ status: RoutineStatus) -> Color {
        switch status {
        case .done: Palette.success
        case .awayDone: Palette.frost
        case .missed: Palette.error
        default: .clear
        }
    }

    private func stroke(_ status: RoutineStatus) -> Color {
        switch status {
        case .done, .awayDone, .missed: .clear
        default: Palette.textTertiary.opacity(0.6)
        }
    }
}

// MARK: - Vault notice

/// On the Vault: a missed home routine today or yesterday, and what it cost.
struct RoutinePenaltyNotice: View {
    @Environment(AppModel.self) private var model
    @Environment(RoutineModel.self) private var routines

    var body: some View {
        let today = routines.today
        let yesterday = today.adding(days: -1, calendar: routines.calendar)
        if let day = [today, yesterday].first(where: { routines.isPenalised($0) }) {
            let full = model.earnedBeforeRoutines(on: day)
            let kept = model.earned(on: day)
            NoticeBanner(symbol: "moon.zzz.fill",
                         title: day == today ? "Today keeps half" : "Yesterday kept half",
                         message: "A home routine wasn't finished in time, so \(kept.formatted()) of \(full.formatted()) counts.",
                         tint: Palette.warning)
        }
    }
}

// MARK: - Questionnaire

/// Builds all eight routines: weekday and weekend, morning and night, at home and away.
struct RoutineQuestionnaireView: View {
    @Environment(RoutineModel.self) private var routines
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var selections: [String: [RoutineItem]] = [:]
    @State private var times: [String: RoutineTimes] = [:]
    @State private var sameAs: [String: Bool] = [:]
    @State private var agreed = false
    @State private var loaded = false

    init(startStep: Int = 0) {
        _step = State(initialValue: startStep)
    }

    /// The pages, in order, and which earlier page each can copy.
    private static let pages: [(key: RoutineKey, copies: RoutineKey?, question: String)] = {
        func key(_ part: RoutinePart, _ days: RoutineDays, _ place: RoutinePlace) -> RoutineKey {
            RoutineKey(part: part, days: days, place: place)
        }
        return [
            (key(.morning, .weekday, .home), nil, "On a weekday at home, what sets today's you up well?"),
            (key(.morning, .weekend, .home), key(.morning, .weekday, .home), "And at the weekend, at home?"),
            (key(.evening, .weekday, .home), nil, "On a night before work, what does tomorrow's you need done?"),
            (key(.evening, .weekend, .home), key(.evening, .weekday, .home), "On a Friday or Saturday night at home?"),
            (key(.morning, .weekday, .away), key(.morning, .weekday, .home), "Away from home on a weekday morning?"),
            (key(.morning, .weekend, .away), key(.morning, .weekday, .away), "Away at the weekend, in the morning?"),
            (key(.evening, .weekday, .away), nil, "Away the night before a work day: what does tomorrow's you need?"),
            (key(.evening, .weekend, .away), key(.evening, .weekday, .away), "Away on a Friday or Saturday night?"),
        ]
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    ProgressView(value: Double(step), total: Double(Self.pages.count + 1))
                        .tint(Palette.rehab)
                    if step == 0 {
                        intro
                    } else if step <= Self.pages.count {
                        page(Self.pages[step - 1])
                    } else {
                        summary
                    }
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.xl)
            }
            .pageBackground()
            .navigationTitle("Your routines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { footer }
            .onAppear(perform: load)
        }
    }

    // MARK: Pages

    private var intro: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Self-care, twice a day")
                .font(.display(30))
                .foregroundStyle(Palette.textPrimary)
            Text("Mornings are for today's you. Nights are for tomorrow's you: whatever you do at 9 pm, the morning you doesn't have to.")
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
            TileRow(title: "Weekdays and weekends", subtitle: "Nights follow the next day: Sunday night is a weekday night",
                    symbol: "calendar", tint: Palette.rehab)
            TileRow(title: "At home and away", subtitle: "Switch to away from the routine itself", symbol: "suitcase.fill",
                    tint: Palette.rehab)
            TileRow(title: "Home routines count", subtitle: "Unfinished by the time you choose, that day keeps half its earnings",
                    symbol: "sterlingsign.circle", tint: Palette.warning)
            Footnote("Eight short questions, already filled in with your answers. A routine counts as done at 80% ticked.")
            if routines.isSetUp {
                Button("Start again from your answers") { resetToAnswers() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func page(_ page: (key: RoutineKey, copies: RoutineKey?, question: String)) -> some View {
        let key = page.key
        let copying = page.copies != nil && (sameAs[key.id] ?? false)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label(key.title, systemImage: key.part.symbol)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.rehab)
                Text(page.question)
                    .font(.display(26))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                let current = times[key.id] ?? RoutineSetup.defaultTimes(key)
                if key.part == .evening && key.place == .away {
                    Toggle("Any time, no set time", isOn: flagBinding(key, \.adHoc))
                        .tint(Palette.rehab)
                        .frame(minHeight: 48)
                }
                if !current.isAdHoc {
                    if key.part == .evening && key.place == .away { RowDivider(inset: 0) }
                    DatePicker("Starts", selection: timeBinding(key, \.start), displayedComponents: .hourAndMinute)
                        .frame(minHeight: 48)
                    RowDivider(inset: 0)
                    DatePicker("Finished by", selection: timeBinding(key, \.finish), displayedComponents: .hourAndMinute)
                        .frame(minHeight: 48)
                    if key.part == .morning {
                        RowDivider(inset: 0)
                        Toggle("Earlier if the calendar starts first", isOn: flagBinding(key, \.beforeFirstEvent))
                            .tint(Palette.rehab)
                            .frame(minHeight: 48)
                    }
                }
            }
            .surface()

            if let source = page.copies {
                Toggle("Same as \(source.title.lowercased())", isOn: Binding(get: { sameAs[key.id] ?? false },
                                                                              set: { sameAs[key.id] = $0 }))
                    .tint(Palette.rehab)
                    .surface()
            }

            if !copying {
                ItemPicker(suggestions: suggestions(for: key), selected: Binding(get: { selections[key.id] ?? [] },
                                                                                   set: { selections[key.id] = $0 }))
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Your routines")
                .font(.display(30))
                .foregroundStyle(Palette.textPrimary)
            VStack(spacing: 0) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    let key = Self.pages[index].key
                    let time = times[key.id] ?? RoutineSetup.defaultTimes(key)
                    let when = time.isAdHoc ? "any time"
                        : "\(clock(time.start))–\(clock(time.finish))\(time.movesForEvents ? " or earlier" : "")"
                    TileRow(title: key.title, subtitle: "\(resolved(key).count) things · \(when)",
                            symbol: key.part.symbol, tint: key.place == .home ? Palette.rehab : Palette.frost)
                    if index < Self.pages.count - 1 { RowDivider() }
                }
            }
            .surface()
            Toggle(isOn: $agreed) {
                Text("I understand: if I don't finish a home routine by its time, that day keeps half its earnings.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
            }
            .tint(Palette.warning)
            .surface()
            if !routines.isSetUp {
                Footnote("This starts tomorrow, so today can't count against you.")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            if step <= Self.pages.count {
                Button(step == 0 ? "Start" : "Next") { withAnimation { step += 1 } }
                    .buttonStyle(PrimaryButtonStyle(tint: Palette.rehab))
                    .disabled(step > 0 && resolved(Self.pages[step - 1].key).isEmpty)
            } else {
                Button("Save routines") {
                    save()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(tint: Palette.rehab))
                .disabled(!agreed)
            }
        }
        .padding(.horizontal, Spacing.page)
        .padding(.vertical, Spacing.s)
        .background(Palette.background.opacity(0.95))
    }

    // MARK: State

    private func load() {
        guard !loaded else { return }
        loaded = true
        let setup = routines.setup
        for page in Self.pages {
            let key = page.key
            let saved = setup.items(key)
            selections[key.id] = saved.isEmpty ? RoutineCatalogue.defaults(for: key) : saved
            times[key.id] = setup.times(key)
            if let source = page.copies {
                // New: away weekends follow away weekdays; home weekends start as their own version.
                let savedSame = !saved.isEmpty && saved == setup.items(source)
                sameAs[key.id] = setup.isSetUp ? savedSame : (key.place == .away && key.days == .weekend)
            }
        }
        agreed = setup.isSetUp
    }

    /// The items a page ends up with, following "same as" back to its source.
    private func resolved(_ key: RoutineKey) -> [RoutineItem] {
        if let page = Self.pages.first(where: { $0.key == key }), let source = page.copies, sameAs[key.id] ?? false {
            return resolved(source)
        }
        return selections[key.id] ?? []
    }

    private func suggestions(for key: RoutineKey) -> [RoutineItem] {
        let custom = (selections[key.id] ?? []).filter { item in !RoutineCatalogue.suggestions(for: key).contains(item) }
        return RoutineCatalogue.suggestions(for: key) + custom
    }

    private func save() {
        var items: [String: [RoutineItem]] = [:]
        for page in Self.pages { items[page.key.id] = resolved(page.key) }
        routines.save(items, times: times)
    }

    private func resetToAnswers() {
        for page in Self.pages {
            selections[page.key.id] = RoutineCatalogue.defaults(for: page.key)
            times[page.key.id] = RoutineSetup.defaultTimes(page.key)
            if page.copies != nil { sameAs[page.key.id] = page.key.place == .away && page.key.days == .weekend }
        }
        sameAs[RoutineKey(part: .morning, days: .weekend, place: .home).id] = false
    }

    private func flagBinding(_ key: RoutineKey, _ path: WritableKeyPath<RoutineTimes, Bool?>) -> Binding<Bool> {
        Binding(get: { (times[key.id] ?? RoutineSetup.defaultTimes(key))[keyPath: path] ?? false },
                set: { value in
                    var current = times[key.id] ?? RoutineSetup.defaultTimes(key)
                    current[keyPath: path] = value
                    times[key.id] = current
                })
    }

    private func timeBinding(_ key: RoutineKey, _ path: WritableKeyPath<RoutineTimes, Int>) -> Binding<Date> {
        let base = DayKey(year: 2024, month: 1, day: 15)
        let calendar = routines.calendar
        return Binding(get: {
            base.date(atMinute: (times[key.id] ?? RoutineSetup.defaultTimes(key))[keyPath: path], calendar: calendar)
        }, set: { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            var value = times[key.id] ?? RoutineSetup.defaultTimes(key)
            value[keyPath: path] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            times[key.id] = value
        })
    }

    private func clock(_ minute: Int) -> String {
        PlannerFormat.time(DayKey(year: 2024, month: 1, day: 15).date(atMinute: minute, calendar: routines.calendar),
                           routines.calendar)
    }
}

/// Suggestions to tick, in the order you'll do them, plus your own.
private struct ItemPicker: View {
    let suggestions: [RoutineItem]
    @Binding var selected: [RoutineItem]
    @State private var custom = ""

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions.indices, id: \.self) { index in
                let item = suggestions[index]
                let isOn = selected.contains(item)
                Button {
                    toggle(item)
                } label: {
                    HStack(spacing: Spacing.s) {
                        IconTile(symbol: item.symbol, tint: isOn ? Palette.rehab : Palette.textTertiary, size: 34, filled: isOn)
                        Text(item.title)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn ? Palette.rehab : Palette.textTertiary)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                RowDivider(inset: 46)
            }
            HStack(spacing: Spacing.s) {
                TextField("Add your own", text: $custom)
                    .submitLabel(.done)
                    .onSubmit(add)
                Button("Add", action: add)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.rehab)
                    .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(minHeight: 48)
        }
        .surface()
    }

    /// Keeps the suggestion order, so the checklist reads in a natural sequence.
    private func toggle(_ item: RoutineItem) {
        if selected.contains(item) {
            selected.removeAll { $0 == item }
        } else {
            let order = suggestions
            selected = order.filter { selected.contains($0) || $0 == item }
        }
    }

    private func add() {
        let title = custom.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        selected.append(RoutineItem(id: "custom-\(UUID().uuidString.prefix(8))", title: title, symbol: "star.fill"))
        custom = ""
    }
}

// MARK: - Style

enum RoutineStyle {
    static func tint(_ status: RoutineStatus) -> Color {
        switch status {
        case .done, .awayDone: Palette.success
        case .missed: Palette.error
        case .open: Palette.warning
        case .awayOpen, .awayMissed: Palette.frost
        case .upcoming, .notSetUp: Palette.rehab
        }
    }

    static func message(_ status: RoutineStatus, window: DateInterval, calendar: Calendar,
                        part: RoutinePart = .morning, costs: Bool = true) -> String {
        let start = PlannerFormat.time(window.start, calendar), end = PlannerFormat.time(window.end, calendar)
        if part.isWalk {
            switch status {
            case .upcoming: return "From \(start)"
            case .open, .awayOpen: return "Any time until \(end)"
            case .done, .awayDone: return "Done"
            case .missed, .awayMissed: return "Missed today"
            case .notSetUp: return "Not set up"
            }
        }
        switch status {
        case .notSetUp: return "Not set up"
        case .upcoming: return "Starts at \(start), finish by \(end)"
        case .open: return costs ? "Finish by \(end) or today keeps half" : "Finish by \(end)"
        case .done: return "Done. Earnings safe."
        case .missed: return costs ? "Missed. Today keeps half its earnings." : "Missed. It starts counting tomorrow."
        case .awayOpen: return window.end.timeIntervalSince(window.start) > 5 * 3_600
            ? "Away: any time tonight, no penalty" : "Away: finish by \(end), no penalty"
        case .awayDone: return "Done, away from home"
        case .awayMissed: return "Away: not finished, no penalty"
        }
    }
}
