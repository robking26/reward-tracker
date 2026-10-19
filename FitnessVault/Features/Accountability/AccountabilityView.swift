import SwiftUI

/// The month view (Phase 5): every fine explained, the transfer estimate, the append-only ledger, closed-month
/// statements and the trial review. Corrections are possible until the month closes.
struct AccountabilityView: View {
    @Environment(CoachModel.self) private var coach
    @State private var selected: MonthKey?

    var body: some View {
        let month = selected ?? coach.today.monthKey
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                let months = coach.accountabilityMonths()
                if months.count > 1 {
                    Picker("Month", selection: Binding(get: { month }, set: { selected = $0 })) {
                        ForEach(months, id: \.self) { Text(title(for: $0)).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Palette.textPrimary)
                }
                MonthSummaryCard(month: month)
                if let statement = coach.statement(for: month) {
                    StatementCard(statement: statement)
                }
                MonthDaysCard(month: month)
                FineLedgerCard(month: month)
                if coach.coach.finesAreSimulated || month == coach.today.monthKey {
                    TrialReviewCard()
                }
                Text("Fines come out of the month's \(coach.settings.monthlyAllocation.formatted(wholePounds: true)) and stay in Starling; they're never spent, moved or turned into debt. Never fined: weight, food, calories, binges, skipped meals, illness, injury, rest, sleep, or anything outside your control.")
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
        }
        .pageBackground()
        .navigationTitle("Accountability")
    }

    private func title(for month: MonthKey) -> String {
        DayKey(year: month.year, month: month.month, day: 1).startDate(calendar: coach.calendar)
            .formatted(.dateTime.month(.wide).year())
    }
}

struct MonthSummaryCard: View {
    @Environment(CoachModel.self) private var coach
    let month: MonthKey

    var body: some View {
        let summary = coach.monthSummary(month)
        let closed = coach.isClosed(month)
        let cap = coach.coach.fineSchedule.monthlyCap
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text(closed ? "Final" : "So far this month")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text(coach.coach.finesAreSimulated ? "Trial · no real money" : "Live · you move it by hand")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Palette.elevated, in: Capsule())
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.transferable.formatted())
                        .font(.largeTitle.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                    Text(closed ? "to keep" : "to keep if nothing else is missed")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
            }
            Divider().overlay(Palette.border)
            LabeledContent("Fines", value: "\(summary.fines.formatted()) of the \(cap.formatted(wholePounds: true)) cap")
            LabeledContent("Days scored", value: "\(summary.daysScored)")
            if let average = summary.averageScore {
                LabeledContent("Average day", value: "\(average)%")
            }
            if summary.capSaved.isPositive {
                LabeledContent("Stopped by the cap", value: summary.capSaved.formatted())
            }
            if !closed {
                Text("You can correct any day until \(closesOn(month)). After that the month is final.")
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Palette.textPrimary)
        .surface()
    }

    private func closesOn(_ month: MonthKey) -> String {
        MonthCloseRule.closesOn(month).startDate(calendar: coach.calendar).formatted(.dateTime.day().month(.wide))
    }
}

struct StatementCard: View {
    @Environment(CoachModel.self) private var coach
    let statement: MonthStatement
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Month-end transfer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            if let plan = statement.plan {
                Text(plan.instruction)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch statement.status {
            case .simulated:
                Label("Simulated. Nothing was sent to Starling.", systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            case .awaitingManualTransfer:
                SmallActionButton(title: "I've moved it", symbol: "checkmark") { confirming = true }
            case .manuallyTransferred:
                Label("You moved it on \(statement.confirmedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")",
                      systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.success)
            }
        }
        .surface()
        .confirmationDialog("Did \(statement.transferable.formatted()) reach Monzo?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Yes, I've moved it") { coach.confirmManualTransfer(statement) }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("This only records that you did it. The app never moves money itself.")
        }
    }
}

struct MonthDaysCard: View {
    @Environment(CoachModel.self) private var coach
    let month: MonthKey

