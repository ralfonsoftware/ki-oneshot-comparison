import Foundation

internal final class ExportReader {
    private let root: [String: JSONValue]
    private var issues: [ExportValidationIssue] = []
    private var ids: [String: Set<UUID>] = [:]

    private init(root: [String: JSONValue]) {
        self.root = root
    }

    static func read(_ json: JSONValue) throws -> EnergyExport {
        guard case .object(let root) = json else {
            throw EnergyExportError.validationFailed([
                ExportValidationIssue(path: "formatVersion", message: "must be the string 'v2'; the document must be an object.")
            ])
        }
        let reader = ExportReader(root: root)
        try reader.checkFormatVersion()
        return try reader.readDocument()
    }

    private func checkFormatVersion() throws {
        guard case .string("v2")? = root["formatVersion"] else {
            throw EnergyExportError.validationFailed([
                ExportValidationIssue(path: "formatVersion", message: "must be the string 'v2'.")
            ])
        }
    }

    private func readDocument() throws -> EnergyExport {
        let exportedAt = requiredInstant(root, "exportedAtUtc", "$")
        let household = requiredObject(root, "household", "$").flatMap { parseHousehold($0, "household") }
        let householdMembers = parseArray("householdMembers", parseHouseholdMember)
        let mainMeter = parseMainMeter()
        let meterReadings = parseArray("meterReadings", parseMeterReading)
        let prompts = parseArray("meterRegressionPrompts", parsePrompt)
        let tariffs = parseArray("tariffs", parseTariff)
        let events = parseArray("events", parseEvent)
        let rooms = parseArray("rooms", parseRoom)
        let powerPoints = parseArray("powerPoints", parsePowerPoint)
        let devices = parseArray("devices", parseDevice)
        let smartPlugReadings = parseArray("smartPlugReadings", parseSmartPlugReading)
        let snapshots = parseArray("statusSnapshots", parseSnapshot)
        let corrections = parseArray("auditCorrections", parseAuditCorrection)

        validateReferences()

        guard issues.isEmpty else { throw EnergyExportError.validationFailed(issues) }
        return EnergyExport(
            formatVersion: "v2",
            exportedAtUtc: exportedAt!.date,
            household: household!,
            householdMembers: householdMembers!,
            mainMeter: mainMeter,
            meterReadings: meterReadings!,
            meterRegressionPrompts: prompts!,
            tariffs: tariffs!,
            events: events!,
            rooms: rooms!,
            powerPoints: powerPoints!,
            devices: devices!,
            smartPlugReadings: smartPlugReadings!,
            statusSnapshots: snapshots!,
            auditCorrections: corrections!
        )
    }

    // MARK: - Entity readers

    private func parseHousehold(_ object: [String: JSONValue], _ path: String) -> ExportHousehold? {
        let id = requiredUUID(object, "id", path)
        let createdAt = requiredInstant(object, "createdAtUtc", path)
        let locale = requiredString(object, "locale", path)
        let currency = requiredString(object, "currency", path)
        let baseline = nullableDecimal(object, "yearlyBaselineKwh", path)
        let threshold = requiredDecimal(object, "trendingThresholdKwh", path)
        let gapDays = requiredInt(object, "lowConfidenceGapDays", path)
        let cadence = requiredInt(object, "tariffCheckCadenceMonths", path)
        let tariffDone: ParsedInstant?? = object["tariffCheckDoneAtUtc"] == nil ? .some(nil) : nullableInstant(object, "tariffCheckDoneAtUtc", path)
        let aiEnabled = requiredBool(object, "aiPlausibilityEnabled", path)
        let aiConfigured = requiredBool(object, "aiPlausibilityBackendConfigured", path)
        let aiLabel = nullableString(object, "aiPlausibilityBackendLabel", path)
        guard let id, let createdAt, let locale, let currency, let baseline,
              let threshold, let gapDays, let cadence, let tariffDone, let aiEnabled,
              let aiConfigured, let aiLabel else { return nil }

        if !isCurrency(currency) { issue(path, "'currency' must be a 3-letter upper-case code.") }
        if threshold < 0 { issue(path, "'trendingThresholdKwh' must be greater than or equal to 0.") }
        if !(1...365).contains(gapDays) { issue(path, "'lowConfidenceGapDays' must be in 1...365.") }
        if !(1...24).contains(cadence) { issue(path, "'tariffCheckCadenceMonths' must be in 1...24.") }

        return ExportHousehold(
            id: id,
            createdAtUtc: createdAt.date,
            locale: locale,
            currency: currency,
            yearlyBaselineKwh: baseline,
            trendingThresholdKwh: threshold,
            lowConfidenceGapDays: gapDays,
            tariffCheckCadenceMonths: cadence,
            tariffCheckDoneAtUtc: tariffDone?.date,
            aiPlausibilityEnabled: aiEnabled,
            aiPlausibilityBackendConfigured: aiConfigured,
            aiPlausibilityBackendLabel: aiLabel
        )
    }

