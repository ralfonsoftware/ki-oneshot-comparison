import Foundation
import Testing
@testable import EnergyCore

/// §5.8 worked examples. Yearly Baseline 3000 kWh, threshold 100 kWh unless stated.
@Suite("Worked examples §5.8 — Status")
struct StatusExampleTests {
    func status(_ readings: [ReadingInput], prompts: [PromptInput] = [], baseline: String? = "3000", threshold: String = "100", capacity: String? = nil, now: Date? = nil) -> StatusOutcome {
        StatusCalculator.compute(StatusInput(
            readings: readings,
            prompts: prompts,
            meterDigitCapacityKwh: capacity.map(dec),
            yearlyBaselineKwh: baseline.map(dec),
            trendingThresholdKwh: dec(threshold),
            lowConfidenceGapDays: 45,
            now: now ?? readings.map(\.timestamp).max() ?? utc(2026, 1, 1)
        ))
    }

    @Test("E1 trending")
    func e1() throws {
        let r = try #require(status([reading(2026, 1, 1, "10000"), reading(2026, 1, 31, "10300")]).result)
        #expect(r.pace.elapsedDays == 30)
        #expect(r.pace.paceKwh == 300)
        #expect(approx(r.baselineToDateKwh, dec("246.5753")))
        #expect(approx(r.thresholdToDateKwh, dec("8.2191")))
        #expect(approx(r.differenceKwh, dec("53.4247")))
        #expect(r.status == .trending)
    }

    @Test("E2 below baseline")
    func e2() throws {
        let r = try #require(status([reading(2026, 1, 1, "10000"), reading(2026, 1, 31, "10245")]).result)
        #expect(approx(r.differenceKwh, dec("-1.5753")))
        #expect(r.status == .belowBaseline)
    }

    @Test("E3 tie resolves to within range")
    func e3() throws {
        let r = try #require(status([reading(2025, 1, 1, "0.01"), reading(2026, 1, 1, "3100.01")]).result)
        #expect(r.pace.elapsedDays == 365)
        #expect(r.differenceKwh == 100)
        #expect(r.thresholdToDateKwh == 100)
        #expect(r.status == .withinRange)
    }

    @Test("E3 literally with a zero first reading")
    func e3Literal() throws {
        // A stored reading must be > 0, but the calculation itself accepts 0 as in the PRD example.
        let r = try #require(status([reading(2025, 1, 1, "0"), reading(2026, 1, 1, "3100")]).result)
        #expect(r.status == .withinRange)
    }

    @Test("E4 one-day floor of 1 kWh")
    func e4() throws {
        let r = try #require(status([reading(2026, 1, 1, "10000"), reading(2026, 1, 2, "10010")]).result)
        #expect(r.thresholdToDateKwh == 1)
        #expect(approx(r.baselineToDateKwh, dec("8.2191")))
        #expect(approx(r.differenceKwh, dec("1.7808")))
        #expect(r.status == .trending)
    }

    @Test("E5 threshold 0 means any overshoot")
    func e5() throws {
        let r = try #require(status([reading(2026, 1, 1, "10000"), reading(2026, 1, 2, "10009")], threshold: "0").result)
        #expect(r.thresholdToDateKwh == 0)
        #expect(approx(r.differenceKwh, dec("0.7808")))
        #expect(r.status == .trending)
    }

    @Test("E6 rollover adds capacity − previous + current")
    func e6() throws {
        let a = reading(2026, 1, 1, "99950"), b = reading(2026, 1, 11, "30")
        let prompt = PromptInput(readingId: b.id, previousReadingId: a.id, resolvedAt: utc(2026, 1, 11), classification: .rollover, digitCapacityKwh: dec("100000"))
        let pace = try #require(Pace.compute(readings: [a, b], prompts: [prompt], meterDigitCapacity: nil))
        #expect(pace.paceKwh == 80)
        #expect(pace.elapsedDays == 10)
    }

