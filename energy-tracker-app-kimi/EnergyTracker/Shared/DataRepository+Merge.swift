import Foundation

extension DataRepository {
    func mergeDuplicates() throws {
        var changed = false
        changed = try mergeHouseholds() || changed
        changed = try mergeMeters() || changed
        changed = try mergeReadings() || changed
        changed = try mergePrompts() || changed
        changed = try mergeSnapshots() || changed
        changed = try mergeCorrections() || changed
        if changed { try context.save() }
    }

    private func mergeHouseholds() throws -> Bool {
        var changed = false
        let groups = Dictionary(grouping: try fetch(Household.self), by: \.generation)
        for (_, duplicates) in groups where duplicates.count > 1 {
            guard let keeper = duplicates.sorted(by: Self.earliestOrder).first else { continue }
            keeper.yearlyBaselineKwh = newest(duplicates, date: { $0.yearlyBaselineUpdatedAt ?? $0.createdAt }).yearlyBaselineKwh
            keeper.trendingThresholdKwh = newest(duplicates, date: { $0.thresholdUpdatedAt ?? $0.createdAt }).trendingThresholdKwh
            keeper.lowConfidenceGapDays = newest(duplicates, date: { $0.gapUpdatedAt ?? $0.createdAt }).lowConfidenceGapDays
            keeper.currency = newest(duplicates, date: { $0.currencyUpdatedAt ?? $0.createdAt }).currency
            keeper.tariffCheckCadenceMonths = newest(duplicates, date: { $0.cadenceUpdatedAt ?? $0.createdAt }).tariffCheckCadenceMonths
            keeper.tariffCheckDoneAt = newest(duplicates, date: { $0.tariffDoneUpdatedAt ?? $0.createdAt }).tariffCheckDoneAt
            keeper.yearlyBaselineUpdatedAt = duplicates.compactMap(\.yearlyBaselineUpdatedAt).max()
            keeper.thresholdUpdatedAt = duplicates.compactMap(\.thresholdUpdatedAt).max()
            keeper.gapUpdatedAt = duplicates.compactMap(\.gapUpdatedAt).max()
            keeper.currencyUpdatedAt = duplicates.compactMap(\.currencyUpdatedAt).max()
            keeper.cadenceUpdatedAt = duplicates.compactMap(\.cadenceUpdatedAt).max()
            keeper.tariffDoneUpdatedAt = duplicates.compactMap(\.tariffDoneUpdatedAt).max()
            keeper.generationChangedAt = duplicates.map(\.generationChangedAt).max() ?? keeper.generationChangedAt
            keeper.updatedAt = duplicates.map(\.updatedAt).max() ?? keeper.updatedAt
            for duplicate in duplicates where duplicate.id != keeper.id { context.delete(duplicate) }
            changed = true
        }
        return changed
    }