    private func parseHouseholdMember(_ object: [String: JSONValue], _ path: String) -> ExportHouseholdMember? {
        let id = identifier(object, path, "householdMembers")
        let name = nullableString(object, "displayName", path)
        guard let id, let name else { return nil }
        return ExportHouseholdMember(id: id, displayName: name)
    }

    private func parseMainMeter() -> ExportMainMeter? {
        guard let value = root["mainMeter"] else {
            issue("$", "'mainMeter' is required.")
            return nil
        }
        if case .null = value { return nil }
        guard case .object(let object) = value else {
            issue("$", "'mainMeter' must be an object or null.")
            return nil
        }
        let path = "mainMeter"
        let id = identifier(object, path, "mainMeter")
        let createdAt = requiredInstant(object, "createdAtUtc", path)
        let capacity = nullableDecimal(object, "digitCapacityKwh", path)
        guard let id, let createdAt, let capacity else { return nil }
        return ExportMainMeter(id: id, createdAtUtc: createdAt.date, digitCapacityKwh: capacity)
    }

    private func parseMeterReading(_ object: [String: JSONValue], _ path: String) -> ExportMeterReading? {
        let id = identifier(object, path, "meterReadings")
        let meterID = requiredUUID(object, "mainMeterId", path)
        let kwh = requiredDecimal(object, "kwhValue", path)
        let timestamp = requiredInstant(object, "readingTimestamp", path)
        let idempotencyKey = requiredUUID(object, "idempotencyKey", path)
        let createdAt = requiredInstant(object, "createdAtUtc", path)
        guard let id, let meterID, let kwh, let timestamp, let idempotencyKey, let createdAt else { return nil }
        _ = idempotencyKey // Required for compatibility, deliberately ignored after validation.
        if kwh <= 0 { issue(path, "'kwhValue' must be greater than 0.") }
        return ExportMeterReading(
            id: id,
            mainMeterId: meterID,
            kwhValue: kwh,
            readingTimestamp: timestamp.date,
            idempotencyKey: id,
            createdAtUtc: createdAt.date
        )
    }

    private func parsePrompt(_ object: [String: JSONValue], _ path: String) -> ExportMeterRegressionPrompt? {
        let id = identifier(object, path, "meterRegressionPrompts")
        let meterID = requiredUUID(object, "mainMeterId", path)
        let readingID = requiredUUID(object, "meterReadingId", path)
        let previousID = requiredUUID(object, "previousMeterReadingId", path)
        let createdAt = requiredInstant(object, "createdAtUtc", path)
        let resolvedAt = nullableInstant(object, "resolvedAtUtc", path)
        let classification = nullableClassification(object, "classification", path)
        let capacity = nullableDecimal(object, "digitCapacityKwh", path)
        guard let id, let meterID, let readingID, let previousID, let createdAt,
              let resolvedAt, let classification, let capacity else { return nil }
        if capacity != nil && classification != .rollover {
            issue(path, "'digitCapacityKwh' may be set only for a rollover prompt.")
        }
        return ExportMeterRegressionPrompt(
            id: id,
            mainMeterId: meterID,
            meterReadingId: readingID,
            previousMeterReadingId: previousID,
            createdAtUtc: createdAt.date,
            resolvedAtUtc: resolvedAt?.date,
            classification: classification,
            digitCapacityKwh: capacity
        )
    }

