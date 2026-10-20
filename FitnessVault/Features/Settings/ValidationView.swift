import SwiftData
import SwiftUI

/// Settings → Test week (Phase 8): how the app is doing against real life, and a report to share.
struct ValidationView: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        let input = coach.validationInput()
        let summary = ValidationSummary(input, calendar: coach.calendar)
        Form {
            Section {
                LabeledContent("Days", value: "\(summary.days)")
                LabeledContent("Suggestions agreed", value: "\(summary.agreed) of \(summary.suggested)")
                LabeledContent("Marked wrong", value: "\(summary.flaggedWrong)")
                LabeledContent("Done · missed", value: "\(summary.done) · \(summary.missed)")
                if summary.assumedMissed > 0 {
                    LabeledContent("Missed because unanswered", value: "\(summary.assumedMissed)")
                }
                if let average = summary.averageUsefulness {
                    LabeledContent("Usefulness", value: String(format: "%.1f of 3", average))
                }
                LabeledContent("Messages not understood", value: "\(summary.unknownMessages) of \(summary.messagesSent)")
            } header: {
                Text("So far")
            } footer: {
                Text("Kept on this iPhone. Nothing here affects your score or fines.")
            }
            if !summary.priorities.isEmpty {
                Section("Fix first") {
                    ForEach(summary.priorities, id: \.self) { Text($0) }
                }
            }
            if !summary.reasons.isEmpty {
                Section("Why suggestions were wrong") {
                    ForEach(summary.reasons, id: \.reason) { item in
                        LabeledContent(item.reason.title, value: "\(item.count)")
                    }
                }
            }
            if !summary.issues.isEmpty {
                Section {
                    ForEach(summary.issues, id: \.self) { Text($0).font(.footnote) }
                } header: {
                    Text("Caught by the plan checker")
                } footer: {
                    Text("Suggestions that clashed or fell outside your day were removed before you saw them. Each one points to a rule to fix.")
                }
            }
            Section {
                ShareLink(item: coach.validationReport(), subject: Text("Vaultality test report")) {
                    Label("Share the report", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Plain text: counts, your reasons and notes, and what the checker caught. No calendar event names, health figures or money. Send it to whoever is fixing the app.")
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Test week")
    }
}
