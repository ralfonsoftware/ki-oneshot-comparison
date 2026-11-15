import Foundation

/// Pure, deterministic calculations from PRD §5. All kWh and money arithmetic uses `Decimal`.
public enum EnergyCalculator {
    private static let secondsPerDay: Decimal = 86_400

    /// Orders readings by timestamp, then by the lowercase UUID string's byte order.
    public static func orderedReadings(_ readings: [MeterReading]) -> [MeterReading] {
        readings.sorted { lhs, rhs in
            if lhs.readingTimestamp != rhs.readingTimestamp {
                return lhs.readingTimestamp < rhs.readingTimestamp
            }
            return uuidOrder(lhs.id) < uuidOrder(rhs.id)
        }
    }

    /// Applies the newest `KwhValue` correction, with ties resolved by highest correction id.
    public static func effectiveReadings(
        _ readings: [MeterReading],
        auditCorrections: [AuditCorrection]
    ) -> [EffectiveReading] {
        let corrections = auditCorrections.filter {
            $0.entityType == .meterReading && $0.fieldName == "KwhValue"
        }
        return orderedReadings(readings).map { reading in
            let newest = corrections
                .filter { $0.entityID == reading.id }
                .max { lhs, rhs in
                    if lhs.correctedAt != rhs.correctedAt {
                        return lhs.correctedAt < rhs.correctedAt
                    }
                    return uuidOrder(lhs.id) < uuidOrder(rhs.id)
                }
            let effectiveValue = newest.flatMap { exactDecimal(fromInvariantString: $0.newValue) } ?? reading.kwhValue
            return EffectiveReading(
                id: reading.id,
                mainMeterID: reading.mainMeterID,
                kwhValue: effectiveValue,
                readingTimestamp: reading.readingTimestamp
            )
        }
    }

    /// Shared Bonus-Decay Normalization from §5.4.
    /// - Precondition: `elapsedDays` is nonnegative.
    public static func normalizeToDate(
        annualRate: Decimal,
        bonus: Decimal = 0,
        elapsedDays: Decimal
    ) -> Decimal {
        precondition(elapsedDays >= 0, "Elapsed time must not be negative")
        // Multiply before dividing so exact anniversary and threshold ties do not
        // acquire a one-ulp bias from a repeating Decimal division.
        let annualPart = annualRate * elapsedDays / 365
        let remainingFraction = max(0, (365 - elapsedDays) / 365)
        return annualPart + bonus * remainingFraction
    }

    /// The 1 kWh-capped floor used by status and observed deviation.
    public static func thresholdToDate(annualThreshold: Decimal, elapsedDays: Decimal) -> Decimal {
        precondition(annualThreshold >= 0, "Annual threshold must not be negative")
        precondition(elapsedDays >= 0, "Elapsed time must not be negative")
        return max(min(annualThreshold, 1), normalizeToDate(annualRate: annualThreshold, elapsedDays: elapsedDays))
    }

    /// Computes §5.2 pace. Nil represents undefined pace.
    public static func pace(
        readings: [MeterReading],
        regressionPrompts: [MeterRegressionPrompt] = [],
        auditCorrections: [AuditCorrection] = [],
        now: Date,
        lowConfidenceGapDays: Int = 45
    ) -> Pace? {
        let ordered = effectiveReadings(readings, auditCorrections: auditCorrections)
        guard !ordered.isEmpty else { return nil }

        let includedBeforeWindow = applyingOpenPromptExclusion(to: ordered, readings: ordered, prompts: regressionPrompts)
        guard let latest = includedBeforeWindow.last else { return nil }
        let cutoff = latest.readingTimestamp.addingTimeInterval(-365 * 86_400)
        let window = includedBeforeWindow.filter { $0.readingTimestamp >= cutoff }
        guard window.count >= 2, let pairResult = walkPairs(window, prompts: regressionPrompts), pairResult.seconds > 0 else {
            return nil
        }

        let elapsedDays = pairResult.seconds / secondsPerDay
        let daysSinceLast = Decimal(now.timeIntervalSince(latest.readingTimestamp)) / secondsPerDay
        return Pace(
            paceToDateKwh: pairResult.kwh,
            elapsedDays: elapsedDays,
            latestReadingTimestamp: latest.readingTimestamp,
            isLowConfidence: daysSinceLast > Decimal(lowConfidenceGapDays)
        )
    }

