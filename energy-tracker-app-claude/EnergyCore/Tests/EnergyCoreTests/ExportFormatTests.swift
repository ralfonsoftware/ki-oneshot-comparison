import Foundation
import Testing
@testable import EnergyCore

let minimalExample = """
{
  "formatVersion": "v2",
  "exportedAtUtc": "2026-09-22T10:00:00+00:00",
  "household": {
    "id": "b6f1f6b0-6b8b-4d3a-9b1a-000000000001",
    "createdAtUtc": "2026-01-05T08:00:00+00:00",
    "locale": "de-DE",
    "currency": "EUR",
    "yearlyBaselineKwh": 3500.0,
    "trendingThresholdKwh": 100.0,
    "lowConfidenceGapDays": 45,
    "tariffCheckCadenceMonths": 3,
    "aiPlausibilityEnabled": false,
    "aiPlausibilityBackendConfigured": false,
    "aiPlausibilityBackendLabel": null
  },
  "householdMembers": [],
  "mainMeter": {
    "id": "b6f1f6b0-6b8b-4d3a-9b1a-000000000003",
    "createdAtUtc": "2026-01-05T09:00:00+00:00",
    "digitCapacityKwh": null
  },
  "meterReadings": [
    {
      "id": "b6f1f6b0-6b8b-4d3a-9b1a-000000000004",
      "mainMeterId": "b6f1f6b0-6b8b-4d3a-9b1a-000000000003",
      "kwhValue": 12345.6,
      "readingTimestamp": "2026-09-01T18:00:00+00:00",
      "idempotencyKey": "b6f1f6b0-6b8b-4d3a-9b1a-000000000004",
      "createdAtUtc": "2026-09-01T18:00:05+00:00"
    }
  ],
  "meterRegressionPrompts": [],
  "tariffs": [
    {
      "id": "b6f1f6b0-6b8b-4d3a-9b1a-000000000006",
      "monthlyBaseFee": 8.50,
      "pricePerKwh": 0.32,
      "currency": "EUR",
      "contractStartDate": "2026-01-01T00:00:00+00:00",
      "contractPeriodMonths": 12,
      "createdAtUtc": "2026-01-05T08:30:00+00:00"
    }
  ],
  "events": [],
  "rooms": [
    {
      "id": "b6f1f6b0-6b8b-4d3a-9b1a-000000000007",
      "name": "Kitchen",
      "createdAtUtc": "2026-01-05T08:15:00+00:00",
      "archivedAt": null
    }
  ],
  "powerPoints": [
    {
      "id": "b6f1f6b0-6b8b-4d3a-9b1a-000000000008",
      "roomId": "b6f1f6b0-6b8b-4d3a-9b1a-000000000007",
      "name": "Counter outlet",
      "createdAtUtc": "2026-01-05T08:16:00+00:00",
      "archivedAt": null
    }
  ],
  "devices": [],
  "smartPlugReadings": [],
  "statusSnapshots": [],
  "auditCorrections": []
}
"""

/// Parses the minimal example, applies `edit` to the JSON tree, and returns the validation failures.
func failures(_ edit: (inout JSONObject) -> Void) -> [String] {
    guard case .object(var top) = try! JSONParser.parse(Data(minimalExample.utf8)) else { return ["not an object"] }
    edit(&top)
    do {
        _ = try ExportFormat.decode(JSONWriter.write(.object(top)))
        return []
    } catch {
        return error.failures
    }
}

extension JSONObject {
    mutating func editArray(_ key: String, _ index: Int, _ body: (inout JSONObject) -> Void) {
        guard case .array(var items)? = self[key], case .object(var o) = items[index] else { return }
        body(&o)
        items[index] = .object(o)
        self[key] = .array(items)
    }

    mutating func editObject(_ key: String, _ body: (inout JSONObject) -> Void) {
        guard case .object(var o)? = self[key] else { return }
        body(&o)
        self[key] = .object(o)
    }

    mutating func append(_ key: String, _ value: JSONValue) {
        guard case .array(var items)? = self[key] else { return }
        items.append(value)
        self[key] = .array(items)
    }

    func item(_ key: String, _ index: Int) -> JSONValue {
        guard case .array(let items)? = self[key] else { return .null }
        return items[index]
    }
}

