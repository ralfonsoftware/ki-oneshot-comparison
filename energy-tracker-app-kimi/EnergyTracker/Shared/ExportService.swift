import Foundation
import EnergyCore

@MainActor
struct ExportService {
    let repository: DataRepository

    func writeExport() throws -> URL {
        let data = try EnergyExportCodec.encode(makeDocument())
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("energy-tracker-export-\(formatter.string(from: Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func makeDocument(exportedAt: Date = Date()) throws -> EnergyExport {
        guard let household = try repository.activeHouseholdRecord() else { throw RepositoryError.missingHousehold }
        let generation = household.generation
        let readings = try repository.readings()
        let prompts = try repository.prompts()
        let tariffs = try repository.tariffs()
        let events = try repository.events()
        let rooms = try repository.rooms()
        let points = try repository.powerPoints()
        let devices = try repository.devices()
        let snapshots = try repository.snapshots()
        let corrections = try repository.fetch(AuditCorrection.self).filter { $0.generation == generation }
        let plugs = try repository.fetch(SmartPlugReading.self).filter { $0.generation == generation }
        let meter = try repository.meter()

        let effectiveValues = try repository.effectiveValues()
        let exportReadings = readings.map { reading in
            ExportMeterReading(
                id: reading.id, mainMeterId: reading.mainMeterId, kwhValue: effectiveValues[reading.id] ?? 0,
                readingTimestamp: reading.readingTimestamp, createdAtUtc: reading.createdAt
            )
        }
        let exportEvents = try events.map { event -> ExportEvent in
            let deviation = try EnergyEngine.deviation(repository: repository, event: event)
            return ExportEvent(
                id: event.id, description: event.eventDescription, occurredAt: event.occurredAt, createdAtUtc: event.createdAt,
                taggedEntityType: event.taggedEntityType.flatMap(ExportTaggedEntityType.init(rawValue:)),
                taggedEntityId: event.taggedEntityId, taggedEntityName: event.taggedEntityName,
                correlationDirection: deviation == .bump ? .bump : deviation == .dip ? .dip : nil,
                correlationComputedAtUtc: deviation == nil ? nil : exportedAt
            )
        }
        return EnergyExport(
            exportedAtUtc: exportedAt,
            household: ExportHousehold(
                id: household.id, createdAtUtc: household.createdAt, locale: household.locale, currency: household.currency,
                yearlyBaselineKwh: DecimalText.decode(household.yearlyBaselineKwh),
                trendingThresholdKwh: DecimalText.decode(household.trendingThresholdKwh) ?? 100,
                lowConfidenceGapDays: household.lowConfidenceGapDays,
                tariffCheckCadenceMonths: household.tariffCheckCadenceMonths,
                tariffCheckDoneAtUtc: household.tariffCheckDoneAt
            ),
            householdMembers: [],
            mainMeter: readings.isEmpty ? nil : meter.map { ExportMainMeter(id: $0.id, createdAtUtc: $0.createdAt, digitCapacityKwh: DecimalText.decode($0.digitCapacityKwh)) },
            meterReadings: exportReadings,
            meterRegressionPrompts: prompts.map {
                ExportMeterRegressionPrompt(
                    id: $0.id, mainMeterId: $0.mainMeterId, meterReadingId: $0.meterReadingId,
                    previousMeterReadingId: $0.previousMeterReadingId, createdAtUtc: $0.createdAt,
                    resolvedAtUtc: $0.resolvedAt, classification: $0.classification.flatMap(RegressionClassification.init(rawValue:)),
                    digitCapacityKwh: DecimalText.decode($0.digitCapacityKwh)
                )
            },
            tariffs: try tariffs.map {
                ExportTariff(
                    id: $0.id, monthlyBaseFee: DecimalText.decode($0.monthlyBaseFee) ?? 0,
                    pricePerKwh: DecimalText.decode($0.pricePerKwh) ?? 0, currency: $0.currency,
                    contractStartDate: try calendarDate($0.contractStartDate), contractPeriodMonths: $0.contractPeriodMonths, createdAtUtc: $0.createdAt
                )
            },
            events: exportEvents,
            rooms: rooms.map { ExportRoom(id: $0.id, name: $0.name, createdAtUtc: $0.createdAt, archivedAt: $0.archivedAt) },
            powerPoints: points.map { ExportPowerPoint(id: $0.id, roomId: $0.roomId, name: $0.name, createdAtUtc: $0.createdAt, archivedAt: $0.archivedAt) },
            devices: devices.map { ExportDevice(id: $0.id, powerPointId: $0.powerPointId, name: $0.name, createdAtUtc: $0.createdAt, archivedAt: $0.archivedAt) },
            smartPlugReadings: plugs.map {
                ExportSmartPlugReading(id: $0.id, powerPointId: $0.powerPointId, roomName: $0.roomName, powerPointName: $0.powerPointName, deviceName: $0.deviceName, intervalStart: $0.intervalStart, intervalEnd: $0.intervalEnd, kwhValue: DecimalText.decode($0.kwhValue) ?? 0)
            },
            statusSnapshots: snapshots.map {
                ExportStatusSnapshot(id: $0.id, status: ConsumptionStatus(rawValue: $0.status.lowercased()) ?? .withinRange, paceToDateKwh: DecimalText.decode($0.paceToDateKwh) ?? 0, baselineToDateKwh: DecimalText.decode($0.baselineToDateKwh) ?? 0, isLowConfidence: $0.isLowConfidence, computedAtUtc: $0.computedAt)
            },
            auditCorrections: corrections.map {
                ExportAuditCorrection(id: $0.id, entityType: $0.entityType, entityId: $0.entityId, fieldName: $0.fieldName, oldValue: $0.oldValue, newValue: $0.newValue, correctedAtUtc: $0.correctedAt)
            }
        )
    }

    private func calendarDate(_ value: String) throws -> CalendarDate {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { throw EnergyEngineError.invalidDate }
        return CalendarDate(year: parts[0], month: parts[1], day: parts[2])
    }
}
