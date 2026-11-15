import Foundation
import SwiftData
import Observation
import EnergyCore

/// What changed, so the app knows which system hooks to run after a write.
struct ChangeKind: OptionSet {
    let rawValue: Int
    static let readings = ChangeKind(rawValue: 1 << 0)
    static let tariffs = ChangeKind(rawValue: 1 << 1)
    static let settings = ChangeKind(rawValue: 1 << 2)
    static let events = ChangeKind(rawValue: 1 << 3)
    static let structure = ChangeKind(rawValue: 1 << 4)
    static let all: ChangeKind = [.readings, .tariffs, .settings, .events, .structure]
}

enum StoreError: LocalizedError, Equatable {
    case invalidReading(Validation.ReadingError)
    case invalidTariff([Validation.TariffError])
    case duplicateTariffStart(CalendarDate)
    case invalidName
    case invalidDescription
    case archivedParent
    case notFound
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidReading(let e):
            switch e {
            case .notPositive: String(localized: "Enter a value greater than 0 kWh.")
            case .tooLarge: String(localized: "That value is too large for a meter reading.")
            case .tooManyDecimals: String(localized: "Use at most 2 decimal places.")
            }
        case .invalidTariff(let errors):
            errors.map { e in
                switch e {
                case .baseFeeOutOfRange: String(localized: "The base fee must be 0 or more.")
                case .priceOutOfRange: String(localized: "The price per kWh must be greater than 0.")
                case .currencyInvalid: String(localized: "Use a 3-letter currency code such as EUR.")
                case .periodOutOfRange: String(localized: "The contract period must be between 1 and 1,200 months.")
                case .startDateOutOfRange: String(localized: "The start date must be between 1900 and 2200.")
                }
            }.joined(separator: "\n")
        case .duplicateTariffStart(let date):
            String(localized: "Another tariff already starts on \(Format.date(date)).")
        case .invalidName: String(localized: "Names need 1 to 200 characters.")
        case .invalidDescription: String(localized: "Describe the event in 1 to 500 characters.")
        case .archivedParent: String(localized: "An archived item cannot get new items.")
        case .notFound: String(localized: "This item no longer exists.")
        case .saveFailed(let message): String(localized: "Could not save: \(message)")
        }
    }
}

enum LogReadingOutcome {
    case saved(readingId: UUID, status: StatusOutcome, openPromptId: UUID?, triggeredRegression: Bool)
    case alreadySaved
}

/// A one-time notice after two Apple devices classified the same reading differently (§7.3).
struct ClassificationNotice: Identifiable, Hashable {
    var id: UUID { readingId }
    var readingId: UUID
    var classification: RegressionClassification
}

