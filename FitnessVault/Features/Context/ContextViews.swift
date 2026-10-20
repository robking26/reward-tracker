import PhotosUI
import SwiftUI

// Phase 6 views: today's mode and weather, social plans, recovery, outings, menus and places.

/// Home or office for today, from the calendar, your choice or (with consent) where the phone is.
struct ModeAndWeatherLine: View {
    @Environment(CoachModel.self) private var coach
    @Environment(SituationModel.self) private var situation

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Menu {
                Button("Working from home", systemImage: "house") { _ = coach.setWorkMode(.home) }
                Button("In the office", systemImage: "building.2") { _ = coach.setWorkMode(.office) }
            } label: {
                Label(coach.workLocation == .unknown ? "Home or office?" : coach.workLocation.title,
                      systemImage: coach.workLocation == .office ? "building.2" : "house")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 4)
                    .background(Palette.elevated, in: Capsule())
            }
            .accessibilityLabel("Today: \(coach.workLocation.title). Change")
            if let weather = situation.weatherSummary {
                Label(weather, systemImage: weather.hasPrefix("Dry") ? "sun.max" : "cloud.rain")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

/// During recovery: gentle guidance and "how are you feeling?" (SO3). No pressure, no fines.
struct RecoveryCard: View {
    @Environment(CoachModel.self) private var coach
    @Environment(SituationModel.self) private var situation

    var body: some View {
        if case .recovering(let feeling) = situation.recoveryStatus(on: situation.today) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Recovery day")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                ForEach(RecoveryPlanner.guidance(feeling), id: \.self) { line in
                    Label(line, systemImage: "leaf")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("How are you feeling?")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                HStack(spacing: Spacing.xs) {
                    ForEach(RecoveryFeeling.allCases) { option in
                        SmallActionButton(title: option.title, symbol: option == feeling ? "checkmark" : "circle") {
                            if option == .normal {
                                _ = coach.backToNormal()
                            } else {
                                situation.setFeeling(option)
                            }
                        }
                    }
                }
            }
            .surface()
        } else if situation.recoveryStatus(on: situation.today) == .restarting {
            NoticeBanner(symbol: "arrow.clockwise", title: "First day back",
                         message: "One easy thing today. If the gym's on, it's a lighter session: just turning up is the win.",
                         tint: Palette.accent)
        }
    }
}

/// An upcoming social plan (next three days) that hasn't been planned yet (SO1–SO2).
struct SocialCard: View {
    @Environment(SituationModel.self) private var situation
    @State private var planning: DetectedSocial?

    var body: some View {
        if let social = situation.nextUnplannedSocial {
            Button {
                planning = social
            } label: {
                NoticeBanner(symbol: "person.2", title: "\(social.title), \(when(social.start))",
                             message: social.needsConfirmation
                                ? "It's in the shared calendar. Going too? A quick plan now makes the day after easier."
                                : "A quick plan now makes the day after easier: drinks, getting home and easy food.",
                             tint: Palette.accent)
            }
            .buttonStyle(CardButtonStyle())
            .sheet(item: Binding(get: { planning.map(IdentifiedSocial.init) }, set: { planning = $0?.social })) { item in
                NavigationStack { SocialPlanView(social: item.social) }
                    .presentationBackground(Palette.background)
            }
        }
    }

    private func when(_ date: Date) -> String {
        let calendar = situation.calendar
        if calendar.isDate(date, inSameDayAs: situation.now()) { return "today at \(date.formatted(date: .omitted, time: .shortened))" }
        return date.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}

struct IdentifiedSocial: Identifiable {
    var social: DetectedSocial
    var id: String { social.eventID }
}

struct SocialPlanView: View {
    @Environment(SituationModel.self) private var situation
    @Environment(\.dismiss) private var dismiss
    let social: DetectedSocial
    @State private var plan: SocialPlan?
    @State private var drinking: DrinkingPlan = .undecided
    @State private var driving = false
    @State private var going = true
    @State private var done: [String: String] = [:]