@Suite("Export file format §8")
struct ExportFormatTests {
    @Test("Minimal example imports")
    func minimal() throws {
        let records = try ExportFormat.decode(Data(minimalExample.utf8))
        #expect(records.household.currency == "EUR")
        #expect(records.household.yearlyBaselineKwh == 3500)
        #expect(records.readings.count == 1)
        #expect(records.readings[0].originalKwhValue == dec("12345.6"))
        #expect(records.tariffs[0].contractStartDate == CalendarDate(year: 2026, month: 1, day: 1))
        #expect(records.tariffs[0].monthlyBaseFee == dec("8.5"))
        #expect(records.powerPoints[0].parentId == records.rooms[0].id)
    }

    @Test("Decimals are read without binary floating point loss")
    func exactDecimals() throws {
        let fails = failures { top in top.editArray("meterReadings", 0) { $0["kwhValue"] = .number("0.1") } }
        #expect(fails.isEmpty)
        guard case .object(var top) = try JSONParser.parse(Data(minimalExample.utf8)) else { return }
        top.editArray("meterReadings", 0) { $0["kwhValue"] = .number("12345678901234.99") }
        let records = try ExportFormat.decode(JSONWriter.write(.object(top)))
        #expect(DecimalMath.string(records.readings[0].originalKwhValue) == "12345678901234.99")
    }

    @Test("contractStartDate uses the calendar date in the value's own offset")
    func startDateOffset() throws {
        guard case .object(var top) = try JSONParser.parse(Data(minimalExample.utf8)) else { return }
        top.editArray("tariffs", 0) { $0["contractStartDate"] = .string("2026-01-01T00:00:00+01:00") }
        let records = try ExportFormat.decode(JSONWriter.write(.object(top)))
        #expect(records.tariffs[0].contractStartDate == CalendarDate(year: 2026, month: 1, day: 1))
    }

    @Test("Rule 1: formatVersion is checked first and alone")
    func rule1() {
        let fails = failures { top in
            top["formatVersion"] = .string("v1")
            top["household"] = nil
        }
        #expect(fails == ["'formatVersion' must be \"v2\"."])
        #expect(failures { $0["formatVersion"] = nil } == ["'formatVersion' must be \"v2\"."])
    }

    @Test("Rule 2: missing property and wrong type")
    func rule2() {
        #expect(failures { $0.editArray("meterReadings", 0) { $0["kwhValue"] = .string("12") } } == ["meterReadings[0]: 'kwhValue' must be a number."])
        #expect(failures { $0.editArray("meterReadings", 0) { $0["readingTimestamp"] = nil } } == ["meterReadings[0]: 'readingTimestamp' is missing."])
        #expect(failures { $0["tariffs"] = nil } == ["(root): 'tariffs' is missing."])
        #expect(failures { $0.editObject("household") { $0["lowConfidenceGapDays"] = .number("4.5") } } == ["household: 'lowConfidenceGapDays' must be an integer."])
        #expect(failures { $0.editArray("meterReadings", 0) { $0["readingTimestamp"] = .string("2026-09-01T18:00:00") } } == ["meterReadings[0]: 'readingTimestamp' must be an ISO 8601 instant with offset."])
    }

    @Test("Rule 3: enum values; status and classification are case-insensitive")
    func rule3() {
        let snapshot = JSONValue.object(JSONObject([
            ("id", .string(uid(50).uuidString)), ("status", .string("WithinRange")), ("paceToDateKwh", .number("1")),
            ("baselineToDateKwh", .number("1")), ("isLowConfidence", .bool(false)), ("computedAtUtc", .string("2026-01-01T00:00:00+00:00")),
        ]))
        #expect(failures { $0.append("statusSnapshots", snapshot) }.isEmpty)
        let bad = failures { top in
            top.append("statusSnapshots", snapshot)
            top.editArray("statusSnapshots", 0) { $0["status"] = .string("alarm") }
        }
        #expect(bad == ["statusSnapshots[0]: 'status' must be one of \"withinrange\", \"belowbaseline\", \"trending\"."])
        let event = JSONValue.object(JSONObject([
            ("id", .string(uid(51).uuidString)), ("description", .string("Sauna")), ("occurredAt", .string("2026-01-01T00:00:00+00:00")),
            ("createdAtUtc", .string("2026-01-01T00:00:00+00:00")), ("taggedEntityType", .string("room")),
            ("taggedEntityId", .null), ("taggedEntityName", .null),
        ]))
        #expect(failures { $0.append("events", event) } == ["events[0]: 'taggedEntityType' must be one of \"Room\", \"PowerPoint\", \"Device\" or null."])
    }

