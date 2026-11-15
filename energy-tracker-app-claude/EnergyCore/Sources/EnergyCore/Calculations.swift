import Foundation

// MARK: - Bonus-Decay Normalization (§5.4)

public enum Normalization {
    /// `annualRate × (elapsedDays / 365) + bonus × max(0, 1 − elapsedDays / 365)`.
    /// Computed with a single division per term to keep `Decimal` exact where the inputs allow it.
    public static func normalizeToDate(annualRate: Decimal, bonus: Decimal, elapsedSeconds: Decimal) -> Decimal {
        precondition(elapsedSeconds >= 0, "elapsed must not be negative")
        let yearSeconds = DecimalMath.secondsPerDay * DecimalMath.daysPerYear
        let prorated = annualRate * elapsedSeconds / yearSeconds
        guard bonus != 0 else { return prorated }
        let remaining = DecimalMath.max(0, (yearSeconds - elapsedSeconds) / yearSeconds)
        return prorated + bonus * remaining
    }

    /// `max(min(annualThreshold, 1), annualThreshold × elapsedDays / 365)` (§5.3).
    public static func thresholdToDate(annualThreshold: Decimal, elapsedSeconds: Decimal) -> Decimal {
        let floor = DecimalMath.min(annualThreshold, 1)
        let scaled = normalizeToDate(annualRate: annualThreshold, bonus: 0, elapsedSeconds: elapsedSeconds)
        return DecimalMath.max(floor, scaled)
    }
}

// MARK: - Pace (§5.2)

public struct PaceResult: Sendable, Hashable {
    public var paceKwh: Decimal
    public var elapsedSeconds: Decimal
    /// First and last reading inside the analysis window.
    public var windowStart: Date
    public var windowEnd: Date
    public var includedReadingCount: Int

    public var elapsedDays: Decimal { elapsedSeconds / DecimalMath.secondsPerDay }
}

struct WalkResult {
    var kwh: Decimal = 0
    var seconds: Decimal = 0
}

public enum Pace {
    /// Pairwise walk (§5.2 step 4). `ordered` must already be ordered and exclusion-filtered.
    static func walk(_ ordered: [ReadingInput], prompts: [PromptInput], meterDigitCapacity: Decimal?) -> WalkResult {
        var resolved: [UUID: PromptInput] = [:]
        for prompt in prompts where prompt.isResolved {
            // Last resolvedAt wins if several exist (§7.3); the merge normally leaves only one.
            if let existing = resolved[prompt.readingId], let a = existing.resolvedAt, let b = prompt.resolvedAt, a >= b { continue }
            resolved[prompt.readingId] = prompt
        }
        var result = WalkResult()
        guard ordered.count >= 2 else { return result }
        for index in 1..<ordered.count {
            let previous = ordered[index - 1]
            let current = ordered[index]
            let seconds = DecimalMath.seconds(from: previous.timestamp, to: current.timestamp)
            if current.value < previous.value, let prompt = resolved[current.id] {
                switch prompt.classification {
                case .rollover:
                    if let capacity = prompt.digitCapacityKwh ?? meterDigitCapacity {
                        result.kwh += (capacity - previous.value) + current.value
                        result.seconds += seconds
                    }
                    // A rollover without any known capacity cannot be measured: treated like a reset.
                case .reset, .none:
                    break
                }
            } else {
                result.kwh += current.value - previous.value
                result.seconds += seconds
            }
        }
        return result
    }

    /// Pace-to-date, or nil when undefined.
    public static func compute(readings: [ReadingInput], prompts: [PromptInput], meterDigitCapacity: Decimal?) -> PaceResult? {
        let ordered = Readings.ordered(readings)
        let included = Readings.applyingOpenPromptExclusion(ordered, prompts: prompts)
        guard let latest = included.last else { return nil }
        let windowStart = latest.timestamp.addingTimeInterval(-365 * 86_400)
        let window = included.filter { $0.timestamp >= windowStart }
        guard window.count >= 2 else { return nil }
        let walked = walk(window, prompts: prompts, meterDigitCapacity: meterDigitCapacity)
        guard walked.seconds > 0 else { return nil }
        return PaceResult(
            paceKwh: walked.kwh,
            elapsedSeconds: walked.seconds,
            windowStart: window[0].timestamp,
            windowEnd: latest.timestamp,
            includedReadingCount: window.count
        )
    }

