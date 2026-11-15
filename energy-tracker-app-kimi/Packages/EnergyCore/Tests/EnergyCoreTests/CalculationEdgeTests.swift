import XCTest
@testable import EnergyCore

final class CalculationEdgeTests: XCTestCase {
    func testReadingOrderingUsesTimestampThenLowercaseUUIDByteOrder() {
        let later = testReading("2025-01-02", 120, id: 3)
        let tiedHigh = testReading("2025-01-01", 110, id: 2)
        let tiedLow = testReading("2025-01-01", 100, id: 1)
        let ordered = EnergyCalculator.orderedReadings([later, tiedHigh, tiedLow])
        XCTAssertEqual(ordered.map(\.id), [tiedLow.id, tiedHigh.id, later.id])
        let pace = EnergyCalculator.pace(readings: [later, tiedHigh, tiedLow], now: utcDate("2025-01-02"))
        assertDecimal(pace?.paceToDateKwh, "20")
        assertDecimal(pace?.elapsedDays, "1")
    }

    func testEffectiveValueUsesNewestCorrectionThenHighestID() {
        let first = testReading("2025-01-01", 100, id: 1)
        let second = testReading("2025-01-02", 200, id: 2)
        let lowerID = AuditCorrection(
            id: testUUID(10),
            entityType: .meterReading,
            entityID: first.id,
            fieldName: "KwhValue",
            oldValue: "100",
            newValue: "110",
            correctedAt: utcDate("2025-01-03")
        )
        let higherID = AuditCorrection(
            id: testUUID(11),
            entityType: .meterReading,
            entityID: first.id,
            fieldName: "KwhValue",
            oldValue: "110",
            newValue: "120",
            correctedAt: utcDate("2025-01-03")
        )
        let effective = EnergyCalculator.effectiveReadings([first, second], auditCorrections: [lowerID, higherID])
        XCTAssertEqual(effective.first?.kwhValue, 120)
        let pace = EnergyCalculator.pace(
            readings: [first, second],
            auditCorrections: [lowerID, higherID],
            now: utcDate("2025-01-03")
        )
        assertDecimal(pace?.paceToDateKwh, "80")
    }

    func testCorrectionOnUnrelatedFieldDoesNotChangeEffectiveValue() {
        let reading = testReading("2025-01-01", 100, id: 1)
        let correction = AuditCorrection(
            entityType: .meterReading,
            entityID: reading.id,
            fieldName: "ReadingTimestamp",
            oldValue: "100",
            newValue: "999",
            correctedAt: utcDate("2025-01-02")
        )
        XCTAssertEqual(EnergyCalculator.effectiveReadings([reading], auditCorrections: [correction]).first?.kwhValue, 100)
    }

    func testOpenPromptBeforeEventWindowExcludesWholeWindow() {
        let trigger = testReading("2024-12-31", 900, id: 10)
        let prompt = MeterRegressionPrompt(
            mainMeterID: testMeterID,
            meterReadingID: trigger.id,
            previousMeterReadingID: testUUID(99)
        )
        let result = EnergyCalculator.observedDeviation(
            occurredAt: utcDate("2025-01-08"),
            readings: [testReading("2025-01-01", 1_000, id: 1), testReading("2025-01-15", 1_150, id: 2), trigger],
            regressionPrompts: [prompt],
            yearlyBaselineKwh: 3_650
        )
        XCTAssertEqual(result, .none)
    }

    func testOpenPromptAfterEventWindowDoesNotChangeWindow() {
        let trigger = testReading("2025-01-20", 100, id: 10)
        let prompt = MeterRegressionPrompt(
            mainMeterID: testMeterID,
            meterReadingID: trigger.id,
            previousMeterReadingID: testUUID(2)
        )
        let result = EnergyCalculator.observedDeviation(
            occurredAt: utcDate("2025-01-08"),
            readings: [testReading("2025-01-01", 1_000, id: 1), testReading("2025-01-15", 1_150, id: 2), trigger],
            regressionPrompts: [prompt],
            yearlyBaselineKwh: 3_650
        )
        XCTAssertEqual(result, .bump)
    }