    @Test("Rule 4: duplicate ids within one array")
    func rule4() {
        let fails = failures { top in top.append("meterReadings", top.item("meterReadings", 0)) }
        #expect(fails.count == 1)
        #expect(fails[0].hasPrefix("meterReadings[1]: id b6f1f6b0-6b8b-4d3a-9b1a-000000000004 appears twice"))
    }

    @Test("Rule 5: references must resolve")
    func rule5() {
        #expect(failures { $0.editArray("meterReadings", 0) { $0["mainMeterId"] = .string(uid(9).uuidString) } } == ["meterReadings[0]: 'mainMeterId' does not match 'mainMeter.id'."])
        #expect(failures { $0.editArray("powerPoints", 0) { $0["roomId"] = .string(uid(9).uuidString) } } == ["powerPoints[0]: 'roomId' does not reference a room."])
        let prompt = JSONValue.object(JSONObject([
            ("id", .string(uid(60).uuidString)), ("mainMeterId", .string("b6f1f6b0-6b8b-4d3a-9b1a-000000000003")),
            ("meterReadingId", .string(uid(61).uuidString)), ("previousMeterReadingId", .string("b6f1f6b0-6b8b-4d3a-9b1a-000000000004")),
            ("createdAtUtc", .string("2026-01-01T00:00:00+00:00")), ("resolvedAtUtc", .null), ("classification", .null), ("digitCapacityKwh", .null),
        ]))
        #expect(failures { $0.append("meterRegressionPrompts", prompt) } == ["meterRegressionPrompts[0]: 'meterReadingId' does not reference a meter reading."])
        let device = JSONValue.object(JSONObject([
            ("id", .string(uid(70).uuidString)), ("powerPointId", .string(uid(71).uuidString)), ("name", .string("Kettle")),
            ("createdAtUtc", .string("2026-01-01T00:00:00+00:00")), ("archivedAt", .null),
        ]))
        #expect(failures { $0.append("devices", device) } == ["devices[0]: 'powerPointId' does not reference a power point."])
        let event = JSONValue.object(JSONObject([
            ("id", .string(uid(51).uuidString)), ("description", .string("Sauna")), ("occurredAt", .string("2026-01-01T00:00:00+00:00")),
            ("createdAtUtc", .string("2026-01-01T00:00:00+00:00")), ("taggedEntityType", .string("Device")),
            ("taggedEntityId", .string("b6f1f6b0-6b8b-4d3a-9b1a-000000000007")), ("taggedEntityName", .string("Kitchen")),
        ]))
        #expect(failures { $0.append("events", event) } == ["events[0]: 'taggedEntityId' does not reference a device."])
        let plug = JSONValue.object(JSONObject([
            ("id", .string(uid(80).uuidString)), ("powerPointId", .string(uid(81).uuidString)), ("roomName", .string("K")),
            ("powerPointName", .string("P")), ("deviceName", .string("D")), ("intervalStart", .string("2026-01-01T00:00:00+00:00")),
            ("intervalEnd", .string("2026-01-01T01:00:00+00:00")), ("kwhValue", .number("0.1")),
        ]))
        #expect(failures { $0.append("smartPlugReadings", plug) } == ["smartPlugReadings[0]: 'powerPointId' does not reference a power point."])
    }