    @Test("E6 rollover falls back to the Main Meter capacity")
    func e6MeterCapacity() throws {
        let a = reading(2026, 1, 1, "99950"), b = reading(2026, 1, 11, "30")
        let prompt = PromptInput(readingId: b.id, previousReadingId: a.id, resolvedAt: utc(2026, 1, 11), classification: .rollover)
        let pace = try #require(Pace.compute(readings: [a, b], prompts: [prompt], meterDigitCapacity: dec("100000")))
        #expect(pace.paceKwh == 80)
    }

    @Test("E7 reset adds nothing")
    func e7() throws {
        let a = reading(2026, 1, 1, "5000"), b = reading(2026, 1, 11, "100"), c = reading(2026, 1, 21, "200")
        let prompt = PromptInput(readingId: b.id, previousReadingId: a.id, resolvedAt: utc(2026, 1, 11), classification: .reset)
        let pace = try #require(Pace.compute(readings: [a, b, c], prompts: [prompt], meterDigitCapacity: nil))
        #expect(pace.paceKwh == 100)
        #expect(pace.elapsedDays == 10)
    }

    @Test("E8 open prompt excludes its reading and everything after")
    func e8() {
        let a = reading(2026, 1, 1, "5000"), b = reading(2026, 1, 11, "100"), c = reading(2026, 1, 21, "200")
        let prompt = PromptInput(readingId: b.id, previousReadingId: a.id)
        #expect(Pace.compute(readings: [a, b, c], prompts: [prompt], meterDigitCapacity: nil) == nil)
        #expect(status([a, b, c], prompts: [prompt]) == .undefined(.awaitingDecision))
    }

    @Test("E9 one reading is undefined")
    func e9() {
        #expect(status([reading(2026, 1, 1, "10000")]) == .undefined(.notEnoughReadings))
        #expect(status([]) == .undefined(.notEnoughReadings))
    }

    @Test("E10 same timestamp is undefined")
    func e10() {
        #expect(status([reading(2026, 1, 1, "10000"), reading(2026, 1, 1, "10010")]) == .undefined(.notEnoughReadings))
    }

    @Test("E11 readings older than 365 days are outside the window")
    func e11() throws {
        let latest = utc(2026, 6, 1)
        let old = ReadingInput(timestamp: latest.addingTimeInterval(-400 * 86_400), value: 1000)
        let mid = ReadingInput(timestamp: latest.addingTimeInterval(-10 * 86_400), value: 5000)
        let last = ReadingInput(timestamp: latest, value: 5100)
        let pace = try #require(Pace.compute(readings: [old, mid, last], prompts: [], meterDigitCapacity: nil))
        #expect(pace.paceKwh == 100)
        #expect(pace.elapsedDays == 10)
        #expect(pace.includedReadingCount == 2)
    }

    @Test("E12 low confidence after the gap")
    func e12() throws {
        let readings = [reading(2026, 1, 1, "1000"), reading(2026, 2, 1, "1200")]
        let now = utc(2026, 2, 1).addingTimeInterval(46 * 86_400)
        let r = try #require(status(readings, now: now).result)
        #expect(r.isLowConfidence)
        #expect(Pace.isLowConfidence(latestReading: utc(2026, 2, 1), now: now, gapDays: 45))
        // Exactly 45 days is not yet low confidence.
        #expect(!Pace.isLowConfidence(latestReading: utc(2026, 2, 1), now: utc(2026, 2, 1).addingTimeInterval(45 * 86_400), gapDays: 45))
    }

    @Test("No baseline makes the Status undefined")
    func noBaseline() {
        #expect(status([reading(2026, 1, 1, "10000"), reading(2026, 1, 31, "10300")], baseline: nil) == .undefined(.noBaseline))
    }