    func testEventWindowIsInclusiveAtBothEnds() {
        let result = EnergyCalculator.observedDeviation(
            occurredAt: utcDate("2025-01-08"),
            readings: [
                testReading("2024-12-31", 900, id: 10),
                testReading("2025-01-01", 1_000, id: 1),
                testReading("2025-01-15", 1_150, id: 2),
                testReading("2025-01-16", 2_000, id: 11)
            ],
            yearlyBaselineKwh: 3_650
        )
        XCTAssertEqual(result, .bump)
    }

    func testDeviationThresholdTiesAreNone() {
        let first = testReading("2025-01-01", 1_000, id: 1)
        for (value, expected) in [(Decimal(1_154), ObservedDeviation.none), (1_126, .none), (1_155, .bump), (1_125, .dip)] {
            let result = EnergyCalculator.observedDeviation(
                occurredAt: utcDate("2025-01-08"),
                readings: [first, testReading("2025-01-15", value, id: 2)],
                yearlyBaselineKwh: 3_650,
                trendingThresholdKwh: 365
            )
            XCTAssertEqual(result, expected)
        }
    }

    func testMissingBaselineAndResetOnlyPeriodAreUndefinedOrNone() {
        let first = testReading("2025-01-01", 100, id: 1)
        let second = testReading("2025-01-02", 10, id: 2)
        XCTAssertNil(EnergyCalculator.status(
            pace: Pace(paceToDateKwh: 10, elapsedDays: 1),
            yearlyBaselineKwh: nil
        ).status)
        XCTAssertEqual(EnergyCalculator.observedDeviation(
            occurredAt: utcDate("2025-01-01"),
            readings: [first, second],
            yearlyBaselineKwh: nil
        ), .none)
        let reset = MeterRegressionPrompt(
            mainMeterID: testMeterID,
            meterReadingID: second.id,
            previousMeterReadingID: first.id,
            resolvedAt: utcDate("2025-01-02"),
            classification: .reset
        )
        XCTAssertNil(EnergyCalculator.pace(
            readings: [first, second],
            regressionPrompts: [reset],
            now: utcDate("2025-01-02")
        ))
    }

    func testExact365DayCutoffIsIncluded() {
        let pace = EnergyCalculator.pace(
            readings: [
                testReading("2024-12-31", 900, id: 1),
                testReading("2025-01-01", 1_000, id: 2),
                testReading("2026-01-01", 1_100, id: 3)
            ],
            now: utcDate("2026-01-01")
        )
        assertDecimal(pace?.paceToDateKwh, "100")
        assertDecimal(pace?.elapsedDays, "365")
    }

    func testFractionalElapsedTimeAndLowConfidenceStrictBoundary() {
        let first = testReading("2025-01-01", 100, id: 1)
        var second = testReading("2025-01-01", 110, id: 2)
        second.readingTimestamp = first.readingTimestamp.addingTimeInterval(12 * 3_600)
        let halfDay = EnergyCalculator.pace(readings: [first, second], now: second.readingTimestamp)
        assertDecimal(halfDay?.elapsedDays, "0.5")

        let readings = [testReading("2025-12-31", 100, id: 3), testReading("2026-01-01", 110, id: 4)]
        let at45 = EnergyCalculator.pace(readings: readings, now: utcDate("2026-02-15"), lowConfidenceGapDays: 45)
        XCTAssertEqual(at45?.isLowConfidence, false)
    }

    func testStatusTieAndSubOneAnnualThreshold() {
        let tied = EnergyCalculator.status(
            pace: Pace(paceToDateKwh: 110, elapsedDays: 365),
            yearlyBaselineKwh: 100,
            trendingThresholdKwh: 10
        )
        XCTAssertEqual(tied.status, .withinRange)
        assertDecimal(EnergyCalculator.thresholdToDate(annualThreshold: Decimal(string: "0.5")!, elapsedDays: 1), "0.5")
    }

    func testBonusDecayNormalizationBeforeAndAfterOneYear() {
        assertDecimal(EnergyCalculator.normalizeToDate(
            annualRate: 3_650,
            bonus: 100,
            elapsedDays: Decimal(string: "182.5")!
        ), "1875")
        assertDecimal(EnergyCalculator.normalizeToDate(annualRate: 3_650, bonus: 100, elapsedDays: 730), "7300")
    }

