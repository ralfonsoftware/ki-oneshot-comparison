import Foundation

/// Input rules shared by the app, the intents and the importer.
public enum Validation {
    public static let maxKwhExclusive: Decimal = Decimal(sign: .plus, exponent: 15, significand: 1)
    public static let maxBaseFeeExclusive: Decimal = Decimal(sign: .plus, exponent: 15, significand: 1)
    public static let maxPricePerKwhExclusive: Decimal = Decimal(sign: .plus, exponent: 13, significand: 1)

    public enum ReadingError: Error, Hashable, Sendable {
        case notPositive, tooLarge, tooManyDecimals
    }

    /// FR-4: > 0, < 10^15, at most 2 decimal places.
    public static func validateReading(_ value: Decimal) -> ReadingError? {
        if value <= 0 { return .notPositive }
        if value >= maxKwhExclusive { return .tooLarge }
        if DecimalMath.decimalPlaces(value) > 2 { return .tooManyDecimals }
        return nil
    }

    public enum TariffError: Error, Hashable, Sendable {
        case baseFeeOutOfRange, priceOutOfRange, currencyInvalid, periodOutOfRange, startDateOutOfRange
    }

    /// FR-12 rules.
    public static func validateTariff(monthlyBaseFee: Decimal, pricePerKwh: Decimal, currency: String, contractPeriodMonths: Int, startDate: CalendarDate) -> [TariffError] {
        var errors: [TariffError] = []
        if monthlyBaseFee < 0 || monthlyBaseFee >= maxBaseFeeExclusive { errors.append(.baseFeeOutOfRange) }
        if pricePerKwh <= 0 || pricePerKwh >= maxPricePerKwhExclusive { errors.append(.priceOutOfRange) }
        if !isCurrencyCode(currency) { errors.append(.currencyInvalid) }
        if !(1...1_200).contains(contractPeriodMonths) { errors.append(.periodOutOfRange) }
        if startDate < CalendarDate.earliestTariffStart || startDate > CalendarDate.latestTariffStart { errors.append(.startDateOutOfRange) }
        return errors
    }

    public static func isCurrencyCode(_ text: String) -> Bool {
        text.count == 3 && text.unicodeScalars.allSatisfy { $0.value >= 0x41 && $0.value <= 0x5A }
    }

    /// FR-18: 1–200 characters after trimming.
    public static func normalizedName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(trimmed.count) else { return nil }
        return trimmed
    }

    /// Event description: 1–500 characters after trimming.
    public static func normalizedEventDescription(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...500).contains(trimmed.count) else { return nil }
        return trimmed
    }

    public static let thresholdRange: ClosedRange<Decimal> = 0...Decimal(sign: .plus, exponent: 15, significand: 1)
    public static let gapDaysRange: ClosedRange<Int> = 1...365
    public static let cadenceRange: ClosedRange<Int> = 1...24
}
