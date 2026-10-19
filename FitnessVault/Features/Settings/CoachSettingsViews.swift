import SwiftUI
import UIKit

// MARK: - Routines

/// Pre-agreed routines (A3). Turning one on is agreeing to it every scheduled day.
struct RoutinesView: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        Form {
            Section {
                ForEach(coach.routines(), id: \.id) { routine in
                    Toggle(isOn: Binding(get: { routine.isEnabled }, set: { coach.setRoutine(routine, enabled: $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(routine.title, systemImage: routine.kind.symbol)
                                .foregroundStyle(Palette.textPrimary)
                            Text(schedule(routine))
                                .font(.caption)
                                .foregroundStyle(Palette.textTertiary)
                            if let reason = routine.reason {
                                Text(reason).font(.caption).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("A routine you turn on counts every scheduled day without asking, including days you don't open the app. Turning one on late in the day never adds a commitment whose time has already passed. Weight is how much it counts towards the day's score (1 light, 5 major).")
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Routines")
    }

    private func schedule(_ routine: Routine) -> String {
        let days = routine.weekdays
        let dayText = days.count == 7 ? "Every day" : days == [1, 2, 3, 4, 5] ? "Weekdays" : days.sorted().map { weekdayName($0) }.joined(separator: ", ")
        let time = routine.minuteOfDay.map { String(format: " · %02d:%02d", $0 / 60, $0 % 60) } ?? " · any time"
        return "\(dayText)\(time) · \(routine.durationMinutes) min · weight \(routine.weight)"
    }

    private func weekdayName(_ iso: Int) -> String {
        ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][max(0, min(6, iso - 1))]
    }
}

// MARK: - Calendars

/// Read-only calendar access and labelling (D-008, D-009).
struct CalendarsSettingsView: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        Form {
            Section {
                LabeledContent("Access", value: coach.calendarAccess.title)
                if coach.calendarAccess == .notDetermined {
                    Button("Allow Calendar Access") { Task { await coach.requestCalendarAccess() } }
                }
            } footer: {
                Text("Read-only. Vaultality never adds, moves or deletes events in your calendars. Event details stay on this iPhone.")
            }

            if coach.calendarAccess == .granted {
                Section {
                    ForEach(coach.availableCalendars) { item in
                        Picker(selection: Binding(get: { coach.calendarRoles[item.id] },
                                                  set: { coach.setRole($0, for: item.id) })) {
                            Text("Not labelled").tag(CalendarRole?.none)
                            ForEach(CalendarRole.allCases) { role in
                                Text(role.title).tag(CalendarRole?.some(role))
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).foregroundStyle(Palette.textPrimary)
                                Text(item.sourceTitle).font(.caption).foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                } header: {
                    Text("Your calendars")
                } footer: {
                    Text("Work: meetings and focus blocks are protected; events titled \"Focus\", \"Deep work\" or \"Do not book\" count as focus time. Shared with Becky: shown for context but never makes you busy. Unlabelled calendars are ignored. If your Outlook work calendar isn't listed, add the work account in iPhone Settings › Calendar › Accounts, if your employer allows it.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Calendars")
        .onAppear { coach.refreshCalendar() }
    }
}

// MARK: - Memory

/// Everything the coach remembers, grouped by store, editable and deletable (M4).
struct MemoryView: View {
    @Environment(CoachModel.self) private var coach
    @State private var exportURL: URL?
    @State private var refresh = 0

    var body: some View {
        List {
            Section {
                Text("Facts you've stated are used as facts. The coach's guesses are marked and never treated as true until you confirm them. Sensitive items are never shown in notifications or widgets.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(MemoryStore.allCases) { store in
                let records = coach.memories(in: store)
                if !records.isEmpty {
                    Section(store.title) {
                        ForEach(records, id: \.id) { record in
                            NavigationLink {
                                MemoryEditView(record: record) { refresh += 1 }
                            } label: {
                                MemoryRow(record: record)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { coach.forget(records[index]) }
                            refresh += 1
                        }
                    }
                }
            }
            Section {
                Button("Export Coach Data") { exportURL = try? coach.exportCoachData() }
                if let exportURL { ShareLink("Share Export", item: exportURL) }
            }
        }
        .id(refresh)
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Coach memory")
    }
}

struct MemoryRow: View {
    let record: MemoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Spacing.xs) {
                Text(record.key).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                if record.status == .hypothesis {
                    Text("Guess").font(.caption2.weight(.semibold)).foregroundStyle(Palette.warning)
                }
                if record.sensitivity.isSensitive {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Palette.textTertiary)
                        .accessibilityLabel("Sensitive: \(record.sensitivity.title)")
                }
            }
            Text(record.value).font(.footnote).foregroundStyle(Palette.textSecondary).lineLimit(3)
            Text(record.source.title).font(.caption2).foregroundStyle(Palette.textTertiary)
        }
    }
}

struct MemoryEditView: View {
    @Environment(CoachModel.self) private var coach
    @Environment(\.dismiss) private var dismiss
    let record: MemoryRecord
    var onChange: () -> Void
    @State private var value = ""
    @State private var sensitivity: Sensitivity = .general

    var body: some View {
        Form {
            Section(record.key) {
                TextEditor(text: $value).frame(minHeight: 140)
            }
            Section {
                Picker("Privacy", selection: $sensitivity) {
                    ForEach(Sensitivity.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("Source", value: record.source.title)
                LabeledContent("Updated", value: record.updatedAt.formatted(date: .abbreviated, time: .shortened))
                if record.status == .hypothesis {
                    Button("Confirm this is true") {
                        coach.confirm(record)
                        onChange()
                        dismiss()
                    }
                }
            }
            Section {
                Button("Save") {
                    if value != record.value { coach.correct(record, value: value) }
                    if sensitivity != record.sensitivity { coach.setSensitivity(sensitivity, for: record) }
                    onChange()
                    dismiss()
                }
                .fontWeight(.semibold)
                Button("Forget This", role: .destructive) {
                    coach.forget(record)
                    onChange()
                    dismiss()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Edit memory")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            value = record.value
            sensitivity = record.sensitivity
        }
    }
}

// MARK: - Accountability

/// The fine rules (A2) and the shape of the day (D-010).
struct AccountabilitySettingsView: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        @Bindable var store = coach.settingsStore
        Form {
            Section {
                ForEach(coach.coach.fineSchedule.bands.sorted(by: { $0.minimumPercent > $1.minimumPercent }), id: \.minimumPercent) { band in
                    LabeledContent(bandTitle(band), value: band.fine.isPositive ? band.fine.formatted(wholePounds: true) : "No fine")
                }
                LabeledContent("Monthly cap", value: coach.coach.fineSchedule.monthlyCap.formatted(wholePounds: true))
                LabeledContent("Mode", value: coach.coach.finesAreSimulated ? "Trial (no real money)" : "Live")
            } header: {
                Text("Daily score and fines")
            } footer: {
                Text("Fines come out of your \(coach.settings.monthlyAllocation.formatted(wholePounds: true)) and stay in Starling; they're never spent or moved. Never fined: weight, food, calories, binges, illness, injury, rest, sleep, or anything outside your control. During the trial nothing real happens; real money only after you review the rules.")
            }

            Section("Your day") {
                MinutePicker(title: "Wake", minutes: $store.settings.coach.wakeMinute)
                MinutePicker(title: "Work starts", minutes: $store.settings.coach.workStartMinute)
                MinutePicker(title: "Lunch", minutes: $store.settings.coach.lunchStartMinute)
                MinutePicker(title: "Lunch ends", minutes: $store.settings.coach.lunchEndMinute)
                MinutePicker(title: "Work ends", minutes: $store.settings.coach.workEndMinute)
                MinutePicker(title: "Dinner", minutes: $store.settings.coach.dinnerMinute)
                MinutePicker(title: "Wind down", minutes: $store.settings.coach.windDownMinute)
                MinutePicker(title: "Bedtime", minutes: $store.settings.coach.bedtimeMinute)
                Stepper("Gym travel: \(store.settings.coach.gymTravelMinutes) min each way",
                        value: $store.settings.coach.gymTravelMinutes, in: 0...60, step: 5)
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Accountability")
        .onDisappear { coach.reload() }
    }

    private func bandTitle(_ band: FineBand) -> String {
        let higher = coach.coach.fineSchedule.bands.map(\.minimumPercent).filter { $0 > band.minimumPercent }.min()
        if let higher { return band.minimumPercent == 0 ? "Below \(higher)%" : "\(band.minimumPercent)–\(higher - 1)%" }
        return "\(band.minimumPercent)–100%"
    }
}

/// A time of day stored as minutes after midnight.
struct MinutePicker: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(minutes * 60)) },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
    }
}

// MARK: - Privacy

/// What the app can access, where data lives, and the controls to export or delete it (E3, M4).
struct PrivacyView: View {
    @Environment(CoachModel.self) private var coach
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?
    @State private var confirmDeleteAll = false
    @State private var confirmDeleteChat = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Apple Health", value: model.healthAccess == .requested ? "Requested (read-only)" : "Not set up")
                LabeledContent("Calendars", value: coach.calendarAccess.title)
                LabeledContent("Microphone and speech", value: "Asked when you first dictate")
                LabeledContent("Location", value: "Not used yet")
                Button("Open iPhone Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } header: {
                Text("Access")
            } footer: {
                Text("You can revoke any of these in iPhone Settings at any time.")
            }

            Section {
                Text("Your coach, memory, calendar view and conversation stay on this iPhone. The coach doesn't send your messages, health or calendar details to any AI service. Dictation runs on the iPhone when supported. Banking tokens are kept in the Keychain on this device only.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            } header: {
                Text("Where your data lives")
            }

            Section {
                Button("Export Coach Data") { exportURL = try? coach.exportCoachData() }
                if let exportURL { ShareLink("Share Export", item: exportURL) }
                Button("Delete Conversation", role: .destructive) { confirmDeleteChat = true }
                Button("Delete All Coach Data", role: .destructive) { confirmDeleteAll = true }
            } header: {
                Text("Your data")
            } footer: {
                Text("Deleting coach data removes memory, conversation, commitments, routines, tasks and daily scores. Banking records stay, because they reflect real transactions.")
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Privacy & data")
        .confirmationDialog("Delete the whole conversation?", isPresented: $confirmDeleteChat, titleVisibility: .visible) {
            Button("Delete Conversation", role: .destructive) { coach.deleteConversation() }
        }
        .confirmationDialog("Delete all coach data? This can't be undone.", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { coach.deleteAllCoachData() }
        }
    }
}

// MARK: - Add commitment

/// Adding a commitment yourself agrees to it. Its weight is fixed once saved (D-012).
struct AddCommitmentView: View {
    @Environment(CoachModel.self) private var coach
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind: CommitmentKind = .other
    @State private var hasTime = true
    @State private var start = Date.now.addingTimeInterval(30 * 60)
    @State private var duration = 30
    @State private var weight = CommitmentKind.other.defaultWeight

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What will you do?", text: $title)
                    Picker("Type", selection: $kind) {
                        ForEach(CommitmentKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .onChange(of: kind) { _, newKind in weight = newKind.defaultWeight }
                }
                Section {
                    Toggle("At a set time", isOn: $hasTime)
                    if hasTime {
                        DatePicker("Start", selection: $start, in: Date.now..., displayedComponents: .hourAndMinute)
                    }
                    Stepper("Takes \(DurationFormat.text(minutes: duration))", value: $duration, in: 5...240, step: 5)
                    Stepper("Weight \(weight) of 5", value: $weight, in: 1...5)
                } footer: {
                    Text("This counts towards today's score once added. Its weight can't change later; moving it to another day needs a real reason.")
                }
            }
            .scrollContentBackground(.hidden)
            .pageBackground()
            .navigationTitle("New commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        coach.addCommitment(title.trimmingCharacters(in: .whitespaces), kind: kind,
                                            start: hasTime ? start : nil, durationMinutes: duration, weight: weight)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationBackground(Palette.background)
    }
}
