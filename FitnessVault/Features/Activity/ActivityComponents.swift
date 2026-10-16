import SwiftUI

// MARK: - Grids

enum ActivityPeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    var timeframe: String {
        switch self {
        case .day: "Today"
        case .week: "Last 7 days"
        case .month: "This month"
        }
    }

    @MainActor
    func days(model: AppModel) -> [DayKey] {
        switch self {
        case .day: [model.today]
        case .week: (0..<7).map { model.today.adding(days: -$0, calendar: model.calendar) }
        case .month: model.currentMonth.days(calendar: model.calendar).filter { $0 <= model.today }
        }
    }
}

/// A metric card for one reward category, linking to its detail screen.
struct ActivityMetricLink: View {
    @Environment(AppModel.self) private var model
    let category: RewardCategory
    let period: ActivityPeriod
    var showsRate = false

    var body: some View {
        let days = period.days(model: model)
        let metrics = days.compactMap { model.metricsByDay[$0] }.combined(day: model.today)
        let measure = MeasureFormat.measurement(category, metrics)
        NavigationLink {
            CategoryDetailView(category: category)
        } label: {
            MetricCard(
                title: category.title,
                symbol: category.symbol,
                timeframe: showsRate ? model.settings.rates.rateDescription(for: category) : period.timeframe,
                measurement: measure.value,
                unit: measure.unit,
                progress: period == .day ? DailyGoals.progress(category, metrics, settings: model.settings) : nil,
                earned: model.earned(category, in: days))
        }
        .buttonStyle(CardButtonStyle())
    }

}

/// Reference goals for the compact progress bars. They don't affect earnings, which have no thresholds.
enum DailyGoals {
    static func progress(_ category: RewardCategory, _ metrics: DailyMetrics, settings: AppSettings) -> Double? {
        func ratio(_ value: Int, _ goal: Int) -> Double { goal > 0 ? min(1, Double(value) / Double(goal)) : 0 }
        switch category {
        case .steps: return ratio(metrics.steps, settings.rates.stepsForCap)
        case .exercise: return ratio(metrics.exerciseSeconds, 30 * 60)
        case .strength: return ratio(metrics.strengthSeconds, 45 * 60)
        case .activeEnergy: return ratio(metrics.activeKilocalories, 600)
        case .swimming: return ratio(metrics.swimmingMetres, 1_000)
        case .flights: return ratio(metrics.flightsClimbed, 10)
        case .mealPhoto, .proteinTarget, .calorieTarget: return nil
        }
    }
}


extension Array where Element == DailyMetrics {
    /// Sums several days into one set of totals.
    func combined(day: DayKey) -> DailyMetrics {
        reduce(into: DailyMetrics(day: day)) { total, next in
            total.steps += next.steps
            total.swimmingMetres += next.swimmingMetres
            total.strengthSeconds += next.strengthSeconds
            total.exerciseSeconds += next.exerciseSeconds
            total.activeKilocalories += next.activeKilocalories
            total.flightsClimbed += next.flightsClimbed
        }
    }
}

// MARK: - Status notices

/// Honest banners for offline, missing permission, stale data and errors.
struct StatusNotices: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Spacing.s) {
            if model.settings.demoMode {
                NoticeBanner(symbol: "theatermasks", title: "Demo mode",
                             message: "Showing generated activity and a pretend bank. No real money moves.",
                             tint: Palette.textSecondary)
            }
            if !model.network.isOnline {
                NoticeBanner(symbol: "wifi.slash", title: "You're offline",
                             message: "Activity still syncs from Apple Health. Banking resumes when you reconnect.")
            }
            switch model.healthAccess {
            case .unavailable where !model.settings.demoMode:
                NoticeBanner(symbol: "heart.slash", title: "Apple Health unavailable",
                             message: "This device can't share Health data, so activity can't earn money here.",
                             tint: Palette.error)
            case .notDetermined where !model.settings.demoMode:
                NoticeBanner(symbol: "heart.text.square", title: "Connect Apple Health",
                             message: "Fitness Vault needs to read your activity to calculate what you've earned.",
                             tint: Palette.accent, actionTitle: "Allow Access") {
                    Task { await model.requestHealthAccess() }
                }
            default:
                EmptyView()
            }
            if let error = model.healthSyncError {
                NoticeBanner(symbol: "exclamationmark.triangle", title: "Sync problem", message: error,
                             actionTitle: "Try Again") {
                    Task { await model.syncHealth() }
                }
            } else if model.healthAccess == .requested && model.isHealthDataStale && model.loadState == .loaded {
                NoticeBanner(symbol: "clock.arrow.circlepath", title: "Activity may be out of date",
                             message: "Last synced \(MeasureFormat.relative(model.lastHealthSync)). Pull down to refresh.")
            }
        }
    }
}

