import Foundation

/// Codable representation of the complete v2 export document.
/// Use `EnergyExportCodec` for strict whole-file validation and exact JSON-decimal parsing.
public struct EnergyExport: Codable, Equatable, Sendable {
    public var formatVersion: String
    public var exportedAtUtc: Date
    public var household: ExportHousehold
    public var householdMembers: [ExportHouseholdMember]
    public var mainMeter: ExportMainMeter?
    public var meterReadings: [ExportMeterReading]
    public var meterRegressionPrompts: [ExportMeterRegressionPrompt]
    public var tariffs: [ExportTariff]
    public var events: [ExportEvent]
    public var rooms: [ExportRoom]
    public var powerPoints: [ExportPowerPoint]
    public var devices: [ExportDevice]
    public var smartPlugReadings: [ExportSmartPlugReading]
    public var statusSnapshots: [ExportStatusSnapshot]
    public var auditCorrections: [ExportAuditCorrection]

    public init(
        formatVersion: String = "v2",
        exportedAtUtc: Date,
        household: ExportHousehold,
        householdMembers: [ExportHouseholdMember] = [],
        mainMeter: ExportMainMeter? = nil,
        meterReadings: [ExportMeterReading] = [],
        meterRegressionPrompts: [ExportMeterRegressionPrompt] = [],
        tariffs: [ExportTariff] = [],
        events: [ExportEvent] = [],
        rooms: [ExportRoom] = [],
        powerPoints: [ExportPowerPoint] = [],
        devices: [ExportDevice] = [],
        smartPlugReadings: [ExportSmartPlugReading] = [],
        statusSnapshots: [ExportStatusSnapshot] = [],
        auditCorrections: [ExportAuditCorrection] = []
    ) {
        self.formatVersion = formatVersion
        self.exportedAtUtc = exportedAtUtc
        self.household = household
        self.householdMembers = householdMembers
        self.mainMeter = mainMeter
        self.meterReadings = meterReadings
        self.meterRegressionPrompts = meterRegressionPrompts
        self.tariffs = tariffs
        self.events = events
        self.rooms = rooms
        self.powerPoints = powerPoints
        self.devices = devices
        self.smartPlugReadings = smartPlugReadings
        self.statusSnapshots = statusSnapshots
        self.auditCorrections = auditCorrections
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAtUtc, household, householdMembers, mainMeter, meterReadings
        case meterRegressionPrompts, tariffs, events, rooms, powerPoints, devices, smartPlugReadings
        case statusSnapshots, auditCorrections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(String.self, forKey: .formatVersion)
        exportedAtUtc = try container.decodeInstant(forKey: .exportedAtUtc)
        household = try container.decode(ExportHousehold.self, forKey: .household)
        householdMembers = try container.decode([ExportHouseholdMember].self, forKey: .householdMembers)
        mainMeter = try container.decodeIfPresent(ExportMainMeter.self, forKey: .mainMeter)
        meterReadings = try container.decode([ExportMeterReading].self, forKey: .meterReadings)
        meterRegressionPrompts = try container.decode([ExportMeterRegressionPrompt].self, forKey: .meterRegressionPrompts)
        tariffs = try container.decode([ExportTariff].self, forKey: .tariffs)
        events = try container.decode([ExportEvent].self, forKey: .events)
        rooms = try container.decode([ExportRoom].self, forKey: .rooms)
        powerPoints = try container.decode([ExportPowerPoint].self, forKey: .powerPoints)
        devices = try container.decode([ExportDevice].self, forKey: .devices)
        smartPlugReadings = try container.decode([ExportSmartPlugReading].self, forKey: .smartPlugReadings)
        statusSnapshots = try container.decode([ExportStatusSnapshot].self, forKey: .statusSnapshots)
        auditCorrections = try container.decode([ExportAuditCorrection].self, forKey: .auditCorrections)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encodeInstant(exportedAtUtc, forKey: .exportedAtUtc)
        try container.encode(household, forKey: .household)
        try container.encode(householdMembers, forKey: .householdMembers)
        try container.encodeIfPresent(mainMeter, forKey: .mainMeter)
        try container.encode(meterReadings, forKey: .meterReadings)
        try container.encode(meterRegressionPrompts, forKey: .meterRegressionPrompts)
        try container.encode(tariffs, forKey: .tariffs)
        try container.encode(events, forKey: .events)
        try container.encode(rooms, forKey: .rooms)
        try container.encode(powerPoints, forKey: .powerPoints)
        try container.encode(devices, forKey: .devices)
        try container.encode(smartPlugReadings, forKey: .smartPlugReadings)
        try container.encode(statusSnapshots, forKey: .statusSnapshots)
        try container.encode(auditCorrections, forKey: .auditCorrections)
    }
}

