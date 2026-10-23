import Charts
import SwiftUI

// MARK: - Card on the Day tab

struct JournalCard: View {
    @Environment(JournalModel.self) private var journal
    @State private var writing = false

    var body: some View {
        HStack(spacing: Spacing.s) {
            NavigationLink {
                JournalView()
            } label: {
                HStack(spacing: Spacing.s) {
                    IconTile(symbol: journal.todaysMood?.symbol ?? "book.fill", tint: tint, size: 44, filled: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Journal")
                            .font(.headline)
                            .foregroundStyle(Palette.textPrimary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                writing = true
            } label: {
                RoundIconLabel(symbol: "square.and.pencil", size: 40, tint: Palette.onAccent, fill: tint)
            }
            .accessibilityLabel("New journal entry")
        }
        .surface()
        .sheet(isPresented: $writing) {
            NavigationStack { JournalComposer(prompt: nil) { _ in } }
                .presentationBackground(Palette.background)
        }
    }

    private var tint: Color { JournalStyle.tint(journal.todaysMood ?? .good) }

    private var subtitle: String {
        var parts: [String] = []
        if let mood = journal.todaysMood { parts.append("Today: \(mood.title.lowercased())") }
        if journal.streak > 1 { parts.append("\(journal.streak)-day streak") }
        if let week = journal.averageMood(lastDays: 7) { parts.append("week \(String(format: "%.1f", week))/5") }
        return parts.isEmpty ? "How are you feeling?" : parts.joined(separator: " · ")
    }
}

// MARK: - Writing an entry

/// Mood, feelings and words. Used for free entries and for the journal items in a routine.
struct JournalComposer: View {
    @Environment(JournalModel.self) private var journal
    @Environment(\.dismiss) private var dismiss
    let prompt: String?
    var routineItemID: String? = nil
    let onSave: (JournalEntry) -> Void
    @State private var mood: Mood?
    @State private var feelings: [String] = []
    @State private var text = ""
    @FocusState private var writingFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text(prompt ?? "How's it going?")
                    .font(.display(28))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionTitle(title: "Mood")
                    HStack(spacing: Spacing.xs) {
                        ForEach(Mood.allCases) { option in
                            MoodButton(mood: option, selected: mood == option) {
                                withAnimation(.snappy) { mood = option }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionTitle(title: "Feeling", detail: "Pick any")
                    ChipFlow().callAsFunction {
                        ForEach(JournalFeelings.all, id: \.self) { feeling in
                            let on = feelings.contains(feeling)
                            Button {
                                if on { feelings.removeAll { $0 == feeling } } else { feelings.append(feeling) }
                            } label: {
                                Chip(text: feeling, tint: on ? Palette.onAccent : Palette.textSecondary,
                                     fill: on ? JournalStyle.tint(mood ?? .good) : Palette.elevated)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionTitle(title: "Write")
                    TextEditor(text: $text)
                        .focused($writingFocused)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                        .padding(Spacing.s)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(placeholder)
                                    .foregroundStyle(Palette.textTertiary)
                                    .padding(Spacing.s)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let mood else { return }
                    let entry = journal.add(mood: mood, feelings: feelings, text: text, prompt: prompt,
                                            routineItemID: routineItemID)
                    onSave(entry)
                    dismiss()
                }
                .disabled(mood == nil || (prompt != nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
    }

    private var placeholder: String {
        switch routineItemID {
        case "journal": "Today I want to…"
        case "wins": "1.\n2.\n3."
        default: "Anything on your mind"
        }
    }
}

private struct MoodButton: View {
    let mood: Mood
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let tint = JournalStyle.tint(mood)
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mood.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? Palette.onAccent : tint)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(selected ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control,
                                                                                           style: .continuous))
                    .scaleEffect(selected ? 1.05 : 1)
                Text(mood.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected ? tint : Palette.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(mood.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Journal and trends

struct JournalView: View {
    @Environment(JournalModel.self) private var journal
    @State private var writing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                MoodTrendCard()
                if !journal.topFeelings(days: 30).isEmpty {
                    FeelingsCard()
                }
                SectionTitle(title: "Entries", detail: journal.entries.isEmpty ? nil : "\(journal.entries.count)")
                if journal.entries.isEmpty {
                    Text("Nothing yet. Your routine's journal items and the pencil button both write here.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .surface()
                }
                ForEach(journal.entries) { entry in
                    NavigationLink {
                        JournalEntryView(entry: entry)
                    } label: {
                        JournalEntryRow(entry: entry, calendar: journal.calendar)
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle("Journal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    writing = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New entry")
            }
        }
        .sheet(isPresented: $writing) {
            NavigationStack { JournalComposer(prompt: nil) { _ in } }
                .presentationBackground(Palette.background)
        }
    }
}

private struct MoodTrendCard: View {
    @Environment(JournalModel.self) private var journal

    var body: some View {
        let series = journal.moodSeries(days: 30)
        let week = journal.averageMood(lastDays: 7)
        let lastWeek = journal.averageMood(lastDays: 7, endingDaysAgo: 7)
        VStack(alignment: .leading, spacing: Spacing.m) {
            CardHeader(title: "Mood, last 30 days", symbol: "chart.line.uptrend.xyaxis", tint: Palette.rehab)
            if series.count >= 2 {
                Chart {
                    ForEach(series.indices, id: \.self) { index in
                        let point = series[index]
                        let date = point.day.startDate(calendar: journal.calendar)
                        AreaMark(x: .value("Day", date), y: .value("Mood", point.mood))
                            .foregroundStyle(LinearGradient(colors: [Palette.rehab.opacity(0.35), Palette.rehab.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Day", date), y: .value("Mood", point.mood))
                            .foregroundStyle(Palette.rehab)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Day", date), y: .value("Mood", point.mood))
                            .foregroundStyle(JournalStyle.tint(Mood(rawValue: Int(point.mood.rounded())) ?? .okay))
                            .symbolSize(36)
                    }
                }
                .chartYScale(domain: 1...5)
                .chartYAxis {
                    AxisMarks(values: [1, 3, 5]) { value in
                        AxisGridLine().foregroundStyle(Palette.border)
                        AxisValueLabel {
                            if let raw = value.as(Int.self), let mood = Mood(rawValue: raw) { Text(mood.title) }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 170)
            } else {
                Text("Write on two different days to see your trend.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            HStack(spacing: Spacing.s) {
                StatTile(value: week.map { String(format: "%.1f", $0) } ?? "–", label: "This week", symbol: "calendar",
                         tint: Palette.rehab)
                StatTile(value: change(week, lastWeek), label: "vs last week", symbol: "arrow.up.arrow.down",
                         tint: Palette.frost)
                StatTile(value: "\(journal.streak)", label: "Day streak", symbol: "flame.fill", tint: Palette.kitchen)
            }
        }
        .surface()
    }

    private func change(_ now: Double?, _ before: Double?) -> String {
        guard let now, let before else { return "–" }
        let delta = now - before
        return delta == 0 ? "Same" : String(format: "%+.1f", delta)
    }
}

private struct FeelingsCard: View {
    @Environment(JournalModel.self) private var journal

    var body: some View {
        let top = journal.topFeelings(days: 30)
        let most = Double(top.first?.count ?? 1)
        VStack(alignment: .leading, spacing: Spacing.s) {
            CardHeader(title: "Feelings, last 30 days", symbol: "heart.fill", tint: Palette.rose)
            ForEach(top.indices, id: \.self) { index in
                let item = top[index]
                HStack(spacing: Spacing.s) {
                    Text(item.feeling)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 92, alignment: .leading)
                    ThinProgressBar(progress: Double(item.count) / most, height: 8, tint: Palette.rose)
                    Text("\(item.count)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
        .surface()
    }
}

private struct JournalEntryRow: View {
    let entry: JournalEntry
    let calendar: Calendar

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            IconTile(symbol: entry.mood.symbol, tint: JournalStyle.tint(entry.mood), size: 40, filled: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.prompt ?? entry.mood.title)
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
                if !entry.text.isEmpty {
                    Text(entry.text)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
                if !entry.feelings.isEmpty {
                    Text(entry.feelings.joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JournalStyle.tint(entry.mood))
                }
            }
            Spacer(minLength: 0)
        }
        .surface()
    }
}

private struct JournalEntryView: View {
    @Environment(JournalModel.self) private var journal
    @Environment(\.dismiss) private var dismiss
    let entry: JournalEntry
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.s) {
                    IconTile(symbol: entry.mood.symbol, tint: JournalStyle.tint(entry.mood), size: 52, filled: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.mood.title)
                            .font(.display(26))
                            .foregroundStyle(Palette.textPrimary)
                        Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                if let prompt = entry.prompt {
                    Text(prompt)
                        .font(.headline)
                        .foregroundStyle(Palette.textSecondary)
                }
                if !entry.text.isEmpty {
                    Text(entry.text)
                        .font(.body)
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .surface()
                        .textSelection(.enabled)
                }
                if !entry.feelings.isEmpty {
                    ChipFlow().callAsFunction {
                        ForEach(entry.feelings, id: \.self) { feeling in
                            Chip(text: feeling, tint: JournalStyle.tint(entry.mood), fill: JournalStyle.tint(entry.mood).opacity(0.14))
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) { confirmingDelete = true }
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                journal.delete(entry)
                dismiss()
            }
        }
    }
}

enum JournalStyle {
    static func tint(_ mood: Mood) -> Color {
        switch mood {
        case .awful: Palette.error
        case .low: Palette.warning
        case .okay: Palette.frost
        case .good: Palette.fresh
        case .great: Palette.accent
        }
    }
}
