import Foundation
import SwiftData
import EnergyCore

/// Records of the data set as loaded from the store, split into the current generation and held-back records (§7.5).
struct LoadedDataSet {
    var household: Household?
    var currentGeneration: UUID?
    var meter: MainMeter?
    var readings: [MeterReading] = []
    var corrections: [AuditCorrection] = []
    var prompts: [MeterRegressionPrompt] = []
    var tariffs: [Tariff] = []
    var events: [EnergyEvent] = []
    var rooms: [Room] = []
    var powerPoints: [PowerPoint] = []
    var devices: [Device] = []
    var snapshots: [StatusSnapshot] = []
    var heldBack = HeldBack()

    /// Effective value per reading id.
    var effectiveValues: [UUID: Decimal] = [:]
    var correctionsByEntity: [UUID: [AuditCorrection]] = [:]

    struct HeldBack {
        var readings: [MeterReading] = []
        var events: [EnergyEvent] = []
        /// Every other held-back record (prompts, corrections, tariffs, structure, snapshots, meters, smart plug readings).
        var others: [any PersistentModel] = []

        var isEmpty: Bool { readings.isEmpty && events.isEmpty && others.isEmpty }
        var all: [any PersistentModel] { readings + events + others }
    }

    var isEmpty: Bool { household == nil }

    var readingInputs: [ReadingInput] {
        readings.map { ReadingInput(id: $0.id, timestamp: $0.readingTimestamp, value: effectiveValues[$0.id] ?? $0.originalKwhValue) }
    }

    var promptInputs: [PromptInput] {
        prompts.compactMap { p in
            guard let readingId = p.meterReadingId, let previous = p.previousMeterReadingId else { return nil }
            return PromptInput(id: p.id, readingId: readingId, previousReadingId: previous, createdAt: p.createdAt, resolvedAt: p.resolvedAt, classification: p.classification, digitCapacityKwh: p.digitCapacityKwh)
        }
    }

    func statusInput(now: Date = Date()) -> StatusInput {
        StatusInput(
            readings: readingInputs,
            prompts: promptInputs,
            meterDigitCapacityKwh: meter?.digitCapacityKwh,
            yearlyBaselineKwh: household?.yearlyBaselineKwh,
            trendingThresholdKwh: household?.trendingThresholdKwh ?? 100,
            lowConfidenceGapDays: household?.lowConfidenceGapDays ?? 45,
            now: now
        )
    }

    func status(now: Date = Date()) -> StatusOutcome {
        StatusCalculator.compute(statusInput(now: now))
    }

    func pace() -> PaceResult? {
        Pace.compute(readings: readingInputs, prompts: promptInputs, meterDigitCapacity: meter?.digitCapacityKwh)
    }

    var latestReading: MeterReading? {
        readings.max { ($0.readingTimestamp, $0.id.uuidString.lowercased()) < ($1.readingTimestamp, $1.id.uuidString.lowercased()) }
    }

    var currentTariff: Tariff? {
        let today = CalendarDate.today()
        guard let id = Tariffs.currentTariffId(tariffs.map { TariffRef(id: $0.id, startDate: $0.contractStartDate, createdAt: $0.createdAt) }, today: today) else { return nil }
        return tariffs.first { $0.id == id }
    }
}

enum DataSetLoader {
    /// The household that carries the current generation: newest generation start, then earliest record (§7.4, §7.5).
    static func primaryHousehold(_ households: [Household]) -> Household? {
        guard !households.isEmpty else { return nil }
        let newest = households.max { a, b in
            let ta = a.generationStartedAt ?? .distantPast, tb = b.generationStartedAt ?? .distantPast
            if ta != tb { return ta < tb }
            return a.id.uuidString.lowercased() > b.id.uuidString.lowercased()
        }?.generation
        return households
            .filter { $0.generation == newest }
            .min { ($0.createdAt, $0.id.uuidString.lowercased()) < ($1.createdAt, $1.id.uuidString.lowercased()) }
    }

    static func load(_ context: ModelContext, includeHistory: Bool = true) -> LoadedDataSet {
        var set = LoadedDataSet()
        let households = (try? context.fetch(FetchDescriptor<Household>())) ?? []
        set.household = primaryHousehold(households)
        let generation = set.household?.generation
        set.currentGeneration = generation

        func split<T: PersistentModel>(_ items: [T], _ gen: (T) -> UUID?) -> (current: [T], held: [T]) {
            var current: [T] = [], held: [T] = []
            for item in items {
                if Generations.isHeldBack(recordGeneration: gen(item), current: generation) { held.append(item) } else { current.append(item) }
            }
            return (current, held)
        }

        let meters = split((try? context.fetch(FetchDescriptor<MainMeter>())) ?? [], \.generation)
        set.meter = meters.current.min { ($0.createdAt, $0.id.uuidString.lowercased()) < ($1.createdAt, $1.id.uuidString.lowercased()) }
        set.heldBack.others += meters.held

        let readings = split((try? context.fetch(FetchDescriptor<MeterReading>())) ?? [], \.generation)
        set.readings = readings.current
        set.heldBack.readings = readings.held

        let corrections = split((try? context.fetch(FetchDescriptor<AuditCorrection>())) ?? [], \.generation)
        set.corrections = corrections.current
        set.heldBack.others += corrections.held

        let prompts = split((try? context.fetch(FetchDescriptor<MeterRegressionPrompt>())) ?? [], \.generation)
        set.prompts = prompts.current
        set.heldBack.others += prompts.held

        let tariffs = split((try? context.fetch(FetchDescriptor<Tariff>())) ?? [], \.generation)
        set.tariffs = tariffs.current
        set.heldBack.others += tariffs.held

        let events = split((try? context.fetch(FetchDescriptor<EnergyEvent>())) ?? [], \.generation)
        set.events = events.current
        set.heldBack.events = events.held

        if includeHistory {
            let rooms = split((try? context.fetch(FetchDescriptor<Room>())) ?? [], \.generation)
            set.rooms = rooms.current
            set.heldBack.others += rooms.held
            let points = split((try? context.fetch(FetchDescriptor<PowerPoint>())) ?? [], \.generation)
            set.powerPoints = points.current
            set.heldBack.others += points.held
            let devices = split((try? context.fetch(FetchDescriptor<Device>())) ?? [], \.generation)
            set.devices = devices.current
            set.heldBack.others += devices.held
            let snapshots = split((try? context.fetch(FetchDescriptor<StatusSnapshot>())) ?? [], \.generation)
            set.snapshots = snapshots.current
            set.heldBack.others += snapshots.held
            if generation != nil {
                var plugs = FetchDescriptor<SmartPlugReading>(predicate: #Predicate { $0.generation != generation })
                plugs.propertiesToFetch = [\.generation]
                set.heldBack.others += ((try? context.fetch(plugs)) ?? []).filter { Generations.isHeldBack(recordGeneration: $0.generation, current: generation) }
            }
        }

        set.correctionsByEntity = Dictionary(grouping: set.corrections.filter { $0.entityId != nil }, by: { $0.entityId! })
        for reading in set.readings {
            let corrections = (set.correctionsByEntity[reading.id] ?? [])
                .filter { $0.entityType == AuditEntityType.meterReading }
                .map { CorrectionInput(id: $0.id, fieldName: $0.fieldName, newValue: $0.newValue, correctedAt: $0.correctedAt) }
            set.effectiveValues[reading.id] = Readings.effectiveValue(original: reading.originalKwhValue, corrections: corrections)
        }
        return set
    }
}