public struct ExportHousehold: Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAtUtc: Date
    public var locale: String
    public var currency: String
    public var yearlyBaselineKwh: Decimal?
    public var trendingThresholdKwh: Decimal
    public var lowConfidenceGapDays: Int
    public var tariffCheckCadenceMonths: Int
    /// Optional additive field used by Energy Tracker to preserve reminder state on round trip.
    /// Older readers ignore it as an unknown property; older files simply omit it.
    public var tariffCheckDoneAtUtc: Date?
    public var aiPlausibilityEnabled: Bool
    public var aiPlausibilityBackendConfigured: Bool
    public var aiPlausibilityBackendLabel: String?

    public init(
        id: UUID,
        createdAtUtc: Date,
        locale: String,
        currency: String,
        yearlyBaselineKwh: Decimal?,
        trendingThresholdKwh: Decimal = 100,
        lowConfidenceGapDays: Int = 45,
        tariffCheckCadenceMonths: Int = 3,
        tariffCheckDoneAtUtc: Date? = nil,
        aiPlausibilityEnabled: Bool = false,
        aiPlausibilityBackendConfigured: Bool = false,
        aiPlausibilityBackendLabel: String? = nil
    ) {
        self.id = id
        self.createdAtUtc = createdAtUtc
        self.locale = locale
        self.currency = currency
        self.yearlyBaselineKwh = yearlyBaselineKwh
        self.trendingThresholdKwh = trendingThresholdKwh
        self.lowConfidenceGapDays = lowConfidenceGapDays
        self.tariffCheckCadenceMonths = tariffCheckCadenceMonths
        self.tariffCheckDoneAtUtc = tariffCheckDoneAtUtc
        self.aiPlausibilityEnabled = aiPlausibilityEnabled
        self.aiPlausibilityBackendConfigured = aiPlausibilityBackendConfigured
        self.aiPlausibilityBackendLabel = aiPlausibilityBackendLabel
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAtUtc, locale, currency, yearlyBaselineKwh, trendingThresholdKwh
        case lowConfidenceGapDays, tariffCheckCadenceMonths, tariffCheckDoneAtUtc, aiPlausibilityEnabled
        case aiPlausibilityBackendConfigured, aiPlausibilityBackendLabel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAtUtc = try container.decodeInstant(forKey: .createdAtUtc)
        locale = try container.decode(String.self, forKey: .locale)
        currency = try container.decode(String.self, forKey: .currency)
        yearlyBaselineKwh = try container.decodeIfPresent(Decimal.self, forKey: .yearlyBaselineKwh)
        trendingThresholdKwh = try container.decode(Decimal.self, forKey: .trendingThresholdKwh)
        lowConfidenceGapDays = try container.decode(Int.self, forKey: .lowConfidenceGapDays)
        tariffCheckCadenceMonths = try container.decode(Int.self, forKey: .tariffCheckCadenceMonths)
        tariffCheckDoneAtUtc = container.contains(.tariffCheckDoneAtUtc) ? try container.decodeInstantIfPresent(forKey: .tariffCheckDoneAtUtc) : nil
        aiPlausibilityEnabled = try container.decode(Bool.self, forKey: .aiPlausibilityEnabled)
        aiPlausibilityBackendConfigured = try container.decode(Bool.self, forKey: .aiPlausibilityBackendConfigured)
        aiPlausibilityBackendLabel = try container.decodeIfPresent(String.self, forKey: .aiPlausibilityBackendLabel)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeInstant(createdAtUtc, forKey: .createdAtUtc)
        try container.encode(locale, forKey: .locale)
        try container.encode(currency, forKey: .currency)
        try container.encodeIfPresent(yearlyBaselineKwh, forKey: .yearlyBaselineKwh)
        try container.encode(trendingThresholdKwh, forKey: .trendingThresholdKwh)
        try container.encode(lowConfidenceGapDays, forKey: .lowConfidenceGapDays)
        try container.encode(tariffCheckCadenceMonths, forKey: .tariffCheckCadenceMonths)
        try container.encodeInstantIfPresent(tariffCheckDoneAtUtc, forKey: .tariffCheckDoneAtUtc)
        try container.encode(false, forKey: .aiPlausibilityEnabled)
        try container.encode(false, forKey: .aiPlausibilityBackendConfigured)
        try container.encodeNil(forKey: .aiPlausibilityBackendLabel)
    }
}

