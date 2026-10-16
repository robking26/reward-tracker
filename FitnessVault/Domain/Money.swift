import Foundation

/// A sterling amount held as integer pence.
///
/// Every ledger balance, reward and transfer in the app uses `Pence`.
/// Floating-point values never touch money.
struct Pence: Hashable, Comparable, Codable, Sendable, AdditiveArithmetic, ExpressibleByIntegerLiteral, CustomStringConvertible {
    var value: Int

    init(_ value: Int) { self.value = value }
    init(integerLiteral value: Int) { self.value = value }

    static let zero = Pence(0)
    static func pounds(_ pounds: Int) -> Pence { Pence(pounds * 100) }

    static func + (lhs: Pence, rhs: Pence) -> Pence { Pence(lhs.value + rhs.value) }
    static func - (lhs: Pence, rhs: Pence) -> Pence { Pence(lhs.value - rhs.value) }
    static func < (lhs: Pence, rhs: Pence) -> Bool { lhs.value < rhs.value }

    /// Clamps negative values to zero.
    var nonNegative: Pence { Pence(Swift.max(0, value)) }
    var isPositive: Bool { value > 0 }

    /// Exact decimal pounds, for display only.
    var decimalPounds: Decimal { Decimal(value) / 100 }

    var description: String { formatted() }

    func formatted() -> String {
        decimalPounds.formatted(Self.style)
    }

    /// "£500" rather than "£500.00", for round allowance figures.
    func formatted(wholePounds: Bool) -> String {
        guard wholePounds, value % 100 == 0 else { return formatted() }
        return decimalPounds.formatted(Self.style.precision(.fractionLength(0)))
    }

    private static let style = Decimal.FormatStyle.Currency(code: "GBP", locale: Locale(identifier: "en_GB"))

    /// Fraction of `total` covered by this amount, clamped to 0...1. Display only.
    func fraction(of total: Pence) -> Double {
        guard total.value > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, Double(value) / Double(total.value)))
    }
}

extension Sequence {
    func sum(_ amount: (Element) -> Pence) -> Pence {
        reduce(.zero) { $0 + amount($1) }
    }
}
