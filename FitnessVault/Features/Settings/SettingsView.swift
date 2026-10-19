import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(CoachModel.self) private var coach
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        @Bindable var store = model.settingsStore
        NavigationStack {
            Form {
                Section {
                    NavigationLink { RoutinesView() } label: {
                        Label("Routines", systemImage: "repeat").foregroundStyle(Palette.textPrimary)
                    }
                    NavigationLink { CalendarsSettingsView() } label: {
                        StatusRow(title: "Calendars", symbol: "calendar", status: coach.calendarAccess.title,
                                  isGood: coach.calendarAccess == .granted && !coach.hasNoWorkCalendar)
                    }
                    NavigationLink { MemoryView() } label: {
                        Label("Coach memory", systemImage: "brain").foregroundStyle(Palette.textPrimary)
                    }
                    NavigationLink { AccountabilitySettingsView() } label: {
                        Label("Accountability and your day", systemImage: "scalemass").foregroundStyle(Palette.textPrimary)
                    }
                    NavigationLink { PrivacyView() } label: {
                        Label("Privacy & data", systemImage: "hand.raised").foregroundStyle(Palette.textPrimary)
                    }
                } header: {
                    Text("Coach")
                }

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
                    // Gold investing is dormant since Vaultality 2.0 (D-005).
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
                    Text("Allowance, payouts, payment history and previous months. Activity earned money until 18 October 2026; from 19 October your £500 is kept minus fines for missed commitments (in trial).")
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
                    Text("Vaultality: your coach for the next action. It plans around your calendar, health and goals, and helps you keep the commitments you agree to. Your coaching data and Health data stay on this iPhone. Banking tokens are kept in the Keychain on this device only. Payments always need your approval in the Starling app.")
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
