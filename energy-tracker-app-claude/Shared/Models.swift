import Foundation
import SwiftData
import EnergyCore

// SwiftData models mirrored to the CloudKit private database (§7.2):
// - no unique constraints,
// - every attribute optional or with a default,
// - no relationships at all: records refer to each other by UUID, so there are no inverse or delete rules to get wrong,
// - exact decimals are stored as invariant-culture strings, which round-trip through CloudKit without loss (§11, Exactness),
// - calendar-only dates are stored as "YYYY-MM-DD" strings (§11, Time).
// Schema changes after the first production deployment are additive only.

@Model
final class Household {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID?
    var generationStartedAt: Date?
    var locale: String = "en-US"
    var currency: String = "EUR"
    var yearlyBaselineKwhText: String?
    var trendingThresholdKwhText: String = "100"
    var lowConfidenceGapDays: Int = 45
    var tariffCheckCadenceMonths: Int = 3
    var tariffCheckDoneAt: Date?
    /// JSON object: settings field name -> ISO 8601 instant of its last change. Drives the per-field merge (§7.4).
    var fieldStampsJSON: String = "{}"

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.generation = generation
        self.generationStartedAt = createdAt
    }

    var yearlyBaselineKwh: Decimal? {
        get { yearlyBaselineKwhText.flatMap(DecimalMath.parse) }
        set { yearlyBaselineKwhText = newValue.map(DecimalMath.string) }
    }

    var trendingThresholdKwh: Decimal {
        get { DecimalMath.parse(trendingThresholdKwhText) ?? 100 }
        set { trendingThresholdKwhText = DecimalMath.string(newValue) }
    }

    var fieldStamps: [String: Date] {
        get {
            guard let data = fieldStampsJSON.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
            return raw.compactMapValues(Instant.parse)
        }
        set {
            let raw = newValue.mapValues { Instant.format($0) }
            if let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]) {
                fieldStampsJSON = String(decoding: data, as: UTF8.self)
            }
        }
    }

    func stamp(_ field: HouseholdField, at date: Date = Date()) {
        var stamps = fieldStamps
        stamps[field.rawValue] = date
        fieldStamps = stamps
    }
}

/// Household settings fields that merge individually (§7.4).
enum HouseholdField: String, CaseIterable {
    case locale, currency, yearlyBaselineKwh, trendingThresholdKwh, lowConfidenceGapDays, tariffCheckCadenceMonths, tariffCheckDoneAt
}

@Model
final class MainMeter {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID?
    var digitCapacityKwhText: String?

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID?) {
        self.id = id
        self.createdAt = createdAt
        self.generation = generation
    }

    var digitCapacityKwh: Decimal? {
        get { digitCapacityKwhText.flatMap(DecimalMath.parse) }
        set { digitCapacityKwhText = newValue.map(DecimalMath.string) }
    }
}

/// Append-only. `kwhValueText` is the original value and never changes.
@Model
final class MeterReading {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID?
    var mainMeterId: UUID?
    var kwhValueText: String = "0"
    var readingTimestamp: Date = Date()

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID?, mainMeterId: UUID?, kwhValue: Decimal, readingTimestamp: Date) {
        self.id = id
        self.createdAt = createdAt
        self.generation = generation
        self.mainMeterId = mainMeterId
        self.kwhValueText = DecimalMath.string(kwhValue)
        self.readingTimestamp = readingTimestamp
    }

    var originalKwhValue: Decimal { DecimalMath.parse(kwhValueText) ?? 0 }
}

@Model
final class MeterRegressionPrompt {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID?
    var mainMeterId: UUID?
    var meterReadingId: UUID?
    var previousMeterReadingId: UUID?
    var resolvedAt: Date?
    var classificationRaw: String?
    var digitCapacityKwhText: String?

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID?, mainMeterId: UUID?, meterReadingId: UUID, previousMeterReadingId: UUID) {
        self.id = id
        self.createdAt = createdAt
        self.generation = generation
        self.mainMeterId = mainMeterId
        self.meterReadingId = meterReadingId
        self.previousMeterReadingId = previousMeterReadingId
    }

    var classification: RegressionClassification? {
        get { classificationRaw.flatMap(RegressionClassification.init(rawValue:)) }
        set { classificationRaw = newValue?.rawValue }
    }

    var digitCapacityKwh: Decimal? {
        get { digitCapacityKwhText.flatMap(DecimalMath.parse) }
        set { digitCapacityKwhText = newValue.map(DecimalMath.string) }
    }

    var isResolved: Bool { resolvedAt != nil && classification != nil }
}

@Model
final class Tariff {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var generation: UUID?
    var monthlyBaseFeeText: String = "0"
    var pricePerKwhText: String = "0"
    var currency: String = "EUR"
    var contractStartDay: String = "2000-01-01"
    var contractPeriodMonths: Int = 12

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID?, monthlyBaseFee: Decimal, pricePerKwh: Decimal, currency: String, contractStartDate: CalendarDate, contractPeriodMonths: Int) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.generation = generation
        self.monthlyBaseFeeText = DecimalMath.string(monthlyBaseFee)
        self.pricePerKwhText = DecimalMath.string(pricePerKwh)
        self.currency = currency
        self.contractStartDay = contractStartDate.iso
        self.contractPeriodMonths = contractPeriodMonths
    }

    var monthlyBaseFee: Decimal {
        get { DecimalMath.parse(monthlyBaseFeeText) ?? 0 }
        set { monthlyBaseFeeText = DecimalMath.string(newValue) }
    }

    var pricePerKwh: Decimal {
        get { DecimalMath.parse(pricePerKwhText) ?? 0 }
        set { pricePerKwhText = DecimalMath.string(newValue) }
    }

    var contractStartDate: CalendarDate {
        get { CalendarDate(iso: contractStartDay) ?? CalendarDate(year: 2000, month: 1, day: 1) }
        set { contractStartDay = newValue.iso }
    }
}