    /// Low confidence when days since the latest included reading exceed the gap setting.
    public static func isLowConfidence(latestReading: Date, now: Date, gapDays: Int) -> Bool {
        daysSince(latestReading, now: now) > Decimal(gapDays)
    }

    public static func daysSince(_ date: Date, now: Date) -> Decimal {
        DecimalMath.seconds(from: date, to: now) / DecimalMath.secondsPerDay
    }
}

// MARK: - Status (§5.3)

public enum EnergyStatus: String, Sendable, Hashable, CaseIterable, Codable {
    case withinRange = "withinrange"
    case belowBaseline = "belowbaseline"
    case trending

    /// Case-insensitive file value (§8.4 rule 3).
    public init?(fileValue: String) {
        self.init(rawValue: fileValue.lowercased())
    }
}

public enum UndefinedReason: Sendable, Hashable {
    /// Fewer than two usable readings, or zero elapsed time.
    case notEnoughReadings
    /// Readings exist but an open regression prompt removes too many of them.
    case awaitingDecision
    /// No Yearly Baseline set.
    case noBaseline
}

public struct StatusResult: Sendable, Hashable {
    public var status: EnergyStatus
    public var pace: PaceResult
    public var baselineToDateKwh: Decimal
    public var thresholdToDateKwh: Decimal
    public var annualThresholdKwh: Decimal
    public var differenceKwh: Decimal
    public var isLowConfidence: Bool
    public var daysSinceLastReading: Decimal
    public var lowConfidenceGapDays: Int
}

public enum StatusOutcome: Sendable, Hashable {
    case defined(StatusResult)
    case undefined(UndefinedReason)

    public var result: StatusResult? {
        if case .defined(let r) = self { return r }
        return nil
    }
}

public struct StatusInput: Sendable {
    public var readings: [ReadingInput]
    public var prompts: [PromptInput]
    public var meterDigitCapacityKwh: Decimal?
    public var yearlyBaselineKwh: Decimal?
    public var trendingThresholdKwh: Decimal
    public var lowConfidenceGapDays: Int
    public var now: Date

    public init(
        readings: [ReadingInput],
        prompts: [PromptInput] = [],
        meterDigitCapacityKwh: Decimal? = nil,
        yearlyBaselineKwh: Decimal?,
        trendingThresholdKwh: Decimal = 100,
        lowConfidenceGapDays: Int = 45,
        now: Date
    ) {
        self.readings = readings
        self.prompts = prompts
        self.meterDigitCapacityKwh = meterDigitCapacityKwh
        self.yearlyBaselineKwh = yearlyBaselineKwh
        self.trendingThresholdKwh = trendingThresholdKwh
        self.lowConfidenceGapDays = lowConfidenceGapDays
        self.now = now
    }
}

public enum StatusCalculator {
    /// Classifies a difference against a threshold. Ties resolve to the calmer state.
    public static func classify(difference: Decimal, thresholdToDate: Decimal) -> EnergyStatus {
        if difference > thresholdToDate { return .trending }
        if difference < 0 { return .belowBaseline }
        return .withinRange
    }

