import Foundation
import XCTest
@testable import EnergyCore

final class ExportValidationTests: XCTestCase {
    func testFormatVersionIsCheckedFirstAndSuppressesAllOtherFailures() {
        let json = validJSON()
            .replacingOccurrences(of: "\"formatVersion\":\"v2\"", with: "\"formatVersion\":\"v1\"")
            .replacingOccurrences(of: "\"kwhValue\":120", with: "\"kwhValue\":\"wrong\"")
            .replacingOccurrences(of: "\"locale\":\"de-DE\",", with: "")
        let issues = validationIssues(json)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.path, "formatVersion")

        let missing = validJSON().replacingOccurrences(of: "\"formatVersion\":\"v2\",", with: "")
        XCTAssertEqual(validationIssues(missing).map(\.path), ["formatVersion"])
    }

    func testMissingRequiredPropertyAndWrongJSONTypesAreAllCollected() {
        let json = validJSON()
            .replacingOccurrences(of: "\"locale\":\"de-DE\",", with: "")
            .replacingOccurrences(of: "\"kwhValue\":120", with: "\"kwhValue\":\"120\"")
            .replacingOccurrences(of: "\"isLowConfidence\":false", with: "\"isLowConfidence\":0")
        let issues = validationIssues(json)
        XCTAssertEqual(issues.count, 3)
        XCTAssertTrue(issues.contains { $0.path == "household" && $0.message.contains("locale") })
        XCTAssertTrue(issues.contains { $0.path == "meterReadings[0]" && $0.message.contains("must be a number") })
        XCTAssertTrue(issues.contains { $0.path == "statusSnapshots[0]" && $0.message.contains("boolean") })
    }

    func testEnumValuesAndCaseRules() {
        let accepted = validJSON()
            .replacingOccurrences(of: "\"classification\":\"reset\"", with: "\"classification\":\"ReSeT\"")
            .replacingOccurrences(of: "\"status\":\"withinrange\"", with: "\"status\":\"WithinRange\"")
        let decoded = decodeJSON(accepted)
        XCTAssertEqual(decoded?.meterRegressionPrompts[0].classification, .reset)
        XCTAssertEqual(decoded?.statusSnapshots[0].status, .withinRange)

        let badClassification = validJSON().replacingOccurrences(of: "\"classification\":\"reset\"", with: "\"classification\":\"unknown\"")
        XCTAssertTrue(validationIssues(badClassification).contains { $0.path == "meterRegressionPrompts[0]" })
        let badStatus = validJSON().replacingOccurrences(of: "\"status\":\"withinrange\"", with: "\"status\":\"within_range\"")
        XCTAssertTrue(validationIssues(badStatus).contains { $0.path == "statusSnapshots[0]" })
        let wrongCaseTag = validJSON().replacingOccurrences(of: "\"taggedEntityType\":\"Device\"", with: "\"taggedEntityType\":\"device\"")
        XCTAssertTrue(validationIssues(wrongCaseTag).contains { $0.path == "events[0]" })
    }

    func testDuplicateIDWithinOneArrayIsRejectedButCrossArrayReuseIsAllowed() {
        let duplicate = validJSON().replacingOccurrences(
            of: "\"id\":\"\(idString(12))\"",
            with: "\"id\":\"\(idString(11))\""
        )
        XCTAssertTrue(validationIssues(duplicate).contains {
            $0.path == "meterReadings[1]" && $0.message.contains("more than once")
        })

        let crossArray = validJSON().replacingOccurrences(
            of: "\"id\":\"\(idString(30))\"",
            with: "\"id\":\"\(idString(40))\""
        )
        XCTAssertNotNil(decodeJSON(crossArray))
    }

    func testEveryRequiredReferenceKindIsResolvedWithinTheFile() {
        let json = validJSON()
            .replacingOccurrences(of: "\"mainMeterId\":\"\(idString(10))\"", with: "\"mainMeterId\":\"\(idString(900))\"")
            .replacingOccurrences(of: "\"meterReadingId\":\"\(idString(12))\"", with: "\"meterReadingId\":\"\(idString(901))\"")
            .replacingOccurrences(of: "\"previousMeterReadingId\":\"\(idString(11))\"", with: "\"previousMeterReadingId\":\"\(idString(902))\"")
            .replacingOccurrences(of: "\"roomId\":\"\(idString(40))\"", with: "\"roomId\":\"\(idString(903))\"")
            .replacingOccurrences(of: "\"powerPointId\":\"\(idString(41))\"", with: "\"powerPointId\":\"\(idString(904))\"")
            .replacingOccurrences(of: "\"taggedEntityId\":\"\(idString(42))\"", with: "\"taggedEntityId\":\"\(idString(905))\"")
        let paths = Set(validationIssues(json).map(\.path))
        XCTAssertTrue(paths.contains("meterReadings[0]"))
        XCTAssertTrue(paths.contains("meterReadings[1]"))
        XCTAssertTrue(paths.contains("meterRegressionPrompts[0]"))
        XCTAssertTrue(paths.contains("powerPoints[0]"))
        XCTAssertTrue(paths.contains("devices[0]"))
        XCTAssertTrue(paths.contains("smartPlugReadings[0]"))
        XCTAssertTrue(paths.contains("events[0]"))
    }

    func testTaggedIDRequiresTypeAndResolvesAgainstNamedArray() {
        let noType = validJSON().replacingOccurrences(of: "\"taggedEntityType\":\"Device\"", with: "\"taggedEntityType\":null")
        XCTAssertTrue(validationIssues(noType).contains {
            $0.path == "events[0]" && $0.message.contains("requires")
        })
        let wrongArray = validJSON()
            .replacingOccurrences(of: "\"taggedEntityType\":\"Device\"", with: "\"taggedEntityType\":\"Room\"")
        XCTAssertTrue(validationIssues(wrongArray).contains { $0.path == "events[0]" })
    }

    func testReadingKWhMustBePositive() {
        for value in ["0", "-1"] {
            let json = validJSON().replacingOccurrences(of: "\"kwhValue\":120", with: "\"kwhValue\":\(value)")
            XCTAssertTrue(validationIssues(json).contains {
                $0.path == "meterReadings[0]" && $0.message.contains("greater than 0")
            })
        }
    }

    func testAllTariffDomainRulesAreValidatedTogether() {
        let json = validJSON()
            .replacingOccurrences(of: "\"monthlyBaseFee\":8.5", with: "\"monthlyBaseFee\":-1")
            .replacingOccurrences(of: "\"pricePerKwh\":0.32", with: "\"pricePerKwh\":0")
            .replacingOccurrences(of: "\"currency\":\"EUR\",\"id\":\"\(idString(20))\"", with: "\"currency\":\"eur\",\"id\":\"\(idString(20))\"")
            .replacingOccurrences(of: "\"contractPeriodMonths\":12", with: "\"contractPeriodMonths\":0")
            .replacingOccurrences(of: "\"contractStartDate\":\"2026-01-01T00:00:00+00:00\"", with: "\"contractStartDate\":\"1899-12-31T00:00:00+00:00\"")
        let tariffIssues = validationIssues(json).filter { $0.path == "tariffs[0]" }
        XCTAssertEqual(tariffIssues.count, 5)
        XCTAssertTrue(tariffIssues.contains { $0.message.contains("monthlyBaseFee") })
        XCTAssertTrue(tariffIssues.contains { $0.message.contains("pricePerKwh") })
        XCTAssertTrue(tariffIssues.contains { $0.message.contains("currency") })
        XCTAssertTrue(tariffIssues.contains { $0.message.contains("contractPeriodMonths") })
        XCTAssertTrue(tariffIssues.contains { $0.message.contains("contractStartDate") })
    }

    func testTariffUpperBoundsAreExclusiveAndPeriodMaximumIsChecked() {
        let json = validJSON()
            .replacingOccurrences(of: "\"monthlyBaseFee\":8.5", with: "\"monthlyBaseFee\":1000000000000000")
            .replacingOccurrences(of: "\"pricePerKwh\":0.32", with: "\"pricePerKwh\":10000000000000")
            .replacingOccurrences(of: "\"contractPeriodMonths\":12", with: "\"contractPeriodMonths\":1201")
        XCTAssertEqual(validationIssues(json).filter { $0.path == "tariffs[0]" }.count, 3)
    }

    func testStructureNamesAndSmartPlugDeviceNameDomainRules() {
        let longName = String(repeating: "x", count: 201)
        let json = validJSON()
            .replacingOccurrences(of: "\"name\":\"Kitchen\"", with: "\"name\":\"   \"")
            .replacingOccurrences(of: "\"deviceName\":\"Plug\"", with: "\"deviceName\":\"\(longName)\"")
        let issues = validationIssues(json)
        XCTAssertTrue(issues.contains { $0.path == "rooms[0]" && $0.message.contains("name") })
        XCTAssertTrue(issues.contains { $0.path == "smartPlugReadings[0]" && $0.message.contains("200") })
    }

    func testDigitCapacityOnNonRolloverPromptIsRejected() {
        let json = validJSON().replacingOccurrences(
            of: "\"digitCapacityKwh\":null,\"id\":\"\(idString(13))\"",
            with: "\"digitCapacityKwh\":100000,\"id\":\"\(idString(13))\""
        )
        XCTAssertTrue(validationIssues(json).contains {
            $0.path == "meterRegressionPrompts[0]" && $0.message.contains("rollover")
        })
    }

    func testHouseholdSettingsDomainRules() {
        let json = validJSON()
            .replacingOccurrences(of: "\"trendingThresholdKwh\":100", with: "\"trendingThresholdKwh\":-1")
            .replacingOccurrences(of: "\"lowConfidenceGapDays\":45", with: "\"lowConfidenceGapDays\":0")
            .replacingOccurrences(of: "\"tariffCheckCadenceMonths\":3", with: "\"tariffCheckCadenceMonths\":25")
            .replacingOccurrences(of: "\"currency\":\"EUR\",\"id\":\"\(idString(1))\"", with: "\"currency\":\"Euro\",\"id\":\"\(idString(1))\"")
        XCTAssertEqual(validationIssues(json).filter { $0.path == "household" }.count, 4)
    }

    func testEventDescriptionLengthAndAuditDecimalStrings() {
        let longDescription = String(repeating: "e", count: 501)
        let badDescription = validJSON().replacingOccurrences(of: "\"description\":\"Away\"", with: "\"description\":\"\(longDescription)\"")
        XCTAssertTrue(validationIssues(badDescription).contains { $0.path == "events[0]" })

        let badAudit = validJSON().replacingOccurrences(of: "\"oldValue\":\"100\"", with: "\"oldValue\":\"not-a-number\"")
        XCTAssertTrue(validationIssues(badAudit).contains { $0.path == "auditCorrections[0]" })
    }

    func testInstantsRequireExplicitOffsetAndValidDate() {
        let noOffset = validJSON().replacingOccurrences(
            of: "\"readingTimestamp\":\"2026-01-01T00:00:00+00:00\"",
            with: "\"readingTimestamp\":\"2026-01-01T00:00:00\""
        )
        XCTAssertTrue(validationIssues(noOffset).contains { $0.path == "meterReadings[0]" })
        let invalidDate = validJSON().replacingOccurrences(
            of: "\"readingTimestamp\":\"2026-01-01T00:00:00+00:00\"",
            with: "\"readingTimestamp\":\"2026-02-30T00:00:00+00:00\""
        )
        XCTAssertTrue(validationIssues(invalidDate).contains { $0.path == "meterReadings[0]" })
    }

    func testTariffFractionDigitsAreValidated() {
        let tariff = validJSON()
            .replacingOccurrences(of: "\"monthlyBaseFee\":8.5", with: "\"monthlyBaseFee\":8.501")
            .replacingOccurrences(of: "\"pricePerKwh\":0.32", with: "\"pricePerKwh\":0.32001")
        let issues = validationIssues(tariff)
        XCTAssertEqual(issues.filter { $0.path == "tariffs[0]" }.count, 2)
    }

    func testMalformedJSONAndNonObjectDocumentAreRejected() {
        XCTAssertThrowsError(try EnergyExportCodec.decode(Data("{".utf8)))
        let issues = validationIssues("[]")
        XCTAssertEqual(issues.map(\.path), ["formatVersion"])
    }

    private func idString(_ value: Int) -> String {
        testUUID(value).uuidString.lowercased()
    }
}
