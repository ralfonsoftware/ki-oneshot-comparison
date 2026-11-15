import Foundation

enum DecimalText {
    static let posix = Locale(identifier: "en_US_POSIX")

    static func encode(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func decode(_ value: String?) -> Decimal? {
        guard let value else { return nil }
        return Decimal(string: value, locale: posix)
    }

    static func decimalPlaces(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        return pieces.count == 2 ? pieces[1].count : 0
    }
}

enum CalendarDay {
    static let posix = Locale(identifier: "en_US_POSIX")

    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    static func date(from string: String, calendar: Calendar = .current) -> Date? {
        let pieces = string.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3, string.count == 10 else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = pieces[0]; components.month = pieces[1]; components.day = pieces[2]
        components.hour = 12
        guard let result = components.date, self.string(from: result, calendar: calendar) == string else { return nil }
        return result
    }

    static func adding(months: Int, to day: String, calendar: Calendar = .current) -> String? {
        guard let date = date(from: day, calendar: calendar),
              let result = calendar.date(byAdding: .month, value: months, to: date) else { return nil }
        return string(from: result, calendar: calendar)
    }
}

enum InputValidation {
    static func reading(_ text: String) -> Decimal? {
        decimal(text, maximumFractionDigits: 2).flatMap { $0 > 0 && $0 < Decimal(sign: .plus, exponent: 15, significand: 1) ? $0 : nil }
    }

    static func nonNegative(_ text: String, maximumFractionDigits: Int = 2) -> Decimal? {
        decimal(text, maximumFractionDigits: maximumFractionDigits).flatMap { $0 >= 0 ? $0 : nil }
    }

    static func tariffBaseFee(_ text: String) -> Decimal? {
        guard let value = nonNegative(text), value < Decimal(sign: .plus, exponent: 15, significand: 1) else { return nil }
        return value
    }

    static func tariffPrice(_ text: String) -> Decimal? {
        guard let value = decimal(text, maximumFractionDigits: 4), value > 0,
              value < Decimal(sign: .plus, exponent: 13, significand: 1) else { return nil }
        return value
    }

    static func decimal(_ text: String, maximumFractionDigits: Int) -> Decimal? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = Locale.current.decimalSeparator ?? "."
        let grouping = Locale.current.groupingSeparator ?? ","
        if separator != "." {
            if trimmed.contains(separator) {
                if grouping != separator { trimmed = trimmed.replacingOccurrences(of: grouping, with: "") }
                trimmed = trimmed.replacingOccurrences(of: separator, with: ".")
            } else if grouping != "." {
                trimmed = trimmed.replacingOccurrences(of: grouping, with: "")
            }
        } else if grouping != "." {
            trimmed = trimmed.replacingOccurrences(of: grouping, with: "")
        }
        guard let places = DecimalText.decimalPlaces(trimmed), places <= maximumFractionDigits,
              let value = DecimalText.decode(trimmed), value.isFinite else { return nil }
        return value
    }

    static func currency(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 3, value.allSatisfy({ $0.isASCII && $0.isUppercase && $0.isLetter }) else { return nil }
        return value
    }

    static func name(_ text: String, maximum: Int = 200) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...maximum).contains(value.count) ? value : nil
    }
}

extension Decimal {
    var isFinite: Bool { !isNaN && !isInfinite }
}

enum EnergyFormat {
    static func kwh(_ value: Decimal, maximumFractionDigits: Int? = nil) -> String {
        let encoded = DecimalText.encode(value)
        let existingPlaces = DecimalText.decimalPlaces(encoded) ?? 0
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits ?? (existingPlaces >= 2 ? 2 : 1)
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? encoded
    }

    static func money(_ value: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(DecimalText.encode(value)) \(currency)"
    }

    static func price(_ value: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 4
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(DecimalText.encode(value)) \(currency)"
    }

    static func decimalInput(_ value: Decimal?) -> String {
        value.map(DecimalText.encode) ?? ""
    }

    static func absolute(_ value: Decimal) -> Decimal { value < 0 ? -value : value }
}
