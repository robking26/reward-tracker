import SwiftUI

/// Connects Trading 212 (demo first), chooses the gold ETC and sets the safety switches.
struct Trading212ConnectionView: View {
    @Environment(AppModel.self) private var model
    @State private var instruments: [BrokerInstrument] = []
    @State private var query = "gold"
    @State private var loading = false
    @State private var status: String?
    @State private var error: String?
    @State private var payees: [PayeeAccount] = []
    @State private var confirmingInstrument = false
    @State private var confirmingLive = false

    var body: some View {
        @Bindable var store = model.settingsStore
        Form {
            Section {
                Picker("Environment", selection: $store.settings.trading212.environment) {
                    ForEach(TradingEnvironment.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: store.settings.trading212.environment) {
                    // A different account: the instrument and live switch must be confirmed again.
                    store.settings.trading212.instrument?.confirmed = false
                    store.settings.trading212.liveTradingConfirmed = false
                    status = nil
                }
                SecureTokenField(title: "API key", item: .trading212Key(for: store.settings.trading212.environment))
                    .id("key-\(store.settings.trading212.environment.rawValue)")
                SecureTokenField(title: "API secret (if your key has one)", item: .trading212Secret(for: store.settings.trading212.environment))
                    .id("secret-\(store.settings.trading212.environment.rawValue)")
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("Test Connection")
                        if loading { Spacer(); ProgressView() }
                    }
                }
                .disabled(loading || !model.network.isOnline)
                if let status { Text(status).font(.footnote).foregroundStyle(Palette.success) }
                if let error { Text(error).font(.footnote).foregroundStyle(Palette.error) }
            } header: {
                Text("Trading 212")
            } footer: {
                Text("Create an API key in Trading 212 under Settings › API (Beta), on an Invest or Stocks ISA account. Give it only account, metadata, portfolio, history and order permissions. Start with Practice (demo). Keys are stored in this iPhone's Keychain only.")
            }

            Section {
                if let instrument = store.settings.trading212.instrument {
                    LabeledContent(instrument.name) {
                        Text(instrument.confirmed ? "Confirmed" : "Not confirmed")
                            .foregroundStyle(instrument.confirmed ? Palette.success : Palette.warning)
                    }
                    Text("\(instrument.ticker) · priced in \(instrument.currencyCode)\(instrument.isin.map { " · \($0)" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                    if !instrument.confirmed {
                        Button("Confirm This Instrument") { confirmingInstrument = true }
                    }
                }
                TextField("Search instruments", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Search Trading 212") { Task { await loadInstruments() } }
                    .disabled(loading || !model.network.isOnline)
                ForEach(filtered.prefix(25)) { item in
                    Button {
                        store.settings.trading212.instrument = GoldInstrument(
                            ticker: item.ticker, name: item.name, isin: item.isin, currencyCode: item.currencyCode,
                            minTradeQuantity: "\(item.minTradeQuantity)", confirmed: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).foregroundStyle(Palette.textPrimary)
                            Text("\(item.ticker) · \(item.type) · \(item.currencyCode)")
                                .font(.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            } header: {
                Text("Gold ETC")
            } footer: {
                Text("Choose a physically backed gold ETC priced in GBP or GBX, then confirm it. Nothing is bought until you confirm.")
            }

            Section {
                Picker("Trading 212 payee", selection: Binding(
                    get: { store.settings.trading212.fundingPayeeAccountUID ?? "" },
                    set: { uid in
                        let payee = payees.first { $0.payeeAccountUID == uid }
                        store.settings.trading212.fundingPayeeAccountUID = payee?.payeeAccountUID
                        store.settings.trading212.fundingPayeeName = payee?.payeeName
                    })) {
                    Text("Send it myself").tag("")
                    ForEach(payees) { payee in
                        Text("\(payee.payeeName) \(payee.description)").tag(payee.payeeAccountUID)
                    }
                }
                .task { await loadPayees() }
            } header: {
                Text("Funding from Starling")
            } footer: {
                Text("To have Vaultality prepare the transfer, save Trading 212's bank details (with your deposit reference) as a payee in Starling first. You still approve every payment in the Starling app.")
            }

            Section {
                Toggle("Buy automatically when cash arrives", isOn: $store.settings.trading212.automationEnabled)
                if store.settings.trading212.environment == .live {
                    Toggle("Allow live trading", isOn: Binding(
                        get: { store.settings.trading212.liveTradingConfirmed },
                        set: { enabled in
                            if enabled { confirmingLive = true } else { store.settings.trading212.liveTradingConfirmed = false }
                        }))
                    .disabled(store.settings.trading212.instrument?.confirmed != true || store.settings.demoMode)
                }
            } header: {
                Text("Safety")
            } footer: {
                Text("Automation is off by default; turn it off any time to stop orders being placed. Live trading needs a confirmed instrument and this explicit switch.")
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Trading 212")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Confirm this gold ETC?", isPresented: $confirmingInstrument, titleVisibility: .visible) {
            Button("Use \(store.settings.trading212.instrument?.name ?? "this instrument")") {
                store.settings.trading212.instrument?.confirmed = true
            }
        } message: {
            Text("Forfeited spending will buy \(store.settings.trading212.instrument?.ticker ?? "this instrument"). Check it's a physically backed gold ETC before confirming.")
        }
        .confirmationDialog("Allow live trading?", isPresented: $confirmingLive, titleVisibility: .visible) {
            Button("Allow Live Trading") { store.settings.trading212.liveTradingConfirmed = true }
        } message: {
            Text("Vaultality will place real buy orders in your Trading 212 account with forfeited spending that has arrived as cash there.")
        }
    }

    private var filtered: [BrokerInstrument] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        return instruments.filter { item in
            let haystack = "\(item.name) \(item.ticker) \(item.isin ?? "")".lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    private func testConnection() async {
        guard let broker = model.investing else {
            error = "Save an API key first."
            return
        }
        loading = true
        defer { loading = false }
        do {
            let currency = try await broker.accountCurrency()
            let cash = try await broker.freeCash()
            status = "Connected to \(broker.environment.title). Account in \(currency), \(cash.formatted()) free."
            error = nil
        } catch {
            self.error = error.localizedDescription
            status = nil
        }
    }

    private func loadInstruments() async {
        guard let broker = model.investing else {
            error = "Save an API key first."
            return
        }
        loading = true
        defer { loading = false }
        do {
            instruments = try await broker.instruments()
            error = filtered.isEmpty ? "No instruments match \"\(query)\"." : nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadPayees() async {
        guard let banking = model.banking else { return }
        payees = (try? await banking.payeeAccounts()) ?? []
    }
}