    @Test("Ordering: same timestamp ordered by lower-case id")
    func ordering() {
        let a = ReadingInput(id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!, timestamp: utc(2026, 1, 1), value: 1)
        let b = ReadingInput(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!, timestamp: utc(2026, 1, 1), value: 2)
        #expect(Readings.ordered([a, b]).map(\.id) == [b.id, a.id])
    }

    @Test("Effective value: newest correction wins, ties by highest id")
    func effective() {
        let c1 = CorrectionInput(id: uid(1), fieldName: "KwhValue", newValue: "10", correctedAt: utc(2026, 1, 1))
        let c2 = CorrectionInput(id: uid(2), fieldName: "KwhValue", newValue: "20", correctedAt: utc(2026, 1, 1))
        let c3 = CorrectionInput(id: uid(3), fieldName: "KwhValue", newValue: "5", correctedAt: utc(2025, 1, 1))
        #expect(Readings.effectiveValue(original: 1, corrections: [c1, c2, c3]) == 20)
        #expect(Readings.effectiveValue(original: 1, corrections: []) == 1)
    }

    @Test("Only the earliest open prompt excludes")
    func earliestOpenPrompt() throws {
        let a = reading(2026, 1, 1, "500"), b = reading(2026, 1, 11, "600"), c = reading(2026, 1, 21, "100"), d = reading(2026, 1, 31, "50")
        let p1 = PromptInput(readingId: d.id, previousReadingId: c.id)
        let p2 = PromptInput(readingId: c.id, previousReadingId: b.id)
        let pace = try #require(Pace.compute(readings: [a, b, c, d], prompts: [p1, p2], meterDigitCapacity: nil))
        #expect(pace.paceKwh == 100)
        #expect(Readings.activeOpenPrompt(readings: Readings.ordered([a, b, c, d]), prompts: [p1, p2])?.id == p2.id)
    }
}

@Suite("Bonus-Decay Normalization §5.4")
struct NormalizationTests {
    @Test func prorates() {
        #expect(Normalization.normalizeToDate(annualRate: 365, bonus: 0, elapsedSeconds: 86_400 * 10) == 10)
    }

    @Test func bonusDecaysToZeroAfterOneYear() {
        #expect(Normalization.normalizeToDate(annualRate: 0, bonus: 100, elapsedSeconds: 0) == 100)
        #expect(Normalization.normalizeToDate(annualRate: 0, bonus: 100, elapsedSeconds: 86_400 * 365) == 0)
        #expect(Normalization.normalizeToDate(annualRate: 0, bonus: 100, elapsedSeconds: 86_400 * 730) == 0)
        #expect(approx(Normalization.normalizeToDate(annualRate: 0, bonus: 365, elapsedSeconds: 86_400 * 100), 265))
    }

    @Test func thresholdFloor() {
        #expect(Normalization.thresholdToDate(annualThreshold: 100, elapsedSeconds: 86_400) == 1)
        #expect(Normalization.thresholdToDate(annualThreshold: dec("0.5"), elapsedSeconds: 86_400) == dec("0.5"))
        #expect(Normalization.thresholdToDate(annualThreshold: 0, elapsedSeconds: 86_400) == 0)
    }
}

@Suite("Tariff comparison §5.5")
struct TariffComparisonTests {
    let current = TariffPrice(monthlyBaseFee: dec("10.00"), pricePerKwh: dec("0.3000"))

    @Test("T1 bonus normalized and included")
    func t1() {
        let c = TariffComparator.compare(annualPaceKwh: 3000, current: current, candidate: TariffPrice(monthlyBaseFee: dec("12.00"), pricePerKwh: dec("0.2800")), bonus: 100)
        #expect(c.currentAnnualCost == dec("1020.00"))
        #expect(c.candidateCostNoBonus == dec("984.00"))
        #expect(c.normalizedSavingsRounded == dec("36.00"))
        #expect(c.normalizedWorthSwitching)
        #expect(c.includedSavingsRounded == dec("136.00"))
        #expect(c.includedWorthSwitching)
    }

