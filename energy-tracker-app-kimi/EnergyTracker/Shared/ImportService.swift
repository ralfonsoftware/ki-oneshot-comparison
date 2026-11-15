import Foundation
import SwiftData
import EnergyCore

@MainActor
struct ImportService {
    let repository: DataRepository

    static func inspect(data: Data) throws -> EnergyExport {
        do { return try EnergyExportCodec.decode(data) }
        catch { throw ImportFailure(error: error) }
    }

    func performImport(_ data: Data) async throws {
        let document = try Self.inspect(data: data)
        let originals = try document.importedMeterReadings()
        await Task.yield()
        let generation = UUID()
        do {
            try deleteEverything()
            let household = Household(
                id: document.household.id, createdAt: document.household.createdAtUtc, generation: generation,
                locale: document.household.locale, currency: document.household.currency,
                yearlyBaselineKwh: document.household.yearlyBaselineKwh
            )
            household.trendingThresholdKwh = DecimalText.encode(document.household.trendingThresholdKwh)
            household.lowConfidenceGapDays = document.household.lowConfidenceGapDays
            household.tariffCheckCadenceMonths = document.household.tariffCheckCadenceMonths
            household.tariffCheckDoneAt = document.household.tariffCheckDoneAtUtc
            household.generationChangedAt = Date()
            repository.context.insert(household)

            if let meter = document.mainMeter {
                repository.context.insert(MainMeter(id: meter.id, createdAt: meter.createdAtUtc, generation: generation, digitCapacityKwh: meter.digitCapacityKwh))
            }
            for reading in originals {
                repository.context.insert(MeterReading(id: reading.id, createdAt: reading.createdAt, generation: generation, mainMeterId: reading.mainMeterID, kwhValue: reading.kwhValue, readingTimestamp: reading.readingTimestamp))
            }
            for prompt in document.meterRegressionPrompts {
                let model = MeterRegressionPrompt(id: prompt.id, createdAt: prompt.createdAtUtc, generation: generation, mainMeterId: prompt.mainMeterId, meterReadingId: prompt.meterReadingId, previousMeterReadingId: prompt.previousMeterReadingId)
                model.resolvedAt = prompt.resolvedAtUtc
                model.classification = prompt.classification?.rawValue
                model.digitCapacityKwh = prompt.digitCapacityKwh.map(DecimalText.encode)
                repository.context.insert(model)
            }
            for tariff in document.tariffs {
                repository.context.insert(Tariff(
                    id: tariff.id, createdAt: tariff.createdAtUtc, generation: generation,
                    monthlyBaseFee: tariff.monthlyBaseFee, pricePerKwh: tariff.pricePerKwh, currency: tariff.currency,
                    contractStartDate: dayString(tariff.contractStartDate), contractPeriodMonths: tariff.contractPeriodMonths
                ))
            }
            for event in document.events {
                let model = EnergyEvent(
                    id: event.id, createdAt: event.createdAtUtc, generation: generation, description: event.description,
                    occurredAt: event.occurredAt, taggedEntityType: event.taggedEntityType?.rawValue,
                    taggedEntityId: event.taggedEntityId, taggedEntityName: event.taggedEntityName
                )
                repository.context.insert(model)
            }
            for room in document.rooms {
                repository.context.insert(Room(id: room.id, createdAt: room.createdAtUtc, generation: generation, name: room.name, archivedAt: room.archivedAt))
            }
            for point in document.powerPoints {
                repository.context.insert(PowerPoint(id: point.id, createdAt: point.createdAtUtc, generation: generation, roomId: point.roomId, name: point.name, archivedAt: point.archivedAt))
            }
            for device in document.devices {
                repository.context.insert(Device(id: device.id, createdAt: device.createdAtUtc, generation: generation, powerPointId: device.powerPointId, name: device.name, archivedAt: device.archivedAt))
            }
            for plug in document.smartPlugReadings {
                repository.context.insert(SmartPlugReading(
                    id: plug.id, createdAt: document.exportedAtUtc, generation: generation, powerPointId: plug.powerPointId,
                    roomName: plug.roomName, powerPointName: plug.powerPointName, deviceName: plug.deviceName,
                    intervalStart: plug.intervalStart, intervalEnd: plug.intervalEnd, kwhValue: plug.kwhValue
                ))
            }
            for snapshot in document.statusSnapshots {
                repository.context.insert(StatusSnapshot(
                    id: snapshot.id, createdAt: snapshot.computedAtUtc, generation: generation,
                    status: snapshot.status.rawValue, paceToDateKwh: snapshot.paceToDateKwh,
                    baselineToDateKwh: snapshot.baselineToDateKwh, isLowConfidence: snapshot.isLowConfidence,
                    computedAt: snapshot.computedAtUtc, causeId: snapshot.id
                ))
            }
            for correction in document.auditCorrections {
                repository.context.insert(AuditCorrection(
                    id: correction.id, createdAt: correction.correctedAtUtc, generation: generation,
                    entityType: correction.entityType, entityId: correction.entityId, fieldName: correction.fieldName,
                    oldValue: correction.oldValue, newValue: correction.newValue, correctedAt: correction.correctedAtUtc
                ))
            }
            try repository.context.save()
            try repository.mergeDuplicates()
            try repository.checkRegressions(commit: false)
            try repository.save()
            NotificationScheduler.rebuildIfEnabled(repository: repository)
        } catch {
            repository.context.rollback()
            throw error
        }
    }