public struct ExportHouseholdMember: Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String?

    public init(id: UUID, displayName: String?) {
        self.id = id
        self.displayName = displayName
    }
}

public struct ExportMainMeter: Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAtUtc: Date
    public var digitCapacityKwh: Decimal?

    public init(id: UUID, createdAtUtc: Date, digitCapacityKwh: Decimal?) {
        self.id = id
        self.createdAtUtc = createdAtUtc
        self.digitCapacityKwh = digitCapacityKwh
    }

    private enum CodingKeys: String, CodingKey { case id, createdAtUtc, digitCapacityKwh }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAtUtc = try container.decodeInstant(forKey: .createdAtUtc)
        digitCapacityKwh = try container.decodeIfPresent(Decimal.self, forKey: .digitCapacityKwh)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeInstant(createdAtUtc, forKey: .createdAtUtc)
        try container.encodeIfPresent(digitCapacityKwh, forKey: .digitCapacityKwh)
    }
}

public struct ExportMeterReading: Codable, Equatable, Sendable {
    public var id: UUID
    public var mainMeterId: UUID
    /// The effective value carried by the file.
    public var kwhValue: Decimal
    public var readingTimestamp: Date
    public var idempotencyKey: UUID
    public var createdAtUtc: Date

    public init(
        id: UUID,
        mainMeterId: UUID,
        kwhValue: Decimal,
        readingTimestamp: Date,
        idempotencyKey: UUID? = nil,
        createdAtUtc: Date
    ) {
        self.id = id
        self.mainMeterId = mainMeterId
        self.kwhValue = kwhValue
        self.readingTimestamp = readingTimestamp
        self.idempotencyKey = idempotencyKey ?? id
        self.createdAtUtc = createdAtUtc
    }

    private enum CodingKeys: String, CodingKey {
        case id, mainMeterId, kwhValue, readingTimestamp, idempotencyKey, createdAtUtc
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        mainMeterId = try container.decode(UUID.self, forKey: .mainMeterId)
        kwhValue = try container.decode(Decimal.self, forKey: .kwhValue)
        readingTimestamp = try container.decodeInstant(forKey: .readingTimestamp)
        _ = try container.decode(UUID.self, forKey: .idempotencyKey) // Accepted and ignored on read.
        idempotencyKey = id
        createdAtUtc = try container.decodeInstant(forKey: .createdAtUtc)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mainMeterId, forKey: .mainMeterId)
        try container.encode(kwhValue, forKey: .kwhValue)
        try container.encodeInstant(readingTimestamp, forKey: .readingTimestamp)
        try container.encode(id, forKey: .idempotencyKey)
        try container.encodeInstant(createdAtUtc, forKey: .createdAtUtc)
    }
}

