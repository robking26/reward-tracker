import Charts
import PhotosUI
import SwiftUI
import UIKit

/// One plotted value. A struct rather than a tuple, so charts can identify points by date.
struct ChartPoint: Identifiable, Hashable {
    var date: Date
    var value: Double
    var id: Date { date }
}

/// Quiet chart axes: tertiary labels, faint grid lines, no axis line.
private struct QuietAxes: ViewModifier {
    func body(content: Content) -> some View {
        content
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel().foregroundStyle(Palette.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(Palette.border)
                    AxisValueLabel().foregroundStyle(Palette.textTertiary)
                }
            }
    }
}

private extension View {
    func quietAxes() -> some View { modifier(QuietAxes()) }
}

/// A big number with a smaller unit and a caption, used at the top of progress cards.
private struct HeadlineValue: View {
    let value: String
    var unit: String = ""
    var caption: String? = nil
    var captionTint: Color = Palette.textSecondary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.display(32))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            if let caption {
                Text(caption)
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(captionTint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Text for a card with nothing to show yet.
private struct EmptyCardText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Body (O-A): trends, not truths

struct BodyTrendCard: View {
    let samples: [BodySample]

    private var weights: [ChartPoint] {
        samples.compactMap { sample in sample.kilograms.map { ChartPoint(date: sample.date, value: $0) } }
    }
    private var fats: [ChartPoint] {
        samples.compactMap { sample in sample.bodyFatPercent.map { ChartPoint(date: sample.date, value: $0) } }
    }

    /// 7-reading rolling average, which smooths water and food swings.
    private var trend: [ChartPoint] {
        let all = weights
        return all.indices.map { index in
            let window = all[max(0, index - 6)...index].map(\.value)
            return ChartPoint(date: all[index].date, value: window.reduce(0, +) / Double(window.count))
        }
    }

    var body: some View {
        let trend = self.trend
        VStack(alignment: .leading, spacing: Spacing.m) {
            CardHeader(title: "Body", symbol: "figure.arms.open", tint: Palette.rose, subtitle: "Trend, not a verdict")
            if weights.isEmpty {
                EmptyCardText(text: "No weigh-ins in Apple Health yet. Smart scales or the Health app both work.")
            } else {
                if let latest = trend.last {
                    HeadlineValue(value: String(format: "%.1f", latest.value), unit: "kg", caption: changeText(trend))
                }
                Chart {
                    ForEach(weights) { point in
                        PointMark(x: .value("Date", point.date), y: .value("kg", point.value))
                            .foregroundStyle(Palette.textTertiary.opacity(0.5))
                            .symbolSize(10)
                    }
                    ForEach(trend) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Trend", point.value))
                            .foregroundStyle(Palette.rose)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .quietAxes()
                .frame(height: 150)
                .accessibilityLabel("Weight trend")
                if let fat = fats.last {
                    Chip(text: String(format: "Body fat ≈ %.1f%%", fat.value), symbol: "percent")
                }
            }
        }
        .surface()
    }

    private func changeText(_ trend: [ChartPoint]) -> String? {
        guard let first = trend.first, let last = trend.last, trend.count > 7 else { return nil }
        return String(format: "%+.1f kg over 90 days", last.value - first.value)
    }
}

// MARK: - Strength (W2)

struct StrengthCard: View {
    @Environment(TrainingModel.self) private var training
    @State private var selected = "inclineDBBench"

    static let lifts = ["inclineDBBench", "flatDBBench", "barbellRow", "latPulldown", "seatedDBShoulderPress",
                        "barbellSquat", "deadlift"]

    var body: some View {
        let records = training.records()
        let points = records.filter { $0.exerciseID == selected }
            .compactMap { record in record.topWeight.map { ChartPoint(date: record.date, value: $0) } }
        let perSide = ExerciseLibrary.exercise(selected)?.perSide ?? false
        VStack(alignment: .leading, spacing: Spacing.m) {
            CardHeader(title: "Strength", symbol: "chart.line.uptrend.xyaxis", tint: Palette.accent) {
                Menu {
                    Picker("Lift", selection: $selected) {
                        ForEach(Self.lifts, id: \.self) { id in
                            Text(ExerciseLibrary.exercise(id)?.name ?? id).tag(id)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(ExerciseLibrary.exercise(selected)?.name ?? selected)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(Palette.elevated, in: Capsule())
                }
            }
            if points.isEmpty {
                EmptyCardText(text: "Log a session with this lift and its working weight shows here.")
            } else {
                if let first = points.first, let last = points.last {
                    HeadlineValue(value: WeightFormat.text(last.value, perSide: perSide),
                                  caption: "\(WeightFormat.text(last.value - first.value)) since you started",
                                  captionTint: last.value >= first.value ? Palette.accent : Palette.textSecondary)
                }
                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("Date", point.date), y: .value("kg", point.value))
                            .foregroundStyle(LinearGradient(colors: [Palette.accent.opacity(0.35), Palette.accent.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Date", point.date), y: .value("kg", point.value))
                            .foregroundStyle(Palette.accent)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    if let last = points.last {
                        PointMark(x: .value("Date", last.date), y: .value("kg", last.value))
                            .foregroundStyle(Palette.accent)
                            .symbolSize(70)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .quietAxes()
                .frame(height: 140)
            }
        }
        .surface()
    }
}

// MARK: - Workouts per week (rolling, no streaks)

struct WorkoutsPerWeekCard: View {
    @Environment(TrainingModel.self) private var training
    @Environment(AppModel.self) private var model

    var body: some View {
        let weeks = lastWeeks(8)
        let total = weeks.map(\.count).reduce(0, +)
        VStack(alignment: .leading, spacing: Spacing.m) {
            CardHeader(title: "Sessions", symbol: "chart.bar.fill", tint: Palette.frost, subtitle: "Last 8 weeks")
            HeadlineValue(value: "\(total)", unit: total == 1 ? "session" : "sessions",
                          caption: String(format: "%.1f a week on average", Double(total) / 8))
            Chart {
                ForEach(weeks, id: \.start) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Sessions", week.count), width: .ratio(0.6))
                        .foregroundStyle(week.isCurrent ? Palette.frost : Palette.frost.opacity(0.45))
                        .cornerRadius(6)
                }
            }
            .quietAxes()
            .frame(height: 120)
        }
        .surface()
    }

    private struct Week {
        var start: Date
        var count: Int
        var isCurrent: Bool
    }

    private func lastWeeks(_ count: Int) -> [Week] {
        let calendar = model.calendar
        let today = model.today
        let weekday = calendar.component(.weekday, from: today.startDate(calendar: calendar)) // 1 = Sunday
        let monday = today.adding(days: -((weekday + 5) % 7), calendar: calendar)
        let finished = training.sessions().filter { $0.endedAt != nil }
        return (0..<count).reversed().map { offset in
            let start = monday.adding(days: -7 * offset, calendar: calendar)
            let end = start.adding(days: 7, calendar: calendar)
            let sessions = finished.filter { session in
                guard let day = DayKey(string: session.day) else { return false }
                return day >= start && day < end
            }.count
            return Week(start: start.startDate(calendar: calendar), count: sessions, isCurrent: offset == 0)
        }
    }
}

// MARK: - Walking (K1)

struct WalkingCard: View {
    @Environment(AppModel.self) private var model
    @Environment(TrainingModel.self) private var training
    @State private var target = WalkingTargets.startingAim

    var body: some View {
        let days = (0..<14).reversed().map { model.today.adding(days: -$0, calendar: model.calendar) }
        let steps = days.map { model.metrics(for: $0).steps }
        let bars = zip(days, steps).map { ChartPoint(date: $0.startDate(calendar: model.calendar), value: Double($1)) }
        let hit = steps.filter { $0 >= target }.count
        VStack(alignment: .leading, spacing: Spacing.m) {
            CardHeader(title: "Walking", symbol: "figure.walk", tint: Palette.fresh, subtitle: "Last 14 days") {
                Chip(text: "Aim \(target.formatted())", symbol: "target", tint: Palette.fresh, fill: Palette.fresh.opacity(0.14))
            }
            if let baseline = WalkingTargets.baseline(Array(steps.dropLast())) {
                HeadlineValue(value: baseline.formatted(), unit: "steps", caption: "Usual day · aim hit on \(hit) of 14")
                Chart {
                    ForEach(bars) { bar in
                        BarMark(x: .value("Day", bar.date, unit: .day), y: .value("Steps", bar.value), width: .ratio(0.62))
                            .foregroundStyle(bar.value >= Double(target) ? Palette.fresh : Palette.fresh.opacity(0.32))
                            .cornerRadius(4)
                    }
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(Palette.textTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .quietAxes()
                .frame(height: 130)
                Footnote("The aim only rises by 500 a week when you've hit it on five days and the knee is settled. Long-term: 12,500.")
            } else {
                EmptyCardText(text: "Your step baseline appears once Apple Health has a few days of walking.")
            }
        }
        .surface()
        .task(id: steps) { target = training.stepTarget(recentSteps: steps) }
    }
}

// MARK: - Swimming (SW1–SW2)

struct SwimCard: View {
    let swims: [SwimSample]

    var body: some View {
        let next = SwimPlan.next(swims.map { SwimRecord(date: $0.date, minutes: $0.minutes, metres: $0.metres) })
        let kilometres = Double(swims.map(\.metres).reduce(0, +)) / 1_000
        VStack(alignment: .leading, spacing: Spacing.m) {
            CardHeader(title: "Swimming", symbol: "figure.pool.swim", tint: Palette.frost, subtitle: "Towards Darwen Masters")
            if swims.isEmpty {
                EmptyCardText(text: "Swims recorded on your Apple Watch appear here.")
            } else {
                HeadlineValue(value: String(format: "%.1f", kilometres), unit: "km", caption: "\(swims.count) swims in 90 days")
                VStack(spacing: 0) {
                    ForEach(swims.suffix(3).reversed(), id: \.date) { swim in
                        HStack {
                            Text(swim.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .foregroundStyle(Palette.textPrimary)
                            Spacer()
                            Text("\(swim.minutes) min · \(swim.metres) m")
                                .monospacedDigit()
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .font(.footnote)
                        .padding(.vertical, Spacing.xs)
                    }
                }
            }
            HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(Palette.frost)
                    .accessibilityHidden(true)
                Text("Next swim: \(next.note)")
                    .font(.footnote)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.frost.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .surface()
    }
}

// MARK: - Knee and the road to five-a-side (O-B, R3)

struct KneeCard: View {
    @Environment(TrainingModel.self) private var training
    @State private var checking = false

    var body: some View {
        let logs = training.symptomLogs().filter { $0.date > Date.now.addingTimeInterval(-28 * 86_400) }
        let settled = training.kneeStatus == .settled
        let statusTint: Color = settled ? Palette.success : Palette.warning
        let steps = milestones
        let done = steps.filter(\.done).count
        VStack(alignment: .leading, spacing: Spacing.m) {
            CardHeader(title: "Knee", symbol: "cross.case.fill", tint: Palette.rehab, subtitle: "Pain, last 4 weeks") {
                Chip(text: training.kneeStatus.title, symbol: settled ? "checkmark" : "exclamationmark.triangle.fill",
                     tint: statusTint, fill: statusTint.opacity(0.15))
            }
            if logs.isEmpty {
                EmptyCardText(text: "No check-ins in the last four weeks.")
            } else {
                Chart {
                    ForEach(logs, id: \.id) { log in
                        BarMark(x: .value("Date", log.date, unit: .day), y: .value("Pain", max(log.pain, 0)), width: .fixed(6))
                            .foregroundStyle(log.pain >= 3 ? Palette.warning : Palette.rehab)
                            .cornerRadius(3)
                    }
                }
                .chartYScale(domain: 0...10)
                .quietAxes()
                .frame(height: 100)
            }
            Button {
                checking = true
            } label: {
                Label("Log a knee check", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle(tint: Palette.rehab, fill: Palette.rehab.opacity(0.14)))

            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text("Road to five-a-side")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Text("\(done) of \(steps.count)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps.indices, id: \.self) { index in
                        MilestoneRow(title: steps[index].title, done: steps[index].done, isLast: index == steps.count - 1)
                    }
                }
            }
            .padding(Spacing.m)
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            Footnote("Each step needs a settled knee, and running or changing direction needs your physio's go-ahead. October 2027 is a hope, not a deadline.")
        }
        .surface()
        .sheet(isPresented: $checking) {
            NavigationStack {
                KneeCheckView(timing: .general) { pain, swelling, sharp in
                    training.logSymptom(timing: .general, pain: pain, swelling: swelling, sharp: sharp)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Palette.background)
        }
    }

    /// Only the steps the app can see are ticked automatically; the rest need the physio, not an app (R3).
    private struct Milestone {
        var title: String
        var done: Bool
    }

    private var milestones: [Milestone] {
        let fortnight = Date.now.addingTimeInterval(-14 * 86_400)
        let recentPain = training.symptomLogs().filter { $0.date > fortnight }.contains { $0.pain >= 3 || $0.swelling || $0.sharp }
        let stepDowns = training.records().filter { $0.exerciseID == "stepDown" && $0.date > fortnight && !$0.pain }.count
        return [
            Milestone(title: "Settled for two weeks", done: !recentPain && training.kneeStatus == .settled),
            Milestone(title: "Pain-free step-downs in two sessions", done: stepDowns >= 2),
            Milestone(title: "Strength work on both legs without flare-ups", done: false),
            Milestone(title: "Jogging trial, with your physio's OK", done: false),
            Milestone(title: "Changes of direction, with your physio's OK", done: false),
            Milestone(title: "Casual five-a-side", done: false),
        ]
    }
}

/// A step on a vertical timeline: a filled dot when done, joined to the next by a line.
private struct MilestoneRow: View {
    let title: String
    let done: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(done ? Palette.success : Palette.elevated)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Palette.onAccent)
                    }
                }
                .frame(width: 18, height: 18)
                if !isLast {
                    Rectangle()
                        .fill(done ? Palette.success.opacity(0.5) : Palette.elevated)
                        .frame(width: 2)
                        .frame(minHeight: 16)
                }
            }
            Text(title)
                .font(.footnote)
                .foregroundStyle(done ? Palette.textPrimary : Palette.textSecondary)
                .padding(.bottom, isLast ? 0 : Spacing.s)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not yet")
    }
}

// MARK: - Progress photos: private, on this iPhone only

/// Stores progress photos in the app's own folder with complete file protection: unreadable while the
/// phone is locked, not in the Photos library, deletable and exportable.
enum ProgressPhotoStore {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ProgressPhotos", isDirectory: true)
    }

    static func all() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func save(_ data: Data, date: Date = .now) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        let url = folder.appendingPathComponent(formatter.string(from: date) + ".jpg")
        let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) ?? data
        try jpeg.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func date(of url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return String(name.prefix(10))
    }
}

struct PhotosCard: View {
    @State private var photos: [URL] = ProgressPhotoStore.all()
    @State private var picked: PhotosPickerItem?
    @State private var viewing: URL?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            CardHeader(title: "Progress photos", symbol: "camera.fill", tint: Palette.kitchen, subtitle: "Private to this iPhone") {
                PhotosPicker(selection: $picked, matching: .images) {
                    RoundIconLabel(symbol: "plus", size: 34, tint: Palette.kitchen, fill: Palette.kitchen.opacity(0.16))
                }
                .accessibilityLabel("Add a progress photo")
            }
            if photos.isEmpty {
                Text("Weekly photos show change the scales miss. They're kept privately inside Vaultality on this iPhone, never in your photo library or shared anywhere.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(photos, id: \.self) { url in
                            Button {
                                viewing = url
                            } label: {
                                PhotoThumbnail(url: url)
                            }
                            .accessibilityLabel("Progress photo, \(ProgressPhotoStore.date(of: url))")
                        }
                    }
                }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Palette.warning)
            }
        }
        .surface()
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        _ = try ProgressPhotoStore.save(data)
                        photos = ProgressPhotoStore.all()
                    }
                } catch {
                    self.error = "Couldn't save that photo."
                }
                picked = nil
            }
        }
        .sheet(item: Binding(get: { viewing.map(IdentifiedURL.init) }, set: { viewing = $0?.url })) { item in
            NavigationStack {
                VStack {
                    if let image = UIImage(contentsOfFile: item.url.path) {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                }
                .navigationTitle(ProgressPhotoStore.date(of: item.url))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { viewing = nil } }
                    ToolbarItem(placement: .topBarTrailing) { ShareLink(item: item.url) }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete Photo", role: .destructive) {
                            ProgressPhotoStore.delete(item.url)
                            photos = ProgressPhotoStore.all()
                            viewing = nil
                        }
                    }
                }
                .pageBackground()
            }
        }
    }
}

private struct IdentifiedURL: Identifiable {
    var url: URL
    var id: URL { url }
}

private struct PhotoThumbnail: View {
    let url: URL

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Palette.elevated
            }
        }
        .frame(width: 88, height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
