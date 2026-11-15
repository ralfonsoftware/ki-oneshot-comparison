import Foundation

/// A calendar date without a time or time zone.
public struct CalendarDate: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        precondition(CalendarDate.isValid(year: year, month: month, day: day), "Invalid Gregorian calendar date")
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year!, month: components.month!, day: components.day!)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Adds calendar months using Gregorian month-end clamping.
    public func adding(months: Int) -> CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let zeroBasedMonth = year * 12 + (month - 1) + months
        let targetYear = zeroBasedMonth >= 0 ? zeroBasedMonth / 12 : (zeroBasedMonth - 11) / 12
        let targetMonth = zeroBasedMonth - targetYear * 12 + 1
        let firstOfMonth = calendar.date(from: DateComponents(year: targetYear, month: targetMonth, day: 1))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)!.count
        return CalendarDate(year: targetYear, month: targetMonth, day: min(day, daysInMonth))
    }

    public var utcMidnight: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    internal static func isValid(year: Int, month: Int, day: Int) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return false
        }
        let result = calendar.dateComponents([.year, .month, .day], from: date)
        return result.year == year && result.month == month && result.day == day
    }
}

/// Settings used by pace, status, and event-deviation calculations.
public struct StatusSettings: Equatable, Sendable {
    public var yearlyBaselineKwh: Decimal?
    public var trendingThresholdKwh: Decimal
    public var lowConfidenceGapDays: Int

    public init(
        yearlyBaselineKwh: Decimal?,
        trendingThresholdKwh: Decimal = 100,
        lowConfidenceGapDays: Int = 45
    ) {
        self.yearlyBaselineKwh = yearlyBaselineKwh
        self.trendingThresholdKwh = trendingThresholdKwh
        self.lowConfidenceGapDays = lowConfidenceGapDays
    }
}

/// A stored reading. `kwhValue` is the original value, not its corrected effective value.
public struct MeterReading: Equatable, Sendable {
    public var id: UUID
    public var mainMeterID: UUID
    public var kwhValue: Decimal
    public var readingTimestamp: Date
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        mainMeterID: UUID,
        kwhValue: Decimal,
        readingTimestamp: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.mainMeterID = mainMeterID
        self.kwhValue = kwhValue
        self.readingTimestamp = readingTimestamp
        self.createdAt = createdAt
    }
}

public enum RegressionClassification: String, Codable, Sendable {
    case reset
    case rollover

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let classification = RegressionClassification(rawValue: value.lowercased()) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown regression classification")
        }
        self = classification
    }
}

/// A regression decision associated with the lower reading.
public struct MeterRegressionPrompt: Equatable, Sendable {
    public var id: UUID
    public var mainMeterID: UUID
    public var meterReadingID: UUID
    public var previousMeterReadingID: UUID
    public var createdAt: Date
    public var resolvedAt: Date?
    public var classification: RegressionClassification?
    public var digitCapacityKwh: Decimal?

    public init(
        id: UUID = UUID(),
        mainMeterID: UUID,
        meterReadingID: UUID,
        previousMeterReadingID: UUID,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil,
        classification: RegressionClassification? = nil,
        digitCapacityKwh: Decimal? = nil
    ) {
        self.id = id
        self.mainMeterID = mainMeterID
        self.meterReadingID = meterReadingID
        self.previousMeterReadingID = previousMeterReadingID
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.classification = classification
        self.digitCapacityKwh = digitCapacityKwh
    }
}

public enum AuditEntityType: String, Codable, Sendable {
    case meterReading = "MeterReading"
    case tariff = "Tariff"
}

/// An append-only correction. Reading corrections use field name `KwhValue`.
public struct AuditCorrection: Equatable, Sendable {
    public var id: UUID
    public var entityType: AuditEntityType
    public var entityID: UUID
    public var fieldName: String
    public var oldValue: String
    public var newValue: String
    public var correctedAt: Date

    public init(
        id: UUID = UUID(),
        entityType: AuditEntityType,
        entityID: UUID,
        fieldName: String,
        oldValue: String,
        newValue: String,
        correctedAt: Date
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.fieldName = fieldName
        self.oldValue = oldValue
        self.newValue = newValue
        self.correctedAt = correctedAt
    }
}

/// A reading after applying its newest effective-value correction.
public struct EffectiveReading: Equatable, Sendable {
    public var id: UUID
    public var mainMeterID: UUID
    public var kwhValue: Decimal
    public var readingTimestamp: Date

    public init(id: UUID, mainMeterID: UUID, kwhValue: Decimal, readingTimestamp: Date) {
        self.id = id
        self.mainMeterID = mainMeterID
        self.kwhValue = kwhValue
        self.readingTimestamp = readingTimestamp
    }
}

/// Defined pace over an exact, possibly fractional, elapsed period.
public struct Pace: Equatable, Sendable {
    public var paceToDateKwh: Decimal
    public var elapsedDays: Decimal
    public var latestReadingTimestamp: Date?
    public var isLowConfidence: Bool

    public init(
        paceToDateKwh: Decimal,
        elapsedDays: Decimal,
        latestReadingTimestamp: Date? = nil,
        isLowConfidence: Bool = false
    ) {
        self.paceToDateKwh = paceToDateKwh
        self.elapsedDays = elapsedDays
        self.latestReadingTimestamp = latestReadingTimestamp
        self.isLowConfidence = isLowConfidence
    }