    var body: some View {
        Form {
            if social.needsConfirmation {
                Section { Toggle("I'm going too", isOn: $going) }
            }
            if going {
                Section {
                    Picker("Drinks", selection: $drinking) {
                        ForEach(DrinkingPlan.allCases) { Text($0.title).tag($0) }
                    }
                    Text(drinking.detail).font(.footnote).foregroundStyle(Palette.textSecondary)
                    Toggle("I'm driving", isOn: $driving)
                } header: {
                    Text("Your plan")
                } footer: {
                    Text("Your call. The aim is choosing beforehand, not giving anything up.")
                }
                let advice = SocialPlanner.advice(kind: social.kind, plan: drinking, driving: driving, eventDays: social.days)
                if !advice.isEmpty {
                    Section {
                        ForEach(advice, id: \.self) { Text($0).font(.subheadline) }
                    }
                }
                if let plan {
                    Section("Before you go") {
                        ForEach(SocialPlanner.preparation(plan: drinking, eventDays: social.days, nextDayHasWorkout: false)) { step in
                            PrepStepRow(step: step, result: done[step.title] ?? (plan.preparedSteps.contains(step.title) ? "Done." : nil)) {
                                // The recovery length follows the drinking plan chosen here.
                                plan.drinking = drinking
                                done[step.title] = situation.prepare(step, for: plan)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(social.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if let plan { situation.save(plan, drinking: drinking, driving: driving, going: going) }
                    dismiss()
                }
            }
        }
        .onAppear {
            let existing = situation.plan(for: social)
            plan = existing
            drinking = existing.drinking
            driving = existing.driving
            going = existing.going
        }
    }
}

struct PrepStepRow: View {
    let step: PrepStep
    let result: String?
    var perform: () -> Void

    var body: some View {
        if step.action == .reminder {
            Label(step.title, systemImage: "circle")
        } else if let result {
            VStack(alignment: .leading, spacing: 2) {
                Label(step.title, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.success)
                Text(result).font(.caption).foregroundStyle(Palette.textSecondary)
            }
        } else {
            Button(action: perform) {
                Label(step.title, systemImage: "plus.circle")
            }
        }
    }
}

/// "You're both free tonight. Fancy badminton?" Or, further ahead, a free weekend (RE1).
struct OutingCard: View {
    @Environment(SituationModel.self) private var situation
    @State private var answered: String?

    var body: some View {
        if let answered {
            NoticeBanner(symbol: "heart", title: "Nice", message: answered, tint: Palette.accent)
        } else if let idea = situation.outingIdea {
            card(title: "Tonight", question: idea.question, idea: idea)
        } else if let weekend = situation.freeWeekend {
            card(title: "Looking ahead",
                 question: "You've both got a free weekend on \(weekend.startDate(calendar: situation.calendar).formatted(.dateTime.day().month(.wide))). Fancy a night in the Lakes?",
                 idea: OutingPlanner.weekendAway)
        }
    }

    private func card(title: String, question: String, idea: OutingIdea) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            Text(question)
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if idea.paid {
                Text("What's the budget?")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                HStack(spacing: Spacing.xs) {
                    ForEach(OutingPlanner.budgetReplies, id: \.self) { budget in
                        SmallActionButton(title: budget, symbol: "sterlingsign") {
                            situation.respond(to: idea, accepted: true, budget: budget)
                            answered = "\(idea.title), \(budget.lowercased()). Have fun."
                        }
                    }
                }
            } else {
                SmallActionButton(title: "Good idea", symbol: "checkmark") {
                    situation.respond(to: idea, accepted: true)
                    answered = "\(idea.title). Have fun."
                }
            }
            Button("Not this time") { situation.respond(to: idea, accepted: false) }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
        }
        .surface()
    }
}

/// Eating out: picks from a photographed or pasted menu (SO1). Estimates, never a lecture.
struct MenuHelperView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @State private var scanning = false
    @State private var reading = false
    @State private var picks: [MenuPick]?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if DocumentScanner.isAvailable {
                        Button("Scan the menu", systemImage: "camera") { scanning = true }
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Photo or screenshot of the menu", systemImage: "photo")
                    }
                    TextEditor(text: $text).frame(minHeight: 120)
                    Button("Suggest something") { picks = MenuAdvisor.picks(from: text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("Read on your iPhone. Nothing is uploaded.")
                }
                if reading { Section { HStack { ProgressView(); Text("Reading…") } } }
                if let picks {
                    Section {
                        if picks.isEmpty {
                            Text("Nothing obvious stood out. Have what you fancy; one meal doesn't change anything.")
                        }
                        ForEach(picks, id: \.dish) { pick in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pick.dish).font(.headline)
                                Text(pick.reason).font(.caption).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    } header: {
                        Text("Good options")
                    } footer: {
                        Text(MenuAdvisor.footnote)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .pageBackground()
            .navigationTitle("Eating out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                read { await TextRecognition.text(in: images) }
            } onCancel: {
                scanning = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            read {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return "" }
                return await TextRecognition.text(in: image)
            }
        }
    }

    private func read(_ work: @escaping () async -> String) {
        reading = true
        Task {
            let result = await work()
            reading = false
            text = result
            picks = MenuAdvisor.picks(from: result)
        }
    }
}

/// Settings → Places, weather and travel (L1–L2). Location only with consent.
struct PlacesSettingsView: View {
    @Environment(CoachModel.self) private var coach
    @Environment(SituationModel.self) private var situation
    @State private var message: String?
    @State private var working = false

    var body: some View {
        @Bindable var store = coach.settingsStore
        Form {
            Section {
                Toggle("Use my location", isOn: Binding(get: { coach.coach.locationConsent }, set: { situation.setLocationConsent($0) }))
            } footer: {
                Text("Only while the app is open. Used to tell home from the office and for travel time to the gym. Never stored as a history.")
            }
            if coach.coach.locationConsent {
                Section("Places") {
                    placeRow("Home", place: coach.coach.places.home) { await save(.home) }
                    placeRow("Office", place: coach.coach.places.office) { await save(.office) }
                    placeRow("Gym", place: coach.coach.places.gym, action: "Find Nuffield Health Bolton") {
                        working = true
                        let place = await situation.findGym()
                        working = false
                        message = place.map { "Found \($0.name)." } ?? "Couldn't find it in Apple Maps."
                    }
                    if let estimate = situation.travelEstimate {
                        LabeledContent("Drive to the gym now", value: "\(estimate.minutes) min")
                    }
                }
            }
            Section {
                Stepper("Usual gym travel: \(store.settings.coach.gymTravelMinutes) min each way",
                        value: $store.settings.coach.gymTravelMinutes, in: 0...60, step: 5)
            } footer: {
                Text("Used when there's no live journey time. Gym plans always include travel both ways and changing.")
            }
            Section {
                Toggle("Plan walks around the weather", isOn: $store.settings.coach.weatherEnabled)
                if let summary = situation.weatherSummary { LabeledContent("Today", value: summary) }
                if let problem = situation.weatherProblem { Text(problem).font(.footnote).foregroundStyle(Palette.warning) }
            } footer: {
                Text("Forecasts from Open-Meteo, free and without an account. Only a location rounded to about 1 km is sent (Bolton if location is off).")
            }
            Section {
                Toggle("Keep recovery history", isOn: $store.settings.coach.trackRecoveryPatterns)
            } footer: {
                Text("Off: recovery days are deleted a week after they end. On: they're kept so patterns can be spotted. Never used for fines.")
            }
            if let message { Section { Text(message) } }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Places and weather")
        .disabled(working)
    }

    private func placeRow(_ title: String, place: SavedPlace?, action: String = "Use where I am now",
                          perform: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: place?.name ?? "Not set")
            Button(action) { Task { await perform() } }
                .font(.footnote.weight(.semibold))
        }
    }

    private func save(_ kind: WorkLocation) async {
        working = true
        let saved = await situation.saveCurrentLocation(as: kind)
        working = false
        message = saved ? "Saved." : "Couldn't get your location. Check that location is allowed for Vaultality in iPhone Settings."
    }
}