public struct ExportMeterRegressionPrompt: Codable, Equatable, Sendable {
    public var id: UUID
    public var mainMeterId: UUID
    public var meterReadingId: UUID
    public var previousMeterReadingId: UUID
    public var createdAtUtc: Date
    public var resolvedAtUtc: Date?
    public var classification: RegressionClassification?
    public var digitCapacityKwh: Decimal?

    public init(
        id: UUID,
        mainMeterId: UUID,
        meterReadingId: UUID,
        previousMeterReadingId: UUID,
        createdAtUtc: Date,
        resolvedAtUtc: Date?,
        classification: RegressionClassification?,
        digitCapacityKwh: Decimal?
    ) {
        self.id = id
        self.mainMeterId = mainMeterId
        self.meterReadingId = meterReadingId
        self.previousMeterReadingId = previousMeterReadingId
        self.createdAtUtc = createdAtUtc
        self.resolvedAtUtc = resolvedAtUtc
        self.classification = classification
        self.digitCapacityKwh = digitCapacityKwh
    }

    private enum CodingKeys: String, CodingKey {
        case id, mainMeterId, meterReadingId, previousMeterReadingId, createdAtUtc
        case resolvedAtUtc, classification, digitCapacityKwh
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        mainMeterId = try container.decode(UUID.self, forKey: .mainMeterId)
        meterReadingId = try container.decode(UUID.self, forKey: .meterReadingId)
        previousMeterReadingId = try container.decode(UUID.self, forKey: .previousMeterReadingId)
        createdAtUtc = try container.decodeInstant(forKey: .createdAtUtc)
        resolvedAtUtc = try container.decodeInstantIfPresent(forKey: .resolvedAtUtc)
        classification = try container.decodeIfPresent(RegressionClassification.self, forKey: .classification)
        digitCapacityKwh = try container.decodeIfPresent(Decimal.self, forKey: .digitCapacityKwh)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mainMeterId, forKey: .mainMeterId)
        try container.encode(meterReadingId, forKey: .meterReadingId)
        try container.encode(previousMeterReadingId, forKey: .previousMeterReadingId)
        try container.encodeInstant(createdAtUtc, forKey: .createdAtUtc)
        try container.encodeInstantIfPresent(resolvedAtUtc, forKey: .resolvedAtUtc)
        try container.encodeIfPresent(classification, forKey: .classification)
        try container.encodeIfPresent(digitCapacityKwh, forKey: .digitCapacityKwh)
    }
}

public struct ExportTariff: Codable, Equatable, Sendable {
    public var id: UUID
    public var monthlyBaseFee: Decimal
    public var pricePerKwh: Decimal
    public var currency: String
    public var contractStartDate: CalendarDate
    public var contractPeriodMonths: Int
    public var createdAtUtc: Date

    public init(
        id: UUID,
        monthlyBaseFee: Decimal,
        pricePerKwh: Decimal,
        currency: String,
        contractStartDate: CalendarDate,
        contractPeriodMonths: Int,
        createdAtUtc: Date
    ) {
        self.id = id
        self.monthlyBaseFee = monthlyBaseFee
        self.pricePerKwh = pricePerKwh
        self.currency = currency
        self.contractStartDate = contractStartDate
        self.contractPeriodMonths = contractPeriodMonths
        self.createdAtUtc = createdAtUtc
    }