    func testMoneyRoundsExactHalvesAwayFromZero() {
        XCTAssertEqual(EnergyCalculator.roundedMoney(Decimal(string: "1.005")!), Decimal(string: "1.01")!)
        XCTAssertEqual(EnergyCalculator.roundedMoney(Decimal(string: "-1.005")!), Decimal(string: "-1.01")!)
        XCTAssertEqual(EnergyCalculator.roundedMoney(Decimal(string: "0.004")!), 0)
    }

    func testWorthDecisionUsesRoundedSavingsAndCarriesConfidence() {
        let current = testTariff(base: 0, price: 1)
        let pace = Pace(paceToDateKwh: 1, elapsedDays: 365, isLowConfidence: true)
        let belowHalfCent = EnergyCalculator.compareTariffs(
            current: current,
            candidate: CandidateTariff(monthlyBaseFee: 0, pricePerKwh: Decimal(string: "0.996")!),
            pace: pace
        )
        XCTAssertFalse(belowHalfCent.isNormalizedWorthSwitching)
        XCTAssertTrue(belowHalfCent.isLowConfidence)
        let halfCent = EnergyCalculator.compareTariffs(
            current: current,
            candidate: CandidateTariff(monthlyBaseFee: 0, pricePerKwh: Decimal(string: "0.995")!),
            pace: pace
        )
        assertDecimal(halfCent.roundedNormalizedSavings, "0.01")
        XCTAssertTrue(halfCent.isNormalizedWorthSwitching)
    }

    func testCurrentTariffTieBreakersAndFutureExclusion() {
        let start = CalendarDate(year: 2026, month: 1, day: 1)
        var older = testTariff(base: 1, price: 1, start: start)
        older.id = testUUID(1)
        older.createdAt = utcDate("2025-01-01")
        var newer = older
        newer.id = testUUID(2)
        newer.createdAt = utcDate("2025-02-01")
        var highestID = newer
        highestID.id = testUUID(3)
        var future = newer
        future.id = testUUID(4)
        future.contractStartDate = CalendarDate(year: 2026, month: 2, day: 1)
        XCTAssertEqual(
            EnergyCalculator.currentTariff(from: [older, future, newer], today: start)?.id,
            newer.id
        )
        XCTAssertEqual(
            EnergyCalculator.currentTariff(from: [older, highestID, newer], today: start)?.id,
            highestID.id
        )
    }

    func testCalendarMonthClampingAndDoneBeforeGate() {
        var tariff = testTariff(
            base: 1,
            price: 1,
            start: CalendarDate(year: 2026, month: 3, day: 31)
        )
        tariff.contractPeriodMonths = 1
        let gate = CalendarDate(year: 2026, month: 1, day: 30)
        let result = EnergyCalculator.tariffCheck(
            tariff: tariff,
            today: gate,
            tariffCheckDoneAt: CalendarDate(year: 2025, month: 12, day: 1),
            cadenceMonths: 1
        )
        XCTAssertEqual(result?.minimumTermEnd, CalendarDate(year: 2026, month: 4, day: 30))
        XCTAssertEqual(result?.gateOpens, gate)
        XCTAssertEqual(result?.isDue, true)
        XCTAssertNil(EnergyCalculator.tariffCheck(tariff: nil, today: gate, tariffCheckDoneAt: nil))
    }

    func testRolloverWithoutCapacityCannotProduceInventedPace() {
        let first = testReading("2025-01-01", 100, id: 1)
        let second = testReading("2025-01-02", 10, id: 2)
        let prompt = MeterRegressionPrompt(
            mainMeterID: testMeterID,
            meterReadingID: second.id,
            previousMeterReadingID: first.id,
            resolvedAt: utcDate("2025-01-02"),
            classification: .rollover,
            digitCapacityKwh: nil
        )
        XCTAssertNil(EnergyCalculator.pace(
            readings: [first, second],
            regressionPrompts: [prompt],
            now: utcDate("2025-01-02")
        ))
    }
}