    private func parseTariff(_ object: [String: JSONValue], _ path: String) -> ExportTariff? {
        let id = identifier(object, path, "tariffs")
        let baseFee = requiredDecimal(object, "monthlyBaseFee", path)
        let price = requiredDecimal(object, "pricePerKwh", path)
        let currency = requiredString(object, "currency", path)
        let start = requiredInstant(object, "contractStartDate", path)
        let months = requiredInt(object, "contractPeriodMonths", path)
        let createdAt = requiredInstant(object, "createdAtUtc", path)
        guard let id, let baseFee, let price, let currency, let start, let months, let createdAt else { return nil }

        let maximumBase = Decimal(string: "1000000000000000")!
        let maximumPrice = Decimal(string: "10000000000000")!
        if baseFee < 0 || baseFee >= maximumBase {
            issue(path, "'monthlyBaseFee' must be at least 0 and less than 10^15.")
        }
        if price <= 0 || price >= maximumPrice {
            issue(path, "'pricePerKwh' must be greater than 0 and less than 10^13.")
        }
        if !hasAtMostDecimalPlaces(baseFee, places: 2) { issue(path, "'monthlyBaseFee' must have at most 2 decimal places.") }
        if !hasAtMostDecimalPlaces(price, places: 4) { issue(path, "'pricePerKwh' must have at most 4 decimal places.") }
        if !isCurrency(currency) { issue(path, "'currency' must be a 3-letter upper-case code.") }
        if !(1...1_200).contains(months) { issue(path, "'contractPeriodMonths' must be in 1...1200.") }
        let earliest = CalendarDate(year: 1900, month: 1, day: 1)
        let latest = CalendarDate(year: 2200, month: 1, day: 1)
        if start.localDate < earliest || start.localDate > latest {
            issue(path, "'contractStartDate' must be between 1900-01-01 and 2200-01-01 inclusive.")
        }
        return ExportTariff(
            id: id,
            monthlyBaseFee: baseFee,
            pricePerKwh: price,
            currency: currency,
            contractStartDate: start.localDate,
            contractPeriodMonths: months,
            createdAtUtc: createdAt.date
        )
    }

    private func parseEvent(_ object: [String: JSONValue], _ path: String) -> ExportEvent? {
        let id = identifier(object, path, "events")
        let description = requiredString(object, "description", path)
        let occurredAt = requiredInstant(object, "occurredAt", path)
        let createdAt = requiredInstant(object, "createdAtUtc", path)
        let tagType = nullableTaggedEntityType(object, "taggedEntityType", path)
        let tagID = nullableUUID(object, "taggedEntityId", path)
        let tagName = nullableString(object, "taggedEntityName", path)
        let direction = nullableCorrelationDirection(object, "correlationDirection", path)
        let computedAt = nullableInstant(object, "correlationComputedAtUtc", path)
        guard let id, let description, let occurredAt, let createdAt, let tagType,
              let tagID, let tagName, let direction, let computedAt else { return nil }
        if description.isEmpty || description.count > 500 {
            issue(path, "'description' must contain 1...500 characters.")
        }
        return ExportEvent(
            id: id,
            description: description,
            occurredAt: occurredAt.date,
            createdAtUtc: createdAt.date,
            taggedEntityType: tagType,
            taggedEntityId: tagID,
            taggedEntityName: tagName,
            correlationDirection: direction,
            correlationComputedAtUtc: computedAt?.date
        )
    }

    private func parseRoom(_ object: [String: JSONValue], _ path: String) -> ExportRoom? {
        let id = identifier(object, path, "rooms")
        let name = requiredString(object, "name", path)
        let createdAt = requiredInstant(object, "createdAtUtc", path)
        let archivedAt = nullableInstant(object, "archivedAt", path)
        guard let id, let name, let createdAt, let archivedAt else { return nil }
        validateStructureName(name, path)
        return ExportRoom(id: id, name: name, createdAtUtc: createdAt.date, archivedAt: archivedAt?.date)
    }

    private func parsePowerPoint(_ object: [String: JSONValue], _ path: String) -> ExportPowerPoint? {
        let id = identifier(object, path, "powerPoints")
        let roomID = requiredUUID(object, "roomId", path)
        let name = requiredString(object, "name", path)
        let createdAt = requiredInstant(object, "createdAtUtc", path)
        let archivedAt = nullableInstant(object, "archivedAt", path)
        guard let id, let roomID, let name, let createdAt, let archivedAt else { return nil }
        validateStructureName(name, path)
        return ExportPowerPoint(
            id: id,
            roomId: roomID,
            name: name,
            createdAtUtc: createdAt.date,
            archivedAt: archivedAt?.date
        )
    }

