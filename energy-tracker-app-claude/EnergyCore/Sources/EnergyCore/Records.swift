import Foundation

/// Plain value records for every entity (§4.2). The app maps its persistent models to and from these.
/// They are the unit of the export format, the merge and the generation rules.

public struct HouseholdRecord: Sendable, Hashable {
    public var id: UUID
    public var createdAt: Date
    public var locale: String
    public var currency: String
    public var yearlyBaselineKwh: Decimal?
    public var trendingThresholdKwh: Decimal
    public var lowConfidenceGapDays: Int
    public var tariffCheckCadenceMonths: Int
    public var tariffCheckDoneAt: Date?

    public init(
        id: UUID = UUID(), createdAt: Date, locale: String = "en-US", currency: String = "EUR",
        yearlyBaselineKwh: Decimal? = nil, trendingThresholdKwh: Decimal = 100, lowConfidenceGapDays: Int = 45,
        tariffCheckCadenceMonths: Int = 3, tariffCheckDoneAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.locale = locale
        self.currency = currency
        self.yearlyBaselineKwh = yearlyBaselineKwh
        self.trendingThresholdKwh = trendingThresholdKwh
        self.lowConfidenceGapDays = lowConfidenceGapDays
        self.tariffCheckCadenceMonths = tariffCheckCadenceMonths
        self.tariffCheckDoneAt = tariffCheckDoneAt
    }
}

public struct MainMeterRecord: Sendable, Hashable {
    public var id: UUID
    public var createdAt: Date
    public var digitCapacityKwh: Decimal?

    public init(id: UUID = UUID(), createdAt: Date, digitCapacityKwh: Decimal? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.digitCapacityKwh = digitCapacityKwh
    }
}

public struct ReadingRecord: Sendable, Hashable {
    public var id: UUID
    public var mainMeterId: UUID
    /// The original value, never changed.
    public var originalKwhValue: Decimal
    /// The effective value after corrections. Written to the file as `kwhValue`.
    public var effectiveKwhValue: Decimal
    public var readingTimestamp: Date
    public var createdAt: Date

    public init(id: UUID = UUID(), mainMeterId: UUID, originalKwhValue: Decimal, effectiveKwhValue: Decimal? = nil, readingTimestamp: Date, createdAt: Date) {
        self.id = id
        self.mainMeterId = mainMeterId
        self.originalKwhValue = originalKwhValue
        self.effectiveKwhValue = effectiveKwhValue ?? originalKwhValue
        self.readingTimestamp = readingTimestamp
        self.createdAt = createdAt
    }
}

public struct PromptRecord: Sendable, Hashable {
    public var id: UUID
    public var mainMeterId: UUID
    public var meterReadingId: UUID
    public var previousMeterReadingId: UUID
    public var createdAt: Date
    public var resolvedAt: Date?
    public var classification: RegressionClassification?
    public var digitCapacityKwh: Decimal?

    public init(id: UUID = UUID(), mainMeterId: UUID, meterReadingId: UUID, previousMeterReadingId: UUID, createdAt: Date, resolvedAt: Date? = nil, classification: RegressionClassification? = nil, digitCapacityKwh: Decimal? = nil) {
        self.id = id
        self.mainMeterId = mainMeterId
        self.meterReadingId = meterReadingId
        self.previousMeterReadingId = previousMeterReadingId
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.classification = classification
        self.digitCapacityKwh = digitCapacityKwh
    }
}

public struct TariffRecord: Sendable, Hashable {
    public var id: UUID
    public var monthlyBaseFee: Decimal
    public var pricePerKwh: Decimal
    public var currency: String
    public var contractStartDate: CalendarDate
    public var contractPeriodMonths: Int
    public var createdAt: Date

    public init(id: UUID = UUID(), monthlyBaseFee: Decimal, pricePerKwh: Decimal, currency: String, contractStartDate: CalendarDate, contractPeriodMonths: Int, createdAt: Date) {
        self.id = id
        self.monthlyBaseFee = monthlyBaseFee
        self.pricePerKwh = pricePerKwh
        self.currency = currency
        self.contractStartDate = contractStartDate
        self.contractPeriodMonths = contractPeriodMonths
        self.createdAt = createdAt
    }
}

public enum TaggedEntityType: String, Sendable, Hashable, CaseIterable, Codable {
    case room = "Room"
    case powerPoint = "PowerPoint"
    case device = "Device"
}

public struct EventRecord: Sendable, Hashable {
    public var id: UUID
    public var description: String
    public var occurredAt: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var taggedEntityType: TaggedEntityType?
    public var taggedEntityId: UUID?
    public var taggedEntityName: String?
    /// Export only: §5.6 result at export time.
    public var exportDeviation: Deviation?

