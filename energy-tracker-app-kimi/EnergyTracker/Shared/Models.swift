import Foundation
import SwiftData

// References deliberately use UUIDs instead of SwiftData relationships. Every
// stored attribute is optional or has a default, as required for CloudKit.

@Model
final class Household {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID = UUID()
    var locale: String = "en-US"
    var currency: String = "EUR"
    var yearlyBaselineKwh: String?
    var trendingThresholdKwh: String = "100"
    var lowConfidenceGapDays: Int = 45
    var tariffCheckCadenceMonths: Int = 3
    var tariffCheckDoneAt: Date?
    var generationChangedAt: Date = Date.distantPast
    var updatedAt: Date = Date()
    var yearlyBaselineUpdatedAt: Date?
    var thresholdUpdatedAt: Date?
    var gapUpdatedAt: Date?
    var currencyUpdatedAt: Date?
    var cadenceUpdatedAt: Date?
    var tariffDoneUpdatedAt: Date?

    init(
        id: UUID = UUID(), createdAt: Date = Date(), generation: UUID = UUID(),
        locale: String = "en-US", currency: String = "EUR", yearlyBaselineKwh: Decimal? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.generation = generation
        self.locale = locale
        self.currency = currency
        self.yearlyBaselineKwh = yearlyBaselineKwh.map(DecimalText.encode)
        let now = Date()
        self.updatedAt = now
        self.yearlyBaselineUpdatedAt = now
        self.thresholdUpdatedAt = now
        self.gapUpdatedAt = now
        self.currencyUpdatedAt = now
        self.cadenceUpdatedAt = now
    }
}

@Model
final class MainMeter {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID = UUID()
    var digitCapacityKwh: String?
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID, digitCapacityKwh: Decimal? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.generation = generation
        self.digitCapacityKwh = digitCapacityKwh.map(DecimalText.encode)
    }
}

@Model
final class MeterReading {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID = UUID()
    var mainMeterId: UUID = UUID()
    var kwhValue: String = "0"
    var readingTimestamp: Date = Date()

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID, mainMeterId: UUID, kwhValue: Decimal, readingTimestamp: Date) {
        self.id = id
        self.createdAt = createdAt
        self.generation = generation
        self.mainMeterId = mainMeterId
        self.kwhValue = DecimalText.encode(kwhValue)
        self.readingTimestamp = readingTimestamp
    }
}

@Model
final class MeterRegressionPrompt {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID = UUID()
    var mainMeterId: UUID = UUID()
    var meterReadingId: UUID = UUID()
    var previousMeterReadingId: UUID = UUID()
    var resolvedAt: Date?
    var classification: String?
    var digitCapacityKwh: String?
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID, mainMeterId: UUID, meterReadingId: UUID, previousMeterReadingId: UUID) {
        self.id = id
        self.createdAt = createdAt
        self.generation = generation
        self.mainMeterId = mainMeterId
        self.meterReadingId = meterReadingId
        self.previousMeterReadingId = previousMeterReadingId
    }
}

@Model
final class Tariff {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID = UUID()
    var monthlyBaseFee: String = "0"
    var pricePerKwh: String = "0.0001"
    var currency: String = "EUR"
    var contractStartDate: String = "2000-01-01"
    var contractPeriodMonths: Int = 12
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID, monthlyBaseFee: Decimal, pricePerKwh: Decimal, currency: String, contractStartDate: String, contractPeriodMonths: Int) {
        self.id = id
        self.createdAt = createdAt
        self.generation = generation
        self.monthlyBaseFee = DecimalText.encode(monthlyBaseFee)
        self.pricePerKwh = DecimalText.encode(pricePerKwh)
        self.currency = currency
        self.contractStartDate = contractStartDate
        self.contractPeriodMonths = contractPeriodMonths
    }
}