    @Test("Rule 6: domain rules")
    func rule6() {
        #expect(failures { $0.editArray("meterReadings", 0) { $0["kwhValue"] = .number("0") } } == ["meterReadings[0]: 'kwhValue' must be greater than 0."])
        #expect(failures { $0.editArray("tariffs", 0) { $0["currency"] = .string("eur") } } == ["tariffs[0]: 'currency' must be a 3-letter upper-case code."])
        #expect(failures { $0.editArray("tariffs", 0) { $0["contractPeriodMonths"] = .number("0") } } == ["tariffs[0]: 'contractPeriodMonths' must be between 1 and 1200."])
        #expect(failures { $0.editArray("tariffs", 0) { $0["pricePerKwh"] = .number("0") } } == ["tariffs[0]: 'pricePerKwh' must be greater than 0 and less than 10^13."])
        #expect(failures { $0.editArray("tariffs", 0) { $0["monthlyBaseFee"] = .number("-1") } } == ["tariffs[0]: 'monthlyBaseFee' must be at least 0 and less than 10^15."])
        #expect(failures { $0.editArray("tariffs", 0) { $0["contractStartDate"] = .string("1899-12-31T00:00:00+00:00") } } == ["tariffs[0]: 'contractStartDate' must be between 1900-01-01 and 2200-01-01."])
        #expect(failures { $0.editArray("rooms", 0) { $0["name"] = .string("   ") } } == ["rooms[0]: 'name' must be 1 to 200 characters."])
        let plug = JSONValue.object(JSONObject([
            ("id", .string(uid(80).uuidString)), ("powerPointId", .null), ("roomName", .string("K")),
            ("powerPointName", .string("P")), ("deviceName", .string(String(repeating: "d", count: 201))), ("intervalStart", .string("2026-01-01T00:00:00+00:00")),
            ("intervalEnd", .string("2026-01-01T01:00:00+00:00")), ("kwhValue", .number("0.1")),
        ]))
        #expect(failures { $0.append("smartPlugReadings", plug) } == ["smartPlugReadings[0]: 'deviceName' must be at most 200 characters."])
        let prompt = JSONValue.object(JSONObject([
            ("id", .string(uid(60).uuidString)), ("mainMeterId", .string("b6f1f6b0-6b8b-4d3a-9b1a-000000000003")),
            ("meterReadingId", .string("b6f1f6b0-6b8b-4d3a-9b1a-000000000004")), ("previousMeterReadingId", .string("b6f1f6b0-6b8b-4d3a-9b1a-000000000004")),
            ("createdAtUtc", .string("2026-01-01T00:00:00+00:00")), ("resolvedAtUtc", .string("2026-01-02T00:00:00+00:00")),
            ("classification", .string("RESET")), ("digitCapacityKwh", .number("100000")),
        ]))
        #expect(failures { $0.append("meterRegressionPrompts", prompt) } == ["meterRegressionPrompts[0]: 'digitCapacityKwh' is only allowed for a rollover."])
    }

    @Test("Every failure is listed, and the display list is capped at 200")
    func manyFailures() throws {
        let fails = failures { top in
            for i in 0..<250 {
                top.append("rooms", .object(JSONObject([("id", .string(uid(1000 + i).uuidString)), ("name", .string("")), ("createdAtUtc", .string("2026-01-01T00:00:00+00:00")), ("archivedAt", .null)])))
            }
        }
        #expect(fails.count == 250)
        let lines = ImportValidationError(failures: fails).displayLines()
        #expect(lines.count == 201)
        #expect(lines.last == "… and 50 more")
    }

    @Test("Unknown properties are ignored; householdMembers with identity fields is ignored")
    func unknown() {
        let fails = failures { top in
            top["somethingNew"] = .string("x")
            top.editObject("household") { $0["extra"] = .number("1") }
            top["householdMembers"] = .array([.object(JSONObject([("id", .string(uid(1).uuidString)), ("displayName", .string("Sam")), ("email", .string("sam@example.com"))]))])
        }
        #expect(fails.isEmpty)
    }

    @Test("Original value comes from the earliest KwhValue correction")
    func originalFromCorrections() throws {
        guard case .object(var top) = try JSONParser.parse(Data(minimalExample.utf8)) else { return }
        let readingId = "b6f1f6b0-6b8b-4d3a-9b1a-000000000004"
        func correction(_ n: Int, _ old: String, _ new: String, _ at: String) -> JSONValue {
            .object(JSONObject([("id", .string(uid(n).uuidString)), ("entityType", .string("MeterReading")), ("entityId", .string(readingId)),
                                ("fieldName", .string("KwhValue")), ("oldValue", .string(old)), ("newValue", .string(new)), ("correctedAtUtc", .string(at))]))
        }
        top.append("auditCorrections", correction(2, "12000", "12300", "2026-09-03T00:00:00+00:00"))
        top.append("auditCorrections", correction(1, "11000", "12000", "2026-09-02T00:00:00+00:00"))
        top.editArray("meterReadings", 0) { $0["kwhValue"] = .number("12300") }
        let records = try ExportFormat.decode(JSONWriter.write(.object(top)))
        #expect(records.readings[0].originalKwhValue == 11000)
        let effective = Readings.effectiveValue(original: records.readings[0].originalKwhValue, corrections: records.corrections.map(\.asInput))
        #expect(effective == 12300)
    }

