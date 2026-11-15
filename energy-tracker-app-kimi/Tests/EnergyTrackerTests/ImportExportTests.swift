import XCTest
import EnergyCore
@testable import EnergyTracker

@MainActor
final class ImportExportTests: XCTestCase {
    private var controller: PersistenceController!
    private var repository: DataRepository!

    override func setUp() async throws {
        controller = PersistenceController(inMemory: true)
        repository = DataRepository(context: controller.container.mainContext)
        _ = try repository.startFresh(yearlyBaseline: 3000, currency: "EUR")
    }

    func testExportImportRoundTripPreservesEffectiveValuesAndHistory() async throws {
        let now = Date()
        guard case .saved(let first) = try repository.saveReading(kwh: 1000, timestamp: now.addingTimeInterval(-30 * 86_400)) else { return XCTFail() }
        _ = try repository.correct(first, to: 1010)
        guard case .saved(let second) = try repository.saveReading(kwh: 1030, timestamp: now) else { return XCTFail() }
        let tariff = try repository.addTariff(baseFee: 10, price: 0.3, currency: "EUR", startDate: "2026-01-01", periodMonths: 12)
        let room = try repository.addRoom(name: "Kitchen")
        let event = try repository.addEvent(description: "Away", occurredAt: now, tag: EventTag(type: "Room", id: room.id, name: room.name))
        let oldGeneration = try XCTUnwrap(repository.currentGeneration())
        let snapshotCount = try repository.snapshots().count

        let data = try EnergyExportCodec.encode(ExportService(repository: repository).makeDocument(exportedAt: now))
        try await ImportService(repository: repository).performImport(data)

        XCTAssertNotEqual(try repository.currentGeneration(), oldGeneration)
        let readings = try repository.readings()
        XCTAssertEqual(readings.map(\.id), [first.id, second.id])
        XCTAssertEqual(try repository.effectiveValue(for: readings[0]), 1010)
        XCTAssertEqual(try repository.corrections(for: readings[0]).count, 1)
        XCTAssertEqual(try repository.tariffs().map(\.id), [tariff.id])
        XCTAssertEqual(try repository.events().map(\.id), [event.id])
        XCTAssertEqual(try repository.events().first?.taggedEntityName, "Kitchen")
        XCTAssertEqual(try repository.snapshots().count, snapshotCount, "Import must not add a snapshot")

        let secondExport = try ExportService(repository: repository).makeDocument(exportedAt: now)
        XCTAssertEqual(secondExport.meterReadings.map(\.kwhValue), [1010, 1030])
        XCTAssertEqual(secondExport.auditCorrections.count, 1)
        XCTAssertEqual(secondExport.rooms.map(\.name), ["Kitchen"])
        XCTAssertEqual(secondExport.household.yearlyBaselineKwh, 3000)
    }

    func testValidationFailureLeavesStoreUntouched() throws {
        let now = Date()
        _ = try repository.saveReading(kwh: 1000, timestamp: now.addingTimeInterval(-100))
        let data = try EnergyExportCodec.encode(ExportService(repository: repository).makeDocument())
        let invalid = String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\"kwhValue\":1000", with: "\"kwhValue\":0")
        XCTAssertThrowsError(try ImportService.inspect(data: Data(invalid.utf8)))
        XCTAssertEqual(try repository.readings().count, 1)
        XCTAssertEqual(try repository.readings().first.map { try repository.effectiveValue(for: $0) }, 1000)
    }

    func testSummaryCountsExactDuplicateReadings() throws {
        let now = Date()
        _ = try repository.saveReading(kwh: 1000, timestamp: now)
        var document = try ExportService(repository: repository).makeDocument()
        guard let reading = document.meterReadings.first else { return XCTFail() }
        var duplicate = reading
        duplicate.id = UUID()
        document.meterReadings.append(duplicate)
        let summary = ImportSummary(document: document)
        XCTAssertEqual(summary.duplicateReadings, 1)
    }
}
