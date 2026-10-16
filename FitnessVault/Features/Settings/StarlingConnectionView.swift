import SwiftUI

/// Connects a Starling personal access token and chooses the account, Savings Space and Monzo payee.
struct StarlingConnectionView: View {
    @Environment(AppModel.self) private var model
    @State private var accounts: [BankAccount] = []
    @State private var spaces: [SavingsSpace] = []
    @State private var payees: [PayeeAccount] = []
    @State private var loading = false
    @State private var error: String?
    @State private var confirmingLive = false

    var body: some View {
        @Bindable var store = model.settingsStore
        Form {
            Section {
                Picker("Environment", selection: $store.settings.bankingEnvironment) {
                    ForEach(BankingEnvironment.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: store.settings.bankingEnvironment) {
                    store.settings.starling = StarlingConfiguration()
                    store.settings.liveTransfersConfirmed = false
                    accounts = []; spaces = []; payees = []
                }
                SecureTokenField(title: "Personal access token", item: .starlingToken(for: store.settings.bankingEnvironment))
                    .id(store.settings.bankingEnvironment)
                Button {
                    Task { await load() }
                } label: {
                    HStack {
                        Text("Load Accounts")
                        if loading { Spacer(); ProgressView() }
                    }
                }
                .disabled(loading || !model.network.isOnline)
            } header: {
                Text("Starling")
            } footer: {
                Text("Create a personal access token in the Starling developer portal with only the read and transfer scopes this app needs: accounts, balance, savings goals and their transfers, payees, and local payments. Use the sandbox first. The token is stored in this iPhone's Keychain and never leaves it except to call Starling.")
            }

            if let error {
                Section { Text(error).foregroundStyle(Palette.error) }
            }

            if !accounts.isEmpty {
                Section("Account") {
                    Picker("Account", selection: Binding(
                        get: { store.settings.starling.accountUID ?? "" },
                        set: { uid in
                            guard let account = accounts.first(where: { $0.accountUID == uid }) else { return }
                            store.settings.starling.accountUID = account.accountUID
                            store.settings.starling.defaultCategoryUID = account.defaultCategoryUID
                            Task { await loadSpaces() }
                        })) {
                        Text("Choose…").tag("")
                        ForEach(accounts) { Text($0.name).tag($0.accountUID) }
                    }
                }
            }

            if !spaces.isEmpty {
                Section {
                    Picker("Savings Space", selection: Binding(
                        get: { store.settings.starling.savingsGoalUID ?? "" },
                        set: { uid in
                            store.settings.starling.savingsGoalUID = uid.isEmpty ? nil : uid
                            store.settings.starling.savingsGoalName = spaces.first { $0.uid == uid }?.name
                        })) {
                        Text("Choose…").tag("")
                        ForEach(spaces) { space in
                            Text("\(space.name) · \(space.balance.formatted())").tag(space.uid)
                        }
                    }
                } header: {
                    Text("Vault Space")
                } footer: {
                    Text("Rewards are released from this Space to your main balance.")
                }
            }

            if !payees.isEmpty {
                Section {
                    Picker("Monzo payee", selection: Binding(
                        get: { store.settings.starling.payeeAccountUID ?? "" },
                        set: { uid in
                            let payee = payees.first { $0.payeeAccountUID == uid }
                            store.settings.starling.payeeAccountUID = payee?.payeeAccountUID
                            store.settings.starling.payeeUID = payee?.payeeUID
                            store.settings.starling.payeeName = payee?.payeeName
                        })) {
                        Text("Choose…").tag("")
                        ForEach(payees) { payee in
                            Text("\(payee.payeeName) \(payee.description)").tag(payee.payeeAccountUID)
                        }
                    }
                } header: {
                    Text("Destination")
                } footer: {
                    Text("Your Monzo account must already be saved as a payee in Starling. The app only pays this existing payee.")
                }
            }

            if store.settings.bankingEnvironment == .production {
                Section {
                    Toggle("Allow live transfers", isOn: Binding(
                        get: { store.settings.liveTransfersConfirmed },
                        set: { enabled in
                            if enabled { confirmingLive = true } else { store.settings.liveTransfersConfirmed = false }
                        }))
                    .disabled(store.settings.demoMode)
                } footer: {
                    Text("Off by default. Leave it off until the sandbox flow has been tested end to end.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Starling")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Allow live transfers?", isPresented: $confirmingLive, titleVisibility: .visible) {
            Button("Allow Live Transfers") { store.settings.liveTransfersConfirmed = true }
        } message: {
            Text("Vaultality will move real money from your Savings Space and create payments to your Monzo payee, which you approve in Starling.")
        }
    }

    private func load() async {
        guard let banking = model.banking else {
            error = "Save a personal access token first."
            return
        }
        loading = true
        defer { loading = false }
        do {
            accounts = try await banking.accounts()
            payees = try await banking.payeeAccounts()
            error = nil
            if model.settings.starling.accountUID != nil { await loadSpaces() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadSpaces() async {
        guard let banking = model.banking, let account = model.settings.starling.accountUID else { return }
        do {
            spaces = try await banking.savingsSpaces(accountUID: account)
            await model.refreshBank()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