    public static func compute(_ input: StatusInput) -> StatusOutcome {
        guard let pace = Pace.compute(readings: input.readings, prompts: input.prompts, meterDigitCapacity: input.meterDigitCapacityKwh) else {
            let ordered = Readings.ordered(input.readings)
            let afterExclusion = Readings.applyingOpenPromptExclusion(ordered, prompts: input.prompts)
            if afterExclusion.count < ordered.count, ordered.count >= 2 { return .undefined(.awaitingDecision) }
            return .undefined(.notEnoughReadings)
        }
        guard let baseline = input.yearlyBaselineKwh else { return .undefined(.noBaseline) }
        let baselineToDate = Normalization.normalizeToDate(annualRate: baseline, bonus: 0, elapsedSeconds: pace.elapsedSeconds)
        let thresholdToDate = Normalization.thresholdToDate(annualThreshold: input.trendingThresholdKwh, elapsedSeconds: pace.elapsedSeconds)
        let difference = pace.paceKwh - baselineToDate
        let daysSince = Pace.daysSince(pace.windowEnd, now: input.now)
        return .defined(StatusResult(
            status: classify(difference: difference, thresholdToDate: thresholdToDate),
            pace: pace,
            baselineToDateKwh: baselineToDate,
            thresholdToDateKwh: thresholdToDate,
            annualThresholdKwh: input.trendingThresholdKwh,
            differenceKwh: difference,
            isLowConfidence: daysSince > Decimal(input.lowConfidenceGapDays),
            daysSinceLastReading: daysSince,
            lowConfidenceGapDays: input.lowConfidenceGapDays
        ))
    }
}

// MARK: - Tariff comparison (§5.5)

public struct TariffPrice: Sendable, Hashable {
    public var monthlyBaseFee: Decimal
    public var pricePerKwh: Decimal

    public init(monthlyBaseFee: Decimal, pricePerKwh: Decimal) {
        self.monthlyBaseFee = monthlyBaseFee
        self.pricePerKwh = pricePerKwh
    }

    public func annualCost(annualKwh: Decimal) -> Decimal {
        monthlyBaseFee * 12 + pricePerKwh * annualKwh
    }
}

public struct TariffComparison: Sendable, Hashable {
    public var annualPaceKwh: Decimal
    public var currentAnnualCost: Decimal
    public var candidateCostNoBonus: Decimal
    public var candidateNormalized: Decimal
    public var normalizedSavings: Decimal
    public var candidateIncluded: Decimal
    public var includedSavings: Decimal
    public var isLowConfidence: Bool

    public var normalizedSavingsRounded: Decimal { DecimalMath.rounded(normalizedSavings, scale: 2) }
    public var includedSavingsRounded: Decimal { DecimalMath.rounded(includedSavings, scale: 2) }
    /// "Without bonus effect" signal.
    public var normalizedWorthSwitching: Bool { normalizedSavingsRounded > 0 }
    /// "With bonus" signal.
    public var includedWorthSwitching: Bool { includedSavingsRounded > 0 }
}

public enum TariffComparator {
    public static func annualPace(paceKwh: Decimal, elapsedSeconds: Decimal) -> Decimal {
        paceKwh * DecimalMath.daysPerYear * DecimalMath.secondsPerDay / elapsedSeconds
    }

    public static func compare(
        annualPaceKwh: Decimal,
        current: TariffPrice,
        candidate: TariffPrice,
        bonus: Decimal,
        isLowConfidence: Bool = false
    ) -> TariffComparison {
        let currentCost = current.annualCost(annualKwh: annualPaceKwh)
        let candidateNoBonus = candidate.annualCost(annualKwh: annualPaceKwh)
        let yearSeconds = DecimalMath.daysPerYear * DecimalMath.secondsPerDay
        let normalized = Normalization.normalizeToDate(annualRate: candidateNoBonus, bonus: bonus, elapsedSeconds: yearSeconds)
        let included = candidateNoBonus - bonus
        return TariffComparison(
            annualPaceKwh: annualPaceKwh,
            currentAnnualCost: currentCost,
            candidateCostNoBonus: candidateNoBonus,
            candidateNormalized: normalized,
            normalizedSavings: currentCost - normalized,
            candidateIncluded: included,
            includedSavings: currentCost - included,
            isLowConfidence: isLowConfidence
        )
    }

    public static func compare(status: StatusResult, current: TariffPrice, candidate: TariffPrice, bonus: Decimal) -> TariffComparison {
        compare(
            annualPaceKwh: annualPace(paceKwh: status.pace.paceKwh, elapsedSeconds: status.pace.elapsedSeconds),
            current: current,
            candidate: candidate,
            bonus: bonus,
            isLowConfidence: status.isLowConfidence
        )
    }

