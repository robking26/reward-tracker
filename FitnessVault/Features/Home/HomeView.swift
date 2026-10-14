import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var showingSettings: Bool
    @Binding var selection: AppTab
    @State private var capturingMeal = false

    private let columns = [GridItem(.flexible(), spacing: Spacing.s), GridItem(.flexible(), spacing: Spacing.s)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    StatusNotices()

                    VaultHeroCard(summary: model.vault)

                    TodayCard(capturingMeal: $capturingMeal, selection: $selection)

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Today's Activity") {
                            CategoryListView(title: "Activity", categories: RewardCategory.activity)
                        }
                        LazyVGrid(columns: columns, spacing: Spacing.s) {
                            ForEach([RewardCategory.steps, .exercise, .strength, .activeEnergy]) { category in
                                ActivityMetricLink(category: category, period: .day)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Nutrition") {
                            CategoryListView(title: "Nutrition", categories: RewardCategory.nutrition)
                        }
                        NutritionGrid()
                    }
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.xl)
                .redacted(reason: model.loadState == .loading ? .placeholder : [])
            }
            .pageBackground()
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton(isPresented: $showingSettings)
                }
            }
            .refreshable {
                await model.syncHealth()
                await model.settleIfDue()
            }
            .mealCapture(isPresented: $capturingMeal)
        }
    }
}

// MARK: - Vault hero

/// The dashboard's focal point: what's left to unlock this month.
struct VaultHeroCard: View {
    let summary: VaultSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text("\(summary.month.monthName()) vault")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("\(summary.percentUnlocked)% unlocked")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(summary.earned.isPositive ? Palette.accent : Palette.textSecondary)
                    .contentTransition(.numericText(value: Double(summary.percentUnlocked)))
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if summary.isFullyUnlocked {
                    MoneyText(amount: summary.allocation, font: .system(.largeTitle, design: .default), weight: .medium,
                              color: Palette.accent)
                    Text("You've unlocked your full \(summary.allocation.formatted()).")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    MoneyText(amount: summary.remainingToUnlock, font: .system(.largeTitle, design: .default), weight: .medium)
                    Text("left to unlock")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            ThinProgressBar(progress: summary.progress)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Earned")
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                    MoneyText(amount: summary.earned, font: .headline, weight: .semibold, color: Palette.accent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Monthly allocation")
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                    MoneyText(amount: summary.allocation, font: .headline, weight: .semibold, color: Palette.textPrimary)
                }
            }
        }
        .surface(radius: Radius.hero, padding: Spacing.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(summary.month.monthName()) vault. \(summary.remainingToUnlock.formatted()) left to unlock. " +
            "Earned \(summary.earned.formatted()) of \(summary.allocation.formatted()), \(summary.percentUnlocked) percent.")
    }
}

// MARK: - Today

struct TodayCard: View {
    @Environment(AppModel.self) private var model
    @Binding var capturingMeal: Bool
    @Binding var selection: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Earned today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    MoneyText(amount: model.earned(on: model.today), font: .title, weight: .medium, color: Palette.accent)
                }
                Spacer()
                Button {
                    capturingMeal = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 52, height: 52)
                        .background(Palette.accent, in: Circle())
                }
                .buttonStyle(CardButtonStyle())
                .accessibilityLabel("Photograph a meal")
            }

            Divider().overlay(Palette.border)

            Button {
                selection = .vault
            } label: {
                PayoutStatusLine()
            }
            .buttonStyle(.plain)
        }
        .surface()
    }
}

/// One line describing where outstanding earnings are on their way to Monzo.
struct PayoutStatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private var pending: PaymentOrder? { model.payments.first { $0.status.isUnresolved } }

    private var symbol: String { pending?.status.symbol ?? (model.isBankConfigured ? "clock" : "building.columns") }
    private var tint: Color { pending?.status.tint ?? Palette.textSecondary }

    private var message: String {
        if let pending {
            switch pending.status {
            case .awaitingApproval: return "\(pending.amount.formatted()) is awaiting your approval in Starling."
            case .processing: return "\(pending.amount.formatted()) is on its way to Monzo."
            default: return "A \(pending.amount.formatted()) payment needs checking before anything else is sent."
            }
        }
        guard model.isBankConfigured else { return "Connect Starling to start receiving money in Monzo." }
        let time = model.nextSettlement.formatted(date: .omitted, time: .shortened)
        let outstanding = model.flow.earned - model.flow.paid - model.flow.awaitingApproval - model.flow.processing - model.flow.needsChecking
        if outstanding.isPositive {
            return "\(outstanding.nonNegative.formatted()) will be prepared for Monzo at \(time). You'll approve it in Starling."
        }
        return "Next payment to Monzo is prepared at \(time)."
    }
}

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
                earned: earned(days),
                earnedCaption: caption)
        }
        .buttonStyle(CardButtonStyle())
    }

    private func earned(_ days: [DayKey]) -> Pence? {
        if category.settlesAfterDayEnds && period == .day { return nil }
        return model.earned(category, in: days)
    }

    private var caption: String? {
        guard category.settlesAfterDayEnds && period == .day else { return nil }
        let reward = model.provisionalNutritionReward(category)
        return reward.isPositive ? "On track for +\(reward.formatted())" : "Confirmed after today"
    }
}

