import SwiftUI

/// Apple-style Move, Exercise and Stand rings, drawn in SwiftUI so they also work in the widget.
struct ActivityRingsView: View {
    let rings: ActivityRingsSnapshot?
    var lineWidth: CGFloat = 14
    var spacing: CGFloat = 3

    static let moveColor = Color(.sRGB, red: 0.98, green: 0.07, blue: 0.31, opacity: 1)
    static let exerciseColor = Color(.sRGB, red: 0.65, green: 1.0, blue: 0.0, opacity: 1)
    static let standColor = Color(.sRGB, red: 0.12, green: 0.92, blue: 0.94, opacity: 1)

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                ring(rings?.move.fraction ?? 0, color: Self.moveColor, inset: 0, size: size)
                ring(rings?.exercise.fraction ?? 0, color: Self.exerciseColor, inset: lineWidth + spacing, size: size)
                ring(rings?.stand.fraction ?? 0, color: Self.standColor, inset: (lineWidth + spacing) * 2, size: size)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private func ring(_ fraction: Double, color: Color, inset: CGFloat, size: CGFloat) -> some View {
        let diameter = max(0, size - inset * 2 - lineWidth)
        return ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, fraction))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Past 100%, a second lap is drawn on top, as in the Fitness app.
            if fraction > 1 {
                Circle()
                    .trim(from: 0, to: min(1, fraction - 1))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.35), radius: 1.5)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var accessibilityText: String {
        guard let rings else { return "Activity rings unavailable" }
        func percent(_ ring: RingProgress) -> Int { Int((ring.fraction * 100).rounded()) }
        return "Move \(percent(rings.move)) percent, Exercise \(percent(rings.exercise)) percent, Stand \(percent(rings.stand)) percent"
    }
}
