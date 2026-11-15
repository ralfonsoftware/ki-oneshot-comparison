import Foundation

/// Exact decimal helpers. Stored values and money never use binary floating point (§11, Exactness).
public enum DecimalMath {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Parses an invariant-culture decimal string ("12345.6", "-1e3"). Returns nil for anything else.
    public static func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, isNumberLexeme(trimmed) else { return nil }
        return Decimal(string: trimmed, locale: posix)
    }

    /// Canonical invariant-culture string, e.g. "12345.6". Round-trips through `parse`.
    public static func string(_ value: Decimal) -> String {
        var v = value
        // Normalise "-0" and trailing zeros via NSDecimalNumber's canonical form.
        if v.isZero { v = 0 }
        return NSDecimalNumber(decimal: v).description(withLocale: posix)
    }

    /// Rounds half away from zero to `scale` decimal places.
    public static func rounded(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    /// Number of decimal places actually used by `value` (e.g. 12.50 -> 1, 12.25 -> 2).
    public static func decimalPlaces(_ value: Decimal) -> Int {
        let normalized = string(value)
        guard let dot = normalized.firstIndex(of: ".") else { return 0 }
        let fraction = normalized[normalized.index(after: dot)...]
        if fraction.contains("E") || fraction.contains("e") { return 0 }
        return fraction.count
    }

    public static func max(_ a: Decimal, _ b: Decimal) -> Decimal { a >= b ? a : b }
    public static func min(_ a: Decimal, _ b: Decimal) -> Decimal { a <= b ? a : b }

    /// Exact elapsed seconds between two instants, at millisecond resolution.
    public static func seconds(from start: Date, to end: Date) -> Decimal {
        let millis = (end.timeIntervalSince(start) * 1000).rounded()
        return Decimal(Int64(millis)) / 1000
    }

    public static let secondsPerDay: Decimal = 86_400
    public static let daysPerYear: Decimal = 365

    /// JSON number grammar (RFC 8259).
    public static func isNumberLexeme(_ text: String) -> Bool {
        var chars = Array(text.utf8)[...]
        func take(_ c: UInt8) -> Bool {
            if chars.first == c { chars = chars.dropFirst(); return true }
            return false
        }
        func digits() -> Int {
            var n = 0
            while let c = chars.first, c >= 0x30, c <= 0x39 { chars = chars.dropFirst(); n += 1 }
            return n
        }
        _ = take(0x2D) // -
        if chars.first == 0x30 { chars = chars.dropFirst() } else if digits() == 0 { return false }
        if take(0x2E) { if digits() == 0 { return false } }
        if take(0x65) || take(0x45) {
            if !take(0x2B) { _ = take(0x2D) }
            if digits() == 0 { return false }
        }
        return chars.isEmpty
    }
}

extension Decimal {
    /// Convenience for literals in code and tests: `Decimal(invariant: "0.2800")`.
    public init?(invariant text: String) {
        guard let d = DecimalMath.parse(text) else { return nil }
        self = d
    }
}
