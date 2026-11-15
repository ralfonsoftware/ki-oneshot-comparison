import Foundation
import EnergyCore

@MainActor
enum EnergyEngine {
    static func status(repository: DataRepository, now: Date = Date()) throws -> LiveStatus {
        let household = try repository.activeHouseholdRecord()
        let input = try calculationInput(repository: repository)
        let settings = StatusSettings(
            yearlyBaselineKwh: DecimalText.decode(household?.yearlyBaselineKwh ?? nil),
            trendingThresholdKwh: DecimalText.decode(household?.trendingThresholdKwh) ?? 100,
            lowConfidenceGapDays: household?.lowConfidenceGapDays ?? 45
        )
        let evaluation = EnergyCalculator.status(readings: input.readings, regressionPrompts: input.prompts, auditCorrections: input.corrections, settings: settings, now: now)
        let pace = evaluation.pace
        let displayStatus = evaluation.status.flatMap { DisplayStatus(rawValue: $0.rawValue) }
        let latestIncluded = latestIncludedTimestamp(input: input)
        let daysSince = latestIncluded.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) }
        return LiveStatus(
            status: displayStatus,
            paceToDate: pace?.paceToDateKwh,
            baselineToDate: evaluation.baselineToDateKwh,
            thresholdToDate: evaluation.thresholdToDateKwh,
            annualThreshold: settings.trendingThresholdKwh,
            difference: evaluation.differenceKwh,
            elapsedDays: pace?.elapsedDays,
            periodStart: pace == nil ? nil : analysisStart(input: input, latest: pace?.latestReadingTimestamp),
            periodEnd: pace?.latestReadingTimestamp,
            isLowConfidence: pace?.isLowConfidence ?? false,
            daysSinceLastReading: daysSince,
            lowConfidenceGapDays: settings.lowConfidenceGapDays,
            undefinedReason: evaluation.status == nil ? (pace == nil ? .needsReadings : .needsBaseline) : nil
        )
    }

    static func compare(repository: DataRepository, current: Tariff, candidateBaseFee: Decimal, candidatePrice: Decimal, bonus: Decimal) throws -> TariffComparisonDisplay {
        guard let pace = try corePace(repository: repository) else { throw EnergyEngineError.undefinedPace }
        let coreCurrent = EnergyCore.Tariff(
            id: current.id, monthlyBaseFee: DecimalText.decode(current.monthlyBaseFee) ?? 0,
            pricePerKwh: DecimalText.decode(current.pricePerKwh) ?? 0, currency: current.currency,
            contractStartDate: try calendarDate(current.contractStartDate), contractPeriodMonths: current.contractPeriodMonths,
            createdAt: current.createdAt
        )
        let result = EnergyCalculator.compareTariffs(
            current: coreCurrent,
            candidate: CandidateTariff(monthlyBaseFee: candidateBaseFee, pricePerKwh: candidatePrice, switchingBonus: bonus),
            pace: pace
        )
        return TariffComparisonDisplay(
            annualPace: result.annualPaceKwh, currentAnnualCost: result.currentAnnualCost,
            candidateAnnualCost: result.candidateCostNoBonus,
            normalizedSavings: result.roundedNormalizedSavings, includedSavings: result.roundedIncludedSavings,
            normalizedWorth: result.isNormalizedWorthSwitching, includedWorth: result.isIncludedWorthSwitching,
            isLowConfidence: result.isLowConfidence
        )
    }

    static func tariffCheck(repository: DataRepository, today: Date = Date()) throws -> TariffCheckDisplay {
        guard let tariff = try repository.currentTariff(today: today) else { return TariffCheckDisplay(isDue: false, minimumTermEnd: nil, nextDue: nil) }
        let household = try repository.activeHouseholdRecord()
        let coreTariff = EnergyCore.Tariff(
            id: tariff.id, monthlyBaseFee: DecimalText.decode(tariff.monthlyBaseFee) ?? 0,
            pricePerKwh: DecimalText.decode(tariff.pricePerKwh) ?? 0, currency: tariff.currency,
            contractStartDate: try calendarDate(tariff.contractStartDate), contractPeriodMonths: tariff.contractPeriodMonths,
            createdAt: tariff.createdAt
        )
        let result = EnergyCalculator.tariffCheck(
            tariff: coreTariff, today: CalendarDate(date: today, calendar: .current),
            tariffCheckDoneAt: household?.tariffCheckDoneAt.map { CalendarDate(date: $0, calendar: .current) },
            cadenceMonths: household?.tariffCheckCadenceMonths ?? 3
        )
        return TariffCheckDisplay(
            isDue: result?.isDue ?? false,
            minimumTermEnd: result.map { date(from: $0.minimumTermEnd) },
            nextDue: result?.nextDueDate.map { date(from: $0) }
        )
    }

    static func deviation(repository: DataRepository, event: EnergyEvent) throws -> DisplayDeviation? {
        let input = try calculationInput(repository: repository)
        let household = try repository.activeHouseholdRecord()
        let result = EnergyCalculator.observedDeviation(
            occurredAt: event.occurredAt, readings: input.readings, regressionPrompts: input.prompts,
            auditCorrections: input.corrections,
            yearlyBaselineKwh: DecimalText.decode(household?.yearlyBaselineKwh ?? nil),
            trendingThresholdKwh: DecimalText.decode(household?.trendingThresholdKwh) ?? 100
        )
        switch result {
        case .bump: return .bump
        case .dip: return .dip
        case .none: return nil
        }
    }

    private static func corePace(repository: DataRepository) throws -> Pace? {
        let input = try calculationInput(repository: repository)
        let household = try repository.activeHouseholdRecord()
        return EnergyCalculator.pace(
            readings: input.readings, regressionPrompts: input.prompts, auditCorrections: input.corrections,
            now: Date(), lowConfidenceGapDays: household?.lowConfidenceGapDays ?? 45
        )
    }

    private struct CalculationInput {
        let readings: [EnergyCore.MeterReading]
        let prompts: [EnergyCore.MeterRegressionPrompt]
        let corrections: [EnergyCore.AuditCorrection]
        let orderedIDs: [UUID]
    }

    private static func calculationInput(repository: DataRepository) throws -> CalculationInput {
        guard let generation = try repository.currentGeneration() else { return CalculationInput(readings: [], prompts: [], corrections: [], orderedIDs: []) }
        let storedReadings = try repository.readings()
        let storedPrompts = try repository.prompts()
        let storedCorrections = try repository.fetch(AuditCorrection.self).filter { $0.generation == generation }
        let readings = storedReadings.map {
            EnergyCore.MeterReading(id: $0.id, mainMeterID: $0.mainMeterId, kwhValue: DecimalText.decode($0.kwhValue) ?? 0, readingTimestamp: $0.readingTimestamp, createdAt: $0.createdAt)
        }
        let prompts = storedPrompts.map {
            EnergyCore.MeterRegressionPrompt(
                id: $0.id, mainMeterID: $0.mainMeterId, meterReadingID: $0.meterReadingId,
                previousMeterReadingID: $0.previousMeterReadingId, createdAt: $0.createdAt,
                resolvedAt: $0.resolvedAt, classification: $0.classification.flatMap(RegressionClassification.init(rawValue:)),
                digitCapacityKwh: $0.digitCapacityKwh.flatMap(DecimalText.decode)
            )
        }
        let corrections = storedCorrections.compactMap { correction -> EnergyCore.AuditCorrection? in
            guard let type = AuditEntityType(rawValue: correction.entityType) else { return nil }
            return EnergyCore.AuditCorrection(id: correction.id, entityType: type, entityID: correction.entityId, fieldName: correction.fieldName, oldValue: correction.oldValue, newValue: correction.newValue, correctedAt: correction.correctedAt)
        }
        return CalculationInput(readings: readings, prompts: prompts, corrections: corrections, orderedIDs: storedReadings.map(\.id))
    }

    private static func latestIncludedTimestamp(input: CalculationInput) -> Date? {
        let openIDs = Set(input.prompts.filter { $0.resolvedAt == nil }.map(\.meterReadingID))
        let ordered = EnergyCalculator.orderedReadings(input.readings)
        let trigger = ordered.first(where: { openIDs.contains($0.id) })
        let included = ordered.filter { reading in
            guard let trigger else { return true }
            if reading.readingTimestamp != trigger.readingTimestamp { return reading.readingTimestamp < trigger.readingTimestamp }
            return reading.id.uuidString.lowercased() < trigger.id.uuidString.lowercased()
        }
        return included.last?.readingTimestamp
    }

    private static func analysisStart(input: CalculationInput, latest: Date?) -> Date? {
        guard let latest else { return nil }
        let openIDs = Set(input.prompts.filter { $0.resolvedAt == nil }.map(\.meterReadingID))
        let ordered = EnergyCalculator.orderedReadings(input.readings)
        let trigger = ordered.first(where: { openIDs.contains($0.id) })
        let included = ordered.filter { reading in
            guard let trigger else { return true }
            if reading.readingTimestamp != trigger.readingTimestamp { return reading.readingTimestamp < trigger.readingTimestamp }
            return reading.id.uuidString.lowercased() < trigger.id.uuidString.lowercased()
        }
        return included.filter { $0.readingTimestamp >= latest.addingTimeInterval(-365 * 86_400) }.first?.readingTimestamp
    }

    private static func date(from value: CalendarDate) -> Date {
        Calendar.current.date(from: DateComponents(year: value.year, month: value.month, day: value.day, hour: 12))!
    }

    private static func calendarDate(_ value: String) throws -> CalendarDate {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { throw EnergyEngineError.invalidDate }
        return CalendarDate(year: parts[0], month: parts[1], day: parts[2])
    }
}