    public init(id: UUID = UUID(), description: String, occurredAt: Date, createdAt: Date, updatedAt: Date? = nil, taggedEntityType: TaggedEntityType? = nil, taggedEntityId: UUID? = nil, taggedEntityName: String? = nil, exportDeviation: Deviation? = nil) {
        self.id = id
        self.description = description
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.taggedEntityType = taggedEntityType
        self.taggedEntityId = taggedEntityId
        self.taggedEntityName = taggedEntityName
        self.exportDeviation = exportDeviation
    }
}

/// Room, Power Point or Device. `parentId` is nil for rooms, the room id for power points, the power point id for devices.
public struct StructureRecord: Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var archivedAt: Date?
    public var parentId: UUID?

    public init(id: UUID = UUID(), name: String, createdAt: Date, archivedAt: Date? = nil, parentId: UUID? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.parentId = parentId
    }
}

public struct SmartPlugReadingRecord: Sendable, Hashable {
    public var id: UUID
    public var powerPointId: UUID?
    public var roomName: String
    public var powerPointName: String
    public var deviceName: String
    public var intervalStart: Date
    public var intervalEnd: Date
    public var kwhValue: Decimal

    public init(id: UUID = UUID(), powerPointId: UUID?, roomName: String, powerPointName: String, deviceName: String, intervalStart: Date, intervalEnd: Date, kwhValue: Decimal) {
        self.id = id
        self.powerPointId = powerPointId
        self.roomName = roomName
        self.powerPointName = powerPointName
        self.deviceName = deviceName
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
        self.kwhValue = kwhValue
    }
}

public struct SnapshotRecord: Sendable, Hashable {
    public var id: UUID
    public var status: EnergyStatus
    public var paceToDateKwh: Decimal
    public var baselineToDateKwh: Decimal
    public var isLowConfidence: Bool
    public var computedAt: Date
    public var causeId: UUID
    public var createdAt: Date

    public init(id: UUID = UUID(), status: EnergyStatus, paceToDateKwh: Decimal, baselineToDateKwh: Decimal, isLowConfidence: Bool, computedAt: Date, causeId: UUID? = nil, createdAt: Date? = nil) {
        self.id = id
        self.status = status
        self.paceToDateKwh = paceToDateKwh
        self.baselineToDateKwh = baselineToDateKwh
        self.isLowConfidence = isLowConfidence
        self.computedAt = computedAt
        self.causeId = causeId ?? id
        self.createdAt = createdAt ?? computedAt
    }
}

public struct CorrectionRecord: Sendable, Hashable {
    public var id: UUID
    public var entityType: String
    public var entityId: UUID
    public var fieldName: String
    public var oldValue: String
    public var newValue: String
    public var correctedAt: Date

    public init(id: UUID = UUID(), entityType: String, entityId: UUID, fieldName: String, oldValue: String, newValue: String, correctedAt: Date) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.fieldName = fieldName
        self.oldValue = oldValue
        self.newValue = newValue
        self.correctedAt = correctedAt
    }

    public var asInput: CorrectionInput {
        CorrectionInput(id: id, fieldName: fieldName, newValue: newValue, correctedAt: correctedAt)
    }
}

/// A whole data set as plain values.
public struct DataSetRecords: Sendable {
    public var exportedAt: Date
    public var household: HouseholdRecord
    public var mainMeter: MainMeterRecord?
    public var readings: [ReadingRecord] = []
    public var prompts: [PromptRecord] = []
    public var tariffs: [TariffRecord] = []
    public var events: [EventRecord] = []
    public var rooms: [StructureRecord] = []
    public var powerPoints: [StructureRecord] = []
    public var devices: [StructureRecord] = []
    public var smartPlugReadings: [SmartPlugReadingRecord] = []
    public var snapshots: [SnapshotRecord] = []
    public var corrections: [CorrectionRecord] = []

    public init(exportedAt: Date, household: HouseholdRecord, mainMeter: MainMeterRecord? = nil) {
        self.exportedAt = exportedAt
        self.household = household
        self.mainMeter = mainMeter
    }

    public struct Counts: Sendable, Hashable {
        public var readings, prompts, tariffs, events, rooms, powerPoints, devices, smartPlugReadings, snapshots, corrections: Int

        public init(readings: Int, prompts: Int, tariffs: Int, events: Int, rooms: Int, powerPoints: Int, devices: Int, smartPlugReadings: Int, snapshots: Int, corrections: Int) {
            self.readings = readings
            self.prompts = prompts
            self.tariffs = tariffs
            self.events = events
            self.rooms = rooms
            self.powerPoints = powerPoints
            self.devices = devices
            self.smartPlugReadings = smartPlugReadings
            self.snapshots = snapshots
            self.corrections = corrections
        }
    }

    public var counts: Counts {
        Counts(readings: readings.count, prompts: prompts.count, tariffs: tariffs.count, events: events.count, rooms: rooms.count, powerPoints: powerPoints.count, devices: devices.count, smartPlugReadings: smartPlugReadings.count, snapshots: snapshots.count, corrections: corrections.count)
    }
}