    private enum CodingKeys: String, CodingKey {
        case id, monthlyBaseFee, pricePerKwh, currency, contractStartDate, contractPeriodMonths, createdAtUtc
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        monthlyBaseFee = try container.decode(Decimal.self, forKey: .monthlyBaseFee)
        pricePerKwh = try container.decode(Decimal.self, forKey: .pricePerKwh)
        currency = try container.decode(String.self, forKey: .currency)
        contractStartDate = try container.decodeCalendarDate(forKey: .contractStartDate)
        contractPeriodMonths = try container.decode(Int.self, forKey: .contractPeriodMonths)
        createdAtUtc = try container.decodeInstant(forKey: .createdAtUtc)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(monthlyBaseFee, forKey: .monthlyBaseFee)
        try container.encode(pricePerKwh, forKey: .pricePerKwh)
        try container.encode(currency, forKey: .currency)
        try container.encodeCalendarDate(contractStartDate, forKey: .contractStartDate)
        try container.encode(contractPeriodMonths, forKey: .contractPeriodMonths)
        try container.encodeInstant(createdAtUtc, forKey: .createdAtUtc)
    }
}

public enum ExportTaggedEntityType: String, Codable, Sendable {
    case room = "Room"
    case powerPoint = "PowerPoint"
    case device = "Device"
}

public enum ExportCorrelationDirection: String, Codable, Sendable {
    case bump = "Bump"
    case dip = "Dip"
}

public struct ExportEvent: Codable, Equatable, Sendable {
    public var id: UUID
    public var description: String
    public var occurredAt: Date
    public var createdAtUtc: Date
    public var taggedEntityType: ExportTaggedEntityType?
    public var taggedEntityId: UUID?
    public var taggedEntityName: String?
    public var correlationDirection: ExportCorrelationDirection?
    public var correlationComputedAtUtc: Date?

    public init(
        id: UUID,
        description: String,
        occurredAt: Date,
        createdAtUtc: Date,
        taggedEntityType: ExportTaggedEntityType? = nil,
        taggedEntityId: UUID? = nil,
        taggedEntityName: String? = nil,
        correlationDirection: ExportCorrelationDirection? = nil,
        correlationComputedAtUtc: Date? = nil
    ) {
        self.id = id
        self.description = description
        self.occurredAt = occurredAt
        self.createdAtUtc = createdAtUtc
        self.taggedEntityType = taggedEntityType
        self.taggedEntityId = taggedEntityId
        self.taggedEntityName = taggedEntityName
        self.correlationDirection = correlationDirection
        self.correlationComputedAtUtc = correlationComputedAtUtc
    }

    private enum CodingKeys: String, CodingKey {
        case id, description, occurredAt, createdAtUtc, taggedEntityType, taggedEntityId, taggedEntityName
        case correlationDirection, correlationComputedAtUtc
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        description = try container.decode(String.self, forKey: .description)
        occurredAt = try container.decodeInstant(forKey: .occurredAt)
        createdAtUtc = try container.decodeInstant(forKey: .createdAtUtc)
        taggedEntityType = try container.decodeIfPresent(ExportTaggedEntityType.self, forKey: .taggedEntityType)
        taggedEntityId = try container.decodeIfPresent(UUID.self, forKey: .taggedEntityId)
        taggedEntityName = try container.decodeIfPresent(String.self, forKey: .taggedEntityName)
        correlationDirection = try container.decodeIfPresent(ExportCorrelationDirection.self, forKey: .correlationDirection)
        correlationComputedAtUtc = try container.decodeInstantIfPresent(forKey: .correlationComputedAtUtc)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(description, forKey: .description)
        try container.encodeInstant(occurredAt, forKey: .occurredAt)
        try container.encodeInstant(createdAtUtc, forKey: .createdAtUtc)
        try container.encodeIfPresent(taggedEntityType, forKey: .taggedEntityType)
        try container.encodeIfPresent(taggedEntityId, forKey: .taggedEntityId)
        try container.encodeIfPresent(taggedEntityName, forKey: .taggedEntityName)
        try container.encodeIfPresent(correlationDirection, forKey: .correlationDirection)
        try container.encodeInstantIfPresent(correlationComputedAtUtc, forKey: .correlationComputedAtUtc)
    }
}

