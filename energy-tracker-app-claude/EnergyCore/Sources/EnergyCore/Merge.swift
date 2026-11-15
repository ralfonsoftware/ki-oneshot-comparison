import Foundation

/// Automatic duplicate merge (§7.4). Deterministic and idempotent: the same input gives the same plan on every
/// Apple device, and applying a plan then planning again gives an empty plan.
public enum DuplicateMerge {
    public struct Household: Sendable, Hashable {
        public var id: UUID
        public var createdAt: Date
        public var generation: UUID?
        public var generationStartedAt: Date?
        /// Last change per settings field name.
        public var fieldStamps: [String: Date]

        public init(id: UUID, createdAt: Date, generation: UUID? = nil, generationStartedAt: Date? = nil, fieldStamps: [String: Date] = [:]) {
            self.id = id
            self.createdAt = createdAt
            self.generation = generation
            self.generationStartedAt = generationStartedAt
            self.fieldStamps = fieldStamps
        }
    }

    public struct Meter: Sendable, Hashable {
        public var id: UUID
        public var createdAt: Date
        public var digitCapacityKwh: Decimal?

        public init(id: UUID, createdAt: Date, digitCapacityKwh: Decimal? = nil) {
            self.id = id
            self.createdAt = createdAt
            self.digitCapacityKwh = digitCapacityKwh
        }
    }

    public struct Reading: Sendable, Hashable {
        public var id: UUID
        public var createdAt: Date
        public var mainMeterId: UUID
        public var timestamp: Date
        public var originalKwh: Decimal

        public init(id: UUID, createdAt: Date, mainMeterId: UUID, timestamp: Date, originalKwh: Decimal) {
            self.id = id
            self.createdAt = createdAt
            self.mainMeterId = mainMeterId
            self.timestamp = timestamp
            self.originalKwh = originalKwh
        }
    }

    public struct Prompt: Sendable, Hashable {
        public var id: UUID
        public var createdAt: Date
        public var mainMeterId: UUID
        public var readingId: UUID
        public var previousReadingId: UUID
        public var resolvedAt: Date?
        public var classification: RegressionClassification?

        public init(id: UUID, createdAt: Date, mainMeterId: UUID, readingId: UUID, previousReadingId: UUID, resolvedAt: Date? = nil, classification: RegressionClassification? = nil) {
            self.id = id
            self.createdAt = createdAt
            self.mainMeterId = mainMeterId
            self.readingId = readingId
            self.previousReadingId = previousReadingId
            self.resolvedAt = resolvedAt
            self.classification = classification
        }

        var isResolved: Bool { resolvedAt != nil && classification != nil }
    }

    public struct Snapshot: Sendable, Hashable {
        public var id: UUID
        public var createdAt: Date
        public var causeId: UUID

        public init(id: UUID, createdAt: Date, causeId: UUID) {
            self.id = id
            self.createdAt = createdAt
            self.causeId = causeId
        }
    }

    public struct Correction: Sendable, Hashable {
        public var id: UUID
        public var entityType: String
        public var entityId: UUID
        public var fieldName: String
        public var oldValue: String
        public var newValue: String
        public var correctedAt: Date

        public init(id: UUID, entityType: String, entityId: UUID, fieldName: String, oldValue: String, newValue: String, correctedAt: Date) {
            self.id = id
            self.entityType = entityType
            self.entityId = entityId
            self.fieldName = fieldName
            self.oldValue = oldValue
            self.newValue = newValue
            self.correctedAt = correctedAt
        }
    }

    public struct Input: Sendable {
        public var households: [Household] = []
        public var meters: [Meter] = []
        public var readings: [Reading] = []
        public var prompts: [Prompt] = []
        public var snapshots: [Snapshot] = []
        public var corrections: [Correction] = []

        public init(households: [Household] = [], meters: [Meter] = [], readings: [Reading] = [], prompts: [Prompt] = [], snapshots: [Snapshot] = [], corrections: [Correction] = []) {
            self.households = households
            self.meters = meters
            self.readings = readings
            self.prompts = prompts
            self.snapshots = snapshots
            self.corrections = corrections
        }
    }

    public struct Plan: Sendable, Hashable {
        public var keepHouseholdId: UUID?
        /// Settings field -> household record to copy the value from (only when it differs from the keeper).
        public var householdFieldSources: [String: UUID] = [:]
        public var deleteHouseholdIds: [UUID] = []

        public var keepMeterId: UUID?
        /// Digit capacity the kept meter should take over from a deleted duplicate.
        public var meterDigitCapacityKwh: Decimal?
        public var deleteMeterIds: [UUID] = []
        /// Reading -> new main meter id.
        public var readingMeterUpdates: [UUID: UUID] = [:]
        /// Prompt -> new main meter id.
        public var promptMeterUpdates: [UUID: UUID] = [:]

