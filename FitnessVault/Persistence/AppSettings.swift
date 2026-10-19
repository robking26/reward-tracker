import Foundation
import Observation

enum BankingEnvironment: String, Codable, CaseIterable, Sendable, Identifiable {
    case sandbox
    case production

    var id: String { rawValue }
    var title: String { self == .sandbox ? "Sandbox" : "Live" }
    var baseURL: URL {
        switch self {
        case .sandbox: URL(string: "https://api-sandbox.starlingbank.com")!
        case .production: URL(string: "https://api.starlingbank.com")!
        }
    }
}

/// Identifiers chosen when connecting Starling. None of these are secrets;
/// the access token lives in the Keychain.
struct StarlingConfiguration: Codable, Hashable, Sendable {
    var accountUID: String?
    var defaultCategoryUID: String?
    var savingsGoalUID: String?
    var savingsGoalName: String?
    var payeeUID: String?
    var payeeAccountUID: String?
    var payeeName: String?

    var isComplete: Bool {
        accountUID != nil && defaultCategoryUID != nil && savingsGoalUID != nil && payeeAccountUID != nil
    }
}

enum TradingEnvironment: String, Codable, CaseIterable, Sendable, Identifiable {
    case demo
    case live

    var id: String { rawValue }
    var title: String { self == .demo ? "Demo (practice)" : "Live" }
    var baseURL: URL {
        switch self {
        case .demo: URL(string: "https://demo.trading212.com/api/v0")!
        case .live: URL(string: "https://live.trading212.com/api/v0")!
        }
    }
}

/// The gold ETC chosen for forfeited spending. Nothing is bought until `confirmed` is true.
struct GoldInstrument: Codable, Hashable, Sendable {
    var ticker: String
    var name: String
    var isin: String?
    /// Trading 212 currency code for the share price, e.g. "GBP", "GBX" (pence) or "USD".
    var currencyCode: String
    /// Smallest quantity Trading 212 accepts, as a decimal string.
    var minTradeQuantity: String
    var confirmed: Bool
}

struct Trading212Configuration: Codable, Hashable, Sendable {
    var environment: TradingEnvironment = .demo
    var instrument: GoldInstrument?
    /// Live orders need the live environment *and* this explicit opt-in.
    var liveTradingConfirmed = false
    /// When on, the app places the gold order by itself once cash is confirmed in Trading 212.
    /// Off by default; funding from Starling always needs approval in the Starling app regardless.
    var automationEnabled = false
    /// Starling payee account used to send forfeited money to Trading 212, if set up.
    var fundingPayeeAccountUID: String?
    var fundingPayeeName: String?
}

/// The shape of the user's days and the accountability rules (D-010, A2). Every field decodes optionally.
struct CoachSettings: Codable, Hashable, Sendable {
    var wakeMinute = 5 * 60 + 55
    var bedtimeMinute = 22 * 60 + 30
    var windDownMinute = 21 * 60 + 30
    var workStartMinute = 8 * 60
    var workEndMinute = 16 * 60
    var lunchStartMinute = 12 * 60
    var lunchEndMinute = 13 * 60
    var focusStartMinute = 13 * 60
    var dinnerMinute = 19 * 60
    /// ISO weekdays: Monday = 1 … Sunday = 7.
    var workdays: Set<Int> = [1, 2, 3, 4, 5]
    var fineSchedule = FineSchedule.trial
    /// Fines are virtual until the trial has been reviewed (D-005).
    var finesAreSimulated = true
    /// Role of each EventKit calendar, keyed by calendar identifier (D-009).
    var calendarRoles: [String: CalendarRole] = [:]
    /// Door to door, one way, until real travel times arrive in Phase 6.
    var gymTravelMinutes = 15

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CoachSettings()
        wakeMinute = (try? c.decodeIfPresent(Int.self, forKey: .wakeMinute)) ?? d.wakeMinute
        bedtimeMinute = (try? c.decodeIfPresent(Int.self, forKey: .bedtimeMinute)) ?? d.bedtimeMinute
        windDownMinute = (try? c.decodeIfPresent(Int.self, forKey: .windDownMinute)) ?? d.windDownMinute
        workStartMinute = (try? c.decodeIfPresent(Int.self, forKey: .workStartMinute)) ?? d.workStartMinute
        workEndMinute = (try? c.decodeIfPresent(Int.self, forKey: .workEndMinute)) ?? d.workEndMinute
        lunchStartMinute = (try? c.decodeIfPresent(Int.self, forKey: .lunchStartMinute)) ?? d.lunchStartMinute
        lunchEndMinute = (try? c.decodeIfPresent(Int.self, forKey: .lunchEndMinute)) ?? d.lunchEndMinute
        focusStartMinute = (try? c.decodeIfPresent(Int.self, forKey: .focusStartMinute)) ?? d.focusStartMinute
        dinnerMinute = (try? c.decodeIfPresent(Int.self, forKey: .dinnerMinute)) ?? d.dinnerMinute
        workdays = (try? c.decodeIfPresent(Set<Int>.self, forKey: .workdays)) ?? d.workdays
        fineSchedule = (try? c.decodeIfPresent(FineSchedule.self, forKey: .fineSchedule)) ?? d.fineSchedule
        finesAreSimulated = (try? c.decodeIfPresent(Bool.self, forKey: .finesAreSimulated)) ?? d.finesAreSimulated
        calendarRoles = (try? c.decodeIfPresent([String: CalendarRole].self, forKey: .calendarRoles)) ?? d.calendarRoles
        gymTravelMinutes = (try? c.decodeIfPresent(Int.self, forKey: .gymTravelMinutes)) ?? d.gymTravelMinutes
    }

    /// The day's shape for the availability engine.
    func shape(isWorkday: Bool) -> DayShape {
        DayShape(wakeMinute: wakeMinute, bedtimeMinute: bedtimeMinute, isWorkday: isWorkday,
                 workStartMinute: workStartMinute, workEndMinute: workEndMinute,
                 lunchStartMinute: lunchStartMinute, lunchEndMinute: lunchEndMinute)
    }

    func isWorkday(_ day: DayKey, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar)) // 1 = Sunday
        return workdays.contains(weekday == 1 ? 7 : weekday - 1)
    }
}