public struct ExportRoom: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAtUtc: Date
    public var archivedAt: Date?

    public init(id: UUID, name: String, createdAtUtc: Date, archivedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.createdAtUtc = createdAtUtc
        self.archivedAt = archivedAt
    }

    private enum CodingKeys: String, CodingKey { case id, name, createdAtUtc, archivedAt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAtUtc = try container.decodeInstant(forKey: .createdAtUtc)
        archivedAt = try container.decodeInstantIfPresent(forKey: .archivedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeInstant(createdAtUtc, forKey: .createdAtUtc)
        try container.encodeInstantIfPresent(archivedAt, forKey: .archivedAt)
    }
}

public struct ExportPowerPoint: Codable, Equatable, Sendable {
    public var id: UUID
    public var roomId: UUID
    public var name: String
    public var createdAtUtc: Date
    public var archivedAt: Date?

    public init(id: UUID, roomId: UUID, name: String, createdAtUtc: Date, archivedAt: Date? = nil) {
        self.id = id
        self.roomId = roomId
        self.name = name
        self.createdAtUtc = createdAtUtc
        self.archivedAt = archivedAt
    }

    private enum CodingKeys: String, CodingKey { case id, roomId, name, createdAtUtc, archivedAt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        roomId = try container.decode(UUID.self, forKey: .roomId)
        name = try container.decode(String.self, forKey: .name)
        createdAtUtc = try container.decodeInstant(forKey: .createdAtUtc)
        archivedAt = try container.decodeInstantIfPresent(forKey: .archivedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(roomId, forKey: .roomId)
        try container.encode(name, forKey: .name)
        try container.encodeInstant(createdAtUtc, forKey: .createdAtUtc)
        try container.encodeInstantIfPresent(archivedAt, forKey: .archivedAt)
    }
}

public struct ExportDevice: Codable, Equatable, Sendable {
    public var id: UUID
    public var powerPointId: UUID
    public var name: String
    public var createdAtUtc: Date
    public var archivedAt: Date?

    public init(id: UUID, powerPointId: UUID, name: String, createdAtUtc: Date, archivedAt: Date? = nil) {
        self.id = id
        self.powerPointId = powerPointId
        self.name = name
        self.createdAtUtc = createdAtUtc
        self.archivedAt = archivedAt
    }

    private enum CodingKeys: String, CodingKey { case id, powerPointId, name, createdAtUtc, archivedAt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        powerPointId = try container.decode(UUID.self, forKey: .powerPointId)
        name = try container.decode(String.self, forKey: .name)
        createdAtUtc = try container.decodeInstant(forKey: .createdAtUtc)
        archivedAt = try container.decodeInstantIfPresent(forKey: .archivedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(powerPointId, forKey: .powerPointId)
        try container.encode(name, forKey: .name)
        try container.encodeInstant(createdAtUtc, forKey: .createdAtUtc)
        try container.encodeInstantIfPresent(archivedAt, forKey: .archivedAt)
    }
}

public struct ExportSmartPlugReading: Codable, Equatable, Sendable {
    public var id: UUID
    public var powerPointId: UUID?
    public var roomName: String
    public var powerPointName: String
    public var deviceName: String
    public var intervalStart: Date
    public var intervalEnd: Date
    public var kwhValue: Decimal

    public init(
        id: UUID,
        powerPointId: UUID?,
        roomName: String,
        powerPointName: String,
        deviceName: String,
        intervalStart: Date,
        intervalEnd: Date,
        kwhValue: Decimal
    ) {
        self.id = id
        self.powerPointId = powerPointId
        self.roomName = roomName
        self.powerPointName = powerPointName
        self.deviceName = deviceName
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
        self.kwhValue = kwhValue
    }

