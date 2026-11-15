import Foundation

public struct ExportValidationIssue: Equatable, Sendable, CustomStringConvertible {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var description: String { "\(path): \(message)" }
}

public enum EnergyExportError: Error, Equatable {
    case malformedJSON(String)
    case validationFailed([ExportValidationIssue])
}

/// Exact-decimal, strictly validating v2 JSON import and export.
public enum EnergyExportCodec {
    /// Encodes a complete v2 document. Decimal values are emitted as JSON numbers and dates as UTC ISO 8601.
    public static func encode(_ export: EnergyExport) throws -> Data {
        var normalized = export
        normalized.householdMembers = []
        normalized.household.aiPlausibilityEnabled = false
        normalized.household.aiPlausibilityBackendConfigured = false
        normalized.household.aiPlausibilityBackendLabel = nil
        for index in normalized.meterReadings.indices {
            normalized.meterReadings[index].idempotencyKey = normalized.meterReadings[index].id
        }
        let json = normalized.jsonValue()
        _ = try ExportReader.read(json)
        return try ExactJSON.data(json)
    }

    /// Parses and validates the whole document before returning any DTOs.
    /// A bad or missing `formatVersion` returns that single issue and suppresses every later check.
    public static func decode(_ data: Data) throws -> EnergyExport {
        let json: JSONValue
        do {
            json = try ExactJSON.parse(data)
        } catch let error as JSONParseError {
            throw EnergyExportError.malformedJSON(error.message)
        }
        return try ExportReader.read(json)
    }
}

public extension EnergyExport {
    /// Converts file readings to domain readings, restoring each original value from its earliest correction.
    /// The file's `kwhValue` remains the effective value, as required by §8.3.
    func importedMeterReadings() throws -> [MeterReading] {
        try meterReadings.map { reading in
            let corrections = auditCorrections
                .filter {
                    $0.entityType == AuditEntityType.meterReading.rawValue &&
                    $0.fieldName == "KwhValue" &&
                    $0.entityId == reading.id
                }
                .sorted { lhs, rhs in
                    if lhs.correctedAtUtc != rhs.correctedAtUtc {
                        return lhs.correctedAtUtc < rhs.correctedAtUtc
                    }
                    return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
                }
            let original: Decimal
            if let earliest = corrections.first {
                guard let value = exactDecimal(fromInvariantString: earliest.oldValue) else {
                    throw EnergyExportError.validationFailed([
                        ExportValidationIssue(
                            path: "auditCorrections",
                            message: "'oldValue' must be an invariant decimal string."
                        )
                    ])
                }
                original = value
            } else {
                original = reading.kwhValue
            }
            return MeterReading(
                id: reading.id,
                mainMeterID: reading.mainMeterId,
                kwhValue: original,
                readingTimestamp: reading.readingTimestamp,
                createdAt: reading.createdAtUtc
            )
        }
    }
}

internal extension EnergyExport {
    func jsonValue() -> JSONValue {
        .object([
            "formatVersion": .string(formatVersion),
            "exportedAtUtc": jsonInstant(exportedAtUtc),
            "household": household.jsonValue(),
            "householdMembers": .array(householdMembers.map { $0.jsonValue() }),
            "mainMeter": mainMeter?.jsonValue() ?? .null,
            "meterReadings": .array(meterReadings.map { $0.jsonValue() }),
            "meterRegressionPrompts": .array(meterRegressionPrompts.map { $0.jsonValue() }),
            "tariffs": .array(tariffs.map { $0.jsonValue() }),
            "events": .array(events.map { $0.jsonValue() }),
            "rooms": .array(rooms.map { $0.jsonValue() }),
            "powerPoints": .array(powerPoints.map { $0.jsonValue() }),
            "devices": .array(devices.map { $0.jsonValue() }),
            "smartPlugReadings": .array(smartPlugReadings.map { $0.jsonValue() }),
            "statusSnapshots": .array(statusSnapshots.map { $0.jsonValue() }),
            "auditCorrections": .array(auditCorrections.map { $0.jsonValue() })
        ])
    }
}

private func jsonInstant(_ date: Date) -> JSONValue { .string(ISO8601Codec.formatUTC(date)) }
private func jsonUUID(_ id: UUID) -> JSONValue { .string(id.uuidString.lowercased()) }
private func jsonNullable<T>(_ value: T?, _ transform: (T) -> JSONValue) -> JSONValue {
    value.map(transform) ?? .null
}

