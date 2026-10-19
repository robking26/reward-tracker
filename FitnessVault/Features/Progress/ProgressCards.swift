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
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Body")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            if weights.isEmpty {
                Text("No weigh-ins in Apple Health yet. Smart scales or the Health app both work. Readings are shown as a trend, not a verdict.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if let latest = trend.last {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(String(format: "%.1f kg", latest.value))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                        if let first = trend.first, trend.count > 7 {
                            let change = latest.value - first.value
                            Text(String(format: "%+.1f kg trend", change))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                Chart {
                    ForEach(weights) { point in
                        PointMark(x: .value("Date", point.date), y: .value("kg", point.value))
                            .foregroundStyle(Palette.textTertiary.opacity(0.5))
                            .symbolSize(12)
                    }
                    ForEach(trend) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Trend", point.value))
                            .foregroundStyle(Palette.accent)
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 150)
                .accessibilityLabel("Weight trend")
                if let fat = fats.last {
                    Text(String(format: "Body fat estimate: %.1f%%", fat.value))
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .surface()
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
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("Strength")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Picker("Lift", selection: $selected) {
                    ForEach(Self.lifts, id: \.self) { id in
                        Text(ExerciseLibrary.exercise(id)?.name ?? id).tag(id)
                    }
                }
                .pickerStyle(.menu)
            }
            if points.isEmpty {
                Text("Log a session with this lift and its working weight shows here.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                if let first = points.first, let last = points.last {
                    let perSide = ExerciseLibrary.exercise(selected)?.perSide ?? false
                    Text("\(WeightFormat.text(last.value, perSide: perSide)) now · \(WeightFormat.text(last.value - first.value)) since you started")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textPrimary)
                }
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value("kg", point.value))
                            .foregroundStyle(Palette.accent)
                        PointMark(x: .value("Date", point.date), y: .value("kg", point.value))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 120)
            }
        }
        .surface()
    }
}

// MARK: - Workouts per week (rolling, no streaks)

struct WorkoutsPerWeekCard: View {
    @Environment(TrainingModel.self) private var training
    @Environment(CoachModel.self) private var coach

    var body: some View {
        let weeks = lastWeeks(8)
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Gym sessions · last 8 weeks")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            Text("\(weeks.map(\.count).reduce(0, +)) sessions in total")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            Chart {
                ForEach(weeks, id: \.start) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Sessions", week.count))
                        .foregroundStyle(Palette.accent)
                    RuleMark(xStart: .value("Week", week.start, unit: .weekOfYear),
                             xEnd: .value("Week", week.start.addingTimeInterval(6 * 86_400), unit: .weekOfYear),
                             y: .value("Target", week.target))
                        .foregroundStyle(Palette.textTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .frame(height: 120)
            Text("Dashed line: that week's target as the routine builds up.")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .surface()
    }

    private struct Week {
        var start: Date
        var count: Int
        var target: Int
    }

    private func lastWeeks(_ count: Int) -> [Week] {
        let calendar = coach.calendar
        let today = coach.today
        let monday = today.adding(days: -(coach.isoWeekday(today) - 1), calendar: calendar)
        let finished = training.sessions().filter { $0.endedAt != nil }
        return (0..<count).reversed().map { offset in
            let start = monday.adding(days: -7 * offset, calendar: calendar)
            let end = start.adding(days: 7, calendar: calendar)
            let sessions = finished.filter { session in
                guard let day = DayKey(string: session.day) else { return false }
                return day >= start && day < end
            }.count
            return Week(start: start.startDate(calendar: calendar), count: sessions,
                        target: RecommendationEngine.weeklyWorkoutTarget(on: start, calendar: calendar))
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
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Walking · last 14 days")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            if let baseline = WalkingTargets.baseline(Array(steps.dropLast())) {
                Text("Usual day \(baseline.formatted()) steps · aiming for \(target.formatted())")
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Chart {
                    ForEach(bars) { bar in
                        BarMark(x: .value("Day", bar.date, unit: .day), y: .value("Steps", bar.value))
                            .foregroundStyle(bar.value >= Double(target) ? Palette.accent : Palette.accent.opacity(0.4))
                    }
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(Palette.textTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .frame(height: 120)
                Text("The target only rises by 500 a week when you've hit it on five days and the knee is settled. Long-term aim: 12,500.")
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
            } else {
                Text("Your step baseline appears once Apple Health has a few days of walking.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
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
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Swimming")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            if swims.isEmpty {
                Text("Swims recorded on your Apple Watch appear here.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Text("\(swims.count) swims · \(Double(swims.map(\.metres).reduce(0, +)) / 1_000, specifier: "%.1f") km")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                ForEach(swims.suffix(3).reversed(), id: \.date) { swim in
                    HStack {
                        Text(swim.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        Spacer()
                        Text("\(swim.minutes) min · \(swim.metres) m").monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                }
            }
            Text("Next swim: \(next.note)")
                .font(.footnote)
                .foregroundStyle(Palette.textPrimary)
            Text("Building towards Darwen Masters at your own pace.")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
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
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("Knee")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text(training.kneeStatus.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(training.kneeStatus == .settled ? Palette.success : Palette.warning)
            }
            if logs.isEmpty {
                Text("No check-ins in the last four weeks.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Chart {
                    ForEach(logs, id: \.id) { log in
                        PointMark(x: .value("Date", log.date), y: .value("Pain", log.pain))
                            .foregroundStyle(log.timing == .nextDay ? Palette.warning : Palette.accent)
                    }
                }
                .chartYScale(domain: 0...10)
                .frame(height: 100)
            }
            Button("Log a knee check") { checking = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accent)

            Divider().overlay(Palette.border)
            Text("Road to five-a-side")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            ForEach(milestones, id: \.title) { milestone in
                Label(milestone.title, systemImage: milestone.done ? "checkmark.circle.fill" : "circle")
                    .font(.footnote)
                    .foregroundStyle(milestone.done ? Palette.success : Palette.textSecondary)
            }
            Text("Each step needs a settled knee, and running or changing direction needs your physio's go-ahead. October 2027 is a hope, not a deadline.")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
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
            HStack {
                Text("Progress photos")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                PhotosPicker(selection: $picked, matching: .images) {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
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
        .frame(width: 72, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
