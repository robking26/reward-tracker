import SwiftUI

/// Colour tokens. The app is predominantly charcoal; accent green is reserved for money earned and progress.
enum Palette {
    static let background = Color(hex: 0x17191B)
    static let surface = Color(hex: 0x222527)
    static let elevated = Color(hex: 0x2C3032)
    static let border = Color(hex: 0x393E40)
    static let textPrimary = Color(hex: 0xF7F8F7)
    static let textSecondary = Color(hex: 0xADB3B1)
    static let textTertiary = Color(hex: 0x7F8884)
    static let accent = Color(hex: 0xC5F277)
    static let success = Color(hex: 0x8DD7AB)
    static let warning = Color(hex: 0xE9BA73)
    static let error = Color(hex: 0xEF8E8E)
    /// Dark text for use on the accent colour.
    static let onAccent = Color(hex: 0x17191B)
}

/// 8pt spacing system.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 40
    /// Horizontal page margin.
    static let page: CGFloat = 20
}

enum Radius {
    static let card: CGFloat = 20
    static let hero: CGFloat = 24
    static let control: CGFloat = 14
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension PaymentStatus {
    var tint: Color {
        switch self {
        case .paid: Palette.success
        case .awaitingApproval, .awaitingInitiation, .processing: Palette.warning
        case .rejected, .failed: Palette.error
        case .reconciliationRequired: Palette.warning
        }
    }
}