    var body: some View {
        let records = coach.dayRecords(in: month).reversed()
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Days")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            if records.isEmpty {
                Text("Scored days appear here after each day ends.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
            }
            ForEach(Array(records), id: \.day) { record in
                if let day = record.dayKey {
                    NavigationLink {
                        DayAccountabilityView(day: day)
                    } label: {
                        DayRecordRow(record: record, day: day)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .surface()
    }
}

struct DayRecordRow: View {
    @Environment(CoachModel.self) private var coach
    let record: DayRecord
    let day: DayKey

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.startDate(calendar: coach.calendar).formatted(.dateTime.weekday(.abbreviated).day().month()))
                    .foregroundStyle(Palette.textPrimary)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            Text(record.fine.isPositive ? record.fine.formatted() : "£0")
                .monospacedDigit()
                .foregroundStyle(record.fine.isPositive ? Palette.warning : Palette.textSecondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var status: String {
        guard record.finalisedAt != nil else { return "Waiting for you to confirm" }
        guard let score = record.scorePercent else { return "Nothing agreed" }
        return "\(score)%"
    }
}

/// Why a day scored what it did: every applicable commitment, its weight, state and history (A5: explain the penalty).
struct DayAccountabilityView: View {
    @Environment(CoachModel.self) private var coach
    let day: DayKey

    var body: some View {
        let items = coach.commitments(on: day).filter { $0.state != .proposed }
        let record = coach.dayRecord(day)
        let closed = coach.isClosed(day.monthKey)
        List {
            if let record {
                Section {
                    Text(record.explanation.isEmpty ? "Not reconciled yet." : record.explanation)
                    if record.fine.isPositive {
                        LabeledContent("Fine", value: record.fine.formatted())
                    }
                } header: {
                    Text("Outcome")
                } footer: {
                    if record.isSimulation { Text("Trial: no real money.") }
                }
            }
            Section {
                ForEach(items, id: \.id) { item in
                    CommitmentAuditRow(item: item, editable: !closed && day < coach.today)
                }
            } header: {
                Text("Commitments")
            } footer: {
                Text(closed ? "This month is closed, so the record is final."
                            : "Weights were fixed when each commitment was agreed and never change afterwards. Excused, moved and cancelled items don't count against you.")
            }
            if let error = coach.lastError {
                Section { Text(error).foregroundStyle(Palette.warning) }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(day.startDate(calendar: coach.calendar).formatted(.dateTime.weekday(.wide).day().month()))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CommitmentAuditRow: View {
    @Environment(CoachModel.self) private var coach
    let item: Commitment
    let editable: Bool
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(coach.history(for: item), id: \.id) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(CommitmentState(rawValue: event.fromRaw)?.title ?? event.fromRaw) → \(CommitmentState(rawValue: event.toRaw)?.title ?? event.toRaw)")
                        .font(.caption.weight(.semibold))
                    Text("\(event.reason ?? "") · \(event.actorRaw) · \(event.at.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            if editable && item.state == .missed {
                Button("Actually, I did this") { coach.transition(item, .correct(to: .completed), reason: "Corrected: it was done") }
                Menu("I couldn't, for a genuine reason") {
                    ForEach(ExcuseReason.allCases) { reason in
                        Button(reason.title) { coach.transition(item, .correct(to: .excused), reason: "Corrected: \(reason.title)") }
                    }
                }
            } else if editable && item.state == .completed {
                Button("Actually, I didn't", role: .destructive) { coach.transition(item, .correct(to: .missed), reason: "Corrected: not done") }
            }
        } label: {
            HStack {
                Label(item.title, systemImage: item.kind.symbol)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.state.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.state == .missed ? Palette.warning : Palette.textSecondary)
                    Text(item.state.isApplicable ? "weight \(item.weight)" : "not counted")
                        .font(.caption2)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .accessibilityHint(item.assumedMissed ? "Counted as missed because it wasn't answered" : "")
    }
}

/// Append-only record of every fine set or changed (A8).
struct FineLedgerCard: View {
    @Environment(CoachModel.self) private var coach
    let month: MonthKey

    var body: some View {
        let entries = coach.fineLedger(in: month)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Ledger")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            if entries.isEmpty {
                Text("Every fine, and every change to one, is recorded here and never deleted.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(entries.prefix(30), id: \.id) { entry in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.dayKey?.startDate(calendar: coach.calendar).formatted(.dateTime.day().month()) ?? entry.day)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.textPrimary)
                        Text(entry.reason)
                            .font(.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    Text(entry.before == entry.after ? entry.after.formatted() : "\(entry.before.formatted()) → \(entry.after.formatted())")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.vertical, 2)
            }
        }
        .surface()
    }
}

/// The trial in numbers, so the rules are reviewed against real data before any money is real (A7).
struct TrialReviewCard: View {
    @Environment(CoachModel.self) private var coach
    @State private var confirmingLive = false

    var body: some View {
        let review = coach.trialReview()
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Trial review")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            if review.daysScored == 0 {
                Text("After a couple of weeks of scored days, this shows how the fine bands would have worked, so you can decide whether to keep them.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LabeledContent("Days scored", value: "\(review.daysScored)")
                if let average = review.averageScore { LabeledContent("Average day", value: "\(average)%") }
                ForEach(review.bandCounts, id: \.label) { band in
                    LabeledContent(band.label, value: "\(band.days) days")
                }
                LabeledContent("Simulated fines", value: review.simulatedFines.formatted())
                LabeledContent("Excused", value: "\(review.excused)")
                if review.assumedMissed > 0 { LabeledContent("Missed because unanswered", value: "\(review.assumedMissed)") }
                ForEach(review.observations, id: \.self) { note in
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if coach.coach.finesAreSimulated {
                if review.isReady {
                    SmallActionButton(title: "Make fines real", symbol: "sterlingsign.circle") { confirmingLive = true }
                    Text("You'd move the money yourself at month end. The app never sends payments.")
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    Text("Fines stay simulated until there are at least \(TrialReview.minimumDays) scored days to review.")
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            } else {
                Button("Go back to the trial") { coach.setFinesLive(false) }
                    .font(.footnote.weight(.semibold))
            }
        }
        .font(.subheadline)
        .foregroundStyle(Palette.textPrimary)
        .surface()
        .confirmationDialog("Make fines real?", isPresented: $confirmingLive, titleVisibility: .visible) {
            Button("Yes, from today") { coach.setFinesLive(true) }
            Button("Keep the trial", role: .cancel) {}
        } message: {
            Text("From today, fines reduce what you move from Starling to Monzo at month end. Bands: \(bands). Cap: \(coach.coach.fineSchedule.monthlyCap.formatted(wholePounds: true)). You can go back to the trial any time.")
        }
    }

    private var bands: String {
        coach.coach.fineSchedule.bands.sorted { $0.minimumPercent > $1.minimumPercent }
            .map { "\($0.minimumPercent)%+ \($0.fine.formatted(wholePounds: true))" }
            .joined(separator: ", ")
    }
}