    /// Computes §5.3 status from an already calculated pace.
    public static func status(
        pace: Pace?,
        yearlyBaselineKwh: Decimal?,
        trendingThresholdKwh: Decimal = 100
    ) -> StatusEvaluation {
        guard let pace, let yearlyBaselineKwh else {
            return StatusEvaluation(status: nil, pace: pace)
        }
        let baseline = normalizeToDate(annualRate: yearlyBaselineKwh, elapsedDays: pace.elapsedDays)
        let threshold = thresholdToDate(annualThreshold: trendingThresholdKwh, elapsedDays: pace.elapsedDays)
        let difference = pace.paceToDateKwh - baseline
        let status: ConsumptionStatus
        if difference > threshold {
            status = .trending
        } else if difference < 0 {
            status = .belowBaseline
        } else {
            status = .withinRange
        }
        return StatusEvaluation(
            status: status,
            pace: pace,
            baselineToDateKwh: baseline,
            thresholdToDateKwh: threshold,
            differenceKwh: difference
        )
    }

    /// Computes pace and status together from stored readings and corrections.
    public static func status(
        readings: [MeterReading],
        regressionPrompts: [MeterRegressionPrompt] = [],
        auditCorrections: [AuditCorrection] = [],
        settings: StatusSettings,
        now: Date
    ) -> StatusEvaluation {
        let pace = pace(
            readings: readings,
            regressionPrompts: regressionPrompts,
            auditCorrections: auditCorrections,
            now: now,
            lowConfidenceGapDays: settings.lowConfidenceGapDays
        )
        return status(
            pace: pace,
            yearlyBaselineKwh: settings.yearlyBaselineKwh,
            trendingThresholdKwh: settings.trendingThresholdKwh
        )
    }

    /// Rounds money to two places, with exact halves rounded away from zero.
    public static func roundedMoney(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }

    /// Compares both tariff signals. Intermediate values are never rounded.
    public static func compareTariffs(
        current: Tariff,
        candidate: CandidateTariff,
        pace: Pace
    ) -> TariffComparison {
        precondition(pace.elapsedDays > 0, "Tariff comparison requires a defined pace")
        let annualPace = pace.paceToDateKwh * 365 / pace.elapsedDays
        let currentAnnualCost = current.monthlyBaseFee * 12 + current.pricePerKwh * annualPace
        let candidateNoBonus = candidate.monthlyBaseFee * 12 + candidate.pricePerKwh * annualPace
        let candidateNormalized = normalizeToDate(
            annualRate: candidateNoBonus,
            bonus: candidate.switchingBonus,
            elapsedDays: 365
        )
        let normalizedSavings = currentAnnualCost - candidateNormalized
        let candidateIncluded = candidateNoBonus - candidate.switchingBonus
        let includedSavings = currentAnnualCost - candidateIncluded
        let roundedNormalized = roundedMoney(normalizedSavings)
        let roundedIncluded = roundedMoney(includedSavings)
        return TariffComparison(
            annualPaceKwh: annualPace,
            currentAnnualCost: currentAnnualCost,
            candidateCostNoBonus: candidateNoBonus,
            candidateNormalizedCost: candidateNormalized,
            normalizedSavings: normalizedSavings,
            candidateIncludedCost: candidateIncluded,
            includedSavings: includedSavings,
            roundedNormalizedSavings: roundedNormalized,
            roundedIncludedSavings: roundedIncluded,
            isNormalizedWorthSwitching: roundedNormalized > 0,
            isIncludedWorthSwitching: roundedIncluded > 0,
            isLowConfidence: pace.isLowConfidence
        )
    }