    @Test("T2 savings of exactly 0.00 is not worth switching")
    func t2() {
        let worth = TariffComparator.compare(annualPaceKwh: 3000, current: current, candidate: TariffPrice(monthlyBaseFee: dec("12.00"), pricePerKwh: dec("0.2880")), bonus: 0)
        #expect(worth.candidateCostNoBonus == dec("1008.00"))
        #expect(worth.normalizedSavingsRounded == dec("12.00"))
        #expect(worth.normalizedWorthSwitching)
        let notWorth = TariffComparator.compare(annualPaceKwh: 3000, current: current, candidate: TariffPrice(monthlyBaseFee: dec("12.00"), pricePerKwh: dec("0.2920")), bonus: 0)
        #expect(notWorth.candidateCostNoBonus == dec("1020.00"))
        #expect(notWorth.normalizedSavingsRounded == 0)
        #expect(!notWorth.normalizedWorthSwitching)
        #expect(!notWorth.includedWorthSwitching)
    }

    @Test("Rounding half away from zero decides")
    func rounding() {
        // savings 0.005 rounds to 0.01 -> worth; −0.005 rounds to −0.01 -> not worth.
        let tiny = TariffComparator.compare(annualPaceKwh: 0, current: TariffPrice(monthlyBaseFee: dec("1.000416666666666666666666666666666667"), pricePerKwh: 1), candidate: TariffPrice(monthlyBaseFee: 1, pricePerKwh: 1), bonus: 0)
        #expect(tiny.normalizedSavingsRounded == dec("0.01"))
        #expect(DecimalMath.rounded(dec("0.005"), scale: 2) == dec("0.01"))
        #expect(DecimalMath.rounded(dec("-0.005"), scale: 2) == dec("-0.01"))
    }

    @Test("Annual pace from pace and elapsed")
    func annualPace() {
        #expect(TariffComparator.annualPace(paceKwh: 300, elapsedSeconds: 30 * 86_400) == dec("3650"))
    }

    @Test("Comparison carries the low-confidence flag")
    func lowConfidence() {
        let c = TariffComparator.compare(annualPaceKwh: 3000, current: current, candidate: current, bonus: 0, isLowConfidence: true)
        #expect(c.isLowConfidence)
    }
}

@Suite("Observed deviation §5.6")
struct DeviationTests {
    func deviation(_ last: String) -> Deviation {
        DeviationCalculator.compute(
            occurredAt: utc(2026, 1, 8),
            readings: [reading(2026, 1, 1, "1000"), reading(2026, 1, 15, last)],
            prompts: [], meterDigitCapacityKwh: nil, yearlyBaselineKwh: 3650, trendingThresholdKwh: 100
        )
    }