struct AppSettings: Codable, Hashable, Sendable {
    static let currentVersion = 3

    /// Vaultality 2.0 starts here: activity no longer earns money from this day (D-005).
    static let activityEarningsCutover = DayKey(year: 2026, month: 10, day: 19)

    var monthlyAllocation: Pence = .pounds(500)
    var rates: RewardRates = .standard
    /// Minutes after midnight. Default 08:00.
    var settlementMinuteOfDay = 8 * 60
    var notificationsEnabled = true
    var bankingEnvironment: BankingEnvironment = .sandbox
    /// Live transfers require production *and* this explicit opt-in.
    var liveTransfersConfirmed = false
    var starling = StarlingConfiguration()
    var trading212 = Trading212Configuration()
    /// Shows preview data in place of Apple Health and banking. Never moves money.
    var demoMode = false
    /// Days after which a day's rewards are final and cannot change.
    var lockAfterDays = 7
    var coach = CoachSettings()
    /// Last day per-activity earnings count. Nil keeps the v1 model running (tests, demo).
    var activityEarningsEnd: DayKey? = AppSettings.activityEarningsCutover.adding(days: -1)
    /// Month-end gold investing through Trading 212 (dormant since D-005).
    var goldInvestingEnabled = false
    var settingsVersion = AppSettings.currentVersion

    init() {}

    // `rates` is deliberately not saved: rates are defined in code.
    private enum CodingKeys: String, CodingKey {
        case monthlyAllocation, settlementMinuteOfDay, notificationsEnabled
        case bankingEnvironment, liveTransfersConfirmed, starling, trading212, demoMode, lockAfterDays
        case coach, activityEarningsEnd, goldInvestingEnabled
        case settingsVersion
    }

    /// Every field is optional when reading, so adding settings never wipes saved ones (such as the Starling setup).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        monthlyAllocation = (try? c.decodeIfPresent(Pence.self, forKey: .monthlyAllocation)) ?? defaults.monthlyAllocation
        settlementMinuteOfDay = (try? c.decodeIfPresent(Int.self, forKey: .settlementMinuteOfDay)) ?? defaults.settlementMinuteOfDay
        notificationsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled)) ?? defaults.notificationsEnabled
        bankingEnvironment = (try? c.decodeIfPresent(BankingEnvironment.self, forKey: .bankingEnvironment)) ?? defaults.bankingEnvironment
        liveTransfersConfirmed = (try? c.decodeIfPresent(Bool.self, forKey: .liveTransfersConfirmed)) ?? defaults.liveTransfersConfirmed
        starling = (try? c.decodeIfPresent(StarlingConfiguration.self, forKey: .starling)) ?? defaults.starling
        trading212 = (try? c.decodeIfPresent(Trading212Configuration.self, forKey: .trading212)) ?? defaults.trading212
        demoMode = (try? c.decodeIfPresent(Bool.self, forKey: .demoMode)) ?? defaults.demoMode
        lockAfterDays = (try? c.decodeIfPresent(Int.self, forKey: .lockAfterDays)) ?? defaults.lockAfterDays
        coach = (try? c.decodeIfPresent(CoachSettings.self, forKey: .coach)) ?? defaults.coach
        goldInvestingEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .goldInvestingEnabled)) ?? defaults.goldInvestingEnabled
        let savedVersion = (try? c.decodeIfPresent(Int.self, forKey: .settingsVersion)) ?? 1
        // Version 1 used a £400 allowance by default; Vaultality's allowance is £500.
        if savedVersion < 2 && monthlyAllocation == .pounds(400) {
            monthlyAllocation = .pounds(500)
        }
        // Settings saved before version 3 belong to the earnings model, so they adopt the cutover;
        // a saved end is kept from then on.
        if savedVersion < 3 {
            activityEarningsEnd = defaults.activityEarningsEnd
        } else if c.contains(.activityEarningsEnd) {
            activityEarningsEnd = try? c.decodeIfPresent(DayKey.self, forKey: .activityEarningsEnd)
        }
        settingsVersion = Self.currentVersion
    }
}

/// Persists `AppSettings` in UserDefaults. Secrets are never stored here.
@Observable
final class SettingsStore {
    private let defaults: UserDefaults
    private static let key = "app.settings.v1"

    var settings: AppSettings {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// The next settlement time after `date`.
    func nextSettlement(after date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let today = calendar.date(byAdding: .minute, value: settings.settlementMinuteOfDay, to: start) ?? date
        return today > date ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    func settlementTime(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .minute, value: settings.settlementMinuteOfDay, to: calendar.startOfDay(for: day)) ?? day
    }
}
