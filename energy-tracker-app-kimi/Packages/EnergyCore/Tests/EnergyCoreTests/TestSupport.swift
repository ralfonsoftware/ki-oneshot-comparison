import Foundation
import XCTest
@testable import EnergyCore

let testMeterID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

func testUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!
}

func utcDate(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string + "T00:00:00+00:00")!
}

func testReading(
    _ day: String,
    _ value: Decimal,
    id: Int,
    meterID: UUID = testMeterID
) -> MeterReading {
    MeterReading(
        id: testUUID(id),
        mainMeterID: meterID,
        kwhValue: value,
        readingTimestamp: utcDate(day),
        createdAt: utcDate(day)
    )
}

func testTariff(
    base: Decimal,
    price: Decimal,
    bonusIgnored: Decimal = 0,
    start: CalendarDate = CalendarDate(year: 2026, month: 1, day: 1)
) -> Tariff {
    Tariff(
        id: testUUID(900),
        monthlyBaseFee: base,
        pricePerKwh: price,
        currency: "EUR",
        contractStartDate: start,
        contractPeriodMonths: 12,
        createdAt: utcDate("2025-12-01")
    )
}

func assertDecimal(
    _ actual: Decimal?,
    _ expected: String,
    accuracy: String = "0.0000001",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let actual else {
        XCTFail("Expected decimal \(expected), got nil", file: file, line: line)
        return
    }
    let expectedDecimal = Decimal(string: expected)!
    let tolerance = Decimal(string: accuracy)!
    var difference = actual - expectedDecimal
    if difference < 0 { difference = -difference }
    XCTAssertLessThanOrEqual(difference, tolerance, "Expected \(expectedDecimal), got \(actual)", file: file, line: line)
}