    public var elapsedSeconds: Decimal { elapsedDays * 86_400 }
}

public enum ConsumptionStatus: String, Codable, Sendable {
    case withinRange = "withinrange"
    case belowBaseline = "belowbaseline"
    case trending

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let status = ConsumptionStatus(rawValue: value.lowercased()) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown consumption status")
        }
        self = status
    }
}

/// A status is undefined when `status` is nil; the other fields explain why when available.
public struct StatusEvaluation: Equatable, Sendable {
    public var status: ConsumptionStatus?
    public var pace: Pace?
    public var baselineToDateKwh: Decimal?
    public var thresholdToDateKwh: Decimal?
    public var differenceKwh: Decimal?

    public init(
        status: ConsumptionStatus?,
        pace: Pace?,
        baselineToDateKwh: Decimal? = nil,
        thresholdToDateKwh: Decimal? = nil,
        differenceKwh: Decimal? = nil
    ) {
        self.status = status
        self.pace = pace
        self.baselineToDateKwh = baselineToDateKwh
        self.thresholdToDateKwh = thresholdToDateKwh
        self.differenceKwh = differenceKwh
    }
}

/// A flat-rate tariff in the stored tariff history.
public struct Tariff: Equatable, Sendable {
    public var id: UUID
    public var monthlyBaseFee: Decimal
    public var pricePerKwh: Decimal
    public var currency: String
    public var contractStartDate: CalendarDate
    public var contractPeriodMonths: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        monthlyBaseFee: Decimal,
        pricePerKwh: Decimal,
        currency: String,
        contractStartDate: CalendarDate,
        contractPeriodMonths: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.monthlyBaseFee = monthlyBaseFee
        self.pricePerKwh = pricePerKwh
        self.currency = currency
        self.contractStartDate = contractStartDate
        self.contractPeriodMonths = contractPeriodMonths
        self.createdAt = createdAt
    }
}

/// Scratch tariff input. It has no identity or contract-history fields.
public struct CandidateTariff: Equatable, Sendable {
    public var monthlyBaseFee: Decimal
    public var pricePerKwh: Decimal
    public var switchingBonus: Decimal

    public init(monthlyBaseFee: Decimal, pricePerKwh: Decimal, switchingBonus: Decimal = 0) {
        self.monthlyBaseFee = monthlyBaseFee
        self.pricePerKwh = pricePerKwh
        self.switchingBonus = switchingBonus
    }
}

/// Exact tariff results plus the two independently rounded display decisions.
public struct TariffComparison: Equatable, Sendable {
    public var annualPaceKwh: Decimal
    public var currentAnnualCost: Decimal
    public var candidateCostNoBonus: Decimal
    public var candidateNormalizedCost: Decimal
    public var normalizedSavings: Decimal
    public var candidateIncludedCost: Decimal
    public var includedSavings: Decimal
    public var roundedNormalizedSavings: Decimal
    public var roundedIncludedSavings: Decimal
    public var isNormalizedWorthSwitching: Bool
    public var isIncludedWorthSwitching: Bool
    public var isLowConfidence: Bool

    public init(
        annualPaceKwh: Decimal,
        currentAnnualCost: Decimal,
        candidateCostNoBonus: Decimal,
        candidateNormalizedCost: Decimal,
        normalizedSavings: Decimal,
        candidateIncludedCost: Decimal,
        includedSavings: Decimal,
        roundedNormalizedSavings: Decimal,
        roundedIncludedSavings: Decimal,
        isNormalizedWorthSwitching: Bool,
        isIncludedWorthSwitching: Bool,
        isLowConfidence: Bool
    ) {
        self.annualPaceKwh = annualPaceKwh
        self.currentAnnualCost = currentAnnualCost
        self.candidateCostNoBonus = candidateCostNoBonus
        self.candidateNormalizedCost = candidateNormalizedCost
        self.normalizedSavings = normalizedSavings
        self.candidateIncludedCost = candidateIncludedCost
        self.includedSavings = includedSavings
        self.roundedNormalizedSavings = roundedNormalizedSavings
        self.roundedIncludedSavings = roundedIncludedSavings
        self.isNormalizedWorthSwitching = isNormalizedWorthSwitching
        self.isIncludedWorthSwitching = isIncludedWorthSwitching
        self.isLowConfidence = isLowConfidence
    }
}

public enum ObservedDeviation: String, Codable, Sendable {
    case bump = "Bump"
    case dip = "Dip"
    case none = "None"
}

/// A minimal event DTO for deterministic observed-deviation calculation.
public struct EnergyEvent: Equatable, Sendable {
    public var id: UUID
    public var description: String
    public var occurredAt: Date
    public var createdAt: Date

    public init(id: UUID = UUID(), description: String, occurredAt: Date, createdAt: Date = Date()) {
        self.id = id
        self.description = description
        self.occurredAt = occurredAt
        self.createdAt = createdAt
    }
}

public struct TariffCheck: Equatable, Sendable {
    public var minimumTermEnd: CalendarDate
    public var gateOpens: CalendarDate
    public var isDue: Bool
    /// The next known date only when the check is not currently due.
    public var nextDueDate: CalendarDate?

    public init(minimumTermEnd: CalendarDate, gateOpens: CalendarDate, isDue: Bool, nextDueDate: CalendarDate?) {
        self.minimumTermEnd = minimumTermEnd
        self.gateOpens = gateOpens
        self.isDue = isDue
        self.nextDueDate = nextDueDate
    }
}