    /// Selects the current tariff: latest nonfuture start, then newest creation, then highest id.
    public static func currentTariff(from tariffs: [Tariff], today: CalendarDate) -> Tariff? {
        tariffs
            .filter { $0.contractStartDate <= today }
            .max { lhs, rhs in
                if lhs.contractStartDate != rhs.contractStartDate {
                    return lhs.contractStartDate < rhs.contractStartDate
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return uuidOrder(lhs.id) < uuidOrder(rhs.id)
            }
    }

    /// Computes the §5.6 deviation in the inclusive ±7-day event window.
    public static func observedDeviation(
        occurredAt: Date,
        readings: [MeterReading],
        regressionPrompts: [MeterRegressionPrompt] = [],
        auditCorrections: [AuditCorrection] = [],
        yearlyBaselineKwh: Decimal?,
        trendingThresholdKwh: Decimal = 100
    ) -> ObservedDeviation {
        guard let yearlyBaselineKwh else { return .none }
        let allOrdered = effectiveReadings(readings, auditCorrections: auditCorrections)
        let start = occurredAt.addingTimeInterval(-7 * 86_400)
        let end = occurredAt.addingTimeInterval(7 * 86_400)
        let window = allOrdered.filter { $0.readingTimestamp >= start && $0.readingTimestamp <= end }
        let included = applyingOpenPromptExclusion(to: window, readings: allOrdered, prompts: regressionPrompts)
        guard included.count >= 2,
              let pairResult = walkPairs(included, prompts: regressionPrompts),
              pairResult.seconds > 0 else {
            return .none
        }
        let elapsedDays = pairResult.seconds / secondsPerDay
        let expected = normalizeToDate(annualRate: yearlyBaselineKwh, elapsedDays: elapsedDays)
        let threshold = thresholdToDate(annualThreshold: trendingThresholdKwh, elapsedDays: elapsedDays)
        let difference = pairResult.kwh - expected
        if difference > threshold { return .bump }
        if difference < -threshold { return .dip }
        return .none
    }

    /// Computes the §5.6 deviation for an event DTO.
    public static func observedDeviation(
        event: EnergyEvent,
        readings: [MeterReading],
        regressionPrompts: [MeterRegressionPrompt] = [],
        auditCorrections: [AuditCorrection] = [],
        yearlyBaselineKwh: Decimal?,
        trendingThresholdKwh: Decimal = 100
    ) -> ObservedDeviation {
        observedDeviation(
            occurredAt: event.occurredAt,
            readings: readings,
            regressionPrompts: regressionPrompts,
            auditCorrections: auditCorrections,
            yearlyBaselineKwh: yearlyBaselineKwh,
            trendingThresholdKwh: trendingThresholdKwh
        )
    }

    /// Computes calendar-based tariff-check state. Nil means there is no current tariff.
    public static func tariffCheck(
        tariff: Tariff?,
        today: CalendarDate,
        tariffCheckDoneAt: CalendarDate?,
        cadenceMonths: Int = 3
    ) -> TariffCheck? {
        guard let tariff else { return nil }
        precondition((1...24).contains(cadenceMonths), "Cadence must be in 1...24 months")
        let minimumTermEnd = tariff.contractStartDate.adding(months: tariff.contractPeriodMonths)
        let gateOpens = minimumTermEnd.adding(months: -3)
        guard today >= gateOpens else {
            return TariffCheck(
                minimumTermEnd: minimumTermEnd,
                gateOpens: gateOpens,
                isDue: false,
                nextDueDate: gateOpens
            )
        }
        guard let tariffCheckDoneAt, tariffCheckDoneAt >= gateOpens else {
            return TariffCheck(
                minimumTermEnd: minimumTermEnd,
                gateOpens: gateOpens,
                isDue: true,
                nextDueDate: nil
            )
        }
        let nextDue = tariffCheckDoneAt.adding(months: cadenceMonths)
        let due = today >= nextDue
        return TariffCheck(
            minimumTermEnd: minimumTermEnd,
            gateOpens: gateOpens,
            isDue: due,
            nextDueDate: due ? nil : nextDue
        )
    }

    private struct PairResult {
        var kwh: Decimal
        var seconds: Decimal
    }

    private static func walkPairs(
        _ readings: [EffectiveReading],
        prompts: [MeterRegressionPrompt]
    ) -> PairResult? {
        guard readings.count >= 2 else { return nil }
        var totalKwh: Decimal = 0
        var totalSeconds: Decimal = 0
        for index in 1..<readings.count {
            let previous = readings[index - 1]
            let current = readings[index]
            let prompt = prompts.first {
                $0.meterReadingID == current.id && $0.resolvedAt != nil && $0.classification != nil
            }
            switch prompt?.classification {
            case .reset:
                continue
            case .rollover:
                guard let capacity = prompt?.digitCapacityKwh else { return nil }
                totalKwh += (capacity - previous.kwhValue) + current.kwhValue
                totalSeconds += Decimal(current.readingTimestamp.timeIntervalSince(previous.readingTimestamp))
            case nil:
                totalKwh += current.kwhValue - previous.kwhValue
                totalSeconds += Decimal(current.readingTimestamp.timeIntervalSince(previous.readingTimestamp))
            }
        }
        return PairResult(kwh: totalKwh, seconds: totalSeconds)
    }

    /// `subset` and `readings` differ for event windows so a trigger before the window excludes it all.
    private static func applyingOpenPromptExclusion(
        to subset: [EffectiveReading],
        readings: [EffectiveReading],
        prompts: [MeterRegressionPrompt]
    ) -> [EffectiveReading] {
        let openReadingIDs = Set(prompts.filter { $0.resolvedAt == nil }.map(\.meterReadingID))
        guard !openReadingIDs.isEmpty,
              let trigger = readings.first(where: { openReadingIDs.contains($0.id) }) else {
            return subset
        }
        return subset.filter { reading in
            if reading.readingTimestamp != trigger.readingTimestamp {
                return reading.readingTimestamp < trigger.readingTimestamp
            }
            return uuidOrder(reading.id) < uuidOrder(trigger.id)
        }
    }

    private static func uuidOrder(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}

/// Parses an invariant decimal string without passing through binary floating point.
internal func exactDecimal(fromInvariantString string: String) -> Decimal? {
    guard !string.isEmpty else { return nil }
    let locale = Locale(identifier: "en_US_POSIX")
    guard let value = Decimal(string: string, locale: locale) else { return nil }
    guard let canonicalInput = CanonicalDecimal(string), let canonicalValue = CanonicalDecimal(decimalString(value)) else {
        return nil
    }
    return canonicalInput == canonicalValue ? value : nil
}

internal func decimalString(_ value: Decimal) -> String {
    var copy = value
    return NSDecimalString(&copy, Locale(identifier: "en_US_POSIX"))
}

/// Sign, significant integer digits, and base-ten exponent, normalized to compare exact numeric equality.
internal struct CanonicalDecimal: Equatable {
    var isNegative: Bool
    var digits: String
    var exponent: Int

    init?(_ source: String) {
        var value = source
        var negative = false
        if value.first == "-" || value.first == "+" {
            negative = value.first == "-"
            value.removeFirst()
        }
        guard !value.isEmpty else { return nil }

        let parts = value.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "e" || $0 == "E" })
        guard parts.count <= 2 else { return nil }
        var explicitExponent = 0
        if parts.count == 2 {
            guard let parsed = Int(parts[1]) else { return nil }
            explicitExponent = parsed
        }
        let mantissa = parts[0]
        let decimalParts = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        guard decimalParts.count <= 2 else { return nil }
        let integer: Substring = decimalParts[0]
        let fraction: Substring = decimalParts.count == 2 ? decimalParts[1] : ""
        guard !integer.isEmpty || !fraction.isEmpty,
              integer.allSatisfy({ $0.isASCII && $0.isNumber }),
              fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }

        var digits = String(integer + fraction)
        guard let exponentWithFraction = adding(explicitExponent, -fraction.count) else { return nil }
        var exponent = exponentWithFraction
        digits = String(digits.drop(while: { $0 == "0" }))
        guard !digits.isEmpty else {
            self.isNegative = false
            self.digits = "0"
            self.exponent = 0
            return
        }
        let trailingZeros = digits.reversed().prefix(while: { $0 == "0" }).count
        if trailingZeros > 0 {
            digits.removeLast(trailingZeros)
            guard let adjusted = adding(exponent, trailingZeros) else { return nil }
            exponent = adjusted
        }
        self.isNegative = negative
        self.digits = digits
        self.exponent = exponent
    }
}

private func adding(_ lhs: Int, _ rhs: Int) -> Int? {
    let result = lhs.addingReportingOverflow(rhs)
    return result.overflow ? nil : result.partialValue
}
