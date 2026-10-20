import SwiftUI

// MARK: - Surface

/// The standard card surface: flat charcoal, continuous corners, a hairline only when Increase Contrast is on.
struct SurfaceModifier: ViewModifier {
    var radius: CGFloat = Radius.card
    var fill: Color = Palette.surface
    var padding: CGFloat = Spacing.m
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1)
                }
            }
    }
}

extension View {
    func surface(radius: CGFloat = Radius.card, fill: Color = Palette.surface, padding: CGFloat = Spacing.m) -> some View {
        modifier(SurfaceModifier(radius: radius, fill: fill, padding: padding))
    }

    /// Applies the app's charcoal page background.
    func pageBackground() -> some View {
        background(Palette.background.ignoresSafeArea())
    }
}

// MARK: - Money

/// Monetary amounts: tabular digits, counting smoothly when the value changes.
struct MoneyText: View {
    let amount: Pence
    var font: Font = .title2
    var weight: Font.Weight = .medium
    var color: Color = Palette.textPrimary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(amount.formatted())
            .font(font.weight(weight))
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(amount.value)))
            .animation(reduceMotion ? nil : .snappy, value: amount)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

// MARK: - Progress

/// A thin progress bar that animates to its value. Respects Reduce Motion.
struct ThinProgressBar: View {
    let progress: Double
    var height: CGFloat = 6
    var tint: Color = Palette.accent
    var track: Color = Palette.elevated

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(shown > 0 ? height : 0, proxy.size.width * shown))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(Text("\(Int((progress * 100).rounded(.down))) percent"))
        .onAppear { update(animated: !reduceMotion) }
        .onChange(of: progress) { update(animated: !reduceMotion) }
    }

    private func update(animated: Bool) {
        let clamped = min(1, max(0, progress))
        if animated {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { shown = clamped }
        } else {
            shown = clamped
        }
    }
}

// MARK: - Section header

/// "Title ......... See All" header, as used on the dashboard.
struct SectionHeader<Destination: View>: View {
    let title: String
    var destination: Destination?

    init(_ title: String, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.destination = destination()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let destination {
                NavigationLink {
                    destination
                } label: {
                    Text("See All")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.vertical, Spacing.xs)
                        .contentShape(Rectangle())
                }
            }
        }
    }
}

extension SectionHeader where Destination == EmptyView {
    init(_ title: String) {
        self.title = title
        self.destination = nil
    }
}

// MARK: - Status badge

struct StatusBadge: View {
    let status: PaymentStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, Spacing.xs + 2)
            .padding(.vertical, Spacing.xxs + 1)
            .background(Palette.elevated, in: Capsule())
            .accessibilityLabel("Status: \(status.title)")
    }
}

// MARK: - Metric card

/// A compact two-column dashboard card: title, timeframe, measurement, earnings and chevron.
struct MetricCard: View {
    let title: String
    let symbol: String
    let timeframe: String
    let measurement: String
    let unit: String
    let earned: Pence?
    /// Shown in place of the earned amount, e.g. "Not rewarded".
    var earnedCaption: String? = nil
    /// False for cards that don't open a detail screen.
    var showsChevron = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            Text(timeframe)
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                    Text(measurement)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                if let earned {
                    Text("+\(earned.formatted())")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(earned.isPositive ? Palette.accent : Palette.textTertiary)
                        .contentTransition(.numericText(value: Double(earned.value)))
                } else if let earnedCaption {
                    Text(earnedCaption)
                        .font(.footnote)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 148, maxHeight: .infinity, alignment: .topLeading)
        .surface()
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(showsChevron ? .isButton : [])
    }

    private var accessibilityText: String {
        var parts = ["\(title), \(timeframe)", "\(measurement) \(unit)"]
        if let earned { parts.append("earned \(earned.formatted())") } else if let earnedCaption { parts.append(earnedCaption) }
        return parts.joined(separator: ", ")
    }
}

/// Press feedback for cards: a gentle native spring.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardPress(configuration: configuration)
    }

    /// A gentle press. With Reduce Motion it dims instead of scaling.
    private struct CardPress: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

/// Banner for offline, stale, permission and error states.
struct NoticeBanner: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = Palette.warning
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.top, Spacing.xxs)
                }
            }
            Spacer(minLength: 0)
        }
        .surface(fill: Palette.surface)
        .accessibilityElement(children: .combine)
    }
}

/// A label/value row used in vault and detail screens.
struct ValueRow: View {
    let title: String
    let value: Pence
    var detail: String? = nil
    var tint: Color = Palette.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Text(value.formatted())
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText(value: Double(value.value)))
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