@Model
final class EnergyEvent {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID = UUID()
    var eventDescription: String = ""
    var occurredAt: Date = Date()
    var taggedEntityType: String?
    var taggedEntityId: UUID?
    var taggedEntityName: String?
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID, description: String, occurredAt: Date, taggedEntityType: String? = nil, taggedEntityId: UUID? = nil, taggedEntityName: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.generation = generation
        self.eventDescription = description
        self.occurredAt = occurredAt
        self.taggedEntityType = taggedEntityType
        self.taggedEntityId = taggedEntityId
        self.taggedEntityName = taggedEntityName
    }
}

@Model
final class Room {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID = UUID()
    var name: String = ""
    var archivedAt: Date?
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID, name: String, archivedAt: Date? = nil) {
        self.id = id; self.createdAt = createdAt; self.generation = generation; self.name = name; self.archivedAt = archivedAt
    }
}

@Model
final class PowerPoint {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID = UUID()
    var roomId: UUID = UUID()
    var name: String = ""
    var archivedAt: Date?
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID, roomId: UUID, name: String, archivedAt: Date? = nil) {
        self.id = id; self.createdAt = createdAt; self.generation = generation; self.roomId = roomId; self.name = name; self.archivedAt = archivedAt
    }
}

@Model
final class Device {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID = UUID()
    var powerPointId: UUID = UUID()
    var name: String = ""
    var archivedAt: Date?
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID, powerPointId: UUID, name: String, archivedAt: Date? = nil) {
        self.id = id; self.createdAt = createdAt; self.generation = generation; self.powerPointId = powerPointId; self.name = name; self.archivedAt = archivedAt
    }
}

@Model
final class StatusSnapshot {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID = UUID()
    var status: String = "withinrange"
    var paceToDateKwh: String = "0"
    var baselineToDateKwh: String = "0"
    var isLowConfidence: Bool = false
    var computedAt: Date = Date()
    var causeId: UUID = UUID()

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID, status: String, paceToDateKwh: Decimal, baselineToDateKwh: Decimal, isLowConfidence: Bool, computedAt: Date, causeId: UUID) {
        self.id = id; self.createdAt = createdAt; self.generation = generation; self.status = status
        self.paceToDateKwh = DecimalText.encode(paceToDateKwh)
        self.baselineToDateKwh = DecimalText.encode(baselineToDateKwh)
        self.isLowConfidence = isLowConfidence; self.computedAt = computedAt; self.causeId = causeId
    }
}

@Model
final class AuditCorrection {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID = UUID()
    var entityType: String = "MeterReading"
    var entityId: UUID = UUID()
    var fieldName: String = "KwhValue"
    var oldValue: String = ""
    var newValue: String = ""
    var correctedAt: Date = Date()

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID, entityType: String, entityId: UUID, fieldName: String, oldValue: String, newValue: String, correctedAt: Date = Date()) {
        self.id = id; self.createdAt = createdAt; self.generation = generation; self.entityType = entityType; self.entityId = entityId
        self.fieldName = fieldName; self.oldValue = oldValue; self.newValue = newValue; self.correctedAt = correctedAt
    }
}

@Model
final class SmartPlugReading {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var generation: UUID = UUID()
    var powerPointId: UUID?
    var roomName: String = ""
    var powerPointName: String = ""
    var deviceName: String = ""
    var intervalStart: Date = Date()
    var intervalEnd: Date = Date()
    var kwhValue: String = "0"

    init(id: UUID = UUID(), createdAt: Date = Date(), generation: UUID, powerPointId: UUID? = nil, roomName: String, powerPointName: String, deviceName: String, intervalStart: Date, intervalEnd: Date, kwhValue: Decimal) {
        self.id = id; self.createdAt = createdAt; self.generation = generation; self.powerPointId = powerPointId
        self.roomName = roomName; self.powerPointName = powerPointName; self.deviceName = deviceName
        self.intervalStart = intervalStart; self.intervalEnd = intervalEnd; self.kwhValue = DecimalText.encode(kwhValue)
    }
}

enum EnergySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Household.self, MainMeter.self, MeterReading.self, MeterRegressionPrompt.self, Tariff.self,
         EnergyEvent.self, Room.self, PowerPoint.self, Device.self, StatusSnapshot.self,
         AuditCorrection.self, SmartPlugReading.self]
    }
}

enum EnergyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [EnergySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