        /// Duplicate reading -> kept reading.
        public var readingRemap: [UUID: UUID] = [:]
        public var deleteReadingIds: [UUID] = []
        public var promptReadingUpdates: [UUID: UUID] = [:]
        public var promptPreviousReadingUpdates: [UUID: UUID] = [:]
        public var deletePromptIds: [UUID] = []
        public var snapshotCauseUpdates: [UUID: UUID] = [:]
        public var deleteSnapshotIds: [UUID] = []
        public var correctionEntityUpdates: [UUID: UUID] = [:]
        public var deleteCorrectionIds: [UUID] = []

        /// Readings whose prompt was classified differently on two Apple devices: reading id -> winning classification.
        public var classificationConflicts: [UUID: RegressionClassification] = [:]

        public var isEmpty: Bool {
            householdFieldSources.isEmpty && deleteHouseholdIds.isEmpty && meterDigitCapacityKwh == nil && deleteMeterIds.isEmpty
                && readingMeterUpdates.isEmpty && promptMeterUpdates.isEmpty && readingRemap.isEmpty && deleteReadingIds.isEmpty
                && promptReadingUpdates.isEmpty && promptPreviousReadingUpdates.isEmpty && deletePromptIds.isEmpty
                && snapshotCauseUpdates.isEmpty && deleteSnapshotIds.isEmpty && correctionEntityUpdates.isEmpty && deleteCorrectionIds.isEmpty
        }

        /// Number of duplicate readings merged.
        public var mergedReadingCount: Int { deleteReadingIds.count }
    }

    /// "Keep the earliest": earliest `createdAt`, ties by lowest id.
    static func earliestFirst(_ a: (Date, UUID), _ b: (Date, UUID)) -> Bool {
        if a.0 != b.0 { return a.0 < b.0 }
        return idAscending(a.1, b.1)
    }