    private func parseDevice(_ object: [String: JSONValue], _ path: String) -> ExportDevice? {
        let id = identifier(object, path, "devices")
        let powerPointID = requiredUUID(object, "powerPointId", path)
        let name = requiredString(object, "name", path)
        let createdAt = requiredInstant(object, "createdAtUtc", path)
        let archivedAt = nullableInstant(object, "archivedAt", path)
        guard let id, let powerPointID, let name, let createdAt, let archivedAt else { return nil }
        validateStructureName(name, path)
        return ExportDevice(
            id: id,
            powerPointId: powerPointID,
            name: name,
            createdAtUtc: createdAt.date,
            archivedAt: archivedAt?.date
        )
    }

    private func parseSmartPlugReading(_ object: [String: JSONValue], _ path: String) -> ExportSmartPlugReading? {
        let id = identifier(object, path, "smartPlugReadings")
        let powerPointID = nullableUUID(object, "powerPointId", path)
        let roomName = requiredString(object, "roomName", path)
        let powerPointName = requiredString(object, "powerPointName", path)
        let deviceName = requiredString(object, "deviceName", path)
        let intervalStart = requiredInstant(object, "intervalStart", path)
        let intervalEnd = requiredInstant(object, "intervalEnd", path)
        let kwh = requiredDecimal(object, "kwhValue", path)
        guard let id, let powerPointID, let roomName, let powerPointName, let deviceName,
              let intervalStart, let intervalEnd, let kwh else { return nil }
        if deviceName.count > 200 { issue(path, "'deviceName' must contain at most 200 characters.") }
        return ExportSmartPlugReading(
            id: id,
            powerPointId: powerPointID,
            roomName: roomName,
            powerPointName: powerPointName,
            deviceName: deviceName,
            intervalStart: intervalStart.date,
            intervalEnd: intervalEnd.date,
            kwhValue: kwh
        )
    }

    private func parseSnapshot(_ object: [String: JSONValue], _ path: String) -> ExportStatusSnapshot? {
        let id = identifier(object, path, "statusSnapshots")
        let status = requiredStatus(object, "status", path)
        let pace = requiredDecimal(object, "paceToDateKwh", path)
        let baseline = requiredDecimal(object, "baselineToDateKwh", path)
        let lowConfidence = requiredBool(object, "isLowConfidence", path)
        let computedAt = requiredInstant(object, "computedAtUtc", path)
        guard let id, let status, let pace, let baseline, let lowConfidence, let computedAt else { return nil }
        return ExportStatusSnapshot(
            id: id,
            status: status,
            paceToDateKwh: pace,
            baselineToDateKwh: baseline,
            isLowConfidence: lowConfidence,
            computedAtUtc: computedAt.date
        )
    }

    private func parseAuditCorrection(_ object: [String: JSONValue], _ path: String) -> ExportAuditCorrection? {
        let id = identifier(object, path, "auditCorrections")
        let entityType = requiredString(object, "entityType", path)
        let entityID = requiredUUID(object, "entityId", path)
        let fieldName = requiredString(object, "fieldName", path)
        let oldValue = requiredString(object, "oldValue", path)
        let newValue = requiredString(object, "newValue", path)
        let correctedAt = requiredInstant(object, "correctedAtUtc", path)
        guard let id, let entityType, let entityID, let fieldName, let oldValue, let newValue, let correctedAt else {
            return nil
        }
        if entityType == AuditEntityType.meterReading.rawValue && fieldName == "KwhValue" {
            if exactDecimal(fromInvariantString: oldValue) == nil {
                issue(path, "'oldValue' must be an invariant decimal string for a KwhValue correction.")
            }
            if exactDecimal(fromInvariantString: newValue) == nil {
                issue(path, "'newValue' must be an invariant decimal string for a KwhValue correction.")
            }
        }
        return ExportAuditCorrection(
            id: id,
            entityType: entityType,
            entityId: entityID,
            fieldName: fieldName,
            oldValue: oldValue,
            newValue: newValue,
            correctedAtUtc: correctedAt.date
        )
    }

    // MARK: - References

