import Foundation
import SwiftData

protocol GenerationRecord: PersistentModel {
    var generation: UUID { get set }
}

extension MainMeter: GenerationRecord {}
extension MeterReading: GenerationRecord {}
extension MeterRegressionPrompt: GenerationRecord {}
extension Tariff: GenerationRecord {}
extension EnergyEvent: GenerationRecord {}
extension Room: GenerationRecord {}
extension PowerPoint: GenerationRecord {}
extension Device: GenerationRecord {}
extension StatusSnapshot: GenerationRecord {}
extension AuditCorrection: GenerationRecord {}
extension SmartPlugReading: GenerationRecord {}

extension DataRepository {
    func heldBackSummary() throws -> HeldBackSummary {
        guard let generation = try currentGeneration() else { return HeldBackSummary() }
        var summary = HeldBackSummary()
        summary.readings = try oldRecords(MeterReading.self, currentGeneration: generation).count
        summary.events = try oldRecords(EnergyEvent.self, currentGeneration: generation).count
        summary.other = try oldRecords(MainMeter.self, currentGeneration: generation).count
            + oldRecords(MeterRegressionPrompt.self, currentGeneration: generation).count
            + oldRecords(Tariff.self, currentGeneration: generation).count
            + oldRecords(Room.self, currentGeneration: generation).count
            + oldRecords(PowerPoint.self, currentGeneration: generation).count
            + oldRecords(Device.self, currentGeneration: generation).count
            + oldRecords(StatusSnapshot.self, currentGeneration: generation).count
            + oldRecords(AuditCorrection.self, currentGeneration: generation).count
            + oldRecords(SmartPlugReading.self, currentGeneration: generation).count
        return summary
    }

    func keepHeldBackRecords() throws {
        guard let generation = try currentGeneration() else { return }
        try rewriteOldRecords(MainMeter.self, to: generation)
        try rewriteOldRecords(MeterReading.self, to: generation)
        try rewriteOldRecords(MeterRegressionPrompt.self, to: generation)
        try rewriteOldRecords(Tariff.self, to: generation)
        try rewriteOldRecords(EnergyEvent.self, to: generation)
        try rewriteOldRecords(Room.self, to: generation)
        try rewriteOldRecords(PowerPoint.self, to: generation)
        try rewriteOldRecords(Device.self, to: generation)
        try rewriteOldRecords(StatusSnapshot.self, to: generation)
        try rewriteOldRecords(AuditCorrection.self, to: generation)
        try rewriteOldRecords(SmartPlugReading.self, to: generation)
        try mergeDuplicates()
        try checkRegressions(commit: false)
        try save()
    }

    func discardHeldBackRecords() throws {
        guard let generation = try currentGeneration() else { return }
        try deleteOldRecords(MainMeter.self, currentGeneration: generation)
        try deleteOldRecords(MeterReading.self, currentGeneration: generation)
        try deleteOldRecords(MeterRegressionPrompt.self, currentGeneration: generation)
        try deleteOldRecords(Tariff.self, currentGeneration: generation)
        try deleteOldRecords(EnergyEvent.self, currentGeneration: generation)
        try deleteOldRecords(Room.self, currentGeneration: generation)
        try deleteOldRecords(PowerPoint.self, currentGeneration: generation)
        try deleteOldRecords(Device.self, currentGeneration: generation)
        try deleteOldRecords(StatusSnapshot.self, currentGeneration: generation)
        try deleteOldRecords(AuditCorrection.self, currentGeneration: generation)
        try deleteOldRecords(SmartPlugReading.self, currentGeneration: generation)
        try save()
    }

    private func oldRecords<T: GenerationRecord>(_ type: T.Type, currentGeneration: UUID) throws -> [T] {
        try fetch(type).filter { $0.generation != currentGeneration }
    }

    private func rewriteOldRecords<T: GenerationRecord>(_ type: T.Type, to generation: UUID) throws {
        for record in try oldRecords(type, currentGeneration: generation) { record.generation = generation }
    }

    private func deleteOldRecords<T: GenerationRecord>(_ type: T.Type, currentGeneration: UUID) throws {
        for record in try oldRecords(type, currentGeneration: currentGeneration) { context.delete(record) }
    }
}
