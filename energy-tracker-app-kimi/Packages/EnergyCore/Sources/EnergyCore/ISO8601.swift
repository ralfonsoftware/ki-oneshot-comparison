import Foundation

internal struct ParsedInstant {
    var date: Date
    /// The calendar date in the offset explicitly carried by the source string.
    var localDate: CalendarDate
}

internal enum ISO8601Codec {
    static func parse(_ string: String) -> ParsedInstant? {
        let bytes = Array(string.utf8)
        guard bytes.count >= 20, bytes.count == string.count else { return nil }

        let suffixStart: Int
        if bytes.last == 90 || bytes.last == 122 { // Z / z
            suffixStart = bytes.count - 1
        } else {
            suffixStart = bytes.count - 6
            guard suffixStart >= 19,
                  bytes[suffixStart] == 43 || bytes[suffixStart] == 45,
                  bytes[suffixStart + 3] == 58,
                  isDigits(bytes, suffixStart + 1..<suffixStart + 3),
                  isDigits(bytes, suffixStart + 4..<suffixStart + 6),
                  integer(bytes, suffixStart + 1..<suffixStart + 3) <= 23,
                  integer(bytes, suffixStart + 4..<suffixStart + 6) <= 59 else { return nil }
        }
        guard suffixStart >= 19,
              bytes[4] == 45, bytes[7] == 45,
              bytes[10] == 84 || bytes[10] == 116, // T / t
              bytes[13] == 58, bytes[16] == 58,
              isDigits(bytes, 0..<4), isDigits(bytes, 5..<7), isDigits(bytes, 8..<10),
              isDigits(bytes, 11..<13), isDigits(bytes, 14..<16), isDigits(bytes, 17..<19) else { return nil }

        let hasFraction: Bool
        if suffixStart == 19 {
            hasFraction = false
        } else {
            guard bytes[19] == 46, suffixStart > 20, isDigits(bytes, 20..<suffixStart) else { return nil }
            hasFraction = true
        }

        let year = integer(bytes, 0..<4)
        let month = integer(bytes, 5..<7)
        let day = integer(bytes, 8..<10)
        guard CalendarDate.isValid(year: year, month: month, day: day) else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = hasFraction
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = formatter.date(from: string) else { return nil }
        return ParsedInstant(date: date, localDate: CalendarDate(year: year, month: month, day: day))
    }

    /// Writes UTC with an explicit `+00:00` offset, retaining Date's useful fractional precision.
    static func formatUTC(_ date: Date) -> String {
        let interval = date.timeIntervalSince1970
        var wholeSeconds = floor(interval)
        var nanoseconds = Int(((interval - wholeSeconds) * 1_000_000_000).rounded())
        if nanoseconds == 1_000_000_000 {
            wholeSeconds += 1
            nanoseconds = 0
        } else if nanoseconds < 0 {
            wholeSeconds -= 1
            nanoseconds += 1_000_000_000
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        var result = formatter.string(from: Date(timeIntervalSince1970: wholeSeconds))
        if nanoseconds != 0 {
            var fraction = String(format: "%09d", nanoseconds)
            while fraction.last == "0" { fraction.removeLast() }
            result += "." + fraction
        }
        return result + "+00:00"
    }

    private static func isDigits(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        !range.isEmpty && bytes[range].allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    private static func integer(_ bytes: [UInt8], _ range: Range<Int>) -> Int {
        bytes[range].reduce(0) { $0 * 10 + Int($1 - 48) }
    }
}

extension CalendarDate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let parsed = ISO8601Codec.parse(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected ISO 8601 instant with explicit offset")
        }
        self = parsed.localDate
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ISO8601Codec.formatUTC(utcMidnight))
    }
}

internal extension KeyedDecodingContainer {
    func decodeInstant(forKey key: Key) throws -> Date {
        let string = try decode(String.self, forKey: key)
        guard let parsed = ISO8601Codec.parse(string) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected ISO 8601 instant with explicit offset")
        }
        return parsed.date
    }

    func decodeInstantIfPresent(forKey key: Key) throws -> Date? {
        guard try decodeNil(forKey: key) == false else { return nil }
        return try decodeInstant(forKey: key)
    }

    func decodeCalendarDate(forKey key: Key) throws -> CalendarDate {
        let string = try decode(String.self, forKey: key)
        guard let parsed = ISO8601Codec.parse(string) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected ISO 8601 instant with explicit offset")
        }
        return parsed.localDate
    }
}

internal extension KeyedEncodingContainer {
    mutating func encodeInstant(_ date: Date, forKey key: Key) throws {
        try encode(ISO8601Codec.formatUTC(date), forKey: key)
    }

    mutating func encodeInstantIfPresent(_ date: Date?, forKey key: Key) throws {
        guard let date else {
            try encodeNil(forKey: key)
            return
        }
        try encodeInstant(date, forKey: key)
    }

    mutating func encodeCalendarDate(_ date: CalendarDate, forKey key: Key) throws {
        try encode(ISO8601Codec.formatUTC(date.utcMidnight), forKey: key)
    }
}