    public static func plan(_ input: Input) -> Plan {
        var plan = Plan()

        // Household: the newest generation wins; within it keep the earliest; per field the last change wins.
        if !input.households.isEmpty {
            let newestGeneration = input.households.max { a, b in
                let ta = a.generationStartedAt ?? .distantPast, tb = b.generationStartedAt ?? .distantPast
                if ta != tb { return ta < tb }
                return idKey(a.id) > idKey(b.id)
            }?.generation
            let current = input.households.filter { $0.generation == newestGeneration }
            let superseded = input.households.filter { $0.generation != newestGeneration }
            let sorted = current.sorted { earliestFirst(($0.createdAt, $0.id), ($1.createdAt, $1.id)) }
            let keeper = sorted[0]
            plan.keepHouseholdId = keeper.id
            if sorted.count > 1 {
                let fields = Set(sorted.flatMap { $0.fieldStamps.keys })
                for field in fields.sorted() {
                    let winner = sorted.max { a, b in
                        let ta = a.fieldStamps[field] ?? .distantPast, tb = b.fieldStamps[field] ?? .distantPast
                        if ta != tb { return ta < tb }
                        // Equal stamps: prefer the keeper, then the lowest id.
                        if a.id == keeper.id { return false }
                        if b.id == keeper.id { return true }
                        return idKey(a.id) > idKey(b.id)
                    }!
                    if winner.id != keeper.id, (winner.fieldStamps[field] ?? .distantPast) > (keeper.fieldStamps[field] ?? .distantPast) {
                        plan.householdFieldSources[field] = winner.id
                    }
                }
            }
            plan.deleteHouseholdIds = (sorted.dropFirst().map(\.id) + superseded.map(\.id)).sorted(by: idAscending)
        }

        // Main Meter.
        var meterRemap: [UUID: UUID] = [:]
        if !input.meters.isEmpty {
            let sorted = input.meters.sorted { earliestFirst(($0.createdAt, $0.id), ($1.createdAt, $1.id)) }
            let keeper = sorted[0]
            plan.keepMeterId = keeper.id
            if keeper.digitCapacityKwh == nil, let known = sorted.first(where: { $0.digitCapacityKwh != nil })?.digitCapacityKwh {
                plan.meterDigitCapacityKwh = known
            }
            for other in sorted.dropFirst() {
                meterRemap[other.id] = keeper.id
                plan.deleteMeterIds.append(other.id)
            }
        }
        func meter(_ id: UUID) -> UUID { meterRemap[id] ?? id }
        for r in input.readings where meterRemap[r.mainMeterId] != nil { plan.readingMeterUpdates[r.id] = meter(r.mainMeterId) }
        for p in input.prompts where meterRemap[p.mainMeterId] != nil { plan.promptMeterUpdates[p.id] = meter(p.mainMeterId) }

        // Exact duplicate readings: same meter, same timestamp to the second, same original value.
        struct ReadingKey: Hashable { var meter: UUID; var second: Int64; var value: String }
        let groups = Dictionary(grouping: input.readings) {
            ReadingKey(meter: meter($0.mainMeterId), second: Int64($0.timestamp.timeIntervalSince1970.rounded(.down)), value: DecimalMath.string($0.originalKwh))
        }
        for (_, group) in groups where group.count > 1 {
            let sorted = group.sorted { earliestFirst(($0.createdAt, $0.id), ($1.createdAt, $1.id)) }
            for dup in sorted.dropFirst() {
                plan.readingRemap[dup.id] = sorted[0].id
                plan.deleteReadingIds.append(dup.id)
            }
        }
        plan.deleteReadingIds.sort(by: idAscending)
        func reading(_ id: UUID) -> UUID { plan.readingRemap[id] ?? id }

        // Prompts: re-point, then one per reading.
        var promptsAfter: [Prompt] = []
        for var p in input.prompts {
            if plan.readingRemap[p.readingId] != nil { plan.promptReadingUpdates[p.id] = reading(p.readingId); p.readingId = reading(p.readingId) }
            if plan.readingRemap[p.previousReadingId] != nil { plan.promptPreviousReadingUpdates[p.id] = reading(p.previousReadingId); p.previousReadingId = reading(p.previousReadingId) }
            promptsAfter.append(p)
        }
        for (readingId, group) in Dictionary(grouping: promptsAfter, by: \.readingId) where group.count > 1 {
            let resolved = group.filter(\.isResolved)
            let keeper: Prompt
            if !resolved.isEmpty {
                keeper = resolved.max { a, b in
                    if a.resolvedAt! != b.resolvedAt! { return a.resolvedAt! < b.resolvedAt! }
                    return idKey(a.id) < idKey(b.id)
                }!
                if Set(resolved.compactMap(\.classification)).count > 1, let winner = keeper.classification {
                    plan.classificationConflicts[readingId] = winner
                }
            } else {
                keeper = group.sorted { earliestFirst(($0.createdAt, $0.id), ($1.createdAt, $1.id)) }[0]
            }
            plan.deletePromptIds += group.filter { $0.id != keeper.id }.map(\.id)
        }
        plan.deletePromptIds.sort(by: idAscending)

        // Snapshots: re-point causes, then one per cause.
        var snapshotsAfter: [Snapshot] = []
        for var s in input.snapshots {
            if plan.readingRemap[s.causeId] != nil { plan.snapshotCauseUpdates[s.id] = reading(s.causeId); s.causeId = reading(s.causeId) }
            snapshotsAfter.append(s)
        }
        for (_, group) in Dictionary(grouping: snapshotsAfter, by: \.causeId) where group.count > 1 {
            let sorted = group.sorted { earliestFirst(($0.createdAt, $0.id), ($1.createdAt, $1.id)) }
            plan.deleteSnapshotIds += sorted.dropFirst().map(\.id)
        }
        plan.deleteSnapshotIds.sort(by: idAscending)

        // Corrections: re-point, then drop identical ones.
        struct CorrectionKey: Hashable { var type: String; var entity: UUID; var field: String; var old: String; var new: String; var at: Date }
        var correctionsAfter: [Correction] = []
        for var c in input.corrections {
            if c.entityType == AuditEntityType.meterReading, plan.readingRemap[c.entityId] != nil {
                plan.correctionEntityUpdates[c.id] = reading(c.entityId)
                c.entityId = reading(c.entityId)
            }
            correctionsAfter.append(c)
        }
        for (_, group) in Dictionary(grouping: correctionsAfter, by: { CorrectionKey(type: $0.entityType, entity: $0.entityId, field: $0.fieldName, old: $0.oldValue, new: $0.newValue, at: $0.correctedAt) }) where group.count > 1 {
            let sorted = group.sorted { idAscending($0.id, $1.id) }
            plan.deleteCorrectionIds += sorted.dropFirst().map(\.id)
        }
        plan.deleteCorrectionIds.sort(by: idAscending)
        return plan
    }
}

/// Data set generation rules (§7.5).
public enum Generations {
    /// Records whose generation differs from the current one are held back. Records without a generation
    /// (created before a generation existed on this Apple device) belong to the current generation.
    public static func isHeldBack(recordGeneration: UUID?, current: UUID?) -> Bool {
        guard let current, let recordGeneration else { return false }
        return recordGeneration != current
    }
}
