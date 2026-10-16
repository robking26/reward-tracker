#if DEBUG
import SwiftData
import SwiftUI

/// Preview-only wiring: an in-memory store, generated Health data and the mock bank.
/// Production views never contain sample balances or activity values.
@MainActor
enum PreviewFixtures {
    static func model() -> AppModel {
        let defaults = UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        let settings = SettingsStore(defaults: defaults)
        settings.settings.demoMode = true
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), settingsStore: settings)
        Task { await model.start() }
        return model
    }
}

#Preview("Metric card") {
    MetricCard(title: "Steps", symbol: "figure.walk", timeframe: "Today", measurement: "8,412", unit: "steps",
               progress: 0.84, earned: Pence(168))
        .frame(width: 180)
        .padding()
        .pageBackground()
        .preferredColorScheme(.dark)
}

#Preview("Vault hero") {
    VaultHeroCard(summary: VaultSummary(month: MonthKey(.now), allocation: .pounds(400), earned: Pence(12_345)))
        .padding()
        .pageBackground()
        .preferredColorScheme(.dark)
}
#endif