    private func deleteEverything() throws {
        try delete(Household.self)
        try delete(MainMeter.self)
        try delete(MeterReading.self)
        try delete(MeterRegressionPrompt.self)
        try delete(Tariff.self)
        try delete(EnergyEvent.self)
        try delete(Room.self)
        try delete(PowerPoint.self)
        try delete(Device.self)
        try delete(StatusSnapshot.self)
        try delete(AuditCorrection.self)
        try delete(SmartPlugReading.self)
    }

    private func delete<T: PersistentModel>(_ type: T.Type) throws {
        for record in try repository.fetch(type) { repository.context.delete(record) }
    }

    private func dayString(_ date: CalendarDate) -> String {
        String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }
}

struct ImportFailure: LocalizedError {
    let error: Error
    var errorDescription: String? {
        guard let exportError = error as? EnergyExportError else { return error.localizedDescription }
        switch exportError {
        case .malformedJSON(let message):
            return String(format: String(localized: "The JSON file could not be read: %@"), message)
        case .validationFailed(let issues):
            let visible = issues.prefix(200).map(\.description).joined(separator: "\n")
            let remaining = issues.count - 200
            let suffix = remaining > 0 ? "\n" + String(format: String(localized: "… and %lld more"), remaining) : ""
            return visible + suffix
        }
    }
}

extension ImportSummary {
    init(document: EnergyExport) {
        counts = [
            "meterReadings": document.meterReadings.count,
            "meterRegressionPrompts": document.meterRegressionPrompts.count,
            "tariffs": document.tariffs.count,
            "events": document.events.count,
            "rooms": document.rooms.count,
            "powerPoints": document.powerPoints.count,
            "devices": document.devices.count,
            "smartPlugReadings": document.smartPlugReadings.count,
            "statusSnapshots": document.statusSnapshots.count,
            "auditCorrections": document.auditCorrections.count,
        ]
        let readings = (try? document.importedMeterReadings()) ?? []
        let groups = Dictionary(grouping: readings) {
            "\($0.mainMeterID)-\(Int64($0.readingTimestamp.timeIntervalSince1970.rounded(.down)))-\(DecimalText.encode($0.kwhValue))"
        }
        duplicateReadings = groups.values.reduce(0) { $0 + max(0, $1.count - 1) }
    }
}
