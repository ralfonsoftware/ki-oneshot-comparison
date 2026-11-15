import Foundation
@testable import EnergyCore

func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .gmt
    return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
}

func dec(_ s: String) -> Decimal { Decimal(invariant: s)! }

func reading(_ y: Int, _ m: Int, _ d: Int, _ value: String, id: UUID = UUID()) -> ReadingInput {
    ReadingInput(id: id, timestamp: utc(y, m, d), value: dec(value))
}

/// Deterministic UUIDs: uid(1) = 00000000-0000-0000-0000-000000000001.
func uid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", n))!
}

/// `|a − b| < tolerance`.
func approx(_ a: Decimal, _ b: Decimal, _ tolerance: String = "0.0001") -> Bool {
    let diff = a - b
    return (diff < 0 ? -diff : diff) < dec(tolerance)
}
