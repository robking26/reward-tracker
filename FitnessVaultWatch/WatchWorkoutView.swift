import SwiftUI

/// Rest countdown and session status on the wrist. Sets are logged on the iPhone (W5).
struct WatchWorkoutView: View {
    @Environment(WatchWorkoutModel.self) private var model
    @State private var confirmEnd = false

    private let accent = Color(.sRGB, red: 0xC5 / 255, green: 0xF2 / 255, blue: 0x77 / 255, opacity: 1)

    var body: some View {
        if model.isActive {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let end = model.restEndsAt, end > .now {
                        Text("Rest")
                            .font(.caption)
                            .foregroundStyle(accent)
                        Text(timerInterval: Date.now...end, countsDown: true)
                            .font(.system(size: 40, weight: .medium))
                            .monospacedDigit()
                        Text("\(model.setLabel): \(model.next)")
                            .font(.footnote)
                            .lineLimit(2)
                        Button("Skip rest") { model.skipRest() }
                    } else {
                        Text(model.next.isEmpty ? "Log your set on your iPhone" : "Up: \(model.next)")
                            .font(.headline)
                            .lineLimit(3)
                    }
                    Button("End workout", role: .destructive) { confirmEnd = true }
                        .padding(.top, 8)
                    if let error = model.healthError {
                        Text(error).font(.caption2).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .confirmationDialog("End the workout?", isPresented: $confirmEnd) {
                Button("End", role: .destructive) { model.endWorkout() }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "dumbbell.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                Text("Start a workout on your iPhone and the rest timer appears here.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
