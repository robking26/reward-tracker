import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        @Bindable var store = model.settingsStore
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        MoneyVaultView()
                    } label: {
                        LabeledContent {
                            Text("\(model.vault.earned.formatted()) of \(model.vault.allocation.formatted(wholePounds: true))")
                                .monospacedDigit()
                        } label: {
                            Label("Money & Vault", systemImage: "sterlingsign.circle")
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                    NavigationLink {
                        StarlingConnectionView()
                    } label: {
                        StatusRow(title: "Starling", symbol: "building.columns",
                                  status: model.settings.demoMode ? "Demo" : (model.isBankConfigured ? model.settings.bankingEnvironment.title : "Not connected"),
                                  isGood: model.isBankConfigured)
                    }
                    StatusRow(title: "Monzo payee", symbol: "arrow.right.circle",
                              status: model.settings.starling.payeeName ?? "Not chosen",
                              isGood: model.settings.starling.payeeAccountUID != nil)
                    // Gold investing is off unless switched on; unearned money stays in Starling.
                    if model.settings.goldInvestingEnabled {
                        NavigationLink {
                            Trading212ConnectionView()
                        } label: {
                            StatusRow(title: "Trading 212", symbol: "chart.line.uptrend.xyaxis",
                                      status: model.settings.demoMode ? "Demo" : (model.isTrading212Connected ? model.settings.trading212.environment.title : "Not connected"),
                                      isGood: model.isTrading212Connected)
                        }
                    }
                } header: {
                    Text("Money")
                } footer: {
                    Text("Allowance, payouts, payment history, previous months and reward rates.")
                }

                Section("Apple Health") {
                    Button {
                        Task { await model.requestHealthAccess() }
                    } label: {
                        StatusRow(title: "Apple Health", symbol: "heart",
                                  status: healthStatus, isGood: model.healthAccess == .requested)
                    }
                    if model.healthAccess == .requested {
                        Text("iOS doesn't tell apps which Health data you've allowed. If activity is missing, check Settings › Health › Data Access & Devices › Vaultality.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                Section("Notifications") {
                    Toggle("Progress and payment updates", isOn: $store.settings.notificationsEnabled)
                        .onChange(of: store.settings.notificationsEnabled) { _, enabled in
                            if enabled { Task { _ = await Notifier.requestPermission() } }
                        }
                }

                Section("Data") {
                    LabeledContent("Last Health sync", value: MeasureFormat.relative(model.lastHealthSync))
                    Button("Sync Apple Health Now") { Task { await model.syncHealth() } }
                    Button("Check Payment Status") { Task { await model.checkPayments() } }
                    Button("Export Transaction History") {
                        do { exportURL = try model.exportHistory() } catch { exportError = error.localizedDescription }
                    }
                    if let exportURL {
                        ShareLink("Share CSV", item: exportURL)
                    }
                    if let exportError {
                        Text(exportError).font(.footnote).foregroundStyle(Palette.error)
                    }
                }

                Section {
                    Toggle("Demo mode", isOn: $store.settings.demoMode)
                        .onChange(of: store.settings.demoMode) {
                            Task {
                                await model.refreshHealthAccess()
                                await model.syncHealth()
                                await model.refreshBank()
                            }
                        }
                } header: {
                    Text("Development")
                } footer: {
                    Text("Demo mode uses generated activity and a pretend bank. It can never move real money.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("Vaultality: healthy habits unlock wealth. Activity recorded in Apple Health unlocks your own monthly allowance from a Starling Savings Space to Monzo; whatever isn't earned stays in Starling. It only reads from Apple Health, and your Health data stays on this iPhone. Banking tokens are kept in the Keychain on this device only. Payments always need your approval in the Starling app.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .pageBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationBackground(Palette.background)
    }

    private var healthStatus: String {
        switch model.healthAccess {
        case .unavailable: "Unavailable"
        case .notDetermined: "Allow access"
        case .requested: "Connected"
        }
    }
}

struct StatusRow: View {
    let title: String
    let symbol: String
    let status: String
    let isGood: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(isGood ? Palette.success : Palette.textTertiary)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(status)
            }
        } label: {
            Label(title, systemImage: symbol)
                .foregroundStyle(Palette.textPrimary)
        }
    }
}

/// Stores a secret in the Keychain. The current value is never displayed.
struct SecureTokenField: View {
    let title: String
    let item: Keychain.Item
    @State private var value = ""
    @State private var hasValue = false

    var body: some View {
        HStack {
            SecureField(hasValue ? "Saved. Enter to replace" : title, text: $value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(save)
            if !value.isEmpty {
                Button("Save", action: save).fontWeight(.semibold)
            } else if hasValue {
                Button("Remove", role: .destructive) {
                    Keychain.delete(item)
                    hasValue = false
                }
            }
        }
        .onAppear { hasValue = Keychain.read(item) != nil }
    }

    private func save() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasValue = Keychain.save(trimmed, for: item)
        value = ""
    }
}
