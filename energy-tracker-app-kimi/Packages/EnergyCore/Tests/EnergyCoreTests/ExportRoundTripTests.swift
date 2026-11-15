import Foundation
import XCTest
@testable import EnergyCore

final class ExportRoundTripTests: XCTestCase {
    func testCompleteExportRoundTripsDeterministically() throws {
        let original = validExport()
        let encoded = try EnergyExportCodec.encode(original)
        let decoded = try EnergyExportCodec.decode(encoded)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(try EnergyExportCodec.encode(decoded), encoded)
    }

    func testCodableDTOsRoundTripWithISO8601Dates() throws {
        let original = validExport()
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(EnergyExport.self, from: data)
        XCTAssertEqual(decoded, original)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("+00:00"))
        XCTAssertFalse(json.contains("T00:00:00Z"))
    }

    func testExactDecimalNumberSurvivesDecodeEncodeWithoutDoublePrecisionLoss() throws {
        let literal = "0.10000000000000000000000000000000000001"
        let json = validJSON().replacingOccurrences(of: "\"kwhValue\":120", with: "\"kwhValue\":\(literal)")
        let decoded = try XCTUnwrap(decodeJSON(json))
        XCTAssertEqual(decoded.meterReadings[0].kwhValue, Decimal(string: literal)!)
        let encoded = try EnergyExportCodec.encode(decoded)
        let output = String(data: encoded, encoding: .utf8)!
        XCTAssertTrue(output.contains("\"kwhValue\":\(literal)"))
        XCTAssertFalse(output.contains("\"kwhValue\":\"\(literal)\""))
        XCTAssertEqual(try EnergyExportCodec.decode(encoded).meterReadings[0].kwhValue, Decimal(string: literal)!)
    }

    func testExponentNumberIsParsedExactlyAsDecimal() throws {
        let json = validJSON().replacingOccurrences(of: "\"kwhValue\":120", with: "\"kwhValue\":1e-20")
        let decoded = try XCTUnwrap(decodeJSON(json))
        XCTAssertEqual(decoded.meterReadings[0].kwhValue, Decimal(string: "0.00000000000000000001")!)
        XCTAssertNotEqual(decoded.meterReadings[0].kwhValue, 0)
    }

    func testUnrepresentableDecimalIsRejectedInsteadOfSilentlyRounded() {
        let literal = "0.123456789012345678901234567890123456789012345"
        let json = validJSON().replacingOccurrences(of: "\"kwhValue\":120", with: "\"kwhValue\":\(literal)")
        XCTAssertThrowsError(try EnergyExportCodec.decode(Data(json.utf8))) { error in
            guard case EnergyExportError.malformedJSON = error else {
                return XCTFail("Expected exact-decimal failure, got \(error)")
            }
        }
    }

    func testUnknownPropertiesAreIgnored() throws {
        let json = validJSON().replacingOccurrences(
            of: "\"locale\":\"de-DE\"",
            with: "\"legacySetting\":{\"nested\":true},\"locale\":\"de-DE\""
        )
        XCTAssertNotNil(decodeJSON(json))
    }

    func testInputOffsetsAreReadAndOutputIsExplicitUTC() throws {
        var json = validJSON().replacingOccurrences(
            of: "\"contractStartDate\":\"2026-01-01T00:00:00+00:00\"",
            with: "\"contractStartDate\":\"2026-01-01T23:30:00-05:00\""
        )
        json = json.replacingOccurrences(
            of: "\"readingTimestamp\":\"2026-01-01T00:00:00+00:00\"",
            with: "\"readingTimestamp\":\"2025-12-31T19:00:00-05:00\""
        )
        let decoded = try XCTUnwrap(decodeJSON(json))
        XCTAssertEqual(decoded.tariffs[0].contractStartDate, CalendarDate(year: 2026, month: 1, day: 1))
        XCTAssertEqual(decoded.meterReadings[0].readingTimestamp, utcDate("2026-01-01"))
        let output = String(data: try EnergyExportCodec.encode(decoded), encoding: .utf8)!
        XCTAssertTrue(output.contains("\"contractStartDate\":\"2026-01-01T00:00:00+00:00\""))
        XCTAssertFalse(output.contains("Z\""))
    }

    func testZAndFractionalSecondsAreAccepted() throws {
        let json = validJSON().replacingOccurrences(
            of: "\"readingTimestamp\":\"2026-01-01T00:00:00+00:00\"",
            with: "\"readingTimestamp\":\"2026-01-01T00:00:00.123Z\""
        )
        let decoded = try XCTUnwrap(decodeJSON(json))
        XCTAssertEqual(decoded.meterReadings[0].readingTimestamp.timeIntervalSince1970, utcDate("2026-01-01").timeIntervalSince1970 + 0.123, accuracy: 0.000001)
    }

    func testOriginalReadingValueComesFromEarliestCorrection() throws {
        var original = validExport()
        original.auditCorrections.append(ExportAuditCorrection(
            id: testUUID(79),
            entityType: "MeterReading",
            entityId: testUUID(11),
            fieldName: "KwhValue",
            oldValue: "90",
            newValue: "95",
            correctedAtUtc: utcDate("2025-12-31")
        ))
        // The earliest correction is now id 79; its old value defines the imported original.
        let decoded = try EnergyExportCodec.decode(try EnergyExportCodec.encode(original))
        let readings = try decoded.importedMeterReadings()
        XCTAssertEqual(readings.first?.kwhValue, 90)
        XCTAssertEqual(readings.last?.kwhValue, 130)
        XCTAssertEqual(decoded.meterReadings.first?.kwhValue, 120)
    }

    func testImportIgnoresIdempotencyKeyAndExportNormalizesCompatibilityFields() throws {
        let json = validJSON()
            .replacingOccurrences(of: "\"idempotencyKey\":\"\(testUUID(11).uuidString.lowercased())\"", with: "\"idempotencyKey\":\"\(testUUID(999).uuidString.lowercased())\"")
            .replacingOccurrences(of: "\"aiPlausibilityEnabled\":false", with: "\"aiPlausibilityEnabled\":true")
        let decoded = try XCTUnwrap(decodeJSON(json))
        XCTAssertEqual(decoded.meterReadings[0].idempotencyKey, testUUID(11))
        let output = String(data: try EnergyExportCodec.encode(decoded), encoding: .utf8)!
        XCTAssertTrue(output.contains("\"aiPlausibilityEnabled\":false"))
        XCTAssertFalse(output.contains(testUUID(999).uuidString.lowercased()))
    }
}
