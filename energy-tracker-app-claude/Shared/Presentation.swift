import Foundation
import SwiftUI
import EnergyCore

// MARK: - Theme (§9.3)

enum Theme {
    static let accent = Color("AccentColor")
    static let error = Color.red

    static func color(_ status: EnergyStatus) -> Color {
        switch status {
        case .withinRange: Color("StatusWithinRange")
        case .belowBaseline: Color("StatusBelowBaseline")
        case .trending: Color("StatusTrending")
        }
    }

    /// Badge label text on a 14–16 % tint of the Status color.
    static func labelColor(_ status: EnergyStatus) -> Color {
        switch status {
        case .withinRange: Color("StatusWithinRangeText")
        case .belowBaseline: Color("StatusBelowBaselineText")
        case .trending: Color("StatusTrendingText")
        }
    }

    /// Gap bands and "uncertain" marks: trending amber at low opacity, never red.
    static var uncertain: Color { Color("StatusTrending") }
    static let tintOpacity = 0.15
}

extension EnergyStatus {
    var label: String {
        switch self {
        case .withinRange: String(localized: "Within range")
        case .belowBaseline: String(localized: "Below baseline")
        case .trending: String(localized: "Trending")
        }
    }

    var symbol: String {
        switch self {
        case .withinRange: "checkmark.circle"
        case .belowBaseline: "arrow.down.circle"
        case .trending: "arrow.up.right.circle"
        }
    }
}

// MARK: - Number and date formats (§11, Exactness: display rounding)

enum Format {
    /// kWh with 1 decimal place, or 2 when the value has 2.
    static func kwh(_ value: Decimal, locale: Locale = .current) -> String {
        let places = DecimalMath.decimalPlaces(DecimalMath.rounded(value, scale: 2)) >= 2 ? 2 : 1
        return number(value, places: places, locale: locale)
    }

    /// kWh rounded to whole numbers, for sentences ("42 kWh under baseline pace").
    static func kwhWhole(_ value: Decimal, locale: Locale = .current) -> String {
        number(value, places: 0, locale: locale)
    }

    static func kwhWithUnit(_ value: Decimal) -> String {
        String(localized: "\(kwh(value)) kWh")
    }

    static func number(_ value: Decimal, places: Int, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = places
        f.maximumFractionDigits = places
        f.roundingMode = .halfUp
        return f.string(from: NSDecimalNumber(decimal: DecimalMath.rounded(value, scale: places))) ?? DecimalMath.string(value)
    }

    /// Money with 2 places in the given currency.
    static func money(_ value: Decimal, currency: String, places: Int = 2, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .currency
        f.currencyCode = currency
        f.minimumFractionDigits = places
        f.maximumFractionDigits = places
        f.roundingMode = .halfUp
        return f.string(from: NSDecimalNumber(decimal: DecimalMath.rounded(value, scale: places))) ?? "\(DecimalMath.string(value)) \(currency)"
    }

    /// Price per kWh with 4 places.
    static func pricePerKwh(_ value: Decimal, currency: String) -> String {
        money(value, currency: currency, places: 4)
    }

    static func currencySymbol(_ code: String, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .currency
        f.currencyCode = code
        return f.currencySymbol ?? code
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func date(_ date: CalendarDate) -> String {
        guard let start = date.startDate(in: .current) else { return date.iso }
        return start.formatted(date: .abbreviated, time: .omitted)
    }

    /// Short day and month, e.g. "3 Apr".
    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func wholeDays(_ days: Decimal) -> Int {
        NSDecimalNumber(decimal: DecimalMath.rounded(days, scale: 0)).intValue
    }

    static func daysFloor(_ days: Decimal) -> Int {
        var input = days, result = Decimal()
        NSDecimalRound(&result, &input, 0, .down)
        return NSDecimalNumber(decimal: result).intValue
    }

    /// Parses user input in the active locale ("12.345,6" in German, "12,345.6" in English). Exact, never via Double.
    static func parseDecimal(_ text: String, locale: Locale = .current) -> Decimal? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        s = s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: "\u{202F}", with: "")
        if decimalSeparator != "." {
            s = s.replacingOccurrences(of: groupingSeparator, with: "")
            s = s.replacingOccurrences(of: decimalSeparator, with: ".")
        } else {
            s = s.replacingOccurrences(of: groupingSeparator, with: "")
        }
        // Accept a comma as decimal separator in an English locale too when it cannot be a grouping separator.
        return DecimalMath.parse(s)
    }

    /// Text for editing a decimal in the active locale (no grouping).
    static func editable(_ value: Decimal, locale: Locale = .current) -> String {
        let text = DecimalMath.string(value)
        let separator = locale.decimalSeparator ?? "."
        return separator == "." ? text : text.replacingOccurrences(of: ".", with: separator)
    }
}

// MARK: - Status copy (§9.4)

enum StatusCopy {
    /// One plain sentence with the actual number.
    static func sentence(_ r: StatusResult) -> String {
        let amount = r.differenceKwh < 0 ? -r.differenceKwh : r.differenceKwh
        let n = Format.kwhWhole(amount)
        switch r.status {
        case .belowBaseline:
            return String(localized: "\(n) kWh under baseline pace so far")
        case .trending:
            return String(localized: "\(n) kWh above baseline pace so far")
        case .withinRange:
            if Format.wholeDays(amount) == 0 { return String(localized: "Right on baseline pace so far") }
            return String(localized: "\(n) kWh above baseline pace so far, inside your margin")
        }
    }

    /// Short sentence for widgets and Siri, e.g. "Within range — 42 kWh under baseline pace."
    static func spoken(_ r: StatusResult) -> String {
        let amount = r.differenceKwh < 0 ? -r.differenceKwh : r.differenceKwh
        let n = Format.kwhWhole(amount)
        let label = r.status.label
        if r.differenceKwh < 0 { return String(localized: "\(label) — \(n) kWh under baseline pace.") }
        if Format.wholeDays(amount) == 0 { return String(localized: "\(label) — right on baseline pace.") }
        return String(localized: "\(label) — \(n) kWh above baseline pace.")
    }

    static func lowConfidence(_ r: StatusResult) -> String {
        let days = Format.daysFloor(r.daysSinceLastReading)
        return String(localized: "Last reading \(days) days ago — status is less certain")
    }

    static func undefined(_ reason: UndefinedReason) -> String {
        switch reason {
        case .notEnoughReadings: String(localized: "Log your first reading to get started")
        case .awaitingDecision: String(localized: "Decide about the lower reading to see your status")
        case .noBaseline: String(localized: "Set your yearly target to see your status")
        }
    }

    static func daysSinceLastReading(_ days: Int) -> String {
        switch days {
        case 0: String(localized: "Last reading today")
        case 1: String(localized: "Last reading yesterday")
        default: String(localized: "Last reading \(days) days ago")
        }
    }
}

// MARK: - Status badge

struct StatusBadge: View {
    var status: EnergyStatus
    var font: Font = .headline

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(font)
            .foregroundStyle(Theme.labelColor(status))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.color(status).opacity(Theme.tintOpacity), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}