private extension ExportHousehold {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "createdAtUtc": jsonInstant(createdAtUtc),
            "locale": .string(locale),
            "currency": .string(currency),
            "yearlyBaselineKwh": jsonNullable(yearlyBaselineKwh) { .number($0) },
            "trendingThresholdKwh": .number(trendingThresholdKwh),
            "lowConfidenceGapDays": .number(Decimal(lowConfidenceGapDays)),
            "tariffCheckCadenceMonths": .number(Decimal(tariffCheckCadenceMonths)),
            "tariffCheckDoneAtUtc": jsonNullable(tariffCheckDoneAtUtc) { jsonInstant($0) },
            "aiPlausibilityEnabled": .bool(false),
            "aiPlausibilityBackendConfigured": .bool(false),
            "aiPlausibilityBackendLabel": .null
        ])
    }
}

private extension ExportHouseholdMember {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "displayName": jsonNullable(displayName) { .string($0) }
        ])
    }
}

private extension ExportMainMeter {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "createdAtUtc": jsonInstant(createdAtUtc),
            "digitCapacityKwh": jsonNullable(digitCapacityKwh) { .number($0) }
        ])
    }
}

private extension ExportMeterReading {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "mainMeterId": jsonUUID(mainMeterId),
            "kwhValue": .number(kwhValue),
            "readingTimestamp": jsonInstant(readingTimestamp),
            "idempotencyKey": jsonUUID(id),
            "createdAtUtc": jsonInstant(createdAtUtc)
        ])
    }
}

private extension ExportMeterRegressionPrompt {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "mainMeterId": jsonUUID(mainMeterId),
            "meterReadingId": jsonUUID(meterReadingId),
            "previousMeterReadingId": jsonUUID(previousMeterReadingId),
            "createdAtUtc": jsonInstant(createdAtUtc),
            "resolvedAtUtc": jsonNullable(resolvedAtUtc) { jsonInstant($0) },
            "classification": jsonNullable(classification) { .string($0.rawValue) },
            "digitCapacityKwh": jsonNullable(digitCapacityKwh) { .number($0) }
        ])
    }
}

private extension ExportTariff {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "monthlyBaseFee": .number(monthlyBaseFee),
            "pricePerKwh": .number(pricePerKwh),
            "currency": .string(currency),
            "contractStartDate": jsonInstant(contractStartDate.utcMidnight),
            "contractPeriodMonths": .number(Decimal(contractPeriodMonths)),
            "createdAtUtc": jsonInstant(createdAtUtc)
        ])
    }
}

private extension ExportEvent {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "description": .string(description),
            "occurredAt": jsonInstant(occurredAt),
            "createdAtUtc": jsonInstant(createdAtUtc),
            "taggedEntityType": jsonNullable(taggedEntityType) { .string($0.rawValue) },
            "taggedEntityId": jsonNullable(taggedEntityId) { jsonUUID($0) },
            "taggedEntityName": jsonNullable(taggedEntityName) { .string($0) },
            "correlationDirection": jsonNullable(correlationDirection) { .string($0.rawValue) },
            "correlationComputedAtUtc": jsonNullable(correlationComputedAtUtc) { jsonInstant($0) }
        ])
    }
}

private extension ExportRoom {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "name": .string(name),
            "createdAtUtc": jsonInstant(createdAtUtc),
            "archivedAt": jsonNullable(archivedAt) { jsonInstant($0) }
        ])
    }
}

private extension ExportPowerPoint {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "roomId": jsonUUID(roomId),
            "name": .string(name),
            "createdAtUtc": jsonInstant(createdAtUtc),
            "archivedAt": jsonNullable(archivedAt) { jsonInstant($0) }
        ])
    }
}

private extension ExportDevice {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "powerPointId": jsonUUID(powerPointId),
            "name": .string(name),
            "createdAtUtc": jsonInstant(createdAtUtc),
            "archivedAt": jsonNullable(archivedAt) { jsonInstant($0) }
        ])
    }
}

private extension ExportSmartPlugReading {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "powerPointId": jsonNullable(powerPointId) { jsonUUID($0) },
            "roomName": .string(roomName),
            "powerPointName": .string(powerPointName),
            "deviceName": .string(deviceName),
            "intervalStart": jsonInstant(intervalStart),
            "intervalEnd": jsonInstant(intervalEnd),
            "kwhValue": .number(kwhValue)
        ])
    }
}

private extension ExportStatusSnapshot {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "status": .string(status.rawValue),
            "paceToDateKwh": .number(paceToDateKwh),
            "baselineToDateKwh": .number(baselineToDateKwh),
            "isLowConfidence": .bool(isLowConfidence),
            "computedAtUtc": jsonInstant(computedAtUtc)
        ])
    }
}

private extension ExportAuditCorrection {
    func jsonValue() -> JSONValue {
        .object([
            "id": jsonUUID(id),
            "entityType": .string(entityType),
            "entityId": jsonUUID(entityId),
            "fieldName": .string(fieldName),
            "oldValue": .string(oldValue),
            "newValue": .string(newValue),
            "correctedAtUtc": jsonInstant(correctedAtUtc)
        ])
    }
}
