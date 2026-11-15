import Foundation

/// ISO 8601 instants with explicit offset (§8.1). Writes UTC `+00:00`, reads any offset.
public enum Instant {
    public static func parse(_ text: String) -> Date? {
        parseWithLocalDate(text)?.date
    }

    /// Parses an instant and also returns its calendar date in the value's own offset (used for `contractStartDate`).
    public static func parseWithLocalDate(_ text: String) -> (date: Date, localDate: CalendarDate)? {
        let b = Array(text.utf8)
        var i = 0
        func number(_ count: Int) -> Int? {
            guard i + count <= b.count else { return nil }
            var v = 0
            for k in 0..<count {
                let c = b[i + k]
                guard c >= 0x30, c <= 0x39 else { return nil }
                v = v * 10 + Int(c - 0x30)
            }
            i += count
            return v
        }
        func take(_ c: Character) -> Bool {
            guard i < b.count, b[i] == c.asciiValue else { return false }
            i += 1
            return true
        }
        guard let year = number(4), take("-"), let month = number(2), take("-"), let day = number(2) else { return nil }
        guard take("T") || take("t") || take(" ") else { return nil }
        guard let hour = number(2), take(":"), let minute = number(2) else { return nil }
        var second = 0
        var fraction: Double = 0
        if take(":") {
            guard let s = number(2) else { return nil }
            second = s
            if take(".") || take(",") {
                let start = i
                while i < b.count, b[i] >= 0x30, b[i] <= 0x39 { i += 1 }
                guard i > start else { return nil }
                fraction = Double("0." + String(decoding: b[start..<i], as: UTF8.self)) ?? 0
            }
        }
        var offsetSeconds = 0
        if take("Z") || take("z") {
            offsetSeconds = 0
        } else if i < b.count, b[i] == UInt8(ascii: "+") || b[i] == UInt8(ascii: "-") {
            let sign = b[i] == UInt8(ascii: "-") ? -1 : 1
            i += 1
            guard let oh = number(2) else { return nil }
            _ = take(":")
            guard let om = number(2) else { return nil }
            offsetSeconds = sign * (oh * 3600 + om * 60)
        } else {
            return nil // explicit offset required
        }
        guard i == b.count else { return nil }
        guard (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let local = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)) else { return nil }
        let localDate = CalendarDate(year: year, month: month, day: day)
        guard CalendarDate(date: local, timeZone: .gmt) == localDate else { return nil }
        let date = local.addingTimeInterval(fraction - Double(offsetSeconds))
        return (date, localDate)
    }

    /// `2026-09-22T10:00:00+00:00`, with milliseconds only when present.
    public static func format(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let whole = date.timeIntervalSince1970.rounded(.down)
        let millis = Int(((date.timeIntervalSince1970 - whole) * 1000).rounded())
        let base = Date(timeIntervalSince1970: whole + (millis == 1000 ? 1 : 0))
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: base)
        var text = String(format: "%04d-%02d-%02dT%02d:%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        if millis > 0, millis < 1000 { text += String(format: ".%03d", millis) }
        return text + "+00:00"
    }

    /// Calendar date written as an instant at `T00:00:00+00:00`.
    public static func format(_ date: CalendarDate) -> String {
        date.iso + "T00:00:00+00:00"
    }

    /// Truncates to whole seconds. New timestamps are stored this way so exports round-trip exactly.
    public static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}
