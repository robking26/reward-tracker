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

struct AppSettings: Codable, Hashable, Sendable {
    var monthlyAllocation: Pence = .pounds(400)
    var rates: RewardRates = .standard
    /// Minutes after midnight. Default 08:00.
    var settlementMinuteOfDay = 8 * 60
    var notificationsEnabled = true
    var bankingEnvironment: BankingEnvironment = .sandbox
    /// Live transfers require production *and* this explicit opt-in.
    var liveTransfersConfirmed = false
    var starling = StarlingConfiguration()
    /// Shows preview data in place of Apple Health and banking. Never moves money.
    var demoMode = false
    /// Days after which a day's rewards are final and cannot change.
    var lockAfterDays = 7

    // `rates` is deliberately not saved: rates are defined in code, so a rate change can never
    // make previously saved settings (such as the Starling setup) fail to load.
    private enum CodingKeys: String, CodingKey {
        case monthlyAllocation, settlementMinuteOfDay, notificationsEnabled
        case bankingEnvironment, liveTransfersConfirmed, starling, demoMode, lockAfterDays
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