    private enum CodingKeys: String, CodingKey {
        case id, powerPointId, roomName, powerPointName, deviceName, intervalStart, intervalEnd, kwhValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        powerPointId = try container.decodeIfPresent(UUID.self, forKey: .powerPointId)
        roomName = try container.decode(String.self, forKey: .roomName)
        powerPointName = try container.decode(String.self, forKey: .powerPointName)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        intervalStart = try container.decodeInstant(forKey: .intervalStart)
        intervalEnd = try container.decodeInstant(forKey: .intervalEnd)
        kwhValue = try container.decode(Decimal.self, forKey: .kwhValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(powerPointId, forKey: .powerPointId)
        try container.encode(roomName, forKey: .roomName)
        try container.encode(powerPointName, forKey: .powerPointName)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encodeInstant(intervalStart, forKey: .intervalStart)
        try container.encodeInstant(intervalEnd, forKey: .intervalEnd)
        try container.encode(kwhValue, forKey: .kwhValue)
    }
}

public struct ExportStatusSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var status: ConsumptionStatus
    public var paceToDateKwh: Decimal
    public var baselineToDateKwh: Decimal
    public var isLowConfidence: Bool
    public var computedAtUtc: Date

    public init(
        id: UUID,
        status: ConsumptionStatus,
        paceToDateKwh: Decimal,
        baselineToDateKwh: Decimal,
        isLowConfidence: Bool,
        computedAtUtc: Date
    ) {
        self.id = id
        self.status = status
        self.paceToDateKwh = paceToDateKwh
        self.baselineToDateKwh = baselineToDateKwh
        self.isLowConfidence = isLowConfidence
        self.computedAtUtc = computedAtUtc
    }

    private enum CodingKeys: String, CodingKey {
        case id, status, paceToDateKwh, baselineToDateKwh, isLowConfidence, computedAtUtc
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        status = try container.decode(ConsumptionStatus.self, forKey: .status)
        paceToDateKwh = try container.decode(Decimal.self, forKey: .paceToDateKwh)
        baselineToDateKwh = try container.decode(Decimal.self, forKey: .baselineToDateKwh)
        isLowConfidence = try container.decode(Bool.self, forKey: .isLowConfidence)
        computedAtUtc = try container.decodeInstant(forKey: .computedAtUtc)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(status, forKey: .status)
        try container.encode(paceToDateKwh, forKey: .paceToDateKwh)
        try container.encode(baselineToDateKwh, forKey: .baselineToDateKwh)
        try container.encode(isLowConfidence, forKey: .isLowConfidence)
        try container.encodeInstant(computedAtUtc, forKey: .computedAtUtc)
    }
}

public struct ExportAuditCorrection: Codable, Equatable, Sendable {
    public var id: UUID
    public var entityType: String
    public var entityId: UUID
    public var fieldName: String
    public var oldValue: String
    public var newValue: String
    public var correctedAtUtc: Date

    public init(
        id: UUID,
        entityType: String,
        entityId: UUID,
        fieldName: String,
        oldValue: String,
        newValue: String,
        correctedAtUtc: Date
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.fieldName = fieldName
        self.oldValue = oldValue
        self.newValue = newValue
        self.correctedAtUtc = correctedAtUtc
    }

    private enum CodingKeys: String, CodingKey {
        case id, entityType, entityId, fieldName, oldValue, newValue, correctedAtUtc
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        entityType = try container.decode(String.self, forKey: .entityType)
        entityId = try container.decode(UUID.self, forKey: .entityId)
        fieldName = try container.decode(String.self, forKey: .fieldName)
        oldValue = try container.decode(String.self, forKey: .oldValue)
        newValue = try container.decode(String.self, forKey: .newValue)
        correctedAtUtc = try container.decodeInstant(forKey: .correctedAtUtc)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(entityType, forKey: .entityType)
        try container.encode(entityId, forKey: .entityId)
        try container.encode(fieldName, forKey: .fieldName)
        try container.encode(oldValue, forKey: .oldValue)
        try container.encode(newValue, forKey: .newValue)
        try container.encodeInstant(correctedAtUtc, forKey: .correctedAtUtc)
    }
}