    /// Comparison from pace alone (no baseline needed).
    public static func compare(pace: PaceResult, isLowConfidence: Bool, current: TariffPrice, candidate: TariffPrice, bonus: Decimal) -> TariffComparison {
        compare(
            annualPaceKwh: annualPace(paceKwh: pace.paceKwh, elapsedSeconds: pace.elapsedSeconds),
            current: current,
            candidate: candidate,
            bonus: bonus,
            isLowConfidence: isLowConfidence
        )
    }
}

// MARK: - Observed deviation (§5.6)

public enum Deviation: String, Sendable, Hashable {
    case bump = "Bump"
    case dip = "Dip"
    case none
}

public enum DeviationCalculator {
    public static let windowSeconds: TimeInterval = 7 * 86_400

    public static func compute(
        occurredAt: Date,
        readings: [ReadingInput],
        prompts: [PromptInput],
        meterDigitCapacityKwh: Decimal?,
        yearlyBaselineKwh: Decimal?,
        trendingThresholdKwh: Decimal
    ) -> Deviation {
        let lower = occurredAt.addingTimeInterval(-windowSeconds)
        let upper = occurredAt.addingTimeInterval(windowSeconds)
        let ordered = Readings.ordered(readings)
        let included = Readings.applyingOpenPromptExclusion(ordered, prompts: prompts)
        let window = included.filter { $0.timestamp >= lower && $0.timestamp <= upper }
        guard window.count >= 2 else { return .none }
        let walked = Pace.walk(window, prompts: prompts, meterDigitCapacity: meterDigitCapacityKwh)
        guard walked.seconds > 0 else { return .none }
        guard let baseline = yearlyBaselineKwh else { return .none }
        let expected = Normalization.normalizeToDate(annualRate: baseline, bonus: 0, elapsedSeconds: walked.seconds)
        let threshold = Normalization.thresholdToDate(annualThreshold: trendingThresholdKwh, elapsedSeconds: walked.seconds)
        let delta = walked.kwh - expected
        if delta > threshold { return .bump }
        if delta < -threshold { return .dip }
        return .none
    }
}

// MARK: - Regression detection (FR-11)

public struct RegressionCandidate: Sendable, Hashable {
    public var readingId: UUID
    public var previousReadingId: UUID
}

public enum RegressionDetector {
    /// Every reading lower than its chronological predecessor, by effective value.
    public static func regressions(in readings: [ReadingInput]) -> [RegressionCandidate] {
        let ordered = Readings.ordered(readings)
        guard ordered.count >= 2 else { return [] }
        var result: [RegressionCandidate] = []
        for index in 1..<ordered.count where ordered[index].value < ordered[index - 1].value {
            result.append(RegressionCandidate(readingId: ordered[index].id, previousReadingId: ordered[index - 1].id))
        }
        return result
    }

    public struct Plan: Sendable, Hashable {
        /// Readings that need a new open prompt.
        public var create: [RegressionCandidate] = []
        /// Open prompts whose reading is no longer a regression.
        public var deleteOpenPromptIds: [UUID] = []
        /// Open prompts whose predecessor changed (e.g. after a backfill): new predecessor id.
        public var updatePrevious: [UUID: UUID] = [:]
    }

    /// Compares detected regressions with stored prompts.
    public static func plan(readings: [ReadingInput], prompts: [PromptInput]) -> Plan {
        let detected = regressions(in: readings)
        let detectedByReading = Dictionary(uniqueKeysWithValues: detected.map { ($0.readingId, $0) })
        let promptsByReading = Dictionary(grouping: prompts, by: \.readingId)
        var plan = Plan()
        for candidate in detected where promptsByReading[candidate.readingId] == nil {
            plan.create.append(candidate)
        }
        for prompt in prompts where !prompt.isResolved {
            if let candidate = detectedByReading[prompt.readingId] {
                if candidate.previousReadingId != prompt.previousReadingId {
                    plan.updatePrevious[prompt.id] = candidate.previousReadingId
                }
            } else {
                plan.deleteOpenPromptIds.append(prompt.id)
            }
        }
        return plan
    }
}
