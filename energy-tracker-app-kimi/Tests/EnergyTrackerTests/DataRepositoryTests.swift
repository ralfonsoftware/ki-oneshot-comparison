import XCTest
import SwiftData
@testable import EnergyTracker

@MainActor
final class DataRepositoryTests: XCTestCase {
    private var controller: PersistenceController!
    private var repository: DataRepository!

    override func setUp() async throws {
        controller = PersistenceController(inMemory: true)
        repository = DataRepository(context: controller.container.mainContext)
        _ = try repository.startFresh(yearlyBaseline: 3000, currency: "EUR")
    }

    func testDuplicateReadingCreatesNothing() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        guard case .saved = try repository.saveReading(kwh: 1000, timestamp: timestamp) else { return XCTFail() }
        guard case .alreadySaved = try repository.saveReading(kwh: 1000, timestamp: timestamp.addingTimeInterval(0.4)) else {
            return XCTFail("Same second and value must merge")
        }
        XCTAssertEqual(try repository.readings().count, 1)
    }

    func testCorrectionIsAppendOnly() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        guard case .saved(let reading) = try repository.saveReading(kwh: 1000, timestamp: timestamp) else { return XCTFail() }
        _ = try repository.correct(reading, to: 1010.5)
        XCTAssertEqual(reading.kwhValue, "1000")
        XCTAssertEqual(try repository.effectiveValue(for: reading), 1010.5)
        XCTAssertEqual(try repository.corrections(for: reading).count, 1)
        XCTAssertNil(try repository.correct(reading, to: 1010.5))
    }

    func testBackfillCreatesRegressionForChronologicalNeighbor() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try repository.saveReading(kwh: 1000, timestamp: start)
        _ = try repository.saveReading(kwh: 2000, timestamp: start.addingTimeInterval(200))
        _ = try repository.saveReading(kwh: 500, timestamp: start.addingTimeInterval(100))
        let prompt = try XCTUnwrap(repository.openPrompt())
        let readings = try repository.readings()
        XCTAssertEqual(prompt.meterReadingId, readings[1].id)
        XCTAssertEqual(prompt.previousMeterReadingId, readings[0].id)
    }

    func testExactDuplicateMergeMovesHistory() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        guard case .saved(let original) = try repository.saveReading(kwh: 1000, timestamp: timestamp) else { return XCTFail() }
        let meter = try XCTUnwrap(repository.meter())
        let duplicate = MeterReading(createdAt: Date().addingTimeInterval(10), generation: original.generation, mainMeterId: meter.id, kwhValue: 1000, readingTimestamp: timestamp)
        repository.context.insert(duplicate)
        repository.context.insert(AuditCorrection(generation: original.generation, entityType: "MeterReading", entityId: duplicate.id, fieldName: "KwhValue", oldValue: "1000", newValue: "1001"))
        try repository.context.save()
        try repository.mergeDuplicates()
        XCTAssertEqual(try repository.readings().count, 1)
        XCTAssertEqual(try repository.corrections(for: original).count, 1)
    }

    func testHeldBackGenerationCanBeKept() throws {
        let meter = try repository.ensureMeter()
        let oldGeneration = UUID()
        repository.context.insert(MeterReading(generation: oldGeneration, mainMeterId: meter.id, kwhValue: 900, readingTimestamp: Date().addingTimeInterval(-1000)))
        repository.context.insert(EnergyEvent(generation: oldGeneration, description: "Away", occurredAt: Date()))
        try repository.context.save()
        XCTAssertEqual(try repository.heldBackSummary().readings, 1)
        XCTAssertEqual(try repository.heldBackSummary().events, 1)
        try repository.keepHeldBackRecords()
        XCTAssertTrue(try repository.heldBackSummary().isEmpty)
        XCTAssertEqual(try repository.readings().count, 1)
        XCTAssertEqual(try repository.events().count, 1)
    }

    func testTariffChangesKeepAuditTrailAfterDeletion() throws {
        let tariff = try repository.addTariff(baseFee: 10, price: 0.3, currency: "EUR", startDate: "2026-01-01", periodMonths: 12)
        try repository.updateTariff(tariff, baseFee: 12, price: 0.3, currency: "EUR", startDate: "2026-01-01", periodMonths: 12)
        let id = tariff.id
        try repository.deleteTariff(tariff)
        let corrections = try repository.corrections(entityType: "Tariff", entityId: id)
        XCTAssertEqual(corrections.count, 1)
        XCTAssertEqual(corrections.first?.fieldName, "MonthlyBaseFee")
    }
}