    private func validateReferences() {
        for (index, object) in rawObjects("meterReadings") {
            reference(object, "mainMeterId", "meterReadings[\(index)]", "mainMeter")
        }
        for (index, object) in rawObjects("meterRegressionPrompts") {
            let path = "meterRegressionPrompts[\(index)]"
            reference(object, "mainMeterId", path, "mainMeter")
            reference(object, "meterReadingId", path, "meterReadings")
            reference(object, "previousMeterReadingId", path, "meterReadings")
        }
        for (index, object) in rawObjects("powerPoints") {
            reference(object, "roomId", "powerPoints[\(index)]", "rooms")
        }
        for (index, object) in rawObjects("devices") {
            reference(object, "powerPointId", "devices[\(index)]", "powerPoints")
        }
        for (index, object) in rawObjects("smartPlugReadings") {
            guard let value = object["powerPointId"], value.isNull == false else { continue }
            reference(object, "powerPointId", "smartPlugReadings[\(index)]", "powerPoints")
        }
        for (index, object) in rawObjects("events") {
            let path = "events[\(index)]"
            guard let idValue = object["taggedEntityId"], !idValue.isNull,
                  case .string(let idString) = idValue, UUID(uuidString: idString) != nil else { continue }
            guard let typeValue = object["taggedEntityType"], !typeValue.isNull else {
                issue(path, "'taggedEntityId' requires 'taggedEntityType' so its reference can be resolved.")
                continue
            }
            guard case .string(let typeString) = typeValue,
                  let type = ExportTaggedEntityType(rawValue: typeString) else { continue }
            let collection: String
            switch type {
            case .room: collection = "rooms"
            case .powerPoint: collection = "powerPoints"
            case .device: collection = "devices"
            }
            reference(object, "taggedEntityId", path, collection)
        }
    }

    private func reference(_ object: [String: JSONValue], _ key: String, _ path: String, _ collection: String) {
        guard case .string(let string)? = object[key], let id = UUID(uuidString: string) else { return }
        if ids[collection]?.contains(id) != true {
            issue(path, "'\(key)' does not reference an id in \(collection).")
        }
    }

    private func rawObjects(_ key: String) -> [(Int, [String: JSONValue])] {
        guard case .array(let values)? = root[key] else { return [] }
        return values.enumerated().compactMap { index, value in
            if case .object(let object) = value { return (index, object) }
            return nil
        }
    }

    // MARK: - Typed properties

    private func parseArray<T>(
        _ key: String,
        _ parse: ([String: JSONValue], String) -> T?
    ) -> [T]? {
        guard let value = root[key] else {
            issue("$", "'\(key)' is required.")
            return nil
        }
        guard case .array(let array) = value else {
            issue("$", "'\(key)' must be an array.")
            return nil
        }
        var result: [T] = []
        for (index, value) in array.enumerated() {
            let path = "\(key)[\(index)]"
            guard case .object(let object) = value else {
                issue(path, "must be an object.")
                continue
            }
            if let item = parse(object, path) { result.append(item) }
        }
        return result
    }

    private func identifier(_ object: [String: JSONValue], _ path: String, _ collection: String) -> UUID? {
        guard let id = requiredUUID(object, "id", path) else { return nil }
        var collectionIDs = ids[collection] ?? []
        if collectionIDs.contains(id) {
            issue(path, "'id' appears more than once in \(collection).")
        } else {
            collectionIDs.insert(id)
            ids[collection] = collectionIDs
        }
        return id
    }

