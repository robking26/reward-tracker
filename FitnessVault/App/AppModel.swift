import Foundation
import Observation
import SwiftData
import WidgetKit

/// The app's single source of state. Coordinates Apple Health sync, reward calculation,
/// the ledger and Starling settlement. Views read derived state from here; they never compute money.
@MainActor
@Observable
final class AppModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let settingsStore: SettingsStore
    let network: NetworkMonitor
    let calendar: Calendar
    private let context: ModelContext
    private let liveHealth: HealthDataProviding
    private let demoHealth: HealthDataProviding
    private let demoBank: BankingService
    private let now: () -> Date

    // MARK: Derived state

    private(set) var loadState: LoadState = .idle
    private(set) var healthAccess: HealthAccess = .notDetermined
    private(set) var lastHealthSync: Date?
    private(set) var healthSyncError: String?
    private(set) var isSyncing = false
    private(set) var isSettling = false

    /// Metrics for the current month and at least the last seven days, keyed by day.
    private(set) var metricsByDay: [DayKey: DailyMetrics] = [:]
    /// Recorded earnings for the current and previous month, keyed by day.
    private(set) var earningsByDay: [DayKey: [RewardCategory: Pence]] = [:]
    private(set) var vault: VaultSummary
    private(set) var flow: MoneyFlow
    private(set) var monthHistory: [VaultSummary] = []
    private(set) var payments: [PaymentOrder] = []
    private(set) var bankSnapshot: BankSnapshot?
    private(set) var bankError: String?
    private(set) var fundingPlan: VaultFunding.Plan?
    /// Today's Activity rings from Apple Health, if available.
    private(set) var todayRings: ActivityRingsSnapshot?
    private var lastWidgetSnapshot: WidgetSnapshot?

    var settings: AppSettings { settingsStore.settings }
    var today: DayKey { DayKey(now(), calendar: calendar) }
    var currentMonth: MonthKey { today.monthKey }
    var todayMetrics: DailyMetrics { metricsByDay[today] ?? DailyMetrics(day: today) }

    init(
        container: ModelContainer,
        settingsStore: SettingsStore = SettingsStore(),
        liveHealth: HealthDataProviding = HealthKitService(),
        demoHealth: HealthDataProviding = MockHealthService(),
        demoBank: BankingService = MockBankingService(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        context = container.mainContext
        self.settingsStore = settingsStore
        self.liveHealth = liveHealth
        self.demoHealth = demoHealth
        self.demoBank = demoBank
        self.calendar = calendar
        self.now = now
        network = NetworkMonitor()
        let month = DayKey(now(), calendar: calendar).monthKey
        vault = .empty(month, allocation: settingsStore.settings.monthlyAllocation)
        flow = MoneyFlow(earned: .zero, transfers: [], payments: [])
    }

    // MARK: Services

    var health: HealthDataProviding { settings.demoMode ? demoHealth : liveHealth }

    var banking: BankingService? {
        if settings.demoMode { return demoBank }
        guard let token = Keychain.read(.starlingToken(for: settings.bankingEnvironment)), !token.isEmpty else { return nil }
        return StarlingClient(environment: settings.bankingEnvironment, token: token,
                              configuration: settings.starling, liveTransfersConfirmed: settings.liveTransfersConfirmed)
    }

    var isBankConfigured: Bool { settings.demoMode || (banking != nil && settings.starling.isComplete) }

    /// Health data older than this is shown as stale.
    var isHealthDataStale: Bool {
        guard let lastHealthSync else { return true }
        return now().timeIntervalSince(lastHealthSync) > 6 * 60 * 60
    }

    // MARK: Lifecycle

    func start() async {
        reload()
        await refreshHealthAccess()
        health.startObservingChanges { [weak self] in
            await self?.syncHealthAfterChange()
        }
        await syncHealth()
        await settleIfDue()
    }

    func refreshHealthAccess() async {
        healthAccess = await health.access()
    }

    func requestHealthAccess() async {
        do {
            try await health.requestAccess()
        } catch {
            healthSyncError = error.localizedDescription
        }
        await refreshHealthAccess()
        await syncHealth()
    }

    /// Called from the background refresh task. Best effort only: iOS decides if and when it runs.
    func backgroundRefresh() async {
        reload()
        await syncHealth()
        await settleIfDue()
    }

    // MARK: Apple Health sync

    /// Health observers fire once per data type, often together. Coalesce them into one sync.
    private func syncHealthAfterChange() async {
        if let last = syncState().lastAttempt, now().timeIntervalSince(last) < 60 { return }
        await syncHealth()
    }

    func syncHealth() async {
        guard !isSyncing else { return }
        if healthAccess == .unavailable && !settings.demoMode {
            healthSyncError = "Apple Health isn't available on this device."
            loadState = .loaded
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        if loadState == .idle { loadState = .loading }

        let state = syncState()
        state.lastAttempt = now()
        let today = self.today
        let start = syncWindowStart(finalisedThrough: state.finalisedThroughDay)

        do {
            let readings = try await health.readings(from: start, through: today)
            upsert(readings)
            // Rings are optional (no Apple Watch, or permission declined), so a failure here isn't a sync failure.
            todayRings = try? await health.activityRings(on: today)
            recalculateRewards(from: start, through: today, finalisedThrough: state.finalisedThroughDay)
            state.lastSuccessfulSync = now()
            state.lastError = nil
            // Days older than the lock window are now final; rates or late data can no longer change them.
            let newlyFinal = today.adding(days: -(settings.lockAfterDays + 1), calendar: calendar)
            if state.finalisedThroughDay.map({ newlyFinal > $0 }) ?? true {
                state.finalisedThrough = newlyFinal.description
            }
            healthSyncError = nil
            loadState = .loaded
        } catch {
            state.lastError = error.localizedDescription
            healthSyncError = "Couldn't read Apple Health. \(error.localizedDescription)"
            loadState = metricsByDay.isEmpty && earningsByDay.isEmpty ? .failed(healthSyncError ?? "") : .loaded
        }
        save()
        reload()
    }

    private func syncWindowStart(finalisedThrough: DayKey?) -> DayKey {
        let monthStart = today.monthKey.firstDay
        let earliest = today.monthKey.previous.firstDay
        guard let finalisedThrough else { return monthStart }
        return max(earliest, min(monthStart, finalisedThrough.adding(days: 1, calendar: calendar)))
    }

    private func upsert(_ readings: [DayKey: HealthDayReading]) {
        for (day, reading) in readings {
            let record = dailyActivity(day) ?? {
                let created = DailyActivity(day: day)
                context.insert(created)
                return created
            }()
            record.steps = reading.steps
            record.swimmingMetres = reading.swimmingMetres
            record.strengthSeconds = reading.strengthSeconds
            record.strengthWorkoutIDs = reading.strengthWorkoutIDs
            record.exerciseSeconds = reading.exerciseSeconds
            record.activeKilocalories = reading.activeKilocalories
            record.flightsClimbed = reading.flightsClimbed
            record.updatedAt = now()
        }
    }

    // MARK: Rewards

    /// Recalculates every unlocked day in the affected months and appends ledger lines for the difference.
    private func recalculateRewards(from start: DayKey, through end: DayKey, finalisedThrough: DayKey?) {
        let months = Set([start.monthKey, end.monthKey])
        for month in months.sorted() {
            let vaultRecord = ensureVault(month)
            let days = month.days(calendar: calendar).filter { $0 <= end }
            var calculated: [DayKey: [RewardCategory: Pence]] = [:]
            for day in days {
                calculated[day] = RewardEngine.rewards(for: metrics(for: day), rates: settings.rates)
            }
            let locked = Set(days.filter { day in finalisedThrough.map { day <= $0 } ?? false })
            let existing = ledgerEntries(month: month).compactMap(\.line)
            let before = existing.sum(\.amount)
            let result = LedgerReconciler.reconcile(
                existing: existing, calculated: calculated, lockedDays: locked, allocation: vaultRecord.allocation)
            guard !result.newLines.isEmpty else { continue }

            for line in result.newLines {
                context.insert(RewardLedgerEntry(line: line))
            }
            let after = before + result.newLines.sum(\.amount)
            audit("ledger", "\(result.newLines.count) reward line(s) recorded for \(month). Month total \(after.formatted()).")
            if before < vaultRecord.allocation && after >= vaultRecord.allocation && settings.notificationsEnabled {
                Notifier.vaultCompleted(vaultRecord.allocation)
            }
        }
    }

    func metrics(for day: DayKey) -> DailyMetrics {
        var metrics = DailyMetrics(day: day)
        if let activity = dailyActivity(day) {
            metrics.steps = activity.steps
            metrics.swimmingMetres = activity.swimmingMetres
            metrics.strengthSeconds = activity.strengthSeconds
            metrics.exerciseSeconds = activity.exerciseSeconds
            metrics.activeKilocalories = activity.activeKilocalories
            metrics.flightsClimbed = activity.flightsClimbed
        }
        return metrics
    }

    func earned(on day: DayKey) -> Pence {
        (earningsByDay[day] ?? [:]).values.sum { $0 }
    }

    func earned(_ category: RewardCategory, in days: [DayKey]) -> Pence {
        days.sum { earningsByDay[$0]?[category] ?? .zero }
    }

    // MARK: Banking

    func refreshBank() async {
        guard let banking, isBankConfigured else {
            bankSnapshot = nil
            return
        }
        guard network.isOnline else {
            bankError = BankingError.offline.errorDescription
            return
        }
        do {
            bankSnapshot = try await banking.snapshot()
            bankError = nil
            let reserved = transfers().filter { $0.status == .requested }.sum(\.amount)
            fundingPlan = VaultFunding.plan(allocation: settings.monthlyAllocation,
                                            spaceBalance: bankSnapshot?.spaceBalance ?? .zero,
                                            reservedForPendingReleases: reserved)
        } catch {
            bankError = error.localizedDescription
        }
    }

    /// Runs the daily settlement once it's due: reconcile, release earned money, then
    /// create at most one Monzo payment that you approve in Starling.
    func settleIfDue(force: Bool = false) async {
        guard !isSettling, isBankConfigured, let banking else { return }
        isSettling = true
        defer { isSettling = false }

        await refreshBank()
        guard bankSnapshot != nil else { return }

        await checkPayments(using: banking)
        await retryRequestedTransfers(using: banking)

        let due = force || isSettlementDue
        await release(using: banking, force: due)
        if due {
            await initiatePayment(using: banking)
            UserDefaults.standard.set(today.description, forKey: Self.lastSettlementKey)
        }
        await refreshBank()
        save()
        reload()
    }

    private static let lastSettlementKey = "settlement.lastDay"

    var isSettlementDue: Bool {
        let last = UserDefaults.standard.string(forKey: Self.lastSettlementKey).flatMap(DayKey.init(string:))
        return now() >= settingsStore.settlementTime(on: now()) && last.map { $0 < today } ?? true
    }

    var nextSettlement: Date { settingsStore.nextSettlement(after: now()) }

    /// Checks every unresolved payment with Starling. Never resends anything.
    func checkPayments() async {
        guard let banking else { return }
        await checkPayments(using: banking)
        save()
        reload()
    }

    private func checkPayments(using banking: BankingService) async {
        for payment in paymentOrders() where payment.status.isUnresolved {
            guard let orderUID = payment.starlingPaymentOrderUID else {
                if payment.status != .reconciliationRequired {
                    payment.status = .reconciliationRequired
                    payment.lastStatusDetail = "No Starling order reference was recorded. Check the Starling app."
                    audit("payment", "Payment needs checking: no order reference.", payment.id.uuidString)
                }
                continue
            }
            do {
                let status = try await banking.paymentStatus(paymentOrderUID: orderUID)
                guard status != payment.status else { continue }
                let previous = payment.status
                payment.status = status
                payment.lastStatusDetail = nil
                audit("payment", "Status \(previous.rawValue) → \(status.rawValue).", payment.id.uuidString)
                if status == .paid && settings.notificationsEnabled { Notifier.paid(payment.amount) }
            } catch {
                payment.lastStatusDetail = error.localizedDescription
            }
        }
    }

    private func retryRequestedTransfers(using banking: BankingService) async {
        for transfer in transfers() where transfer.status == .requested {
            // Re-sending with the same transfer UID is idempotent at Starling.
            await perform(transfer, using: banking)
        }
    }

    private func release(using banking: BankingService, force: Bool) async {
        guard let snapshot = bankSnapshot else { return }
        let all = transfers().map { (amount: $0.amount, status: $0.status) }
        let amount = SettlementPlanner.releaseAmount(
            earned: totalEarned(), transfers: all, spaceBalance: snapshot.spaceBalance, force: force)
        guard amount.isPositive else { return }
        let transfer = BankTransfer(amount: amount, isSandbox: banking.isSandbox)
        context.insert(transfer)
        audit("transfer", "Release of \(amount.formatted()) requested.", transfer.id.uuidString)
        save() // Record intent before calling the bank, so a crash can't lose track of it.
        await perform(transfer, using: banking)
    }

    private func perform(_ transfer: BankTransfer, using banking: BankingService) async {
        do {
            try await banking.releaseFromSpace(amount: transfer.amount, transferID: transfer.id)
            transfer.status = .confirmed
            audit("transfer", "Starling confirmed release of \(transfer.amount.formatted()).", transfer.id.uuidString)
        } catch BankingError.http(let code, let message) {
            transfer.status = .failed
            transfer.note = message
            audit("transfer", "Release failed (\(code)).", transfer.id.uuidString)
        } catch {
            // Offline or unknown outcome: stays requested and is retried with the same ID.
            transfer.note = error.localizedDescription
        }
        save()
    }

    private func initiatePayment(using banking: BankingService) async {
        guard let snapshot = bankSnapshot else { return }
        let decision = SettlementPlanner.paymentDecision(
            settleableEarned: settleableEarned(),
            releasedConfirmed: transfers().filter { $0.status == .confirmed }.sum(\.amount),
            payments: paymentOrders().map { (amount: $0.amount, status: $0.status) },
            mainBalance: snapshot.mainBalance)
        guard case .pay(let amount) = decision else { return }

        let yesterday = today.adding(days: -1, calendar: calendar)
        let order = PaymentOrder(amount: amount, reference: "Fitness Vault", coversThrough: yesterday,
                                 isSandbox: banking.isSandbox)
        context.insert(order)
        audit("payment", "Payment of \(amount.formatted()) to Monzo prepared.", order.id.uuidString)
        save()

        do {
            switch try await banking.initiatePayment(amount: amount, externalID: order.id, reference: order.reference) {
            case .accepted(let uid):
                order.starlingPaymentOrderUID = uid
                order.status = .awaitingApproval
                audit("payment", "Starling created order \(uid). Awaiting your approval in Starling.", order.id.uuidString)
                if settings.notificationsEnabled { Notifier.awaitingApproval(amount) }
            case .rejected(let message):
                order.status = .rejected
                order.lastStatusDetail = message
                audit("payment", "Starling rejected the payment: \(message)", order.id.uuidString)
            }
        } catch BankingError.offline {
            // Never sent. Safe to remove the local intent so tomorrow's run can try again.
            context.delete(order)
            audit("payment", "Payment not sent: offline.")
        } catch {
            order.status = .reconciliationRequired
            order.lastStatusDetail = error.localizedDescription
            audit("payment", "Payment outcome unknown: \(error.localizedDescription)", order.id.uuidString)
        }
        save()
    }

    /// After you've checked the Starling app and confirmed no payment was made, this frees the
    /// earnings so the next settlement can include them. It never marks anything as paid.
    func confirmPaymentNotSent(_ payment: PaymentOrder) {
        guard payment.status == .reconciliationRequired || payment.status == .awaitingInitiation else { return }
        payment.status = .failed
        payment.lastStatusDetail = "You confirmed this payment wasn't made in Starling."
        audit("payment", "Marked as not sent after manual check.", payment.id.uuidString)
        save()
        reload()
    }

    /// Moves only the shortfall into the Space for this month's allocation.
    func topUpSpace() async {
        guard let banking, let plan = fundingPlan, plan.topUpRequired.isPositive else { return }
        let id = UUID()
        audit("transfer", "Monthly top-up of \(plan.topUpRequired.formatted()) requested.", id.uuidString)
        do {
            try await banking.addToSpace(amount: plan.topUpRequired, transferID: id)
            audit("transfer", "Top-up confirmed.", id.uuidString)
        } catch {
            bankError = error.localizedDescription
        }
        save()
        await refreshBank()
    }

    // MARK: Totals

    func totalEarned() -> Pence {
        (try? context.fetch(FetchDescriptor<RewardLedgerEntry>()))?.sum(\.amount) ?? .zero
    }

    /// Earnings from finished days that were fully synced after they ended.
    func settleableEarned() -> Pence {
        guard let lastSync = syncState().lastSuccessfulSync else { return .zero }
        let entries = (try? context.fetch(FetchDescriptor<RewardLedgerEntry>())) ?? []
        return entries.filter { entry in
            guard let day = DayKey(string: entry.day) else { return false }
            return day < today && day.endDate(calendar: calendar) <= lastSync
        }.sum(\.amount)
    }

    // MARK: Reload

    func reload() {
        let month = currentMonth
        let vaultRecord = ensureVault(month)
        let monthEntries = ledgerEntries(month: month)
        // Keep the previous month too, so weekly views that span a month boundary are complete.
        let recentEntries = monthEntries + ledgerEntries(month: month.previous)

        var byDay: [DayKey: [RewardCategory: Pence]] = [:]
        for entry in recentEntries {
            guard let day = DayKey(string: entry.day), let category = entry.category else { continue }
            byDay[day, default: [:]][category, default: .zero] = byDay[day, default: [:]][category, default: .zero] + entry.amount
        }
        earningsByDay = byDay

        var metrics: [DayKey: DailyMetrics] = [:]
        var day = min(month.firstDay, today.adding(days: -6, calendar: calendar))
        while day <= today {
            metrics[day] = self.metrics(for: day)
            day = day.adding(days: 1, calendar: calendar)
        }
        metricsByDay = metrics

        vault = VaultSummary(month: month, allocation: vaultRecord.allocation, earned: monthEntries.sum(\.amount))
        payments = paymentOrders()
        flow = MoneyFlow(earned: totalEarned(),
                         transfers: transfers().map { (amount: $0.amount, status: $0.status) },
                         payments: payments.map { (amount: $0.amount, status: $0.status) })
        monthHistory = vaults().compactMap { record in
            guard let key = record.monthKey, key < month else { return nil }
            return VaultSummary(month: key, allocation: record.allocation, earned: ledgerEntries(month: key).sum(\.amount))
        }
        lastHealthSync = syncState().lastSuccessfulSync
        publishWidgetSnapshot()
    }

    /// Today's earnings by input, highest first, with equal standing for every category.
    private func widgetBreakdown() -> [WidgetCategoryLine] {
        let earnings = earningsByDay[today] ?? [:]
        let metrics = todayMetrics
        return RewardCategory.allCases
            .compactMap { category -> WidgetCategoryLine? in
                let amount = earnings[category] ?? .zero
                guard amount.isPositive else { return nil }
                let measure = MeasureFormat.measurement(category, metrics)
                return WidgetCategoryLine(
                    id: category.rawValue, title: category.title, symbol: category.symbol,
                    detail: "\(measure.value) \(measure.unit)", earnedPence: amount.value)
            }
            .sorted { $0.earnedPence > $1.earnedPence }
    }

    /// Shares today's numbers with the home-screen widget, refreshing it only when something changed.
    private func publishWidgetSnapshot() {
        let snapshot = WidgetSnapshot(
            day: today.description,
            earnedTodayPence: earned(on: today).value,
            steps: todayMetrics.steps,
            breakdown: widgetBreakdown(),
            rings: todayRings,
            monthEarnedPence: vault.earned.value,
            monthAllocationPence: vault.allocation.value,
            isDemo: settings.demoMode,
            updatedAt: lastHealthSync ?? now())
        if let lastWidgetSnapshot, lastWidgetSnapshot.hasSameContent(as: snapshot) { return }
        WidgetSnapshotStore.save(snapshot)
        lastWidgetSnapshot = snapshot
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
    }

    // MARK: Store access

    private func ensureVault(_ month: MonthKey) -> MonthlyVault {
        let key = month.description
        let descriptor = FetchDescriptor<MonthlyVault>(predicate: #Predicate { $0.month == key })
        if let existing = try? context.fetch(descriptor).first {
            // An untouched current month follows the allocation setting.
            if month == currentMonth, existing.allocationPence != settings.monthlyAllocation.value,
               ledgerEntries(month: month).isEmpty {
                existing.allocationPence = settings.monthlyAllocation.value
            }
            return existing
        }
        let plan = bankSnapshot.map { VaultFunding.plan(allocation: settings.monthlyAllocation, spaceBalance: $0.spaceBalance) }
        let created = MonthlyVault(month: month, allocation: settings.monthlyAllocation,
                                   openingSpaceBalance: bankSnapshot?.spaceBalance, plan: plan)
        context.insert(created)
        audit("vault", "Opened \(month) vault with \(settings.monthlyAllocation.formatted()).")
        return created
    }

    private func vaults() -> [MonthlyVault] {
        (try? context.fetch(FetchDescriptor<MonthlyVault>(sortBy: [SortDescriptor(\.month, order: .reverse)]))) ?? []
    }

    private func dailyActivity(_ day: DayKey) -> DailyActivity? {
        let key = day.description
        return try? context.fetch(FetchDescriptor<DailyActivity>(predicate: #Predicate { $0.day == key })).first
    }

    private func ledgerEntries(month: MonthKey) -> [RewardLedgerEntry] {
        let key = month.description
        return (try? context.fetch(FetchDescriptor<RewardLedgerEntry>(predicate: #Predicate { $0.month == key }))) ?? []
    }

    private func transfers() -> [BankTransfer] {
        (try? context.fetch(FetchDescriptor<BankTransfer>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    private func paymentOrders() -> [PaymentOrder] {
        (try? context.fetch(FetchDescriptor<PaymentOrder>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    private func syncState() -> HealthSyncState {
        if let state = try? context.fetch(FetchDescriptor<HealthSyncState>()).first { return state }
        let state = HealthSyncState()
        context.insert(state)
        return state
    }

    private func audit(_ kind: String, _ message: String, _ relatedID: String? = nil) {
        context.insert(AuditEvent(kind: kind, message: message, relatedID: relatedID))
    }

    private func save() {
        do { try context.save() } catch { healthSyncError = "Couldn't save: \(error.localizedDescription)" }
    }

    // MARK: Export

    /// Writes the full financial history as CSV and returns the file URL.
    func exportHistory() throws -> URL {
        var rows = ["type,id,date,day,category_or_status,amount_gbp"]
        func money(_ pence: Pence) -> String { "\(pence.decimalPounds)" }
        let iso = ISO8601DateFormatter()
        for entry in (try? context.fetch(FetchDescriptor<RewardLedgerEntry>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [] {
            rows.append("reward,\(entry.id),\(iso.string(from: entry.createdAt)),\(entry.day),\(entry.categoryRaw),\(money(entry.amount))")
        }
        for transfer in transfers() {
            rows.append("release,\(transfer.id),\(iso.string(from: transfer.createdAt)),,\(transfer.statusRaw),\(money(transfer.amount))")
        }
        for payment in paymentOrders() {
            rows.append("payment,\(payment.id),\(iso.string(from: payment.createdAt)),\(payment.coversThroughDay),\(payment.statusRaw),\(money(payment.amount))")
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "FitnessVault-history.csv")
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

extension HealthSyncState {
    var finalisedThroughDay: DayKey? { finalisedThrough.flatMap(DayKey.init(string:)) }
}
