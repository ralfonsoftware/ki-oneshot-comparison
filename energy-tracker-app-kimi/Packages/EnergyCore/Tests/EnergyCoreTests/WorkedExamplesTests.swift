import XCTest
@testable import EnergyCore

final class WorkedExamplesTests: XCTestCase {
    func testE1Trending() {
        let readings = [testReading("2025-01-01", 10_000, id: 1), testReading("2025-01-31", 10_300, id: 2)]
        let pace = EnergyCalculator.pace(readings: readings, now: utcDate("2025-01-31"))
        assertDecimal(pace?.elapsedDays, "30")
        assertDecimal(pace?.paceToDateKwh, "300")
        let result = EnergyCalculator.status(pace: pace, yearlyBaselineKwh: 3_000)
        assertDecimal(result.baselineToDateKwh, "246.5753424657534")
        assertDecimal(result.thresholdToDateKwh, "8.21917808219178")
        assertDecimal(result.differenceKwh, "53.4246575342466")
        XCTAssertEqual(result.status, .trending)
    }

    func testE2BelowBaseline() {
        let pace = EnergyCalculator.pace(
            readings: [testReading("2025-01-01", 10_000, id: 1), testReading("2025-01-31", 10_245, id: 2)],
            now: utcDate("2025-01-31")
        )
        let result = EnergyCalculator.status(pace: pace, yearlyBaselineKwh: 3_000)
        assertDecimal(result.differenceKwh, "-1.5753424657534")
        XCTAssertEqual(result.status, .belowBaseline)
    }

    func testE3AnnualTieIsWithinRange() {
        let pace = EnergyCalculator.pace(
            readings: [testReading("2025-01-01", 0, id: 1), testReading("2026-01-01", 3_100, id: 2)],
            now: utcDate("2026-01-01")
        )
        let result = EnergyCalculator.status(pace: pace, yearlyBaselineKwh: 3_000)
        assertDecimal(result.differenceKwh, "100")
        assertDecimal(result.thresholdToDateKwh, "100")
        XCTAssertEqual(result.status, .withinRange)
    }

    func testE4OneKWhFloor() {
        let pace = EnergyCalculator.pace(
            readings: [testReading("2025-01-01", 10_000, id: 1), testReading("2025-01-02", 10_010, id: 2)],
            now: utcDate("2025-01-02")
        )
        let result = EnergyCalculator.status(pace: pace, yearlyBaselineKwh: 3_000)
        assertDecimal(result.thresholdToDateKwh, "1")
        assertDecimal(result.differenceKwh, "1.78082191780822")
        XCTAssertEqual(result.status, .trending)
    }

    func testE5ZeroThresholdRemainsZero() {
        let pace = EnergyCalculator.pace(
            readings: [testReading("2025-01-01", 10_000, id: 1), testReading("2025-01-02", 10_009, id: 2)],
            now: utcDate("2025-01-02")
        )
        let result = EnergyCalculator.status(pace: pace, yearlyBaselineKwh: 3_000, trendingThresholdKwh: 0)
        assertDecimal(result.thresholdToDateKwh, "0")
        assertDecimal(result.differenceKwh, "0.78082191780822")
        XCTAssertEqual(result.status, .trending)
    }

    func testE6ResolvedRollover() {
        let first = testReading("2025-01-01", 99_950, id: 1)
        let second = testReading("2025-01-11", 30, id: 2)
        let prompt = MeterRegressionPrompt(
            id: testUUID(20),
            mainMeterID: testMeterID,
            meterReadingID: second.id,
            previousMeterReadingID: first.id,
            resolvedAt: utcDate("2025-01-11"),
            classification: .rollover,
            digitCapacityKwh: 100_000
        )
        let pace = EnergyCalculator.pace(readings: [first, second], regressionPrompts: [prompt], now: utcDate("2025-01-11"))
        assertDecimal(pace?.paceToDateKwh, "80")
        assertDecimal(pace?.elapsedDays, "10")
    }

    func testE7ResetDropsConsumptionAndTime() {
        let first = testReading("2025-01-01", 5_000, id: 1)
        let second = testReading("2025-01-11", 100, id: 2)
        let third = testReading("2025-01-21", 200, id: 3)
        let prompt = MeterRegressionPrompt(
            mainMeterID: testMeterID,
            meterReadingID: second.id,
            previousMeterReadingID: first.id,
            resolvedAt: utcDate("2025-01-11"),
            classification: .reset
        )
        let pace = EnergyCalculator.pace(
            readings: [first, second, third],
            regressionPrompts: [prompt],
            now: utcDate("2025-01-21")
        )
        assertDecimal(pace?.paceToDateKwh, "100")
        assertDecimal(pace?.elapsedDays, "10")
    }

    func testE8OpenPromptExcludesTriggerAndLaterReadings() {
        let first = testReading("2025-01-01", 5_000, id: 1)
        let second = testReading("2025-01-11", 100, id: 2)
        let third = testReading("2025-01-21", 200, id: 3)
        let prompt = MeterRegressionPrompt(
            mainMeterID: testMeterID,
            meterReadingID: second.id,
            previousMeterReadingID: first.id
        )
        XCTAssertNil(EnergyCalculator.pace(
            readings: [first, second, third],
            regressionPrompts: [prompt],
            now: utcDate("2025-01-21")
        ))
    }

    func testE9OneReadingIsUndefined() {
        XCTAssertNil(EnergyCalculator.pace(
            readings: [testReading("2025-01-01", 10_000, id: 1)],
            now: utcDate("2025-01-02")
        ))
    }

