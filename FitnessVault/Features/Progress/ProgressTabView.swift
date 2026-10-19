import SwiftUI

/// Progress (N5): rolling trends and cumulative totals, never streaks (U2).
/// Phase 1 shows consistency, money kept, house-sale preparation and movement; body, strength, swim,
/// rehab and photos arrive with Phase 3.
struct ProgressTabView: View {
    @Environment(CoachModel.self) private var coach
    @Environment(AppModel.self) private var model
    @Binding var showingSettings: Bool
    @State private var period: ActivityPeriod = .week

    private let columns = [GridItem(.flexible(), spacing: Spacing.s), GridItem(.flexible(), spacing: Spacing.s)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    StatusNotices()
                    ConsistencyCard()
                    HouseSaleCard()

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Movement")
                        Picker("Period", selection: $period) {
                            ForEach(ActivityPeriod.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        LazyVGrid(columns: columns, spacing: Spacing.s) {
                            ForEach(RewardCategory.activity) { category in
                                ActivityMetricLink(category: category, period: period)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.xl)
                .animation(.snappy, value: period)
            }
            .pageBackground()
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton(isPresented: $showingSettings)
                }
            }
            .refreshable {
                await model.syncHealth()
                await coach.refresh()
            }
        }
    }
}

/// The last 14 days as simple marks, plus a rolling count. A missed day is one mark, not a reset (U2).
struct ConsistencyCard: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        let days = (1...14).reversed().map { coach.today.adding(days: -$0, calendar: coach.calendar) }
        let records = Dictionary(uniqueKeysWithValues: days.compactMap { day in coach.dayRecord(day).map { (day, $0) } })
        let scored = records.values.filter { $0.finalisedAt != nil && $0.scorePercent != nil }
        let strong = scored.filter { ($0.scorePercent ?? 0) >= 80 }.count
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Consistency · last 14 days")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            if scored.isEmpty {
                Text("Your first scored day appears here once a day with agreed commitments has ended.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(strong) of \(scored.count) days at 80% or more")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
            }
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colour(records[day]))
                        .frame(height: 24)
                        .accessibilityLabel(accessibility(day, records[day]))
                }
            }
            Divider().overlay(Palette.border)
            HStack {
                Text("Kept this month")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("\((coach.settings.monthlyAllocation - coach.monthFines).nonNegative.formatted()) of \(coach.settings.monthlyAllocation.formatted(wholePounds: true))")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .surface()
    }

    private func colour(_ record: DayRecord?) -> Color {
        guard let record, record.finalisedAt != nil, let score = record.scorePercent else { return Palette.elevated }
        switch score {
        case 80...: return Palette.accent
        case 60..<80: return Palette.accent.opacity(0.6)
        case 40..<60: return Palette.warning.opacity(0.6)
        default: return Palette.warning.opacity(0.35)
        }
    }

    private func accessibility(_ day: DayKey, _ record: DayRecord?) -> String {
        let label = day.startDate(calendar: coach.calendar).formatted(.dateTime.weekday(.wide).day().month())
        guard let record, let score = record.scorePercent, record.finalisedAt != nil else { return "\(label): not scored" }
        return "\(label): \(score) percent"
    }
}

/// House-sale preparation (O-C): small finished steps add up.
struct HouseSaleCard: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        let tasks = coach.allTasks().filter { $0.area == .houseSale }
        let parents = Set(tasks.compactMap(\.parentID))
        let steps = tasks.filter { !parents.contains($0.id) && $0.state != .dropped }
        let done = steps.filter { $0.state == .done }.count
        if !steps.isEmpty {
            NavigationLink {
                TaskListView(area: .houseSale)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        Text("House sale")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Text("\(done) of \(steps.count) steps done")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    ThinProgressBar(progress: Double(done) / Double(steps.count))
                }
                .surface()
            }
            .buttonStyle(CardButtonStyle())
        }
    }
}

/// A backlog area's tasks, grouped under their parent jobs. Opened deliberately, never shown on Today (H2).
struct TaskListView: View {
    @Environment(CoachModel.self) private var coach
    let area: TaskArea

    var body: some View {
        let tasks = coach.allTasks().filter { $0.area == area && $0.state != .dropped }
        let topLevel = tasks.filter { $0.parentID == nil }
        List {
            ForEach(topLevel, id: \.id) { parent in
                let children = tasks.filter { $0.parentID == parent.id }
                Section(parent.title) {
                    if children.isEmpty {
                        TaskRow(task: parent)
                    } else {
                        ForEach(children, id: \.id) { TaskRow(task: $0) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(area.title)
    }
}

struct TaskRow: View {
    @Environment(CoachModel.self) private var coach
    let task: TaskItem

    var body: some View {
        Button {
            coach.setState(task.state == .done ? .open : .done, for: task)
        } label: {
            HStack {
                Image(systemName: task.state == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.state == .done ? Palette.success : Palette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .foregroundStyle(Palette.textPrimary)
                        .strikethrough(task.state == .done)
                    if let note = task.resumeNote {
                        Text("Where you got to: \(note)").font(.caption).foregroundStyle(Palette.textTertiary)
                    }
                }
                Spacer()
                Text(DurationFormat.text(minutes: task.estimatedMinutes))
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .accessibilityLabel("\(task.title), \(task.state == .done ? "done" : "not done")")
    }
}