    @Test("V1 bump") func v1() { #expect(deviation("1150") == .bump) }
    @Test("V2 dip") func v2() { #expect(deviation("1130") == .dip) }
    @Test("V3 none") func v3() { #expect(deviation("1142") == .none) }

    @Test("Readings outside ±7 days are ignored")
    func window() {
        let d = DeviationCalculator.compute(occurredAt: utc(2026, 1, 8), readings: [reading(2025, 12, 31, "1000"), reading(2026, 1, 15, "1150")], prompts: [], meterDigitCapacityKwh: nil, yearlyBaselineKwh: 3650, trendingThresholdKwh: 100)
        #expect(d == .none)
    }

    @Test("Open prompt before the window removes the whole window")
    func openPromptOutsideWindow() {
        let a = reading(2025, 12, 1, "5000"), b = reading(2025, 12, 20, "100")
        let c = reading(2026, 1, 1, "1000"), d = reading(2026, 1, 15, "1150")
        let p = PromptInput(readingId: b.id, previousReadingId: a.id)
        #expect(DeviationCalculator.compute(occurredAt: utc(2026, 1, 8), readings: [a, b, c, d], prompts: [p], meterDigitCapacityKwh: nil, yearlyBaselineKwh: 3650, trendingThresholdKwh: 100) == .none)
    }

    @Test("No baseline gives none")
    func noBaseline() {
        #expect(DeviationCalculator.compute(occurredAt: utc(2026, 1, 8), readings: [reading(2026, 1, 1, "1000"), reading(2026, 1, 15, "1150")], prompts: [], meterDigitCapacityKwh: nil, yearlyBaselineKwh: nil, trendingThresholdKwh: 100) == .none)
    }
}

@Suite("Tariff Check §5.7 and current tariff")
struct TariffCheckTests {
    let start = CalendarDate(year: 2026, month: 1, day: 1)

    @Test("R1 gate opens three months before the minimum term ends")
    func r1() throws {
        let before = try #require(TariffCheck.state(contractStartDate: start, contractPeriodMonths: 12, doneOn: nil, cadenceMonths: 3, today: CalendarDate(year: 2026, month: 9, day: 30)))
        #expect(before.gateOpens == CalendarDate(year: 2026, month: 10, day: 1))
        #expect(before.minimumTermEnd == CalendarDate(year: 2027, month: 1, day: 1))
        #expect(!before.isDue)
        let on = try #require(TariffCheck.state(contractStartDate: start, contractPeriodMonths: 12, doneOn: nil, cadenceMonths: 3, today: CalendarDate(year: 2026, month: 10, day: 1)))
        #expect(on.isDue)
    }

    @Test("R2 done resets the cycle by the cadence")
    func r2() throws {
        let done = CalendarDate(year: 2026, month: 10, day: 5)
        let s = try #require(TariffCheck.state(contractStartDate: start, contractPeriodMonths: 12, doneOn: done, cadenceMonths: 3, today: CalendarDate(year: 2027, month: 1, day: 4)))
        #expect(s.dueDate == CalendarDate(year: 2027, month: 1, day: 5))
        #expect(!s.isDue)
        let due = try #require(TariffCheck.state(contractStartDate: start, contractPeriodMonths: 12, doneOn: done, cadenceMonths: 3, today: CalendarDate(year: 2027, month: 1, day: 5)))
        #expect(due.isDue)
    }

    @Test("Done before the gate is ignored so a new tariff starts fresh")
    func doneBeforeGate() throws {
        let s = try #require(TariffCheck.state(contractStartDate: start, contractPeriodMonths: 12, doneOn: CalendarDate(year: 2026, month: 9, day: 1), cadenceMonths: 3, today: CalendarDate(year: 2026, month: 10, day: 1)))
        #expect(s.isDue)
    }

    @Test("Gate stays open after the minimum term ends")
    func staysOpen() throws {
        let s = try #require(TariffCheck.state(contractStartDate: start, contractPeriodMonths: 12, doneOn: nil, cadenceMonths: 3, today: CalendarDate(year: 2030, month: 1, day: 1)))
        #expect(s.isDue)
    }

    @Test("No current tariff means no Tariff Check")
    func noTariff() {
        #expect(TariffCheck.state(contractStartDate: nil, contractPeriodMonths: 12, doneOn: nil, cadenceMonths: 3, today: start) == nil)
    }

    @Test("Current tariff: latest start not in the future, ties by createdAt then id")
    func current() {
        let today = CalendarDate(year: 2026, month: 6, day: 1)
        let a = TariffRef(id: uid(1), startDate: CalendarDate(year: 2025, month: 1, day: 1), createdAt: utc(2025, 1, 1))
        let b = TariffRef(id: uid(2), startDate: CalendarDate(year: 2026, month: 1, day: 1), createdAt: utc(2026, 1, 1))
        let future = TariffRef(id: uid(3), startDate: CalendarDate(year: 2027, month: 1, day: 1), createdAt: utc(2026, 5, 1))
        #expect(Tariffs.currentTariffId([a, b, future], today: today) == uid(2))
        let tieNewer = TariffRef(id: uid(4), startDate: b.startDate, createdAt: utc(2026, 2, 1))
        #expect(Tariffs.currentTariffId([a, b, tieNewer], today: today) == uid(4))
        let tieSameCreated = TariffRef(id: uid(5), startDate: b.startDate, createdAt: b.createdAt)
        #expect(Tariffs.currentTariffId([b, tieSameCreated], today: today) == uid(5))
        #expect(Tariffs.currentTariffId([future], today: today) == nil)
        #expect(Tariffs.duplicateStartDates([a, b, tieNewer]).count == 1)
    }

    @Test("Calendar month arithmetic clamps the day")
    func months() {
        #expect(CalendarDate(year: 2026, month: 1, day: 31).adding(months: 1) == CalendarDate(year: 2026, month: 2, day: 28))
        #expect(CalendarDate(year: 2026, month: 3, day: 15).adding(months: -3) == CalendarDate(year: 2025, month: 12, day: 15))
        #expect(CalendarDate(iso: "2026-02-30") == nil)
        #expect(CalendarDate(iso: "2026-02-28") == CalendarDate(year: 2026, month: 2, day: 28))
    }
}

@Suite("Regression detection FR-11")
struct RegressionTests {
    @Test("Detects by chronological order, not entry order")
    func backfill() {
        let a = reading(2026, 1, 1, "1000"), c = reading(2026, 1, 21, "1200")
        // Backfilled between a and c with a lower value than a.
        let b = reading(2026, 1, 11, "900")
        let found = RegressionDetector.regressions(in: [a, c, b])
        #expect(found == [RegressionCandidate(readingId: b.id, previousReadingId: a.id)])
    }

    @Test("Plan creates, keeps and deletes prompts")
    func plan() {
        let a = reading(2026, 1, 1, "1000"), b = reading(2026, 1, 11, "900"), c = reading(2026, 1, 21, "1200")
        let stale = PromptInput(readingId: c.id, previousReadingId: b.id)
        let resolvedStale = PromptInput(readingId: a.id, previousReadingId: b.id, resolvedAt: utc(2026, 1, 1), classification: .reset)
        let plan = RegressionDetector.plan(readings: [a, b, c], prompts: [stale, resolvedStale])
        #expect(plan.create == [RegressionCandidate(readingId: b.id, previousReadingId: a.id)])
        #expect(plan.deleteOpenPromptIds == [stale.id])
    }
}

@Suite("Validation")
struct ValidationTests {
    @Test func readings() {
        #expect(Validation.validateReading(0) == .notPositive)
        #expect(Validation.validateReading(-1) == .notPositive)
        #expect(Validation.validateReading(dec("1000000000000000")) == .tooLarge)
        #expect(Validation.validateReading(dec("999999999999999.99")) == nil)
        #expect(Validation.validateReading(dec("1.234")) == .tooManyDecimals)
        #expect(Validation.validateReading(dec("12345.60")) == nil)
    }

    @Test func tariffs() {
        let ok = CalendarDate(year: 2026, month: 1, day: 1)
        #expect(Validation.validateTariff(monthlyBaseFee: 0, pricePerKwh: dec("0.3"), currency: "EUR", contractPeriodMonths: 12, startDate: ok).isEmpty)
        #expect(Validation.validateTariff(monthlyBaseFee: -1, pricePerKwh: 0, currency: "eur", contractPeriodMonths: 0, startDate: CalendarDate(year: 1899, month: 12, day: 31)).count == 5)
        #expect(Validation.validateTariff(monthlyBaseFee: 0, pricePerKwh: 1, currency: "EUR", contractPeriodMonths: 1200, startDate: CalendarDate.latestTariffStart).isEmpty)
    }

    @Test func names() {
        #expect(Validation.normalizedName("  Kitchen ") == "Kitchen")
        #expect(Validation.normalizedName("   ") == nil)
        #expect(Validation.normalizedName(String(repeating: "x", count: 201)) == nil)
    }
}