enum EnergyEngineError: LocalizedError {
    case undefinedPace
    case invalidDate
    var errorDescription: String? {
        switch self {
        case .undefinedPace: String(localized: "Log at least two readings to compare tariffs.")
        case .invalidDate: String(localized: "The calendar date is invalid.")
        }
    }
}

extension DataRepository {
    func snapshots() throws -> [StatusSnapshot] {
        guard let generation = try currentGeneration() else { return [] }
        return try fetch(StatusSnapshot.self)
            .filter { $0.generation == generation }
            .sorted {
                if $0.computedAt != $1.computedAt { return $0.computedAt < $1.computedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func captureSnapshot(causeId: UUID) throws {
        guard let generation = try currentGeneration() else { return }
        if try fetch(StatusSnapshot.self).contains(where: { $0.generation == generation && $0.causeId == causeId }) { return }
        let status = try EnergyEngine.status(repository: self)
        guard let value = status.status, let pace = status.paceToDate, let baseline = status.baselineToDate else { return }
        let snapshot = StatusSnapshot(
            generation: generation, status: value.rawValue, paceToDateKwh: pace,
            baselineToDateKwh: baseline, isLowConfidence: status.isLowConfidence,
            computedAt: Date(), causeId: causeId
        )
        context.insert(snapshot)
        try save()
    }
}