@Model
final class EnergyEvent {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var generation: UUID?
    /// The Event description (1–500 characters).
    var text: String = ""
    var occurredAt: Date = Date()
    var taggedEntityTypeRaw: String?
    var taggedEntityId: UUID?
    var taggedEntityName: String?

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID?, text: String, occurredAt: Date) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.generation = generation
        self.text = text
        self.occurredAt = occurredAt
    }

    var taggedEntityType: TaggedEntityType? {
        get { taggedEntityTypeRaw.flatMap(TaggedEntityType.init(rawValue:)) }
        set { taggedEntityTypeRaw = newValue?.rawValue }
    }
}

@Model
final class Room {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var generation: UUID?
    var name: String = ""
    var archivedAt: Date?

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID?, name: String) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.generation = generation
        self.name = name
    }
}

@Model
final class PowerPoint {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var generation: UUID?
    var roomId: UUID?
    var name: String = ""
    var archivedAt: Date?

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID?, roomId: UUID?, name: String) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.generation = generation
        self.roomId = roomId
        self.name = name
    }
}

@Model
final class Device {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var generation: UUID?
    var powerPointId: UUID?
    var name: String = ""
    var archivedAt: Date?

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID?, powerPointId: UUID?, name: String) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.generation = generation
        self.powerPointId = powerPointId
        self.name = name
    }
}

/// Append-only.
@Model
final class StatusSnapshot {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID?
    var statusRaw: String = EnergyStatus.withinRange.rawValue
    var paceToDateKwhText: String = "0"
    var baselineToDateKwhText: String = "0"
    var isLowConfidence: Bool = false
    var computedAt: Date = Date()
    var causeId: UUID?

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID?, status: EnergyStatus, paceToDateKwh: Decimal, baselineToDateKwh: Decimal, isLowConfidence: Bool, computedAt: Date, causeId: UUID) {
        self.id = id
        self.createdAt = createdAt
        self.generation = generation
        self.statusRaw = status.rawValue
        self.paceToDateKwhText = DecimalMath.string(paceToDateKwh)
        self.baselineToDateKwhText = DecimalMath.string(baselineToDateKwh)
        self.isLowConfidence = isLowConfidence
        self.computedAt = computedAt
        self.causeId = causeId
    }

    var status: EnergyStatus { EnergyStatus(fileValue: statusRaw) ?? .withinRange }
    var paceToDateKwh: Decimal { DecimalMath.parse(paceToDateKwhText) ?? 0 }
    var baselineToDateKwh: Decimal { DecimalMath.parse(baselineToDateKwhText) ?? 0 }
}

/// Append-only.
@Model
final class AuditCorrection {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID?
    var entityType: String = AuditEntityType.meterReading
    var entityId: UUID?
    var fieldName: String = AuditField.kwhValue
    var oldValue: String = ""
    var newValue: String = ""
    var correctedAt: Date = Date()

    init(id: UUID = UUID(), generation: UUID?, entityType: String, entityId: UUID, fieldName: String, oldValue: String, newValue: String, correctedAt: Date) {
        self.id = id
        self.createdAt = correctedAt
        self.generation = generation
        self.entityType = entityType
        self.entityId = entityId
        self.fieldName = fieldName
        self.oldValue = oldValue
        self.newValue = newValue
        self.correctedAt = correctedAt
    }
}

/// Written by import only; stored, exported again, never shown (D8).
@Model
final class SmartPlugReading {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID?
    var powerPointId: UUID?
    var roomName: String = ""
    var powerPointName: String = ""
    var deviceName: String = ""
    var intervalStart: Date = Date()
    var intervalEnd: Date = Date()
    var kwhValueText: String = "0"

    init(id: UUID, generation: UUID?, powerPointId: UUID?, roomName: String, powerPointName: String, deviceName: String, intervalStart: Date, intervalEnd: Date, kwhValue: Decimal) {
        self.id = id
        self.generation = generation
        self.powerPointId = powerPointId
        self.roomName = roomName
        self.powerPointName = powerPointName
        self.deviceName = deviceName
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
        self.kwhValueText = DecimalMath.string(kwhValue)
    }

    var kwhValue: Decimal { DecimalMath.parse(kwhValueText) ?? 0 }
}

// MARK: - Schema versioning (§11, Schema evolution)

enum EnergySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Household.self, MainMeter.self, MeterReading.self, MeterRegressionPrompt.self, Tariff.self, EnergyEvent.self,
         Room.self, PowerPoint.self, Device.self, StatusSnapshot.self, AuditCorrection.self, SmartPlugReading.self]
    }
}

/// Explicit migration plan from the first release on. Later versions add a `VersionedSchema` and a lightweight
/// (additive) stage here; CloudKit allows additive changes only (§7.2).
enum EnergyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [EnergySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
