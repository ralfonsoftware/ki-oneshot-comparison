import Foundation

/// Lower-case UUID string, the canonical id order key (§5.1).
@inline(__always)
func idKey(_ id: UUID) -> String { id.uuidString.lowercased() }

/// `a` before `b` by lower-case UUID string byte order.
public func idAscending(_ a: UUID, _ b: UUID) -> Bool { idKey(a) < idKey(b) }

/// A Main Meter reading with its **effective** value.
public struct ReadingInput: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var value: Decimal

    public init(id: UUID = UUID(), timestamp: Date, value: Decimal) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}

public enum RegressionClassification: String, Sendable, Hashable, CaseIterable, Codable {
    case reset
    case rollover
}

public struct PromptInput: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var readingId: UUID
    public var previousReadingId: UUID
    public var createdAt: Date
    public var resolvedAt: Date?
    public var classification: RegressionClassification?
    public var digitCapacityKwh: Decimal?

    public init(
        id: UUID = UUID(),
        readingId: UUID,
        previousReadingId: UUID,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        resolvedAt: Date? = nil,
        classification: RegressionClassification? = nil,
        digitCapacityKwh: Decimal? = nil
    ) {
        self.id = id
        self.readingId = readingId
        self.previousReadingId = previousReadingId
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.classification = classification
        self.digitCapacityKwh = digitCapacityKwh
    }

    /// Resolved means a decision was taken. Anything else is open.
    public var isResolved: Bool { resolvedAt != nil && classification != nil }
}

public struct CorrectionInput: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var fieldName: String
    public var newValue: String
    public var correctedAt: Date

    public init(id: UUID, fieldName: String, newValue: String, correctedAt: Date) {
        self.id = id
        self.fieldName = fieldName
        self.newValue = newValue
        self.correctedAt = correctedAt
    }
}

public enum AuditField {
    public static let kwhValue = "KwhValue"
    public static let monthlyBaseFee = "MonthlyBaseFee"
    public static let pricePerKwh = "PricePerKwh"
    public static let currency = "Currency"
    public static let contractStartDate = "ContractStartDate"
    public static let contractPeriodMonths = "ContractPeriodMonths"
}

public enum AuditEntityType {
    public static let meterReading = "MeterReading"
    public static let tariff = "Tariff"
}

public enum Readings {
    /// Effective value: `newValue` of the newest `KwhValue` correction (newest `correctedAt`, ties by highest id),
    /// or the original value (§4.2).
    public static func effectiveValue(original: Decimal, corrections: [CorrectionInput]) -> Decimal {
        let newest = corrections
            .filter { $0.fieldName == AuditField.kwhValue }
            .max { a, b in
                if a.correctedAt != b.correctedAt { return a.correctedAt < b.correctedAt }
                return idAscending(a.id, b.id)
            }
        guard let newest, let value = DecimalMath.parse(newest.newValue) else { return original }
        return value
    }

    /// Orders readings by timestamp, then id (§5.1).
    public static func ordered(_ readings: [ReadingInput]) -> [ReadingInput] {
        readings.sorted { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return idAscending(a.id, b.id)
        }
    }

    /// The open prompt that excludes readings: the one whose reading is ordered earliest (FR-11).
    public static func activeOpenPrompt(readings ordered: [ReadingInput], prompts: [PromptInput]) -> PromptInput? {
        let open = prompts.filter { !$0.isResolved }
        guard !open.isEmpty else { return nil }
        let position = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        return open
            .filter { position[$0.readingId] != nil }
            .min { (position[$0.readingId] ?? .max) < (position[$1.readingId] ?? .max) }
    }

    /// Drops the active open prompt's reading and everything ordered at or after it (§5.2 step 2).
    public static func applyingOpenPromptExclusion(_ ordered: [ReadingInput], prompts: [PromptInput]) -> [ReadingInput] {
        guard let open = activeOpenPrompt(readings: ordered, prompts: prompts),
              let cut = ordered.firstIndex(where: { $0.id == open.readingId }) else { return ordered }
        return Array(ordered[..<cut])
    }
}
