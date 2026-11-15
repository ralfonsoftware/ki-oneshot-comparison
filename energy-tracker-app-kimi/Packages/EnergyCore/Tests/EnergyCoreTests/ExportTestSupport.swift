import Foundation
import XCTest
@testable import EnergyCore

func validExport() -> EnergyExport {
    let created = utcDate("2026-01-01")
    let meterID = testUUID(10)
    let firstReadingID = testUUID(11)
    let secondReadingID = testUUID(12)
    let roomID = testUUID(40)
    let powerPointID = testUUID(41)
    let deviceID = testUUID(42)
    return EnergyExport(
        exportedAtUtc: utcDate("2026-09-22"),
        household: ExportHousehold(
            id: testUUID(1),
            createdAtUtc: created,
            locale: "de-DE",
            currency: "EUR",
            yearlyBaselineKwh: Decimal(string: "3500.0")!,
            trendingThresholdKwh: 100,
            lowConfidenceGapDays: 45,
            tariffCheckCadenceMonths: 3
        ),
        mainMeter: ExportMainMeter(id: meterID, createdAtUtc: created, digitCapacityKwh: 100_000),
        meterReadings: [
            ExportMeterReading(
                id: firstReadingID,
                mainMeterId: meterID,
                kwhValue: 120,
                readingTimestamp: utcDate("2026-01-01"),
                createdAtUtc: utcDate("2026-01-01")
            ),
            ExportMeterReading(
                id: secondReadingID,
                mainMeterId: meterID,
                kwhValue: 130,
                readingTimestamp: utcDate("2026-01-11"),
                createdAtUtc: utcDate("2026-01-11")
            )
        ],
        meterRegressionPrompts: [
            ExportMeterRegressionPrompt(
                id: testUUID(13),
                mainMeterId: meterID,
                meterReadingId: secondReadingID,
                previousMeterReadingId: firstReadingID,
                createdAtUtc: utcDate("2026-01-11"),
                resolvedAtUtc: utcDate("2026-01-11"),
                classification: .reset,
                digitCapacityKwh: nil
            )
        ],
        tariffs: [
            ExportTariff(
                id: testUUID(20),
                monthlyBaseFee: Decimal(string: "8.50")!,
                pricePerKwh: Decimal(string: "0.32")!,
                currency: "EUR",
                contractStartDate: CalendarDate(year: 2026, month: 1, day: 1),
                contractPeriodMonths: 12,
                createdAtUtc: created
            )
        ],
        events: [
            ExportEvent(
                id: testUUID(30),
                description: "Away",
                occurredAt: utcDate("2026-01-05"),
                createdAtUtc: utcDate("2026-01-05"),
                taggedEntityType: .device,
                taggedEntityId: deviceID,
                taggedEntityName: "Heater",
                correlationDirection: .bump,
                correlationComputedAtUtc: utcDate("2026-09-22")
            )
        ],
        rooms: [ExportRoom(id: roomID, name: "Kitchen", createdAtUtc: created)],
        powerPoints: [ExportPowerPoint(id: powerPointID, roomId: roomID, name: "Counter outlet", createdAtUtc: created)],
        devices: [ExportDevice(id: deviceID, powerPointId: powerPointID, name: "Heater", createdAtUtc: created)],
        smartPlugReadings: [
            ExportSmartPlugReading(
                id: testUUID(60),
                powerPointId: powerPointID,
                roomName: "Kitchen",
                powerPointName: "Counter outlet",
                deviceName: "Plug",
                intervalStart: utcDate("2026-01-01"),
                intervalEnd: utcDate("2026-01-02"),
                kwhValue: Decimal(string: "0.001")!
            )
        ],
        statusSnapshots: [
            ExportStatusSnapshot(
                id: testUUID(70),
                status: .withinRange,
                paceToDateKwh: 100,
                baselineToDateKwh: 95,
                isLowConfidence: false,
                computedAtUtc: utcDate("2026-01-11")
            )
        ],
        auditCorrections: [
            ExportAuditCorrection(
                id: testUUID(80),
                entityType: "MeterReading",
                entityId: firstReadingID,
                fieldName: "KwhValue",
                oldValue: "100",
                newValue: "120",
                correctedAtUtc: utcDate("2026-01-02")
            )
        ]
    )
}

func validJSON() -> String {
    String(data: try! EnergyExportCodec.encode(validExport()), encoding: .utf8)!
}

func validationIssues(_ json: String, file: StaticString = #filePath, line: UInt = #line) -> [ExportValidationIssue] {
    do {
        _ = try EnergyExportCodec.decode(Data(json.utf8))
        XCTFail("Expected import validation to fail", file: file, line: line)
        return []
    } catch EnergyExportError.validationFailed(let issues) {
        return issues
    } catch {
        XCTFail("Expected validation issues, got \(error)", file: file, line: line)
        return []
    }
}

func decodeJSON(_ json: String, file: StaticString = #filePath, line: UInt = #line) -> EnergyExport? {
    do {
        return try EnergyExportCodec.decode(Data(json.utf8))
    } catch {
        XCTFail("Expected valid import, got \(error)", file: file, line: line)
        return nil
    }
}
