import Foundation

/// Import validation failure: the whole file is rejected (§8.4).
public struct ImportValidationError: Error, Sendable, CustomStringConvertible {
    public var failures: [String]

    public init(failures: [String]) {
        self.failures = failures
    }

    public var description: String { failures.joined(separator: "\n") }

    /// First 200 failures, then "… and N more" (FR-20).
    public func displayLines(limit: Int = 200) -> [String] {
        guard failures.count > limit else { return failures }
        return Array(failures.prefix(limit)) + ["… and \(failures.count - limit) more"]
    }
}

/// Reads and writes the v2 export file (§8).
public enum ExportFormat {
    public static let formatVersion = "v2"

    public static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        "energy-tracker-export-\(CalendarDate(date: date, timeZone: timeZone).iso).json"
    }

    // MARK: Decode

    public static func decode(_ data: Data) throws(ImportValidationError) -> DataSetRecords {
        let root: JSONValue
        do {
            root = try JSONParser.parse(data)
        } catch let error as JSONSyntaxError {
            throw ImportValidationError(failures: [error.description])
        } catch {
            throw ImportValidationError(failures: ["The file is not valid JSON."])
        }
        guard case .object(let top) = root else {
            throw ImportValidationError(failures: ["The file must contain a JSON object."])
        }
        // Rule 1 first; nothing else is reported when it fails.
        guard case .string(let version)? = top["formatVersion"], version == formatVersion else {
            throw ImportValidationError(failures: ["'formatVersion' must be \"v2\"."])
        }
        var decoder = Decoder()
        let records = decoder.decode(top)
        if !decoder.failures.isEmpty || records == nil {
            throw ImportValidationError(failures: decoder.failures.isEmpty ? ["The file could not be read."] : decoder.failures)
        }
        return records!
    }

    private struct Decoder {
        var failures: [String] = []

        mutating func fail(_ path: String, _ message: String) { failures.append("\(path): \(message)") }

        // MARK: Typed readers. Each records a failure and returns nil on a problem.

        struct Obj {
            var object: JSONObject
            var path: String
        }

        mutating func value(_ o: Obj, _ key: String, nullable: Bool) -> JSONValue?? {
            guard let v = o.object[key] else {
                if nullable { return .some(nil) }
                fail(o.path, "'\(key)' is missing.")
                return nil
            }
            if case .null = v {
                if nullable { return .some(nil) }
                fail(o.path, "'\(key)' must not be null.")
                return nil
            }
            return .some(v)
        }

        mutating func string(_ o: Obj, _ key: String) -> String? {
            guard let v = value(o, key, nullable: false), let v else { return nil }
            guard case .string(let s) = v else { fail(o.path, "'\(key)' must be a string."); return nil }
            return s
        }

        mutating func optionalString(_ o: Obj, _ key: String) -> String?? {
            guard let v = value(o, key, nullable: true) else { return nil }
            guard let v else { return .some(nil) }
            guard case .string(let s) = v else { fail(o.path, "'\(key)' must be a string or null."); return nil }
            return .some(s)
        }

        mutating func uuid(_ o: Obj, _ key: String) -> UUID? {
            guard let v = value(o, key, nullable: false), let v else { return nil }
            guard case .string(let s) = v, let id = UUID(uuidString: s) else { fail(o.path, "'\(key)' must be a UUID string."); return nil }
            return id
        }

        mutating func optionalUUID(_ o: Obj, _ key: String) -> UUID?? {
            guard let v = value(o, key, nullable: true) else { return nil }
            guard let v else { return .some(nil) }
            guard case .string(let s) = v, let id = UUID(uuidString: s) else { fail(o.path, "'\(key)' must be a UUID string or null."); return nil }
            return .some(id)
        }

        mutating func instant(_ o: Obj, _ key: String) -> Date? {
            guard let v = value(o, key, nullable: false), let v else { return nil }
            guard case .string(let s) = v, let date = Instant.parse(s) else { fail(o.path, "'\(key)' must be an ISO 8601 instant with offset."); return nil }
            return date
        }

        mutating func optionalInstant(_ o: Obj, _ key: String) -> Date?? {
            guard let v = value(o, key, nullable: true) else { return nil }
            guard let v else { return .some(nil) }
            guard case .string(let s) = v, let date = Instant.parse(s) else { fail(o.path, "'\(key)' must be an ISO 8601 instant with offset or null."); return nil }
            return .some(date)
        }

        mutating func decimal(_ o: Obj, _ key: String) -> Decimal? {
            guard let v = value(o, key, nullable: false), let v else { return nil }
            guard case .number(let n) = v, let d = DecimalMath.parse(n) else { fail(o.path, "'\(key)' must be a number."); return nil }
            return d
        }

        mutating func optionalDecimal(_ o: Obj, _ key: String) -> Decimal?? {
            guard let v = value(o, key, nullable: true) else { return nil }
            guard let v else { return .some(nil) }
            guard case .number(let n) = v, let d = DecimalMath.parse(n) else { fail(o.path, "'\(key)' must be a number or null."); return nil }
            return .some(d)
        }

        mutating func int(_ o: Obj, _ key: String) -> Int? {
            guard let v = value(o, key, nullable: false), let v else { return nil }
            guard case .number(let n) = v, let d = DecimalMath.parse(n), d == DecimalMath.rounded(d, scale: 0),
                  d >= Decimal(Int32.min), d <= Decimal(Int32.max) else { fail(o.path, "'\(key)' must be an integer."); return nil }
            return NSDecimalNumber(decimal: d).intValue
        }

        mutating func bool(_ o: Obj, _ key: String) -> Bool? {
            guard let v = value(o, key, nullable: false), let v else { return nil }
            guard case .bool(let b) = v else { fail(o.path, "'\(key)' must be a boolean."); return nil }
            return b
        }

        mutating func objects(_ top: JSONObject, _ key: String) -> [Obj] {
            guard let v = top[key] else { fail("(root)", "'\(key)' is missing."); return [] }
            guard case .array(let items) = v else { fail("(root)", "'\(key)' must be an array."); return [] }
            var result: [Obj] = []
            for (i, item) in items.enumerated() {
                let path = "\(key)[\(i)]"
                guard case .object(let o) = item else { fail(path, "must be an object."); continue }
                result.append(Obj(object: o, path: path))
            }
            return result
        }

        mutating func checkUniqueIds(_ key: String, _ items: [(path: String, id: UUID)]) {
            var seen: [UUID: String] = [:]
            for item in items {
                if let first = seen[item.id] {
                    fail(item.path, "id \(item.id.uuidString.lowercased()) appears twice in '\(key)' (first at \(first)).")
                } else {
                    seen[item.id] = item.path
                }
            }
        }

        // MARK: Whole document

        mutating func decode(_ top: JSONObject) -> DataSetRecords? {
            let exportedAt = instant(Obj(object: top, path: "(root)"), "exportedAtUtc") ?? Date(timeIntervalSince1970: 0)

            // Household
            var household: HouseholdRecord?
            if let hv = top["household"] {
                if case .object(let ho) = hv {
                    household = decodeHousehold(Obj(object: ho, path: "household"))
                } else {
                    fail("(root)", "'household' must be an object.")
                }
            } else {
                fail("(root)", "'household' is missing.")
            }
            // householdMembers is ignored on read, including any identity fields older files carry.

            // Main Meter
            var mainMeter: MainMeterRecord?
            switch top["mainMeter"] {
            case .none, .some(.null): mainMeter = nil
            case .some(.object(let mo)):
                let o = Obj(object: mo, path: "mainMeter")
                let id = uuid(o, "id"), created = instant(o, "createdAtUtc"), capacity = optionalDecimal(o, "digitCapacityKwh")
                if let id, let created, let capacity {
                    if let c = capacity, c <= 0 { fail(o.path, "'digitCapacityKwh' must be greater than 0.") }
                    mainMeter = MainMeterRecord(id: id, createdAt: created, digitCapacityKwh: capacity)
                }
            default: fail("(root)", "'mainMeter' must be an object or null.")
            }

            let readingObjs = objects(top, "meterReadings")
            let promptObjs = objects(top, "meterRegressionPrompts")
            let tariffObjs = objects(top, "tariffs")
            let eventObjs = objects(top, "events")
            let roomObjs = objects(top, "rooms")
            let pointObjs = objects(top, "powerPoints")
            let deviceObjs = objects(top, "devices")
            let plugObjs = objects(top, "smartPlugReadings")
            let snapshotObjs = objects(top, "statusSnapshots")
            let correctionObjs = objects(top, "auditCorrections")

            // Corrections first: readings need them to compute original values.
            var corrections: [CorrectionRecord] = []
            var correctionIds: [(String, UUID)] = []
            for o in correctionObjs {
                let id = uuid(o, "id"), type = string(o, "entityType"), entityId = uuid(o, "entityId"), field = string(o, "fieldName"),
                    old = string(o, "oldValue"), new = string(o, "newValue"), at = instant(o, "correctedAtUtc")
                if let id { correctionIds.append((o.path, id)) }
                if let id, let type, let entityId, let field, let old, let new, let at {
                    corrections.append(CorrectionRecord(id: id, entityType: type, entityId: entityId, fieldName: field, oldValue: old, newValue: new, correctedAt: at))
                }
            }
            checkUniqueIds("auditCorrections", correctionIds)

            // Earliest KwhValue correction per reading -> original value (§8.3).
            var earliestCorrection: [UUID: CorrectionRecord] = [:]
            for c in corrections where c.entityType == AuditEntityType.meterReading && c.fieldName == AuditField.kwhValue {
                if let e = earliestCorrection[c.entityId], (e.correctedAt, idKey(e.id)) <= (c.correctedAt, idKey(c.id)) { continue }
                earliestCorrection[c.entityId] = c
            }

            var readings: [ReadingRecord] = []
            var readingIds: [(String, UUID)] = []
            for o in readingObjs {
                let id = uuid(o, "id"), meterId = uuid(o, "mainMeterId"), kwh = decimal(o, "kwhValue"), ts = instant(o, "readingTimestamp"), created = instant(o, "createdAtUtc")
                if let id { readingIds.append((o.path, id)) }
                if let meterId {
                    if mainMeter == nil { fail(o.path, "'mainMeterId' does not resolve: 'mainMeter' is null.") }
                    else if mainMeter?.id != meterId { fail(o.path, "'mainMeterId' does not match 'mainMeter.id'.") }
                }
                if let kwh, kwh <= 0 { fail(o.path, "'kwhValue' must be greater than 0.") }
                if let id, let meterId, let kwh, let ts, let created {
                    var original = kwh
                    if let first = earliestCorrection[id] {
                        if let old = DecimalMath.parse(first.oldValue) { original = old }
                        else { fail("auditCorrections", "correction \(idKey(first.id)) has an 'oldValue' that is not a number.") }
                    }
                    readings.append(ReadingRecord(id: id, mainMeterId: meterId, originalKwhValue: original, effectiveKwhValue: kwh, readingTimestamp: ts, createdAt: created))
                }
            }
            checkUniqueIds("meterReadings", readingIds)
            let fileReadingIds = Set(readingIds.map(\.1))

            var prompts: [PromptRecord] = []
            var promptIds: [(String, UUID)] = []
            for o in promptObjs {
                let id = uuid(o, "id"), meterId = uuid(o, "mainMeterId"), readingId = uuid(o, "meterReadingId"), prevId = uuid(o, "previousMeterReadingId"),
                    created = instant(o, "createdAtUtc"), resolved = optionalInstant(o, "resolvedAtUtc"), capacity = optionalDecimal(o, "digitCapacityKwh")
                var classification: RegressionClassification?? = .some(nil)
                switch o.object["classification"] {
                case .none, .some(.null): classification = .some(nil)
                case .some(.string(let s)):
                    if let c = RegressionClassification(rawValue: s.lowercased()) { classification = .some(c) }
                    else { fail(o.path, "'classification' must be one of \"reset\", \"rollover\" or null."); classification = nil }
                default: fail(o.path, "'classification' must be a string or null."); classification = nil
                }
                if let id { promptIds.append((o.path, id)) }
                if let meterId, mainMeter?.id != meterId { fail(o.path, "'mainMeterId' does not match 'mainMeter.id'.") }
                if let readingId, !fileReadingIds.contains(readingId) { fail(o.path, "'meterReadingId' does not reference a meter reading.") }
                if let prevId, !fileReadingIds.contains(prevId) { fail(o.path, "'previousMeterReadingId' does not reference a meter reading.") }
                if let capacity, let c = capacity {
                    if case .some(.some(.rollover)) = classification {
                        if c <= 0 { fail(o.path, "'digitCapacityKwh' must be greater than 0.") }
                    } else {
                        fail(o.path, "'digitCapacityKwh' is only allowed for a rollover.")
                    }
                }
                if let id, let meterId, let readingId, let prevId, let created, let resolved, let classification, let capacity {
                    prompts.append(PromptRecord(id: id, mainMeterId: meterId, meterReadingId: readingId, previousMeterReadingId: prevId, createdAt: created, resolvedAt: resolved, classification: classification, digitCapacityKwh: capacity))
                }
            }
            checkUniqueIds("meterRegressionPrompts", promptIds)

            var tariffs: [TariffRecord] = []
            var tariffIds: [(String, UUID)] = []
            for o in tariffObjs {
                let id = uuid(o, "id"), fee = decimal(o, "monthlyBaseFee"), price = decimal(o, "pricePerKwh"), currency = string(o, "currency"),
                    period = int(o, "contractPeriodMonths"), created = instant(o, "createdAtUtc")
                var start: CalendarDate?
                if let raw = string(o, "contractStartDate") {
                    if let parsed = Instant.parseWithLocalDate(raw) { start = parsed.localDate }
                    else { fail(o.path, "'contractStartDate' must be an ISO 8601 instant with offset.") }
                }
                if let id { tariffIds.append((o.path, id)) }
                if let fee, let price, let currency, let period, let start {
                    for error in Validation.validateTariff(monthlyBaseFee: fee, pricePerKwh: price, currency: currency, contractPeriodMonths: period, startDate: start) {
                        switch error {
                        case .baseFeeOutOfRange: fail(o.path, "'monthlyBaseFee' must be at least 0 and less than 10^15.")
                        case .priceOutOfRange: fail(o.path, "'pricePerKwh' must be greater than 0 and less than 10^13.")
                        case .currencyInvalid: fail(o.path, "'currency' must be a 3-letter upper-case code.")
                        case .periodOutOfRange: fail(o.path, "'contractPeriodMonths' must be between 1 and 1200.")
                        case .startDateOutOfRange: fail(o.path, "'contractStartDate' must be between 1900-01-01 and 2200-01-01.")
                        }
                    }
                    if let id, let created {
                        tariffs.append(TariffRecord(id: id, monthlyBaseFee: fee, pricePerKwh: price, currency: currency, contractStartDate: start, contractPeriodMonths: period, createdAt: created))
                    }
                }
            }
            checkUniqueIds("tariffs", tariffIds)

            // References resolve against every id present in the file, so one bad record is reported once.
            func ids(_ objs: [Obj]) -> Set<UUID> {
                Set(objs.compactMap { o -> UUID? in if case .string(let s)? = o.object["id"] { return UUID(uuidString: s) }; return nil })
            }
            let roomIds = ids(roomObjs), pointIds = ids(pointObjs), deviceIds = ids(deviceObjs)
            let rooms = decodeStructure(roomObjs, key: "rooms", parentKey: nil, parents: [])
            let points = decodeStructure(pointObjs, key: "powerPoints", parentKey: "roomId", parents: roomIds)
            let devices = decodeStructure(deviceObjs, key: "devices", parentKey: "powerPointId", parents: pointIds)

            var events: [EventRecord] = []
            var eventIds: [(String, UUID)] = []
            for o in eventObjs {
                let id = uuid(o, "id"), desc = string(o, "description"), at = instant(o, "occurredAt"), created = instant(o, "createdAtUtc"),
                    tagId = optionalUUID(o, "taggedEntityId"), tagName = optionalString(o, "taggedEntityName")
                let updated = o.object.has("updatedAtUtc") ? optionalInstant(o, "updatedAtUtc") : .some(nil)
                var tagType: TaggedEntityType?? = .some(nil)
                switch o.object["taggedEntityType"] {
                case .none, .some(.null): tagType = .some(nil)
                case .some(.string(let s)):
                    if let t = TaggedEntityType(rawValue: s) { tagType = .some(t) }
                    else { fail(o.path, "'taggedEntityType' must be one of \"Room\", \"PowerPoint\", \"Device\" or null."); tagType = nil }
                default: fail(o.path, "'taggedEntityType' must be a string or null."); tagType = nil
                }
                if let id { eventIds.append((o.path, id)) }
                if let desc, Validation.normalizedEventDescription(desc) == nil { fail(o.path, "'description' must be 1 to 500 characters.") }
                if let tagId, let t = tagId {
                    switch tagType {
                    case .some(.some(.room)): if !roomIds.contains(t) { fail(o.path, "'taggedEntityId' does not reference a room.") }
                    case .some(.some(.powerPoint)): if !pointIds.contains(t) { fail(o.path, "'taggedEntityId' does not reference a power point.") }
                    case .some(.some(.device)): if !deviceIds.contains(t) { fail(o.path, "'taggedEntityId' does not reference a device.") }
                    case .some(.none): fail(o.path, "'taggedEntityId' is set but 'taggedEntityType' is null.")
                    case .none: break
                    }
                }
                if let id, let desc, let at, let created, let tagId, let tagName, let tagType, let updated {
                    events.append(EventRecord(id: id, description: desc, occurredAt: at, createdAt: created, updatedAt: updated ?? created, taggedEntityType: tagType, taggedEntityId: tagId, taggedEntityName: tagName))
                }
            }
            checkUniqueIds("events", eventIds)

            var plugs: [SmartPlugReadingRecord] = []
            var plugIds: [(String, UUID)] = []
            for o in plugObjs {
                let id = uuid(o, "id"), pointId = optionalUUID(o, "powerPointId"), room = string(o, "roomName"), point = string(o, "powerPointName"),
                    device = string(o, "deviceName"), start = instant(o, "intervalStart"), end = instant(o, "intervalEnd"), kwh = decimal(o, "kwhValue")
                if let id { plugIds.append((o.path, id)) }
                if let pointId, let p = pointId, !pointIds.contains(p) { fail(o.path, "'powerPointId' does not reference a power point.") }
                if let device, device.count > 200 { fail(o.path, "'deviceName' must be at most 200 characters.") }
                if let id, let pointId, let room, let point, let device, let start, let end, let kwh {
                    plugs.append(SmartPlugReadingRecord(id: id, powerPointId: pointId, roomName: room, powerPointName: point, deviceName: device, intervalStart: start, intervalEnd: end, kwhValue: kwh))
                }
            }
            checkUniqueIds("smartPlugReadings", plugIds)

            var snapshots: [SnapshotRecord] = []
            var snapshotIds: [(String, UUID)] = []
            for o in snapshotObjs {
                let id = uuid(o, "id"), pace = decimal(o, "paceToDateKwh"), baseline = decimal(o, "baselineToDateKwh"), low = bool(o, "isLowConfidence"), at = instant(o, "computedAtUtc")
                let cause = o.object.has("causeId") ? optionalUUID(o, "causeId") : .some(nil)
                var status: EnergyStatus?
                if let raw = string(o, "status") {
                    status = EnergyStatus(fileValue: raw)
                    if status == nil { fail(o.path, "'status' must be one of \"withinrange\", \"belowbaseline\", \"trending\".") }
                }
                if let id { snapshotIds.append((o.path, id)) }
                if let id, let pace, let baseline, let low, let at, let status, let cause {
                    snapshots.append(SnapshotRecord(id: id, status: status, paceToDateKwh: pace, baselineToDateKwh: baseline, isLowConfidence: low, computedAt: at, causeId: cause ?? id))
                }
            }
            checkUniqueIds("statusSnapshots", snapshotIds)

            guard let household, failures.isEmpty else { return nil }
            var records = DataSetRecords(exportedAt: exportedAt, household: household, mainMeter: mainMeter)
            records.readings = readings
            records.prompts = prompts
            records.tariffs = tariffs
            records.events = events
            records.rooms = rooms
            records.powerPoints = points
            records.devices = devices
            records.smartPlugReadings = plugs
            records.snapshots = snapshots
            records.corrections = corrections
            return records
        }

        mutating func decodeHousehold(_ o: Obj) -> HouseholdRecord? {
            let id = uuid(o, "id"), created = instant(o, "createdAtUtc"), locale = string(o, "locale"), currency = string(o, "currency"),
                baseline = optionalDecimal(o, "yearlyBaselineKwh"), threshold = decimal(o, "trendingThresholdKwh"),
                gap = int(o, "lowConfidenceGapDays"), cadence = int(o, "tariffCheckCadenceMonths")
            let done = o.object.has("tariffCheckDoneAtUtc") ? optionalInstant(o, "tariffCheckDoneAtUtc") : .some(nil)
            if let currency, !Validation.isCurrencyCode(currency) { fail(o.path, "'currency' must be a 3-letter upper-case code.") }
            if let baseline, let b = baseline, b < 0 { fail(o.path, "'yearlyBaselineKwh' must not be negative.") }
            if let threshold, threshold < 0 { fail(o.path, "'trendingThresholdKwh' must not be negative.") }
            if let gap, !Validation.gapDaysRange.contains(gap) { fail(o.path, "'lowConfidenceGapDays' must be between 1 and 365.") }
            if let cadence, !Validation.cadenceRange.contains(cadence) { fail(o.path, "'tariffCheckCadenceMonths' must be between 1 and 24.") }
            guard let id, let created, let locale, let currency, let baseline, let threshold, let gap, let cadence, let done else { return nil }
            return HouseholdRecord(id: id, createdAt: created, locale: locale, currency: currency, yearlyBaselineKwh: baseline, trendingThresholdKwh: threshold, lowConfidenceGapDays: gap, tariffCheckCadenceMonths: cadence, tariffCheckDoneAt: done)
        }

        mutating func decodeStructure(_ objs: [Obj], key: String, parentKey: String?, parents: Set<UUID>) -> [StructureRecord] {
            var result: [StructureRecord] = []
            var ids: [(String, UUID)] = []
            for o in objs {
                let id = uuid(o, "id"), name = string(o, "name"), created = instant(o, "createdAtUtc"), archived = optionalInstant(o, "archivedAt")
                var parent: UUID?? = .some(nil)
                if let parentKey {
                    if let p = uuid(o, parentKey) {
                        parent = .some(p)
                        if !parents.contains(p) {
                            fail(o.path, "'\(parentKey)' does not reference \(parentKey == "roomId" ? "a room" : "a power point").")
                        }
                    } else {
                        parent = nil
                    }
                }
                if let id { ids.append((o.path, id)) }
                var normalized: String?
                if let name {
                    normalized = Validation.normalizedName(name)
                    if normalized == nil { fail(o.path, "'name' must be 1 to 200 characters.") }
                }
                if let id, let normalized, let created, let archived, let parent {
                    result.append(StructureRecord(id: id, name: normalized, createdAt: created, archivedAt: archived, parentId: parent))
                }
            }
            checkUniqueIds(key, ids)
            return result
        }
    }

    // MARK: Encode

    public static func encode(_ records: DataSetRecords) -> Data {
        JSONWriter.write(.object(document(records)))
    }

    static func num(_ d: Decimal) -> JSONValue { .number(DecimalMath.string(d)) }
    static func num(_ i: Int) -> JSONValue { .number(String(i)) }
    static func str(_ s: String) -> JSONValue { .string(s) }
    static func id(_ u: UUID) -> JSONValue { .string(u.uuidString.lowercased()) }
    static func id(_ u: UUID?) -> JSONValue { u.map { .string($0.uuidString.lowercased()) } ?? .null }
    static func time(_ d: Date) -> JSONValue { .string(Instant.format(d)) }
    static func time(_ d: Date?) -> JSONValue { d.map { .string(Instant.format($0)) } ?? .null }
    static func optNum(_ d: Decimal?) -> JSONValue { d.map(num) ?? .null }
    static func optStr(_ s: String?) -> JSONValue { s.map(JSONValue.string) ?? .null }

    static func document(_ r: DataSetRecords) -> JSONObject {
        let h = r.household
        let household = JSONObject([
            ("id", id(h.id)),
            ("createdAtUtc", time(h.createdAt)),
            ("locale", str(h.locale)),
            ("currency", str(h.currency)),
            ("yearlyBaselineKwh", optNum(h.yearlyBaselineKwh)),
            ("trendingThresholdKwh", num(h.trendingThresholdKwh)),
            ("lowConfidenceGapDays", num(h.lowConfidenceGapDays)),
            ("tariffCheckCadenceMonths", num(h.tariffCheckCadenceMonths)),
            ("aiPlausibilityEnabled", .bool(false)),
            ("aiPlausibilityBackendConfigured", .bool(false)),
            ("aiPlausibilityBackendLabel", .null),
            // Extension: not in the old format, ignored by older readers (§8.1 unknown properties).
            ("tariffCheckDoneAtUtc", time(h.tariffCheckDoneAt)),
        ])
        let meter: JSONValue = r.mainMeter.map { m in
            .object(JSONObject([("id", id(m.id)), ("createdAtUtc", time(m.createdAt)), ("digitCapacityKwh", optNum(m.digitCapacityKwh))]))
        } ?? .null

        let readings = r.readings.sorted { ($0.readingTimestamp, idKey($0.id)) < ($1.readingTimestamp, idKey($1.id)) }.map { x in
            JSONValue.object(JSONObject([
                ("id", id(x.id)), ("mainMeterId", id(x.mainMeterId)), ("kwhValue", num(x.effectiveKwhValue)),
                ("readingTimestamp", time(x.readingTimestamp)), ("idempotencyKey", id(x.id)), ("createdAtUtc", time(x.createdAt)),
            ]))
        }
        let prompts = r.prompts.map { p in
            JSONValue.object(JSONObject([
                ("id", id(p.id)), ("mainMeterId", id(p.mainMeterId)), ("meterReadingId", id(p.meterReadingId)),
                ("previousMeterReadingId", id(p.previousMeterReadingId)), ("createdAtUtc", time(p.createdAt)),
                ("resolvedAtUtc", time(p.resolvedAt)), ("classification", optStr(p.classification?.rawValue)),
                ("digitCapacityKwh", p.classification == .rollover ? optNum(p.digitCapacityKwh) : .null),
            ]))
        }
        let tariffs = r.tariffs.map { t in
            JSONValue.object(JSONObject([
                ("id", id(t.id)), ("monthlyBaseFee", num(t.monthlyBaseFee)), ("pricePerKwh", num(t.pricePerKwh)), ("currency", str(t.currency)),
                ("contractStartDate", str(Instant.format(t.contractStartDate))), ("contractPeriodMonths", num(t.contractPeriodMonths)),
                ("createdAtUtc", time(t.createdAt)),
            ]))
        }
        let events = r.events.map { e in
            let direction: JSONValue = switch e.exportDeviation {
            case .bump: str("Bump")
            case .dip: str("Dip")
            default: .null
            }
            let directionSet: Bool = if case .string = direction { true } else { false }
            return JSONValue.object(JSONObject([
                ("id", id(e.id)), ("description", str(e.description)), ("occurredAt", time(e.occurredAt)), ("createdAtUtc", time(e.createdAt)),
                ("taggedEntityType", optStr(e.taggedEntityType?.rawValue)), ("taggedEntityId", id(e.taggedEntityId)),
                ("taggedEntityName", optStr(e.taggedEntityName)), ("correlationDirection", direction),
                ("correlationComputedAtUtc", directionSet ? time(r.exportedAt) : .null),
                ("updatedAtUtc", time(e.updatedAt)),
            ]))
        }
        func structure(_ items: [StructureRecord], parentKey: String?) -> JSONValue {
            .array(items.map { s in
                var pairs: [(String, JSONValue)] = [("id", id(s.id))]
                if let parentKey { pairs.append((parentKey, id(s.parentId))) }
                pairs += [("name", str(s.name)), ("createdAtUtc", time(s.createdAt)), ("archivedAt", time(s.archivedAt))]
                return .object(JSONObject(pairs))
            })
        }
        let plugs = r.smartPlugReadings.map { p in
            JSONValue.object(JSONObject([
                ("id", id(p.id)), ("powerPointId", id(p.powerPointId)), ("roomName", str(p.roomName)), ("powerPointName", str(p.powerPointName)),
                ("deviceName", str(p.deviceName)), ("intervalStart", time(p.intervalStart)), ("intervalEnd", time(p.intervalEnd)), ("kwhValue", num(p.kwhValue)),
            ]))
        }
        let snapshots = r.snapshots.sorted { ($0.computedAt, idKey($0.id)) < ($1.computedAt, idKey($1.id)) }.map { s in
            JSONValue.object(JSONObject([
                ("id", id(s.id)), ("status", str(s.status.rawValue)), ("paceToDateKwh", num(s.paceToDateKwh)), ("baselineToDateKwh", num(s.baselineToDateKwh)),
                ("isLowConfidence", .bool(s.isLowConfidence)), ("computedAtUtc", time(s.computedAt)),
                // Extension: keeps the cause across a round trip; ignored by older readers.
                ("causeId", id(s.causeId)),
            ]))
        }
        let corrections = r.corrections.sorted { ($0.correctedAt, idKey($0.id)) < ($1.correctedAt, idKey($1.id)) }.map { c in
            JSONValue.object(JSONObject([
                ("id", id(c.id)), ("entityType", str(c.entityType)), ("entityId", id(c.entityId)), ("fieldName", str(c.fieldName)),
                ("oldValue", str(c.oldValue)), ("newValue", str(c.newValue)), ("correctedAtUtc", time(c.correctedAt)),
            ]))
        }
        return JSONObject([
            ("formatVersion", str(formatVersion)),
            ("exportedAtUtc", time(r.exportedAt)),
            ("household", .object(household)),
            ("householdMembers", .array([])),
            ("mainMeter", meter),
            ("meterReadings", .array(readings)),
            ("meterRegressionPrompts", .array(prompts)),
            ("tariffs", .array(tariffs)),
            ("events", .array(events)),
            ("rooms", structure(r.rooms, parentKey: nil)),
            ("powerPoints", structure(r.powerPoints, parentKey: "roomId")),
            ("devices", structure(r.devices, parentKey: "powerPointId")),
            ("smartPlugReadings", .array(plugs)),
            ("statusSnapshots", .array(snapshots)),
            ("auditCorrections", .array(corrections)),
        ])
    }
}