/// Single owner of all reads and writes on the main context. Writes are saved before they return (§11, Durability).
@MainActor
@Observable
final class EnergyStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    private(set) var data = LoadedDataSet()
    /// Increments on every reload; views key derived values on it.
    private(set) var version = 0
    private(set) var classificationNotices: [ClassificationNotice] = []

    /// Called after every local write and every processed sync import.
    var afterChange: ((ChangeKind, _ remote: Bool) -> Void)?

    init(container: ModelContainer) {
        self.container = container
        context.autosaveEnabled = false
        reload()
    }

    func reload() {
        data = DataSetLoader.load(context)
        version += 1
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            log.error("Save failed: \(error.localizedDescription, privacy: .public)")
            context.rollback()
            reload()
            throw StoreError.saveFailed(error.localizedDescription)
        }
    }

    private func finish(_ kind: ChangeKind, remote: Bool = false) {
        reload()
        afterChange?(kind, remote)
    }

    var generation: UUID? { data.currentGeneration }

    // MARK: - Household and Main Meter

    @discardableResult
    func ensureHousehold() -> Household {
        if let household = data.household { return household }
        let household = Household(generation: UUID())
        household.currency = Locale.current.currency?.identifier ?? "EUR"
        household.locale = Locale.current.identifier(.bcp47)
        household.fieldStamps = Dictionary(uniqueKeysWithValues: HouseholdField.allCases.map { ($0.rawValue, household.createdAt) })
        context.insert(household)
        data.household = household
        data.currentGeneration = household.generation
        return household
    }

    @discardableResult
    func ensureMeter() -> MainMeter {
        if let meter = data.meter { return meter }
        let meter = MainMeter(generation: ensureHousehold().generation)
        context.insert(meter)
        data.meter = meter
        return meter
    }

    /// Start fresh (FR-3). Both values are optional and can be set later.
    func startFresh(yearlyBaselineKwh: Decimal?, currency: String?) throws {
        let household = ensureHousehold()
        if let yearlyBaselineKwh {
            household.yearlyBaselineKwh = yearlyBaselineKwh
            household.stamp(.yearlyBaselineKwh)
        }
        if let currency, Validation.isCurrencyCode(currency) {
            household.currency = currency
            household.stamp(.currency)
        }
        try save()
        finish(.settings)
    }

    // MARK: - Settings (FR-5, FR-14, FR-24)

    func setYearlyBaseline(_ value: Decimal?) throws {
        let h = ensureHousehold()
        guard h.yearlyBaselineKwh != value else { return }
        h.yearlyBaselineKwh = value
        h.stamp(.yearlyBaselineKwh)
        try save()
        finish(.settings)
    }

    func setTrendingThreshold(_ value: Decimal) throws {
        let h = ensureHousehold()
        guard value >= 0, h.trendingThresholdKwh != value else { return }
        h.trendingThresholdKwh = value
        h.stamp(.trendingThresholdKwh)
        try save()
        finish(.settings)
    }

    func setLowConfidenceGapDays(_ value: Int) throws {
        let h = ensureHousehold()
        guard Validation.gapDaysRange.contains(value), h.lowConfidenceGapDays != value else { return }
        h.lowConfidenceGapDays = value
        h.stamp(.lowConfidenceGapDays)
        try save()
        finish(.settings)
    }

    func setTariffCheckCadence(_ value: Int) throws {
        let h = ensureHousehold()
        guard Validation.cadenceRange.contains(value), h.tariffCheckCadenceMonths != value else { return }
        h.tariffCheckCadenceMonths = value
        h.stamp(.tariffCheckCadenceMonths)
        try save()
        finish(.settings)
    }

    func setCurrency(_ value: String) throws {
        let h = ensureHousehold()
        guard Validation.isCurrencyCode(value), h.currency != value else { return }
        h.currency = value
        h.stamp(.currency)
        try save()
        finish(.settings)
    }

    func markTariffCheckDone(now: Date = Date()) throws {
        let h = ensureHousehold()
        h.tariffCheckDoneAt = now
        h.stamp(.tariffCheckDoneAt)
        try save()
        finish(.settings)
    }

    // MARK: - Readings (FR-4, FR-10, FR-11)

    func logReading(kwh: Decimal, at date: Date) throws -> LogReadingOutcome {
        if let error = Validation.validateReading(kwh) { throw StoreError.invalidReading(error) }
        let meter = ensureMeter()
        let timestamp = Instant.wholeSeconds(date)
        // Exact-duplicate rule (§7.4): same meter, same second, same original value.
        let second = Int64(timestamp.timeIntervalSince1970)
        if data.readings.contains(where: { $0.mainMeterId == meter.id && Int64($0.readingTimestamp.timeIntervalSince1970.rounded(.down)) == second && $0.originalKwhValue == kwh }) {
            return .alreadySaved
        }
        let reading = MeterReading(generation: generation, mainMeterId: meter.id, kwhValue: kwh, readingTimestamp: timestamp)
        context.insert(reading)
        try save()
        reload()
        let created = try checkRegressions()
        let status = data.status()
        writeSnapshot(status: status, causeId: reading.id)
        try save()
        let open = Readings.activeOpenPrompt(readings: Readings.ordered(data.readingInputs), prompts: data.promptInputs)
        finish(.readings)
        return .saved(readingId: reading.id, status: data.status(), openPromptId: created.isEmpty ? nil : open?.id, triggeredRegression: !created.isEmpty)
    }

    enum CorrectionOutcome { case corrected(openPromptId: UUID?), unchanged }

    func correctReading(id: UUID, newValue: Decimal, now: Date = Date()) throws -> CorrectionOutcome {
        if let error = Validation.validateReading(newValue) { throw StoreError.invalidReading(error) }
        guard let reading = data.readings.first(where: { $0.id == id }) else { throw StoreError.notFound }
        let effective = data.effectiveValues[id] ?? reading.originalKwhValue
        guard effective != newValue else { return .unchanged }
        let correction = AuditCorrection(generation: generation, entityType: AuditEntityType.meterReading, entityId: id, fieldName: AuditField.kwhValue,
                                         oldValue: DecimalMath.string(effective), newValue: DecimalMath.string(newValue), correctedAt: now)
        context.insert(correction)
        try save()
        reload()
        let created = try checkRegressions()
        writeSnapshot(status: data.status(), causeId: correction.id)
        try save()
        let open = Readings.activeOpenPrompt(readings: Readings.ordered(data.readingInputs), prompts: data.promptInputs)
        finish(.readings)
        return .corrected(openPromptId: created.isEmpty ? nil : open?.id)
    }

    /// Resolves an open regression prompt (FR-11).
    func resolvePrompt(id: UUID, classification: RegressionClassification, digitCapacityKwh: Decimal?, now: Date = Date()) throws {
        guard let prompt = data.prompts.first(where: { $0.id == id }) else { throw StoreError.notFound }
        prompt.classification = classification
        prompt.resolvedAt = now
        prompt.digitCapacityKwh = classification == .rollover ? digitCapacityKwh : nil
        if classification == .rollover, let capacity = digitCapacityKwh {
            ensureMeter().digitCapacityKwh = capacity
        }
        try save()
        reload()
        writeSnapshot(status: data.status(), causeId: prompt.id)
        try save()
        finish(.readings)
    }

    /// Changes a resolved classification from the reading's detail. A changed decision is a new prompt record,
    /// so its snapshot has its own cause and the merge keeps the latest decision (§7.3, §7.4).
    func changeClassification(readingId: UUID, classification: RegressionClassification, digitCapacityKwh: Decimal?, now: Date = Date()) throws {
        let existing = data.prompts.filter { $0.meterReadingId == readingId }
        guard let previous = existing.first?.previousMeterReadingId else { throw StoreError.notFound }
        let prompt = MeterRegressionPrompt(generation: generation, mainMeterId: ensureMeter().id, meterReadingId: readingId, previousMeterReadingId: previous)
        prompt.classification = classification
        prompt.resolvedAt = now
        prompt.digitCapacityKwh = classification == .rollover ? digitCapacityKwh : nil
        if classification == .rollover, let capacity = digitCapacityKwh { ensureMeter().digitCapacityKwh = capacity }
        context.insert(prompt)
        existing.forEach(context.delete)
        try save()
        reload()
        writeSnapshot(status: data.status(), causeId: prompt.id)
        try save()
        finish(.readings)
    }

    /// Creates prompts for new regressions, removes open prompts that no longer apply, re-points predecessors.
    /// Returns the ids of created prompts.
    @discardableResult
    func checkRegressions(now: Date = Date()) throws -> [UUID] {
        guard let meter = data.meter else { return [] }
        let plan = RegressionDetector.plan(readings: data.readingInputs, prompts: data.promptInputs)
        guard !plan.create.isEmpty || !plan.deleteOpenPromptIds.isEmpty || !plan.updatePrevious.isEmpty else { return [] }
        var created: [UUID] = []
        for candidate in plan.create {
            let prompt = MeterRegressionPrompt(createdAt: now, generation: generation, mainMeterId: meter.id, meterReadingId: candidate.readingId, previousMeterReadingId: candidate.previousReadingId)
            context.insert(prompt)
            created.append(prompt.id)
        }
        for prompt in data.prompts {
            if plan.deleteOpenPromptIds.contains(prompt.id) { context.delete(prompt) }
            if let previous = plan.updatePrevious[prompt.id] { prompt.previousMeterReadingId = previous }
        }
        try save()
        reload()
        return created
    }

    /// Stored only by the Apple device that made the change, and only when the Status is defined (FR-9).
    private func writeSnapshot(status: StatusOutcome, causeId: UUID, now: Date = Date()) {
        guard let r = status.result else { return }
        let snapshot = StatusSnapshot(generation: generation, status: r.status, paceToDateKwh: r.pace.paceKwh, baselineToDateKwh: r.baselineToDateKwh,
                                      isLowConfidence: r.isLowConfidence, computedAt: now, causeId: causeId)
        context.insert(snapshot)
    }

    // MARK: - Tariffs (FR-12, FR-14)

    struct TariffDraft: Equatable {
        var monthlyBaseFee: Decimal
        var pricePerKwh: Decimal
        var currency: String
        var contractStartDate: CalendarDate
        var contractPeriodMonths: Int
    }

    private func validate(_ draft: TariffDraft, excluding id: UUID?) throws {
        let errors = Validation.validateTariff(monthlyBaseFee: draft.monthlyBaseFee, pricePerKwh: draft.pricePerKwh, currency: draft.currency,
                                               contractPeriodMonths: draft.contractPeriodMonths, startDate: draft.contractStartDate)
        if !errors.isEmpty { throw StoreError.invalidTariff(errors) }
        if data.tariffs.contains(where: { $0.id != id && $0.contractStartDate == draft.contractStartDate }) {
            throw StoreError.duplicateTariffStart(draft.contractStartDate)
        }
    }

    @discardableResult
    func addTariff(_ draft: TariffDraft) throws -> UUID {
        ensureHousehold()
        try validate(draft, excluding: nil)
        let tariff = Tariff(generation: generation, monthlyBaseFee: draft.monthlyBaseFee, pricePerKwh: draft.pricePerKwh, currency: draft.currency,
                            contractStartDate: draft.contractStartDate, contractPeriodMonths: draft.contractPeriodMonths)
        context.insert(tariff)
        try save()
        finish(.tariffs)
        return tariff.id
    }

    /// Every changed field appends an Audit Correction (FR-12).
    func updateTariff(id: UUID, _ draft: TariffDraft, now: Date = Date()) throws {
        guard let tariff = data.tariffs.first(where: { $0.id == id }) else { throw StoreError.notFound }
        try validate(draft, excluding: id)
        func audit(_ field: String, _ old: String, _ new: String) {
            guard old != new else { return }
            context.insert(AuditCorrection(generation: generation, entityType: AuditEntityType.tariff, entityId: id, fieldName: field, oldValue: old, newValue: new, correctedAt: now))
        }
        audit(AuditField.monthlyBaseFee, DecimalMath.string(tariff.monthlyBaseFee), DecimalMath.string(draft.monthlyBaseFee))
        audit(AuditField.pricePerKwh, DecimalMath.string(tariff.pricePerKwh), DecimalMath.string(draft.pricePerKwh))
        audit(AuditField.currency, tariff.currency, draft.currency)
        audit(AuditField.contractStartDate, tariff.contractStartDate.iso, draft.contractStartDate.iso)
        audit(AuditField.contractPeriodMonths, String(tariff.contractPeriodMonths), String(draft.contractPeriodMonths))
        tariff.monthlyBaseFee = draft.monthlyBaseFee
        tariff.pricePerKwh = draft.pricePerKwh
        tariff.currency = draft.currency
        tariff.contractStartDate = draft.contractStartDate
        tariff.contractPeriodMonths = draft.contractPeriodMonths
        tariff.updatedAt = now
        try save()
        finish(.tariffs)
    }

    /// Deleting keeps the tariff's Audit Corrections.
    func deleteTariff(id: UUID) throws {
        guard let tariff = data.tariffs.first(where: { $0.id == id }) else { throw StoreError.notFound }
        context.delete(tariff)
        try save()
        finish(.tariffs)
    }

    /// Start dates shared by several tariffs after a sync (FR-12).
    var duplicateTariffStarts: [(date: CalendarDate, tariffs: [Tariff])] {
        let groups = Tariffs.duplicateStartDates(data.tariffs.map { TariffRef(id: $0.id, startDate: $0.contractStartDate, createdAt: $0.createdAt) })
        return groups.keys.sorted().map { date in (date, groups[date]!.compactMap { id in data.tariffs.first { $0.id == id } }) }
    }

    // MARK: - Events (FR-15)

    struct EventTag: Hashable {
        var type: TaggedEntityType
        var id: UUID
        var name: String
    }

    @discardableResult
    func addEvent(text: String, occurredAt: Date, tag: EventTag?) throws -> UUID {
        guard let description = Validation.normalizedEventDescription(text) else { throw StoreError.invalidDescription }
        ensureHousehold()
        let event = EnergyEvent(generation: generation, text: description, occurredAt: Instant.wholeSeconds(occurredAt))
        apply(tag, to: event)
        context.insert(event)
        try save()
        finish(.events)
        return event.id
    }

    func updateEvent(id: UUID, text: String, occurredAt: Date, tag: EventTag?, tagChanged: Bool) throws {
        guard let event = data.events.first(where: { $0.id == id }) else { throw StoreError.notFound }
        guard let description = Validation.normalizedEventDescription(text) else { throw StoreError.invalidDescription }
        event.text = description
        event.occurredAt = Instant.wholeSeconds(occurredAt)
        // The tag text is copied at tagging time and only changes when the user picks a new tag.
        if tagChanged { apply(tag, to: event) }
        event.updatedAt = Date()
        try save()
        finish(.events)
    }

    private func apply(_ tag: EventTag?, to event: EnergyEvent) {
        event.taggedEntityType = tag?.type
        event.taggedEntityId = tag?.id
        event.taggedEntityName = tag?.name
    }

    func deleteEvent(id: UUID) throws {
        guard let event = data.events.first(where: { $0.id == id }) else { throw StoreError.notFound }
        context.delete(event)
        try save()
        finish(.events)
    }

    /// The 5 most recent distinct descriptions (FR-15).
    var recentEventDescriptions: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for event in data.events.sorted(by: { $0.createdAt > $1.createdAt }) where !seen.contains(event.text) {
            seen.insert(event.text)
            result.append(event.text)
            if result.count == 5 { break }
        }
        return result
    }

    // MARK: - Structure (FR-18)

    @discardableResult
    func addRoom(name: String) throws -> UUID {
        guard let name = Validation.normalizedName(name) else { throw StoreError.invalidName }
        ensureHousehold()
        let room = Room(generation: generation, name: name)
        context.insert(room)
        try save()
        finish(.structure)
        return room.id
    }

    @discardableResult
    func addPowerPoint(roomId: UUID, name: String) throws -> UUID {
        guard let name = Validation.normalizedName(name) else { throw StoreError.invalidName }
        guard let room = data.rooms.first(where: { $0.id == roomId }) else { throw StoreError.notFound }
        guard room.archivedAt == nil else { throw StoreError.archivedParent }
        let point = PowerPoint(generation: generation, roomId: roomId, name: name)
        context.insert(point)
        try save()
        finish(.structure)
        return point.id
    }

    @discardableResult
    func addDevice(powerPointId: UUID, name: String) throws -> UUID {
        guard let name = Validation.normalizedName(name) else { throw StoreError.invalidName }
        guard let point = data.powerPoints.first(where: { $0.id == powerPointId }) else { throw StoreError.notFound }
        guard point.archivedAt == nil else { throw StoreError.archivedParent }
        let device = Device(generation: generation, powerPointId: powerPointId, name: name)
        context.insert(device)
        try save()
        finish(.structure)
        return device.id
    }

    enum StructureKind { case room, powerPoint, device }

    func rename(_ kind: StructureKind, id: UUID, to newName: String) throws {
        guard let name = Validation.normalizedName(newName) else { throw StoreError.invalidName }
        switch kind {
        case .room: guard let r = data.rooms.first(where: { $0.id == id }) else { throw StoreError.notFound }; r.name = name; r.updatedAt = Date()
        case .powerPoint: guard let p = data.powerPoints.first(where: { $0.id == id }) else { throw StoreError.notFound }; p.name = name; p.updatedAt = Date()
        case .device: guard let d = data.devices.first(where: { $0.id == id }) else { throw StoreError.notFound }; d.name = name; d.updatedAt = Date()
        }
        try save()
        finish(.structure)
    }

    func setArchived(_ kind: StructureKind, id: UUID, archived: Bool) throws {
        let stamp: Date? = archived ? Date() : nil
        switch kind {
        case .room: guard let r = data.rooms.first(where: { $0.id == id }) else { throw StoreError.notFound }; r.archivedAt = stamp; r.updatedAt = Date()
        case .powerPoint: guard let p = data.powerPoints.first(where: { $0.id == id }) else { throw StoreError.notFound }; p.archivedAt = stamp; p.updatedAt = Date()
        case .device: guard let d = data.devices.first(where: { $0.id == id }) else { throw StoreError.notFound }; d.archivedAt = stamp; d.updatedAt = Date()
        }
        try save()
        finish(.structure)
    }

    func movePowerPoint(id: UUID, toRoom roomId: UUID) throws {
        guard let point = data.powerPoints.first(where: { $0.id == id }), let room = data.rooms.first(where: { $0.id == roomId }) else { throw StoreError.notFound }
        guard room.archivedAt == nil else { throw StoreError.archivedParent }
        point.roomId = roomId
        point.updatedAt = Date()
        try save()
        finish(.structure)
    }

    func moveDevice(id: UUID, toPowerPoint pointId: UUID) throws {
        guard let device = data.devices.first(where: { $0.id == id }), let point = data.powerPoints.first(where: { $0.id == pointId }) else { throw StoreError.notFound }
        guard point.archivedAt == nil else { throw StoreError.archivedParent }
        device.powerPointId = pointId
        device.updatedAt = Date()
        try save()
        finish(.structure)
    }

    // MARK: - Held-back records after a restore (§7.5)

    func keepHeldBack() throws {
        guard let generation else { return }
        for record in data.heldBack.all { setGeneration(record, generation) }
        try save()
        reload()
        try runMaintenance(remote: false)
        finish(.all)
    }

    func discardHeldBack() throws {
        for record in data.heldBack.all { context.delete(record) }
        try save()
        finish(.all)
    }

    private func setGeneration(_ record: any PersistentModel, _ generation: UUID) {
        switch record {
        case let r as MeterReading: r.generation = generation
        case let r as EnergyEvent: r.generation = generation
        case let r as MainMeter: r.generation = generation
        case let r as AuditCorrection: r.generation = generation
        case let r as MeterRegressionPrompt: r.generation = generation
        case let r as Tariff: r.generation = generation
        case let r as Room: r.generation = generation
        case let r as PowerPoint: r.generation = generation
        case let r as Device: r.generation = generation
        case let r as StatusSnapshot: r.generation = generation
        case let r as SmartPlugReading: r.generation = generation
        default: break
        }
    }

    // MARK: - Maintenance: merge and regression check (§7.4, §7.6)

    /// Runs at launch, after each sync import and after import. Returns the number of merged duplicate readings.
    @discardableResult
    func runMaintenance(remote: Bool) throws -> Int {
        let merged = try applyMerge()
        reload()
        try checkRegressions()
        if remote { finish(.all, remote: true) } else { reload() }
        return merged
    }

    private func applyMerge() throws -> Int {
        let households = (try? context.fetch(FetchDescriptor<Household>())) ?? []
        let input = DuplicateMerge.Input(
            households: households.map { .init(id: $0.id, createdAt: $0.createdAt, generation: $0.generation, generationStartedAt: $0.generationStartedAt, fieldStamps: $0.fieldStamps) },
            meters: allCurrent(MainMeter.self, \.generation).map { .init(id: $0.id, createdAt: $0.createdAt, digitCapacityKwh: $0.digitCapacityKwh) },
            readings: data.readings.compactMap { r in r.mainMeterId.map { .init(id: r.id, createdAt: r.createdAt, mainMeterId: $0, timestamp: r.readingTimestamp, originalKwh: r.originalKwhValue) } },
            prompts: data.prompts.compactMap { p in
                guard let reading = p.meterReadingId, let previous = p.previousMeterReadingId, let meter = p.mainMeterId ?? data.meter?.id else { return nil }
                return .init(id: p.id, createdAt: p.createdAt, mainMeterId: meter, readingId: reading, previousReadingId: previous, resolvedAt: p.resolvedAt, classification: p.classification)
            },
            snapshots: data.snapshots.compactMap { s in s.causeId.map { .init(id: s.id, createdAt: s.createdAt, causeId: $0) } },
            corrections: data.corrections.compactMap { c in c.entityId.map { .init(id: c.id, entityType: c.entityType, entityId: $0, fieldName: c.fieldName, oldValue: c.oldValue, newValue: c.newValue, correctedAt: c.correctedAt) } }
        )
        let plan = DuplicateMerge.plan(input)
        if !plan.classificationConflicts.isEmpty { addNotices(plan.classificationConflicts) }
        guard !plan.isEmpty else { return 0 }

        let byId = Dictionary(households.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if let keepId = plan.keepHouseholdId, let keeper = byId[keepId] {
            var stamps = keeper.fieldStamps
            for (field, sourceId) in plan.householdFieldSources {
                guard let source = byId[sourceId], let f = HouseholdField(rawValue: field) else { continue }
                switch f {
                case .locale: keeper.locale = source.locale
                case .currency: keeper.currency = source.currency
                case .yearlyBaselineKwh: keeper.yearlyBaselineKwhText = source.yearlyBaselineKwhText
                case .trendingThresholdKwh: keeper.trendingThresholdKwhText = source.trendingThresholdKwhText
                case .lowConfidenceGapDays: keeper.lowConfidenceGapDays = source.lowConfidenceGapDays
                case .tariffCheckCadenceMonths: keeper.tariffCheckCadenceMonths = source.tariffCheckCadenceMonths
                case .tariffCheckDoneAt: keeper.tariffCheckDoneAt = source.tariffCheckDoneAt
                }
                stamps[field] = source.fieldStamps[field]
            }
            keeper.fieldStamps = stamps
        }
        for id in plan.deleteHouseholdIds { if let h = byId[id] { context.delete(h) } }

        let meters = allCurrent(MainMeter.self, \.generation)
        if let keepId = plan.keepMeterId, let capacity = plan.meterDigitCapacityKwh { meters.first { $0.id == keepId }?.digitCapacityKwh = capacity }
        for meter in meters where plan.deleteMeterIds.contains(meter.id) { context.delete(meter) }

        let deleteReadings = Set(plan.deleteReadingIds)
        for r in data.readings {
            if let m = plan.readingMeterUpdates[r.id] { r.mainMeterId = m }
            if deleteReadings.contains(r.id) { context.delete(r) }
        }
        let deletePrompts = Set(plan.deletePromptIds)
        for p in data.prompts {
            if let m = plan.promptMeterUpdates[p.id] { p.mainMeterId = m }
            if let r = plan.promptReadingUpdates[p.id] { p.meterReadingId = r }
            if let r = plan.promptPreviousReadingUpdates[p.id] { p.previousMeterReadingId = r }
            if deletePrompts.contains(p.id) { context.delete(p) }
        }
        let deleteSnapshots = Set(plan.deleteSnapshotIds)
        for s in data.snapshots {
            if let c = plan.snapshotCauseUpdates[s.id] { s.causeId = c }
            if deleteSnapshots.contains(s.id) { context.delete(s) }
        }
        let deleteCorrections = Set(plan.deleteCorrectionIds)
        for c in data.corrections {
            if let e = plan.correctionEntityUpdates[c.id] { c.entityId = e }
            if deleteCorrections.contains(c.id) { context.delete(c) }
        }
        try save()
        return plan.mergedReadingCount
    }

    private func allCurrent<T: PersistentModel>(_ type: T.Type, _ gen: (T) -> UUID?) -> [T] {
        ((try? context.fetch(FetchDescriptor<T>())) ?? []).filter { !Generations.isHeldBack(recordGeneration: gen($0), current: generation) }
    }

    // MARK: - Classification notices (per Apple device, shown once)

    private static let dismissedNoticesKey = "dismissedClassificationNotices"

    private func addNotices(_ conflicts: [UUID: RegressionClassification]) {
        let dismissed = Set(AppConfig.sharedDefaults.stringArray(forKey: Self.dismissedNoticesKey) ?? [])
        for (reading, classification) in conflicts where !dismissed.contains(reading.uuidString) {
            classificationNotices.removeAll { $0.readingId == reading }
            classificationNotices.append(ClassificationNotice(readingId: reading, classification: classification))
        }
    }

    func dismissNotice(_ notice: ClassificationNotice) {
        classificationNotices.removeAll { $0 == notice }
        var dismissed = AppConfig.sharedDefaults.stringArray(forKey: Self.dismissedNoticesKey) ?? []
        dismissed.append(notice.readingId.uuidString)
        AppConfig.sharedDefaults.set(dismissed, forKey: Self.dismissedNoticesKey)
    }

    // MARK: - Export (FR-19)

    func exportRecords(now: Date = Date()) -> DataSetRecords? {
        guard let h = data.household else { return nil }
        var r = DataSetRecords(exportedAt: now, household: HouseholdRecord(
            id: h.id, createdAt: h.createdAt, locale: h.locale, currency: h.currency, yearlyBaselineKwh: h.yearlyBaselineKwh,
            trendingThresholdKwh: h.trendingThresholdKwh, lowConfidenceGapDays: h.lowConfidenceGapDays,
            tariffCheckCadenceMonths: h.tariffCheckCadenceMonths, tariffCheckDoneAt: h.tariffCheckDoneAt))
        if let meter = data.meter, !data.readings.isEmpty || meter.digitCapacityKwh != nil {
            r.mainMeter = MainMeterRecord(id: meter.id, createdAt: meter.createdAt, digitCapacityKwh: meter.digitCapacityKwh)
        }
        let meterId = data.meter?.id
        r.readings = data.readings.map { x in
            ReadingRecord(id: x.id, mainMeterId: meterId ?? x.mainMeterId ?? UUID(), originalKwhValue: x.originalKwhValue,
                          effectiveKwhValue: data.effectiveValues[x.id], readingTimestamp: x.readingTimestamp, createdAt: x.createdAt)
        }
        r.prompts = data.prompts.compactMap { p in
            guard let reading = p.meterReadingId, let previous = p.previousMeterReadingId else { return nil }
            return PromptRecord(id: p.id, mainMeterId: meterId ?? p.mainMeterId ?? UUID(), meterReadingId: reading, previousMeterReadingId: previous,
                                createdAt: p.createdAt, resolvedAt: p.resolvedAt, classification: p.classification, digitCapacityKwh: p.digitCapacityKwh)
        }
        r.tariffs = data.tariffs.sorted { $0.contractStartDate < $1.contractStartDate }.map { t in
            TariffRecord(id: t.id, monthlyBaseFee: t.monthlyBaseFee, pricePerKwh: t.pricePerKwh, currency: t.currency,
                         contractStartDate: t.contractStartDate, contractPeriodMonths: t.contractPeriodMonths, createdAt: t.createdAt)
        }
        let readings = data.readingInputs, prompts = data.promptInputs
        r.events = data.events.sorted { $0.occurredAt < $1.occurredAt }.map { e in
            EventRecord(id: e.id, description: e.text, occurredAt: e.occurredAt, createdAt: e.createdAt, updatedAt: e.updatedAt,
                        taggedEntityType: e.taggedEntityType, taggedEntityId: e.taggedEntityId, taggedEntityName: e.taggedEntityName,
                        exportDeviation: DeviationCalculator.compute(occurredAt: e.occurredAt, readings: readings, prompts: prompts,
                                                                     meterDigitCapacityKwh: data.meter?.digitCapacityKwh,
                                                                     yearlyBaselineKwh: h.yearlyBaselineKwh, trendingThresholdKwh: h.trendingThresholdKwh))
        }
        r.rooms = data.rooms.sorted { $0.createdAt < $1.createdAt }.map { StructureRecord(id: $0.id, name: $0.name, createdAt: $0.createdAt, archivedAt: $0.archivedAt) }
        r.powerPoints = data.powerPoints.sorted { $0.createdAt < $1.createdAt }.map { StructureRecord(id: $0.id, name: $0.name, createdAt: $0.createdAt, archivedAt: $0.archivedAt, parentId: $0.roomId) }
        r.devices = data.devices.sorted { $0.createdAt < $1.createdAt }.map { StructureRecord(id: $0.id, name: $0.name, createdAt: $0.createdAt, archivedAt: $0.archivedAt, parentId: $0.powerPointId) }
        let plugs = ((try? context.fetch(FetchDescriptor<SmartPlugReading>(sortBy: [SortDescriptor(\.intervalStart)]))) ?? [])
            .filter { !Generations.isHeldBack(recordGeneration: $0.generation, current: generation) }
        r.smartPlugReadings = plugs.map { SmartPlugReadingRecord(id: $0.id, powerPointId: $0.powerPointId, roomName: $0.roomName, powerPointName: $0.powerPointName,
                                                                 deviceName: $0.deviceName, intervalStart: $0.intervalStart, intervalEnd: $0.intervalEnd, kwhValue: $0.kwhValue) }
        r.snapshots = data.snapshots.map { SnapshotRecord(id: $0.id, status: $0.status, paceToDateKwh: $0.paceToDateKwh, baselineToDateKwh: $0.baselineToDateKwh,
                                                          isLowConfidence: $0.isLowConfidence, computedAt: $0.computedAt, causeId: $0.causeId ?? $0.id, createdAt: $0.createdAt) }
        r.corrections = data.corrections.compactMap { c in
            c.entityId.map { CorrectionRecord(id: c.id, entityType: c.entityType, entityId: $0, fieldName: c.fieldName, oldValue: c.oldValue, newValue: c.newValue, correctedAt: c.correctedAt) }
        }
        return r
    }

    // MARK: - Import: replace all (FR-20, §7.5)

    struct ImportResult {
        var mergedDuplicateReadings: Int
    }

    /// Counts of the current data set, shown before it is replaced.
    var currentCounts: DataSetRecords.Counts {
        let plugCount = (try? context.fetchCount(FetchDescriptor<SmartPlugReading>())) ?? 0
        return DataSetRecords.Counts(readings: data.readings.count, prompts: data.prompts.count, tariffs: data.tariffs.count, events: data.events.count,
                                     rooms: data.rooms.count, powerPoints: data.powerPoints.count, devices: data.devices.count,
                                     smartPlugReadings: plugCount, snapshots: data.snapshots.count, corrections: data.corrections.count)
    }

    /// Deletes every record on every Apple device of this Apple Account and writes the file's records under a new generation.
    func replaceAll(with records: DataSetRecords, progress: @escaping (Double) -> Void) async throws -> ImportResult {
        let generation = UUID()
        let now = Date()
        let total = Double(max(1, records.readings.count + records.prompts.count + records.tariffs.count + records.events.count + records.rooms.count
            + records.powerPoints.count + records.devices.count + records.smartPlugReadings.count + records.snapshots.count + records.corrections.count))
        var done = 0.0
        progress(0)

        // 1. Delete everything, all generations.
        try deleteAll(Household.self); try deleteAll(MainMeter.self); try deleteAll(MeterReading.self); try deleteAll(MeterRegressionPrompt.self)
        try deleteAll(Tariff.self); try deleteAll(EnergyEvent.self); try deleteAll(Room.self); try deleteAll(PowerPoint.self); try deleteAll(Device.self)
        try deleteAll(StatusSnapshot.self); try deleteAll(AuditCorrection.self); try deleteAll(SmartPlugReading.self)
        try save()
        await Task.yield()

        // 2. Household with the new generation; its settings win over any stale copy (§7.4).
        let h = records.household
        let household = Household(id: h.id, createdAt: h.createdAt, generation: generation)
        household.generationStartedAt = now
        household.locale = h.locale
        household.currency = h.currency
        household.yearlyBaselineKwh = h.yearlyBaselineKwh
        household.trendingThresholdKwh = h.trendingThresholdKwh
        household.lowConfidenceGapDays = h.lowConfidenceGapDays
        household.tariffCheckCadenceMonths = h.tariffCheckCadenceMonths
        household.tariffCheckDoneAt = h.tariffCheckDoneAt
        household.fieldStamps = Dictionary(uniqueKeysWithValues: HouseholdField.allCases.map { ($0.rawValue, now) })
        context.insert(household)
        if let m = records.mainMeter {
            let meter = MainMeter(id: m.id, createdAt: m.createdAt, generation: generation)
            meter.digitCapacityKwh = m.digitCapacityKwh
            context.insert(meter)
        }

        // 3. Everything else, in batches with progress.
        var pending = 0
        func step() async throws {
            done += 1
            pending += 1
            if pending >= 500 {
                pending = 0
                try save()
                progress(min(0.99, done / total))
                await Task.yield()
            }
        }
        for x in records.readings {
            context.insert(MeterReading(id: x.id, createdAt: x.createdAt, generation: generation, mainMeterId: x.mainMeterId, kwhValue: x.originalKwhValue, readingTimestamp: x.readingTimestamp))
            try await step()
        }
        for x in records.corrections {
            context.insert(AuditCorrection(id: x.id, generation: generation, entityType: x.entityType, entityId: x.entityId, fieldName: x.fieldName, oldValue: x.oldValue, newValue: x.newValue, correctedAt: x.correctedAt))
            try await step()
        }
        for x in records.prompts {
            let p = MeterRegressionPrompt(id: x.id, createdAt: x.createdAt, generation: generation, mainMeterId: x.mainMeterId, meterReadingId: x.meterReadingId, previousMeterReadingId: x.previousMeterReadingId)
            p.resolvedAt = x.resolvedAt
            p.classification = x.classification
            p.digitCapacityKwh = x.digitCapacityKwh
            context.insert(p)
            try await step()
        }
        for x in records.tariffs {
            context.insert(Tariff(id: x.id, createdAt: x.createdAt, generation: generation, monthlyBaseFee: x.monthlyBaseFee, pricePerKwh: x.pricePerKwh, currency: x.currency, contractStartDate: x.contractStartDate, contractPeriodMonths: x.contractPeriodMonths))
            try await step()
        }
        for x in records.events {
            let e = EnergyEvent(id: x.id, createdAt: x.createdAt, generation: generation, text: x.description, occurredAt: x.occurredAt)
            e.updatedAt = x.updatedAt
            e.taggedEntityType = x.taggedEntityType
            e.taggedEntityId = x.taggedEntityId
            e.taggedEntityName = x.taggedEntityName
            context.insert(e)
            try await step()
        }
        for x in records.rooms {
            let r = Room(id: x.id, createdAt: x.createdAt, generation: generation, name: x.name)
            r.archivedAt = x.archivedAt
            context.insert(r)
            try await step()
        }
        for x in records.powerPoints {
            let p = PowerPoint(id: x.id, createdAt: x.createdAt, generation: generation, roomId: x.parentId, name: x.name)
            p.archivedAt = x.archivedAt
            context.insert(p)
            try await step()
        }
        for x in records.devices {
            let d = Device(id: x.id, createdAt: x.createdAt, generation: generation, powerPointId: x.parentId, name: x.name)
            d.archivedAt = x.archivedAt
            context.insert(d)
            try await step()
        }
        for x in records.snapshots {
            context.insert(StatusSnapshot(id: x.id, createdAt: x.createdAt, generation: generation, status: x.status, paceToDateKwh: x.paceToDateKwh,
                                          baselineToDateKwh: x.baselineToDateKwh, isLowConfidence: x.isLowConfidence, computedAt: x.computedAt, causeId: x.causeId))
            try await step()
        }
        for x in records.smartPlugReadings {
            context.insert(SmartPlugReading(id: x.id, generation: generation, powerPointId: x.powerPointId, roomName: x.roomName, powerPointName: x.powerPointName,
                                            deviceName: x.deviceName, intervalStart: x.intervalStart, intervalEnd: x.intervalEnd, kwhValue: x.kwhValue))
            try await step()
        }
        try save()
        reload()
        // 4. Merge exact duplicates from the file. The import writes no Status Snapshot.
        let merged = try runMaintenance(remote: false)
        progress(1)
        finish(.all)
        return ImportResult(mergedDuplicateReadings: merged)
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        // Deleted one by one so every deletion is mirrored to CloudKit.
        for item in (try context.fetch(FetchDescriptor<T>())) { context.delete(item) }
    }
}
