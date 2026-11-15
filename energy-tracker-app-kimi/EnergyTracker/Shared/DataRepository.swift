import Foundation
import SwiftData
import WidgetKit

enum ReadingSaveOutcome {
    case saved(MeterReading)
    case alreadySaved
}

enum RegressionKind: String, CaseIterable {
    case reset
    case rollover
}

struct HeldBackSummary: Equatable {
    var readings = 0
    var events = 0
    var other = 0

    var isEmpty: Bool { readings == 0 && events == 0 && other == 0 }
}

@MainActor
final class DataRepository {
    let context: ModelContext
    var lastMergeNotice: String?

    init(context: ModelContext) {
        self.context = context
    }

    func fetch<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    func save() throws {
        try context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func performMaintenance() throws {
        try mergeDuplicates()
        try checkRegressions(commit: false)
        if context.hasChanges { try save() }
    }

    // MARK: - Active data set

    func activeHouseholdRecord() throws -> Household? {
        let households = try fetch(Household.self)
        guard let newestGeneration = households.sorted(by: Self.newestGenerationOrder).first else { return nil }
        return households
            .filter { $0.generation == newestGeneration.generation }
            .sorted(by: Self.earliestOrder)
            .first
    }

    func currentGeneration() throws -> UUID? {
        try activeHouseholdRecord()?.generation
    }

    func isDataSetEmpty() throws -> Bool {
        try activeHouseholdRecord() == nil
    }

    @discardableResult
    func ensureHousehold() throws -> Household {
        if let household = try activeHouseholdRecord() { return household }
        let currency = Locale.current.currency?.identifier.uppercased() ?? "EUR"
        let household = Household(currency: InputValidation.currency(currency) ?? "EUR")
        household.generationChangedAt = Date()
        context.insert(household)
        return household
    }

    func meter() throws -> MainMeter? {
        guard let generation = try currentGeneration() else { return nil }
        return try fetch(MainMeter.self)
            .filter { $0.generation == generation }
            .sorted(by: Self.earliestOrder)
            .first
    }

    @discardableResult
    func ensureMeter() throws -> MainMeter {
        if let meter = try meter() { return meter }
        let household = try ensureHousehold()
        let meter = MainMeter(generation: household.generation)
        context.insert(meter)
        return meter
    }

    func readings() throws -> [MeterReading] {
        guard let generation = try currentGeneration() else { return [] }
        return try fetch(MeterReading.self)
            .filter { $0.generation == generation }
            .sorted(by: Self.readingOrder)
    }

    func prompts() throws -> [MeterRegressionPrompt] {
        guard let generation = try currentGeneration() else { return [] }
        let readingOrder = Dictionary(uniqueKeysWithValues: try readings().enumerated().map { ($0.element.id, $0.offset) })
        return try fetch(MeterRegressionPrompt.self)
            .filter { $0.generation == generation }
            .sorted {
                let left = readingOrder[$0.meterReadingId] ?? .max
                let right = readingOrder[$1.meterReadingId] ?? .max
                return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
            }
    }

    func openPrompt() throws -> MeterRegressionPrompt? {
        try prompts().filter { $0.resolvedAt == nil }.first
    }

    func corrections(for reading: MeterReading) throws -> [AuditCorrection] {
        try corrections(entityType: "MeterReading", entityId: reading.id)
            .filter { $0.fieldName == "KwhValue" }
    }

    func corrections(entityType: String, entityId: UUID) throws -> [AuditCorrection] {
        guard let generation = try currentGeneration() else { return [] }
        return try fetch(AuditCorrection.self)
            .filter { $0.generation == generation && $0.entityType == entityType && $0.entityId == entityId }
            .sorted { lhs, rhs in
                if lhs.correctedAt != rhs.correctedAt { return lhs.correctedAt < rhs.correctedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func effectiveValue(for reading: MeterReading) throws -> Decimal {
        let corrections = try corrections(for: reading)
        if let latest = corrections.last, let value = DecimalText.decode(latest.newValue) { return value }
        return DecimalText.decode(reading.kwhValue) ?? 0
    }

    func effectiveValues() throws -> [UUID: Decimal] {
        let readings = try readings()
        var values = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, DecimalText.decode($0.kwhValue) ?? 0) })
        let corrections = try fetch(AuditCorrection.self)
            .filter { $0.entityType == "MeterReading" && $0.fieldName == "KwhValue" }
            .sorted {
                if $0.correctedAt != $1.correctedAt { return $0.correctedAt < $1.correctedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        for correction in corrections {
            if values[correction.entityId] != nil, let value = DecimalText.decode(correction.newValue) {
                values[correction.entityId] = value
            }
        }
        return values
    }

    // MARK: - Readings and decisions

    func saveReading(kwh: Decimal, timestamp: Date = Date()) throws -> ReadingSaveOutcome {
        guard kwh > 0, kwh < Decimal(sign: .plus, exponent: 15, significand: 1) else {
            throw RepositoryError.invalidReading
        }
        let household = try ensureHousehold()
        let meter = try ensureMeter()
        let duplicate = try readings().contains {
            $0.mainMeterId == meter.id &&
            Self.second($0.readingTimestamp) == Self.second(timestamp) &&
            DecimalText.decode($0.kwhValue) == kwh
        }
        if duplicate { return .alreadySaved }

        let reading = MeterReading(generation: household.generation, mainMeterId: meter.id, kwhValue: kwh, readingTimestamp: timestamp)
        context.insert(reading)
        try checkRegressions(commit: false)
        try save()
        try captureSnapshot(causeId: reading.id)
        return .saved(reading)
    }

    @discardableResult
    func checkRegressions(commit: Bool = true) throws -> [MeterRegressionPrompt] {
        guard let generation = try currentGeneration(), let meter = try meter() else { return [] }
        let readings = try readings()
        let prompts = try fetch(MeterRegressionPrompt.self).filter { $0.generation == generation }
        var effectiveValues: [UUID: Decimal] = [:]
        for reading in readings { effectiveValues[reading.id] = DecimalText.decode(reading.kwhValue) ?? 0 }
        let corrections = try fetch(AuditCorrection.self)
            .filter { $0.generation == generation && $0.entityType == "MeterReading" && $0.fieldName == "KwhValue" }
            .sorted {
                if $0.correctedAt != $1.correctedAt { return $0.correctedAt < $1.correctedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        for correction in corrections {
            if let value = DecimalText.decode(correction.newValue) { effectiveValues[correction.entityId] = value }
        }
        var existingByReading = Dictionary<UUID, [MeterRegressionPrompt]>()
        for prompt in prompts { existingByReading[prompt.meterReadingId, default: []].append(prompt) }
        var created: [MeterRegressionPrompt] = []

        for (previous, current) in zip(readings, readings.dropFirst()) {
            guard let previousValue = effectiveValues[previous.id], let currentValue = effectiveValues[current.id], currentValue < previousValue else { continue }
            if existingByReading[current.id]?.isEmpty == false { continue }
            let prompt = MeterRegressionPrompt(
                generation: generation, mainMeterId: meter.id,
                meterReadingId: current.id, previousMeterReadingId: previous.id
            )
            context.insert(prompt)
            existingByReading[current.id] = [prompt]
            created.append(prompt)
        }
        if commit && !created.isEmpty { try save() }
        return created
    }

    func resolve(_ prompt: MeterRegressionPrompt, kind: RegressionKind, digitCapacity: Decimal? = nil) throws {
        prompt.classification = kind.rawValue
        prompt.resolvedAt = Date()
        prompt.updatedAt = Date()
        prompt.digitCapacityKwh = kind == .rollover ? digitCapacity.map(DecimalText.encode) : nil
        if kind == .rollover, let digitCapacity {
            guard digitCapacity > 0 else { throw RepositoryError.invalidDigitCapacity }
            let meter = try ensureMeter()
            meter.digitCapacityKwh = DecimalText.encode(digitCapacity)
            meter.updatedAt = Date()
        }
        try checkRegressions(commit: false)
        try save()
        try captureSnapshot(causeId: prompt.id)
    }

    func correct(_ reading: MeterReading, to newValue: Decimal) throws -> AuditCorrection? {
        guard newValue > 0, newValue < Decimal(sign: .plus, exponent: 15, significand: 1) else {
            throw RepositoryError.invalidReading
        }
        let oldValue = try effectiveValue(for: reading)
        guard oldValue != newValue else { return nil }
        let correction = AuditCorrection(
            generation: reading.generation, entityType: "MeterReading", entityId: reading.id,
            fieldName: "KwhValue", oldValue: DecimalText.encode(oldValue), newValue: DecimalText.encode(newValue)
        )
        context.insert(correction)
        try checkRegressions(commit: false)
        try save()
        try captureSnapshot(causeId: correction.id)
        return correction
    }

    // MARK: - Shared deterministic ordering

    static func earliestOrder<T: HouseholdLike>(_ lhs: T, _ rhs: T) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func newestGenerationOrder(_ lhs: Household, _ rhs: Household) -> Bool {
        if lhs.generationChangedAt != rhs.generationChangedAt { return lhs.generationChangedAt > rhs.generationChangedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    static func readingOrder(_ lhs: MeterReading, _ rhs: MeterReading) -> Bool {
        if lhs.readingTimestamp != rhs.readingTimestamp { return lhs.readingTimestamp < rhs.readingTimestamp }
        return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
    }

    static func second(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970.rounded(.down)) }
}

protocol HouseholdLike {
    var id: UUID { get }
    var createdAt: Date { get }
}

extension Household: HouseholdLike {}
extension MainMeter: HouseholdLike {}
extension MeterReading: HouseholdLike {}
extension StatusSnapshot: HouseholdLike {}
extension AuditCorrection: HouseholdLike {}

enum RepositoryError: LocalizedError {
    case invalidReading
    case invalidDigitCapacity
    case invalidTariff
    case duplicateTariffStart
    case invalidEvent
    case invalidName
    case archivedParent
    case missingHousehold

    var errorDescription: String? {
        switch self {
        case .invalidReading: String(localized: "Enter a reading greater than 0 with at most 2 decimal places.")
        case .invalidDigitCapacity: String(localized: "Enter a digit capacity greater than 0.")
        case .invalidTariff: String(localized: "Check the tariff values and contract period.")
        case .duplicateTariffStart: String(localized: "Another tariff already starts on this date.")
        case .invalidEvent: String(localized: "Enter an event description of 1 to 500 characters.")
        case .invalidName: String(localized: "Enter a name of 1 to 200 characters.")
        case .archivedParent: String(localized: "Restore the archived parent before adding an item here.")
        case .missingHousehold: String(localized: "Set up the household before continuing.")
        }
    }
}