    private func requiredObject(_ object: [String: JSONValue], _ key: String, _ path: String) -> [String: JSONValue]? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        guard case .object(let result) = value else {
            issue(path, "'\(key)' must be an object.")
            return nil
        }
        return result
    }

    private func requiredString(_ object: [String: JSONValue], _ key: String, _ path: String) -> String? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        guard case .string(let result) = value else {
            issue(path, "'\(key)' must be a string.")
            return nil
        }
        return result
    }

    private func nullableString(_ object: [String: JSONValue], _ key: String, _ path: String) -> String?? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        if case .null = value { return .some(nil) }
        guard case .string(let result) = value else {
            issue(path, "'\(key)' must be a string or null.")
            return nil
        }
        return .some(result)
    }

    private func requiredUUID(_ object: [String: JSONValue], _ key: String, _ path: String) -> UUID? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        guard case .string(let string) = value else {
            issue(path, "'\(key)' must be a UUID string.")
            return nil
        }
        guard let id = UUID(uuidString: string) else {
            issue(path, "'\(key)' must be a valid UUID string.")
            return nil
        }
        return id
    }

    private func nullableUUID(_ object: [String: JSONValue], _ key: String, _ path: String) -> UUID?? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        if case .null = value { return .some(nil) }
        guard case .string(let string) = value, let id = UUID(uuidString: string) else {
            issue(path, "'\(key)' must be a UUID string or null.")
            return nil
        }
        return .some(id)
    }

    private func requiredDecimal(_ object: [String: JSONValue], _ key: String, _ path: String) -> Decimal? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        guard case .number(let result) = value else {
            issue(path, "'\(key)' must be a number.")
            return nil
        }
        return result
    }

    private func nullableDecimal(_ object: [String: JSONValue], _ key: String, _ path: String) -> Decimal?? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        if case .null = value { return .some(nil) }
        guard case .number(let result) = value else {
            issue(path, "'\(key)' must be a number or null.")
            return nil
        }
        return .some(result)
    }

    private func requiredInt(_ object: [String: JSONValue], _ key: String, _ path: String) -> Int? {
        guard let decimal = requiredDecimal(object, key, path) else { return nil }
        let string = decimalString(decimal)
        guard let result = Int(string), Decimal(result) == decimal else {
            issue(path, "'\(key)' must be an integer.")
            return nil
        }
        return result
    }

    private func requiredBool(_ object: [String: JSONValue], _ key: String, _ path: String) -> Bool? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        guard case .bool(let result) = value else {
            issue(path, "'\(key)' must be a boolean.")
            return nil
        }
        return result
    }

    private func requiredInstant(_ object: [String: JSONValue], _ key: String, _ path: String) -> ParsedInstant? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        guard case .string(let string) = value else {
            issue(path, "'\(key)' must be an ISO 8601 string with explicit offset.")
            return nil
        }
        guard let result = ISO8601Codec.parse(string) else {
            issue(path, "'\(key)' must be a valid ISO 8601 instant with explicit offset.")
            return nil
        }
        return result
    }

    private func nullableInstant(_ object: [String: JSONValue], _ key: String, _ path: String) -> ParsedInstant?? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        if case .null = value { return .some(nil) }
        guard case .string(let string) = value, let result = ISO8601Codec.parse(string) else {
            issue(path, "'\(key)' must be an ISO 8601 instant with explicit offset or null.")
            return nil
        }
        return .some(result)
    }

    private func requiredStatus(_ object: [String: JSONValue], _ key: String, _ path: String) -> ConsumptionStatus? {
        guard let string = requiredString(object, key, path) else { return nil }
        guard let result = ConsumptionStatus(rawValue: string.lowercased()) else {
            issue(path, "'\(key)' has an unknown status value.")
            return nil
        }
        return result
    }

    private func nullableClassification(
        _ object: [String: JSONValue],
        _ key: String,
        _ path: String
    ) -> RegressionClassification?? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        if case .null = value { return .some(nil) }
        guard case .string(let string) = value else {
            issue(path, "'\(key)' must be 'reset', 'rollover', or null.")
            return nil
        }
        guard let result = RegressionClassification(rawValue: string.lowercased()) else {
            issue(path, "'\(key)' has an unknown classification value.")
            return nil
        }
        return .some(result)
    }

    private func nullableTaggedEntityType(
        _ object: [String: JSONValue],
        _ key: String,
        _ path: String
    ) -> ExportTaggedEntityType?? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        if case .null = value { return .some(nil) }
        guard case .string(let string) = value, let result = ExportTaggedEntityType(rawValue: string) else {
            issue(path, "'\(key)' must be 'Room', 'PowerPoint', 'Device', or null.")
            return nil
        }
        return .some(result)
    }

    private func nullableCorrelationDirection(
        _ object: [String: JSONValue],
        _ key: String,
        _ path: String
    ) -> ExportCorrelationDirection?? {
        guard let value = object[key] else {
            issue(path, "'\(key)' is required.")
            return nil
        }
        if case .null = value { return .some(nil) }
        guard case .string(let string) = value, let result = ExportCorrelationDirection(rawValue: string) else {
            issue(path, "'\(key)' must be 'Bump', 'Dip', or null.")
            return nil
        }
        return .some(result)
    }

    // MARK: - Small domain checks

    private func validateStructureName(_ name: String, _ path: String) {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issue(path, "'name' must not be empty.")
        } else if name.count > 200 {
            issue(path, "'name' must contain at most 200 characters.")
        }
    }

    private func hasAtMostDecimalPlaces(_ value: Decimal, places: Int) -> Bool {
        guard let canonical = CanonicalDecimal(decimalString(value)) else { return false }
        return max(0, -canonical.exponent) <= places
    }

    private func isCurrency(_ currency: String) -> Bool {
        currency.count == 3 && currency.utf8.allSatisfy { $0 >= 65 && $0 <= 90 }
    }

    private func issue(_ path: String, _ message: String) {
        issues.append(ExportValidationIssue(path: path, message: message))
    }
}

private extension JSONValue {
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}
