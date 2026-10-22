import SwiftUI

/// Which calendar is which, your places, working hours, and how much to fit in each week.
struct DaySettingsView: View {
    @Environment(PlannerModel.self) private var planner
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if planner.access == .granted {
                        LabeledContent("Calendar access", value: planner.access.title)
                    } else {
                        Button("Allow calendar access") {
                            Task { await planner.requestCalendarAccess() }
                        }
                    }
                    ForEach(planner.calendars) { info in
                        Picker(selection: roleBinding(info.id)) {
                            ForEach(CalendarRole.allCases) { role in
                                Text(role.title).tag(role)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.title)
                                Text(info.sourceTitle)
                                    .font(.caption)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                } header: {
                    Text("Calendars")
                } footer: {
                    Text("Everything in yours counts. Work's 9 am \"Office focus\" or \"Home focus\" sets where you start the day. Becky's events only count once you say they're shared. Outlook appears here once the work account is added in Settings › Calendar › Accounts; Becky's once she shares her iCloud calendar with you.")
                }

                Section {
                    ForEach(PlaceID.saveable) { id in
                        NavigationLink {
                            PlaceSearchView(id: id)
                        } label: {
                            LabeledContent {
                                Text(planner.settings.places[id]?.name ?? "Not set")
                                    .foregroundStyle(planner.settings.places[id] == nil ? Palette.warning : Palette.textSecondary)
                            } label: {
                                Label(id.title, systemImage: id.symbol)
                            }
                        }
                    }
                    if planner.location.isAuthorised {
                        LabeledContent("Current location", value: "Used for drive times")
                    } else if planner.location.canAsk {
                        Button("Use my location for drive times") { planner.requestLocation() }
                    } else {
                        LabeledContent("Current location", value: "Off in iOS Settings")
                    }
                } header: {
                    Text("Places")
                } footer: {
                    Text("Drive times come from Apple Maps, plus 10% and parking. Your location is only read while the app is open.")
                }

                Section("Work hours") {
                    DatePicker("Start", selection: minuteBinding(\.workStartMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Finish", selection: minuteBinding(\.workEndMinute), displayedComponents: .hourAndMinute)
                }

                Section {
                    DatePicker("Earliest", selection: minuteBinding(\.dayStartMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Latest finish", selection: minuteBinding(\.dayEndMinute), displayedComponents: .hourAndMinute)
                } header: {
                    Text("Suggestions between")
                }

                Section("Each week") {
                    Stepper("Gym: \(planner.settings.gymPerWeek)", value: intBinding(\.gymPerWeek), in: 0...7)
                    Stepper("Swims: \(planner.settings.swimsPerWeek)", value: intBinding(\.swimsPerWeek), in: 0...7)
                    Stepper("Runs: \(planner.settings.runsPerWeek)", value: intBinding(\.runsPerWeek), in: 0...7)
                }

                Section {
                    Stepper("Gym workout: \(planner.settings.gymMinutes) min", value: intBinding(\.gymMinutes), in: 60...120, step: 15)
                    Stepper("Swim, changing included: \(planner.settings.swimMinutes) min", value: intBinding(\.swimMinutes),
                            in: 30...120, step: 15)
                    Stepper("Aldi shop: \(planner.settings.shopMinutes) min", value: intBinding(\.shopMinutes), in: 15...120, step: 15)
                    Stepper("Walk: \(planner.settings.walkMinutes) min", value: intBinding(\.walkMinutes), in: 15...90, step: 15)
                    Stepper("Run: \(planner.settings.runMinutes) min", value: intBinding(\.runMinutes), in: 15...90, step: 5)
                    Stepper("Drive if Maps has no time: \(planner.settings.fallbackTravelMinutes) min",
                            value: intBinding(\.fallbackTravelMinutes), in: 5...60, step: 5)
                } header: {
                    Text("How long")
                } footer: {
                    Text("Drives are added on top. Runs are only suggested while your knee is settled.")
                }

                Section {
                    Button("Ask again about Becky's events", role: .destructive) { confirmingReset = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Day settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Forget which of Becky's events are shared?", isPresented: $confirmingReset,
                                titleVisibility: .visible) {
                Button("Ask again", role: .destructive) { planner.resetBeckyAnswers() }
            }
        }
    }

    private func roleBinding(_ id: String) -> Binding<CalendarRole> {
        Binding(get: { planner.settings.roles[id] ?? .ignored }, set: { planner.setRole($0, for: id) })
    }

    private func intBinding(_ path: WritableKeyPath<PlannerSettings, Int>) -> Binding<Int> {
        Binding(get: { planner.settings[keyPath: path] }, set: { value in planner.update { $0[keyPath: path] = value } })
    }

    /// Minutes after midnight as a time of day, on a fixed date so the clocks changing never shifts it.
    private func minuteBinding(_ path: WritableKeyPath<PlannerSettings, Int>) -> Binding<Date> {
        let calendar = planner.calendar
        let base = DayKey(year: 2024, month: 1, day: 15)
        return Binding(get: { base.date(atMinute: planner.settings[keyPath: path], calendar: calendar) },
                       set: { date in
                           let parts = calendar.dateComponents([.hour, .minute], from: date)
                           let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                           planner.update { $0[keyPath: path] = minute }
                       })
    }
}

/// Finds a place in Apple Maps and saves it.
private struct PlaceSearchView: View {
    @Environment(PlannerModel.self) private var planner
    @Environment(\.dismiss) private var dismiss
    let id: PlaceID
    @State private var query = ""
    @State private var results: [PlaceResult] = []
    @State private var searching = false

    var body: some View {
        List {
            if let saved = planner.settings.places[id] {
                Section("Saved") {
                    Text(saved.name)
                    Button("Remove", role: .destructive) {
                        planner.setPlace(nil, for: id)
                        dismiss()
                    }
                }
            }
            Section {
                if searching {
                    ProgressView()
                }
                ForEach(results) { result in
                    Button {
                        planner.setPlace(result.place, for: id)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.place.name)
                                .foregroundStyle(Palette.textPrimary)
                            if !result.address.isEmpty {
                                Text(result.address)
                                    .font(.caption)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                }
            } footer: {
                if results.isEmpty && !query.isEmpty && !searching {
                    Text("No matches. Try a postcode or the full name.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(id.title)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: id.searchHint)
        .onSubmit(of: .search) { Task { await search() } }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await search()
        }
        .onAppear {
            if query.isEmpty && (id == .aldi || id == .pool) { query = id == .aldi ? "Aldi" : "Swimming pool" }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []
            return
        }
        searching = true
        results = await planner.searchPlaces(text)
        searching = false
    }
}