    private func mergeMeters() throws -> Bool {
        var changed = false
        let groups = Dictionary(grouping: try fetch(MainMeter.self), by: \.generation)
        let allReadings = try fetch(MeterReading.self)
        let allPrompts = try fetch(MeterRegressionPrompt.self)
        for (_, duplicates) in groups where duplicates.count > 1 {
            guard let keeper = duplicates.sorted(by: Self.earliestOrder).first else { continue }
            let ids = Set(duplicates.map(\.id))
            for reading in allReadings where ids.contains(reading.mainMeterId) { reading.mainMeterId = keeper.id }
            for prompt in allPrompts where ids.contains(prompt.mainMeterId) { prompt.mainMeterId = keeper.id }
            let withCapacity = duplicates.filter { $0.digitCapacityKwh != nil }
            let newestCapacity = withCapacity.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString > rhs.id.uuidString
            }.first
            if let capacity = newestCapacity?.digitCapacityKwh {
                keeper.digitCapacityKwh = capacity
            }
            keeper.updatedAt = duplicates.map(\.updatedAt).max() ?? keeper.updatedAt
            for duplicate in duplicates where duplicate.id != keeper.id { context.delete(duplicate) }
            changed = true
        }
        return changed
    }

    private struct ReadingKey: Hashable {
        let generation: UUID
        let meter: UUID
        let second: Int64
        let value: String
    }

    private func mergeReadings() throws -> Bool {
        let all = try fetch(MeterReading.self)
        let groups = Dictionary(grouping: all) {
            ReadingKey(generation: $0.generation, meter: $0.mainMeterId, second: Self.second($0.readingTimestamp), value: DecimalText.encode(DecimalText.decode($0.kwhValue) ?? -1))
        }
        var changed = false
        let corrections = try fetch(AuditCorrection.self)
        let prompts = try fetch(MeterRegressionPrompt.self)
        let snapshots = try fetch(StatusSnapshot.self)
        for (_, duplicates) in groups where duplicates.count > 1 {
            guard let keeper = duplicates.sorted(by: Self.earliestOrder).first else { continue }
            let ids = Set(duplicates.map(\.id))
            for correction in corrections where correction.entityType == "MeterReading" && ids.contains(correction.entityId) { correction.entityId = keeper.id }
            for prompt in prompts {
                if ids.contains(prompt.meterReadingId) { prompt.meterReadingId = keeper.id }
                if ids.contains(prompt.previousMeterReadingId) { prompt.previousMeterReadingId = keeper.id }
            }
            for snapshot in snapshots where ids.contains(snapshot.causeId) { snapshot.causeId = keeper.id }
            for duplicate in duplicates where duplicate.id != keeper.id { context.delete(duplicate) }
            changed = true
        }
        return changed
    }

    private func mergePrompts() throws -> Bool {
        var changed = false
        let groups = Dictionary(grouping: try fetch(MeterRegressionPrompt.self)) { "\($0.generation)-\($0.meterReadingId)" }
        for (_, duplicates) in groups where duplicates.count > 1 {
            let resolved = duplicates.filter { $0.resolvedAt != nil }
            let pool = resolved.isEmpty ? duplicates : resolved
            let keeper = pool.sorted { lhs, rhs in
                if resolved.isEmpty { return Self.earliestOrderForPrompt(lhs, rhs) }
                if lhs.resolvedAt != rhs.resolvedAt { return (lhs.resolvedAt ?? .distantPast) > (rhs.resolvedAt ?? .distantPast) }
                return lhs.id.uuidString > rhs.id.uuidString
            }.first!
            if !resolved.isEmpty {
                let classifications = Set(resolved.map { $0.classification ?? "" })
                if classifications.count > 1, keeper.classification != nil {
                    lastMergeNotice = String(format: String(localized: "This reading was classified differently on another device. It is now: %@."), keeper.classification!)
                }
            }
            for duplicate in duplicates where duplicate.id != keeper.id { context.delete(duplicate) }
            changed = true
        }
        return changed
    }

    private func mergeSnapshots() throws -> Bool {
        var changed = false
        let groups = Dictionary(grouping: try fetch(StatusSnapshot.self)) { "\($0.generation)-\($0.causeId)" }
        for (_, duplicates) in groups where duplicates.count > 1 {
            let keeper = duplicates.sorted(by: Self.earliestOrder).first!
            for duplicate in duplicates where duplicate.id != keeper.id { context.delete(duplicate) }
            changed = true
        }
        return changed
    }

    private struct CorrectionKey: Hashable {
        let generation: UUID
        let entityType: String
        let entityId: UUID
        let field: String
        let old: String
        let new: String
        let correctedAt: Date
    }

    private func mergeCorrections() throws -> Bool {
        var changed = false
        let groups = Dictionary(grouping: try fetch(AuditCorrection.self)) {
            CorrectionKey(generation: $0.generation, entityType: $0.entityType, entityId: $0.entityId, field: $0.fieldName, old: $0.oldValue, new: $0.newValue, correctedAt: $0.correctedAt)
        }
        for (_, duplicates) in groups where duplicates.count > 1 {
            let keeper = duplicates.sorted(by: Self.earliestOrder).first!
            for duplicate in duplicates where duplicate.id != keeper.id { context.delete(duplicate) }
            changed = true
        }
        return changed
    }

    private func newest(_ values: [Household], date: (Household) -> Date) -> Household {
        values.sorted { lhs, rhs in
            let left = date(lhs), right = date(rhs)
            if left != right { return left > right }
            return lhs.id.uuidString > rhs.id.uuidString
        }.first!
    }

    private static func earliestOrderForPrompt(_ lhs: MeterRegressionPrompt, _ rhs: MeterRegressionPrompt) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