    @Test("Export → import round trip is identical")
    func roundTrip() throws {
        let meter = MainMeterRecord(id: uid(2), createdAt: utc(2026, 1, 1, 9), digitCapacityKwh: 100_000)
        var r = DataSetRecords(exportedAt: utc(2026, 9, 22, 10), household: HouseholdRecord(id: uid(1), createdAt: utc(2026, 1, 1), locale: "de-DE", currency: "EUR", yearlyBaselineKwh: dec("3500.5"), trendingThresholdKwh: 100, lowConfidenceGapDays: 30, tariffCheckCadenceMonths: 6, tariffCheckDoneAt: utc(2026, 10, 5)), mainMeter: meter)
        r.readings = [
            ReadingRecord(id: uid(10), mainMeterId: meter.id, originalKwhValue: dec("99950"), readingTimestamp: utc(2026, 1, 1), createdAt: utc(2026, 1, 1, 0, 0, 5)),
            ReadingRecord(id: uid(11), mainMeterId: meter.id, originalKwhValue: dec("30.25"), effectiveKwhValue: dec("31.25"), readingTimestamp: utc(2026, 1, 11), createdAt: utc(2026, 1, 11)),
        ]
        r.corrections = [CorrectionRecord(id: uid(20), entityType: "MeterReading", entityId: uid(11), fieldName: "KwhValue", oldValue: "30.25", newValue: "31.25", correctedAt: utc(2026, 1, 12))]
        r.prompts = [PromptRecord(id: uid(30), mainMeterId: meter.id, meterReadingId: uid(11), previousMeterReadingId: uid(10), createdAt: utc(2026, 1, 11), resolvedAt: utc(2026, 1, 11, 1), classification: .rollover, digitCapacityKwh: 100_000)]
        r.tariffs = [TariffRecord(id: uid(40), monthlyBaseFee: dec("8.5"), pricePerKwh: dec("0.3215"), currency: "EUR", contractStartDate: CalendarDate(year: 2026, month: 1, day: 1), contractPeriodMonths: 24, createdAt: utc(2026, 1, 1))]
        r.rooms = [StructureRecord(id: uid(50), name: "Kitchen", createdAt: utc(2026, 1, 1))]
        r.powerPoints = [StructureRecord(id: uid(51), name: "Counter \"left\"", createdAt: utc(2026, 1, 1), archivedAt: utc(2026, 2, 1), parentId: uid(50))]
        r.devices = [StructureRecord(id: uid(52), name: "Kettle ☕️", createdAt: utc(2026, 1, 1), parentId: uid(51))]
        r.events = [EventRecord(id: uid(60), description: "Sauna 3h\nwith friends", occurredAt: utc(2026, 1, 5, 18, 30), createdAt: utc(2026, 1, 5), updatedAt: utc(2026, 1, 6), taggedEntityType: .device, taggedEntityId: uid(52), taggedEntityName: "Kettle")]
        r.smartPlugReadings = [SmartPlugReadingRecord(id: uid(70), powerPointId: uid(51), roomName: "Kitchen", powerPointName: "Counter", deviceName: "Kettle", intervalStart: utc(2026, 1, 1), intervalEnd: utc(2026, 1, 1, 1), kwhValue: dec("0.125"))]
        r.snapshots = [SnapshotRecord(id: uid(80), status: .trending, paceToDateKwh: dec("80"), baselineToDateKwh: dec("95.89041095890410958904109589041095890"), isLowConfidence: false, computedAt: utc(2026, 1, 11, 0, 0, 1), causeId: uid(11))]

        let data = ExportFormat.encode(r)
        let back = try ExportFormat.decode(data)
        #expect(back.household == r.household)
        #expect(back.mainMeter == r.mainMeter)
        #expect(back.readings == r.readings)
        #expect(back.corrections == r.corrections)
        #expect(back.prompts == r.prompts)
        #expect(back.tariffs == r.tariffs)
        #expect(back.rooms == r.rooms)
        #expect(back.powerPoints == r.powerPoints)
        #expect(back.devices == r.devices)
        #expect(back.events == r.events)
        #expect(back.smartPlugReadings == r.smartPlugReadings)
        #expect(back.snapshots == r.snapshots)
        // Writing again gives the same bytes.
        #expect(ExportFormat.encode(back) == data)

        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"householdMembers\": []"))
        #expect(text.contains("\"aiPlausibilityEnabled\": false"))
        #expect(text.contains("\"aiPlausibilityBackendLabel\": null"))
        #expect(text.contains("\"kwhValue\": 31.25"))
        #expect(text.contains("\"contractStartDate\": \"2026-01-01T00:00:00+00:00\""))
        #expect(text.contains("\"idempotencyKey\": \"00000000-0000-0000-0000-00000000000b\""))
    }

    @Test("Event correlation is written at export time")
    func correlation() throws {
        var r = DataSetRecords(exportedAt: utc(2026, 9, 22, 10), household: HouseholdRecord(createdAt: utc(2026, 1, 1)))
        r.events = [EventRecord(id: uid(1), description: "A", occurredAt: utc(2026, 1, 1), createdAt: utc(2026, 1, 1), exportDeviation: .bump),
                    EventRecord(id: uid(2), description: "B", occurredAt: utc(2026, 1, 1), createdAt: utc(2026, 1, 1), exportDeviation: Deviation.none)]
        guard case .object(let top) = try JSONParser.parse(ExportFormat.encode(r)) else { Issue.record(); return }
        guard case .object(let e0) = top.item("events", 0), case .object(let e1) = top.item("events", 1) else { Issue.record(); return }
        guard case .string("Bump")? = e0["correlationDirection"], case .string("2026-09-22T10:00:00+00:00")? = e0["correlationComputedAtUtc"] else { Issue.record("bump"); return }
        guard case .null? = e1["correlationDirection"], case .null? = e1["correlationComputedAtUtc"] else { Issue.record("none"); return }
        guard case .null? = top["mainMeter"] else { Issue.record("meter"); return }
    }

    @Test func fileName() {
        #expect(ExportFormat.fileName(for: utc(2026, 11, 7, 12), timeZone: .gmt) == "energy-tracker-export-2026-11-07.json")
    }
}