/// Reference goals for the compact progress bars. They don't affect earnings, which have no thresholds.
enum DailyGoals {
    static func progress(_ category: RewardCategory, _ metrics: DailyMetrics, settings: AppSettings) -> Double? {
        func ratio(_ value: Int, _ goal: Int) -> Double { goal > 0 ? min(1, Double(value) / Double(goal)) : 0 }
        switch category {
        case .steps: return ratio(metrics.steps, 10_000)
        case .exercise: return ratio(metrics.exerciseSeconds, 30 * 60)
        case .strength: return ratio(metrics.strengthSeconds, 45 * 60)
        case .activeEnergy: return ratio(metrics.activeKilocalories, 600)
        case .swimming: return ratio(metrics.swimmingMetres, 1_000)
        case .flights: return ratio(metrics.flightsClimbed, 10)
        case .mealPhoto: return ratio(metrics.rewardEligibleMeals, settings.rates.maxRewardedMealPhotosPerDay)
        case .proteinTarget: return ratio(metrics.proteinGrams, settings.nutrition.proteinGrams)
        case .calorieTarget: return ratio(metrics.dietaryKilocalories, settings.nutrition.calorieRange.lowerBound)
        }
    }
}

struct NutritionGrid: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.flexible(), spacing: Spacing.s), GridItem(.flexible(), spacing: Spacing.s)]

    var body: some View {
        let today = model.todayMetrics
        let targets = model.settings.nutrition
        LazyVGrid(columns: columns, spacing: Spacing.s) {
            NavigationLink { CategoryDetailView(category: .calorieTarget) } label: {
                MetricCard(title: "Calories", symbol: "flame", timeframe: "\(MeasureFormat.number(targets.calorieRange.lowerBound))–\(MeasureFormat.number(targets.calorieRange.upperBound)) kcal",
                           measurement: MeasureFormat.number(today.dietaryKilocalories), unit: "kcal",
                           progress: DailyGoals.progress(.calorieTarget, today, settings: model.settings), earned: nil,
                           earnedCaption: caption(.calorieTarget))
            }
            .buttonStyle(CardButtonStyle())

            NavigationLink { CategoryDetailView(category: .proteinTarget) } label: {
                MetricCard(title: "Protein", symbol: "fork.knife", timeframe: "Target \(targets.proteinGrams) g",
                           measurement: MeasureFormat.number(today.proteinGrams), unit: "g",
                           progress: DailyGoals.progress(.proteinTarget, today, settings: model.settings), earned: nil,
                           earnedCaption: caption(.proteinTarget))
            }
            .buttonStyle(CardButtonStyle())

            NavigationLink { MealsJournalList() } label: {
                MetricCard(title: "Fat", symbol: "drop", timeframe: "Today",
                           measurement: MeasureFormat.number(today.fatGrams), unit: "g",
                           progress: nil, earned: nil, earnedCaption: "Tracked, not rewarded")
            }
            .buttonStyle(CardButtonStyle())

            NavigationLink { MealsJournalList() } label: {
                MetricCard(title: "Carbs", symbol: "leaf", timeframe: "Today",
                           measurement: MeasureFormat.number(today.carbohydrateGrams), unit: "g",
                           progress: nil, earned: nil, earnedCaption: "Tracked, not rewarded")
            }
            .buttonStyle(CardButtonStyle())
        }
    }

    private func caption(_ category: RewardCategory) -> String {
        let reward = model.provisionalNutritionReward(category)
        return reward.isPositive ? "On track for +\(reward.formatted())" : "Confirmed after today"
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
            total.rewardEligibleMeals += next.rewardEligibleMeals
            total.loggedMeals += next.loggedMeals
            total.proteinGrams += next.proteinGrams
            total.dietaryKilocalories += next.dietaryKilocalories
            total.carbohydrateGrams += next.carbohydrateGrams
            total.fatGrams += next.fatGrams
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

#if DEBUG
#Preview {
    RootView()
        .environment(PreviewFixtures.model())
        .preferredColorScheme(.dark)
}
#endif
