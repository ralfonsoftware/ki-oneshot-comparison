import Foundation

/// A calendar-only date (no time, no zone). Used for tariff start dates so a time-zone change never moves them (§11, Time).
public struct CalendarDate: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`.
    public init?(iso text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        let candidate = CalendarDate(year: y, month: m, day: d)
        // Reject impossible dates such as 2026-02-30.
        guard let date = candidate.startDate(in: .gmt), CalendarDate(date: date, timeZone: .gmt) == candidate else { return nil }
        self = candidate
    }

    /// The calendar date of `date` as seen in `timeZone`.
    public init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { iso }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Midnight at the start of this date in `timeZone`.
    public func startDate(in timeZone: TimeZone = .current) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Adds calendar months; the day is clamped to the target month's length (31 Jan + 1 month = 28/29 Feb).
    public func adding(months: Int) -> CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let start = startDate(in: .gmt),
              let moved = calendar.date(byAdding: .month, value: months, to: start) else { return self }
        return CalendarDate(date: moved, timeZone: .gmt)
    }

    public static func today(timeZone: TimeZone = .current, now: Date = Date()) -> CalendarDate {
        CalendarDate(date: now, timeZone: timeZone)
    }

    public static let earliestTariffStart = CalendarDate(year: 1900, month: 1, day: 1)
    public static let latestTariffStart = CalendarDate(year: 2200, month: 1, day: 1)
}

// MARK: - Tariffs (FR-12, §5.7)

public struct TariffRef: Sendable, Hashable {
    public var id: UUID
    public var startDate: CalendarDate
    public var createdAt: Date

    public init(id: UUID, startDate: CalendarDate, createdAt: Date) {
        self.id = id
        self.startDate = startDate
        self.createdAt = createdAt
    }
}

public enum Tariffs {
    /// The entry with the latest start date not in the future (ties: newest `createdAt`, then highest id).
    public static func currentTariffId(_ tariffs: [TariffRef], today: CalendarDate) -> UUID? {
        tariffs
            .filter { $0.startDate <= today }
            .max { a, b in
                if a.startDate != b.startDate { return a.startDate < b.startDate }
                if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                return idAscending(a.id, b.id)
            }?.id
    }

    /// Start dates used by more than one tariff (sync can produce them; FR-12).
    public static func duplicateStartDates(_ tariffs: [TariffRef]) -> [CalendarDate: [UUID]] {
        Dictionary(grouping: tariffs, by: \.startDate)
            .filter { $0.value.count > 1 }
            .mapValues { $0.sorted { a, b in a.createdAt != b.createdAt ? a.createdAt < b.createdAt : idAscending(a.id, b.id) }.map(\.id) }
    }
}

public struct TariffCheckState: Sendable, Hashable {
    public var isDue: Bool
    public var minimumTermEnd: CalendarDate
    public var gateOpens: CalendarDate
    /// The day the check is (or was) due: `gateOpens`, or the done date plus the cadence.
    public var dueDate: CalendarDate
}

public enum TariffCheck {
    public static let gateMonthsBeforeTermEnd = 3

    public static func state(
        contractStartDate: CalendarDate?,
        contractPeriodMonths: Int,
        doneOn: CalendarDate?,
        cadenceMonths: Int,
        today: CalendarDate
    ) -> TariffCheckState? {
        guard let start = contractStartDate else { return nil }
        let termEnd = start.adding(months: contractPeriodMonths)
        let gate = termEnd.adding(months: -gateMonthsBeforeTermEnd)
        var dueDate = gate
        if let done = doneOn, done >= gate {
            dueDate = done.adding(months: cadenceMonths)
        }
        return TariffCheckState(isDue: today >= dueDate, minimumTermEnd: termEnd, gateOpens: gate, dueDate: dueDate)
    }
}
