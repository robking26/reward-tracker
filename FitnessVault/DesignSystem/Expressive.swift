import SwiftUI

// The expressive layer used by the Gym and Kitchen: tinted icon tiles, chips, gradient hero cards, big rounded
// numerals and capsule buttons. Each area has its own hue on top of the charcoal base; lime stays for progress.

extension Palette {
    /// Kitchen: warm tangerine.
    static let kitchen = Color(hex: 0xFFB36B)
    /// Freezer and cold things.
    static let frost = Color(hex: 0x8CCBFF)
    /// Rehab and the knee.
    static let rehab = Color(hex: 0xB8A5FF)
    /// Lunches and fresh food.
    static let fresh = Color(hex: 0x7FE0C3)
    static let rose = Color(hex: 0xFF9AA8)
    /// A slightly lighter card used inside other cards.
    static let inset = Color(hex: 0x2C3132)
}

extension Font {
    /// Big rounded numerals and hero titles.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

enum Radius2 {
    static let hero: CGFloat = 28
    static let tile: CGFloat = 12
}

// MARK: - Icon tile

/// A tinted rounded square holding an SF Symbol.
struct IconTile: View {
    let symbol: String
    var tint: Color = Palette.accent
    var size: CGFloat = 36
    var filled = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        let fill: Color = filled ? tint : tint.opacity(0.16)
        let ink: Color = filled ? Palette.onAccent : tint
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(fill, in: shape)
            .accessibilityHidden(true)
    }
}

// MARK: - Chip

/// A small capsule label: "45 min", "38 g protein".
struct Chip: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = Palette.textSecondary
    var fill: Color = Palette.elevated

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(fill, in: Capsule())
    }
}

/// Chips that wrap onto several lines.
struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Hero card

/// A large card washed with the area's hue from the top corner, with an oversized symbol as artwork.
struct HeroCardModifier: ViewModifier {
    let tint: Color
    var symbol: String? = nil
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius2.hero, style: .continuous)
        let wash = LinearGradient(colors: [tint.opacity(0.34), tint.opacity(0.08), Palette.surface],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        content
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .topTrailing) {
                    Palette.surface
                    wash
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 150, weight: .bold))
                            .foregroundStyle(tint.opacity(0.10))
                            .rotationEffect(.degrees(-12))
                            .offset(x: 34, y: -26)
                            .accessibilityHidden(true)
                    }
                }
                .clipShape(shape)
            }
            .overlay {
                shape.strokeBorder(contrast == .increased ? Palette.border : tint.opacity(0.18), lineWidth: 1)
            }
    }
}

extension View {
    func heroCard(tint: Color, symbol: String? = nil) -> some View {
        modifier(HeroCardModifier(tint: tint, symbol: symbol))
    }
}

// MARK: - Buttons

/// The one big action on a screen: a full-width capsule in the area's hue.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent
    var ink: Color = Palette.onAccent

    func makeBody(configuration: Configuration) -> some View {
        PrimaryLabel(configuration: configuration, tint: tint, ink: ink)
    }

    private struct PrimaryLabel: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let ink: Color
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(.headline)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(tint.opacity(isEnabled ? 1 : 0.35), in: Capsule())
                .shadow(color: tint.opacity(isEnabled ? 0.28 : 0), radius: 16, y: 6)
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: pressed)
        }
    }
}

/// A quieter capsule action.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.textPrimary
    var fill: Color = Palette.elevated

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A round icon button, for steppers and overflow menus.
struct RoundIconLabel: View {
    let symbol: String
    var size: CGFloat = 44
    var tint: Color = Palette.textPrimary
    var fill: Color = Palette.elevated

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .contentShape(Circle())
    }
}

// MARK: - Pill tabs

/// A horizontally scrolling set of capsule tabs with a sliding selection.
struct PillTabs<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    var tint: Color = Palette.accent
    let title: (Item) -> String
    let symbol: (Item) -> String
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    tab(item)
                }
            }
            .padding(4)
            .background(Palette.surface, in: Capsule())
        }
        .scrollClipDisabled()
    }

    private func tab(_ item: Item) -> some View {
        let selected = item == selection
        let ink: Color = selected ? Palette.onAccent : Palette.textSecondary
        return Button {
            if reduceMotion {
                selection = item
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = item }
            }
        } label: {
            Label(title(item), systemImage: symbol(item))
                .font(.subheadline.weight(.semibold))
                .labelStyle(PillLabelStyle(showsIcon: selected))
                .foregroundStyle(ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background {
                    if selected {
                        Capsule().fill(tint).matchedGeometryEffect(id: "pill", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PillLabelStyle: LabelStyle {
    let showsIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            if showsIcon { configuration.icon.font(.footnote.weight(.bold)) }
            configuration.title
        }
    }
}

// MARK: - Card header

/// Icon tile, title and an optional trailing view: the top row of every Gym and Kitchen card.
struct CardHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    var tint: Color = Palette.accent
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.s) {
            IconTile(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.xs)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, symbol: String, tint: Color = Palette.accent, subtitle: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

/// A large section title between groups of cards.
struct SectionTitle: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.top, Spacing.xs)
    }
}

// MARK: - Stat tile

/// One big number with a label: used in rows of three.
struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    var tint: Color = Palette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            IconTile(symbol: symbol, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.display(24))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ring

/// A thick progress ring with rounded ends.
struct RingGauge: View {
    let progress: Double
    var tint: Color = Palette.accent
    var lineWidth: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .onAppear { update() }
        .onChange(of: progress) { update() }
        .accessibilityHidden(true)
    }

    private func update() {
        let clamped = min(1, max(0, progress))
        if reduceMotion {
            shown = clamped
        } else {
            withAnimation(.spring(response: 1, dampingFraction: 0.85)) { shown = clamped }
        }
    }
}

// MARK: - Rows

/// A row inside a card: icon tile, title, subtitle and trailing content, at least 56 points tall.
struct TileRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    var tint: Color = Palette.accent
    var done = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.s) {
            IconTile(symbol: done ? "checkmark" : symbol, tint: done ? Palette.success : tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(done ? Palette.textTertiary : Palette.textPrimary)
                    .strikethrough(done, color: Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.xs)
            trailing
        }
        .frame(minHeight: 56)
    }
}

extension TileRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String, tint: Color = Palette.accent, done: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.done = done
        self.trailing = EmptyView()
    }
}

/// A hairline between rows inside a card, indented past the icon tile.
struct RowDivider: View {
    var inset: CGFloat = 52

    var body: some View {
        Rectangle()
            .fill(Palette.border.opacity(0.6))
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

/// Footnote text under a group of cards.
struct Footnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.xxs)
    }
}

/// Recipe artwork without photos: a deterministic two-tone gradient with the dish's symbol.
struct DishArtwork: View {
    let title: String
    let symbol: String
    var height: CGFloat = 110

    private static let hues: [Color] = [
        Color(hex: 0xFFB36B), Color(hex: 0xFF9AA8), Color(hex: 0x7FE0C3), Color(hex: 0x8CCBFF),
        Color(hex: 0xC5F277), Color(hex: 0xB8A5FF), Color(hex: 0xFFD66B),
    ]

    var body: some View {
        let seed = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let first = Self.hues[seed % Self.hues.count]
        let second = Self.hues[(seed / 7 + 3) % Self.hues.count]
        let gradient = LinearGradient(colors: [first.opacity(0.85), second.opacity(0.55)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            gradient
            Image(systemName: symbol)
                .font(.system(size: height * 0.42, weight: .semibold))
                .foregroundStyle(Palette.background.opacity(0.55))
                .rotationEffect(.degrees(-8))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