@Suite("JSON and instants")
struct JSONTests {
    @Test func parsesEscapes() throws {
        let v = try JSONParser.parse(Data(#"{"a":"x\"y\\zé😀","n":[1,-2.5e3,0.0],"t":true,"f":false,"z":null}"#.utf8))
        guard case .object(let o) = v, case .string(let s)? = o["a"], case .array(let n)? = o["n"] else { Issue.record(); return }
        #expect(s == "x\"y\\zé😀")
        guard case .number("-2.5e3") = n[1] else { Issue.record(); return }
    }

    @Test func rejectsBadJSON() {
        #expect(throws: JSONSyntaxError.self) { try JSONParser.parse(Data("{\"a\":}".utf8)) }
        #expect(throws: JSONSyntaxError.self) { try JSONParser.parse(Data("[1,]".utf8)) }
        #expect(throws: JSONSyntaxError.self) { try JSONParser.parse(Data("01".utf8)) }
        #expect(throws: JSONSyntaxError.self) { try JSONParser.parse(Data("{} x".utf8)) }
    }

    @Test func invalidJSONRejectsImport() {
        #expect(throws: ImportValidationError.self) { try ExportFormat.decode(Data("not json".utf8)) }
    }

    @Test func instants() {
        #expect(Instant.parse("2026-09-22T10:00:00+00:00") == utc(2026, 9, 22, 10))
        #expect(Instant.parse("2026-09-22T12:00:00+02:00") == utc(2026, 9, 22, 10))
        #expect(Instant.parse("2026-09-22T10:00:00Z") == utc(2026, 9, 22, 10))
        #expect(Instant.parse("2026-09-22T10:00:00.250+00:00") == utc(2026, 9, 22, 10).addingTimeInterval(0.25))
        #expect(Instant.parse("2026-09-22T10:00:00") == nil)
        #expect(Instant.parse("2026-02-30T10:00:00Z") == nil)
        #expect(Instant.format(utc(2026, 9, 22, 10)) == "2026-09-22T10:00:00+00:00")
        #expect(Instant.format(utc(2026, 9, 22, 10).addingTimeInterval(0.25)) == "2026-09-22T10:00:00.250+00:00")
    }

    @Test func decimalStrings() {
        #expect(DecimalMath.string(dec("12345.60")) == "12345.6")
        #expect(DecimalMath.string(dec("-0")) == "0")
        #expect(DecimalMath.parse("1,5") == nil)
        #expect(DecimalMath.parse("abc") == nil)
        #expect(DecimalMath.decimalPlaces(dec("1.25")) == 2)
        #expect(DecimalMath.decimalPlaces(dec("100")) == 0)
    }
}