    func testE10ZeroElapsedIsUndefined() {
        let first = testReading("2025-01-01", 10_000, id: 1)
        let second = testReading("2025-01-01", 10_010, id: 2)
        XCTAssertNil(EnergyCalculator.pace(readings: [first, second], now: utcDate("2025-01-02")))
    }

    func testE11ReadingOlderThan365DayWindowIsIgnored() {
        let readings = [
            testReading("2024-11-27", 9_000, id: 1),
            testReading("2025-12-22", 10_000, id: 2),
            testReading("2026-01-01", 10_100, id: 3)
        ]
        let pace = EnergyCalculator.pace(readings: readings, now: utcDate("2026-01-01"))
        assertDecimal(pace?.paceToDateKwh, "100")
        assertDecimal(pace?.elapsedDays, "10")
    }

    func testE12FortySixDayGapIsLowConfidence() {
        let readings = [testReading("2025-12-31", 10_000, id: 1), testReading("2026-01-01", 10_010, id: 2)]
        let pace = EnergyCalculator.pace(
            readings: readings,
            now: utcDate("2026-02-16"),
            lowConfidenceGapDays: 45
        )
        XCTAssertEqual(pace?.isLowConfidence, true)
    }

    func testT1BonusNormalizedAndIncludedSignals() {
        let current = testTariff(base: 10, price: Decimal(string: "0.3000")!)
        let candidate = CandidateTariff(
            monthlyBaseFee: 12,
            pricePerKwh: Decimal(string: "0.2800")!,
            switchingBonus: 100
        )
        let result = EnergyCalculator.compareTariffs(
            current: current,
            candidate: candidate,
            pace: Pace(paceToDateKwh: 3_000, elapsedDays: 365)
        )
        assertDecimal(result.currentAnnualCost, "1020")
        assertDecimal(result.candidateCostNoBonus, "984")
        assertDecimal(result.normalizedSavings, "36")
        assertDecimal(result.includedSavings, "136")
        XCTAssertTrue(result.isNormalizedWorthSwitching)
        XCTAssertTrue(result.isIncludedWorthSwitching)
    }

    func testT2WorthAndZeroTie() {
        let current = testTariff(base: 10, price: Decimal(string: "0.3000")!)
        let pace = Pace(paceToDateKwh: 3_000, elapsedDays: 365)
        let worth = EnergyCalculator.compareTariffs(
            current: current,
            candidate: CandidateTariff(monthlyBaseFee: 12, pricePerKwh: Decimal(string: "0.2880")!),
            pace: pace
        )
        assertDecimal(worth.candidateCostNoBonus, "1008")
        assertDecimal(worth.normalizedSavings, "12")
        XCTAssertTrue(worth.isNormalizedWorthSwitching)

        let tie = EnergyCalculator.compareTariffs(
            current: current,
            candidate: CandidateTariff(monthlyBaseFee: 12, pricePerKwh: Decimal(string: "0.2920")!),
            pace: pace
        )
        assertDecimal(tie.candidateCostNoBonus, "1020")
        assertDecimal(tie.normalizedSavings, "0")
        XCTAssertFalse(tie.isNormalizedWorthSwitching)
        XCTAssertFalse(tie.isIncludedWorthSwitching)
    }

    func testV1Bump() {
        let result = deviation(value: 1_150)
        XCTAssertEqual(result, .bump)
    }

    func testV2Dip() {
        XCTAssertEqual(deviation(value: 1_130), .dip)
    }

    func testV3None() {
        XCTAssertEqual(deviation(value: 1_142), .none)
    }

    func testR1GateOpensThreeMonthsBeforeMinimumTermEnd() {
        let tariff = testTariff(base: 10, price: Decimal(string: "0.3")!)
        let before = EnergyCalculator.tariffCheck(
            tariff: tariff,
            today: CalendarDate(year: 2026, month: 9, day: 30),
            tariffCheckDoneAt: nil
        )
        XCTAssertEqual(before?.minimumTermEnd, CalendarDate(year: 2027, month: 1, day: 1))
        XCTAssertEqual(before?.gateOpens, CalendarDate(year: 2026, month: 10, day: 1))
        XCTAssertEqual(before?.isDue, false)
        XCTAssertEqual(before?.nextDueDate, CalendarDate(year: 2026, month: 10, day: 1))
        let onGate = EnergyCalculator.tariffCheck(
            tariff: tariff,
            today: CalendarDate(year: 2026, month: 10, day: 1),
            tariffCheckDoneAt: nil
        )
        XCTAssertEqual(onGate?.isDue, true)
    }

    func testR2DoneDateStartsCadence() {
        let tariff = testTariff(base: 10, price: Decimal(string: "0.3")!)
        let done = CalendarDate(year: 2026, month: 10, day: 5)
        let result = EnergyCalculator.tariffCheck(
            tariff: tariff,
            today: done,
            tariffCheckDoneAt: done,
            cadenceMonths: 3
        )
        XCTAssertEqual(result?.isDue, false)
        XCTAssertEqual(result?.nextDueDate, CalendarDate(year: 2027, month: 1, day: 5))
        XCTAssertEqual(EnergyCalculator.tariffCheck(
            tariff: tariff,
            today: CalendarDate(year: 2027, month: 1, day: 5),
            tariffCheckDoneAt: done,
            cadenceMonths: 3
        )?.isDue, true)
    }

    private func deviation(value: Decimal) -> ObservedDeviation {
        EnergyCalculator.observedDeviation(
            occurredAt: utcDate("2025-01-08"),
            readings: [testReading("2025-01-01", 1_000, id: 1), testReading("2025-01-15", value, id: 2)],
            yearlyBaselineKwh: 3_650
        )
    }
}
