import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        @Bindable var store = model.settingsStore
        NavigationStack {
            Form {
                Section("Connections") {
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
                    Button {
                        Task { await model.requestHealthAccess() }
                    } label: {
                        StatusRow(title: "Apple Health", symbol: "heart",
                                  status: healthStatus, isGood: model.healthAccess == .requested)
                    }
                    if model.healthAccess == .requested {
                        Text("iOS doesn't tell apps which Health data you've allowed. If activity is missing, check Settings › Health › Data Access & Devices › Fitness Vault.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                Section {
                    LabeledContent("Monthly allocation") {
                        Stepper(store.settings.monthlyAllocation.formatted(),
                                value: Binding(get: { store.settings.monthlyAllocation.value / 100 },
                                               set: { store.settings.monthlyAllocation = .pounds($0) }),
                                in: 0...2_000, step: 25)
                            .monospacedDigit()
                    }
                    DatePicker("Daily settlement", selection: Binding(
                        get: { model.settingsStore.settlementTime(on: .now) },
                        set: { date in
                            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                            store.settings.settlementMinuteOfDay = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
                        }), displayedComponents: .hourAndMinute)
                } header: {
                    Text("Vault")
                } footer: {
                    Text("A new allocation applies from next month, or now if nothing has been earned this month. Settlement is best effort in the background and always runs when you open the app after this time.")
                }

                Section {
                    Stepper("Protein: \(store.settings.nutrition.proteinGrams) g",
                            value: $store.settings.nutrition.proteinGrams, in: 40...300, step: 5)
                        .monospacedDigit()
                    Stepper("Calories from \(MeasureFormat.number(store.settings.nutrition.minimumKilocalories))",
                            value: $store.settings.nutrition.minimumKilocalories,
                            in: NutritionTargets.lowestAllowedMinimum...4_000, step: 50)
                        .monospacedDigit()
                    Stepper("Calories up to \(MeasureFormat.number(store.settings.nutrition.maximumKilocalories))",
                            value: $store.settings.nutrition.maximumKilocalories,
                            in: store.settings.nutrition.minimumKilocalories...5_000, step: 50)
                        .monospacedDigit()
                } header: {
                    Text("Daily nutrition targets")
                } footer: {
                    Text("Calories use a range so eating too little is never rewarded. Changes apply to days that aren't yet final.")
                }

                Section {
                    ForEach(RewardCategory.allCases) { category in
                        LabeledContent {
                            Text(model.settings.rates.rateDescription(for: category))
                                .monospacedDigit()
                        } label: {
                            Label(category.title, systemImage: category.symbol)
                        }
                    }
                } header: {
                    Text("Reward rates")
                } footer: {
                    Text("Rewards stop once the month's allocation is unlocked. Days become final after \(model.settings.lockAfterDays) days and are never recalculated.")
                }

                Section("Notifications") {
                    Toggle("Progress and payment updates", isOn: $store.settings.notificationsEnabled)
                        .onChange(of: store.settings.notificationsEnabled) { _, enabled in
                            if enabled { Task { _ = await Notifier.requestPermission() } }
                        }
                }

                Section {
                    Picker("Analysis", selection: $store.settings.mealAnalysisMode) {
                        ForEach(MealAnalysisMode.allCases) { Text($0.title).tag($0) }
                    }
                    if store.settings.mealAnalysisMode == .remote {
                        TextField("https://your-server.example/analyse", text: $store.settings.mealAnalysisEndpoint)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureTokenField(title: "Device token", item: .mealAnalysisDeviceToken)
                    }
                    Toggle("Keep meal thumbnails", isOn: $store.settings.keepMealThumbnails)
                    Toggle("Save meals to Apple Health", isOn: $store.settings.saveMealsToHealth)
                } header: {
                    Text("AI meal logging")
                } footer: {
                    Text("Only a resized photo without location data is sent for analysis. Full-size photos are never stored. The mock mode returns placeholder values for development and is not a real estimate.")
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
                    Text("Fitness Vault turns activity recorded in Apple Health into money released from your own Starling Savings Space to your Monzo account. Your Health data stays on this iPhone. Banking tokens are kept in the Keychain on this device only. Payments always need your approval in the Starling app.")
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
