import Foundation

/// Internal JSON representation whose numbers never pass through `Double`.
internal enum JSONValue {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case null
}

internal struct JSONParseError: Error {
    let message: String
}

internal enum ExactJSON {
    static func parse(_ data: Data) throws -> JSONValue {
        guard String(data: data, encoding: .utf8) != nil else {
            throw JSONParseError(message: "Document is not valid UTF-8.")
        }
        var parser = Parser(bytes: Array(data))
        do {
            let value = try parser.parseValue()
            parser.skipWhitespace()
            guard parser.index == parser.bytes.count else {
                throw JSONParseError(message: "Unexpected content at byte \(parser.index).")
            }
            return value
        } catch let error as JSONParseError {
            throw error
        } catch {
            throw JSONParseError(message: "Malformed JSON document.")
        }
    }

    static func data(_ value: JSONValue) throws -> Data {
        var output = ""
        try write(value, to: &output)
        return output.data(using: .utf8)!
    }

    private static func write(_ value: JSONValue, to output: inout String) throws {
        switch value {
        case .object(let object):
            output += "{"
            for (index, key) in object.keys.sorted().enumerated() {
                if index > 0 { output += "," }
                writeString(key, to: &output)
                output += ":"
                try write(object[key]!, to: &output)
            }
            output += "}"
        case .array(let array):
            output += "["
            for (index, item) in array.enumerated() {
                if index > 0 { output += "," }
                try write(item, to: &output)
            }
            output += "]"
        case .string(let string):
            writeString(string, to: &output)
        case .number(let decimal):
            let string = decimalString(decimal)
            guard CanonicalDecimal(string) != nil else {
                throw JSONParseError(message: "A Decimal value cannot be represented as a JSON number.")
            }
            output += string
        case .bool(let bool):
            output += bool ? "true" : "false"
        case .null:
            output += "null"
        }
    }

    private static func writeString(_ string: String, to output: inout String) {
        output += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04X", scalar.value)
                } else {
                    output += String(scalar)
                }
            }
        }
        output += "\""
    }
}

private struct Parser {
    let bytes: [UInt8]
    var index = 0

    mutating func parseValue() throws -> JSONValue {
        skipWhitespace()
        guard index < bytes.count else { throw error("Expected a JSON value") }
        switch bytes[index] {
        case 123: return try parseObject() // {
        case 91: return try parseArray() // [
        case 34: return .string(try parseString())
        case 116: try consume("true"); return .bool(true)
        case 102: try consume("false"); return .bool(false)
        case 110: try consume("null"); return .null
        case 45, 48...57: return try parseNumber()
        default: throw error("Unexpected byte")
        }
    }

    mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 32, 9, 10, 13: index += 1
            default: return
            }
        }
    }

    mutating func parseObject() throws -> JSONValue {
        index += 1
        skipWhitespace()
        var object: [String: JSONValue] = [:]
        if consumeIf(125) { return .object(object) }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == 34 else { throw error("Expected an object key") }
            let key = try parseString()
            skipWhitespace()
            guard consumeIf(58) else { throw error("Expected ':'") }
            object[key] = try parseValue()
            skipWhitespace()
            if consumeIf(125) { break }
            guard consumeIf(44) else { throw error("Expected ',' or '}'") }
        }
        return .object(object)
    }

    mutating func parseArray() throws -> JSONValue {
        index += 1
        skipWhitespace()
        var array: [JSONValue] = []
        if consumeIf(93) { return .array(array) }
        while true {
            array.append(try parseValue())
            skipWhitespace()
            if consumeIf(93) { break }
            guard consumeIf(44) else { throw error("Expected ',' or ']'") }
        }
        return .array(array)
    }

    mutating func parseString() throws -> String {
        index += 1
        var output: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 {
                return String(decoding: output, as: UTF8.self)
            }
            if byte < 0x20 { throw error("Unescaped control character in string") }
            if byte != 92 {
                output.append(byte)
                continue
            }
            guard index < bytes.count else { throw error("Unfinished string escape") }
            let escaped = bytes[index]
            index += 1
            switch escaped {
            case 34, 92, 47: output.append(escaped)
            case 98: output.append(8)
            case 102: output.append(12)
            case 110: output.append(10)
            case 114: output.append(13)
            case 116: output.append(9)
            case 117:
                let first = try parseHexQuad()
                let scalarValue: UInt32
                if (0xD800...0xDBFF).contains(first) {
                    guard index + 1 < bytes.count, bytes[index] == 92, bytes[index + 1] == 117 else {
                        throw error("Missing low surrogate")
                    }
                    index += 2
                    let second = try parseHexQuad()
                    guard (0xDC00...0xDFFF).contains(second) else { throw error("Invalid low surrogate") }
                    scalarValue = 0x10000 + ((UInt32(first) - 0xD800) << 10) + (UInt32(second) - 0xDC00)
                } else if (0xDC00...0xDFFF).contains(first) {
                    throw error("Unexpected low surrogate")
                } else {
                    scalarValue = UInt32(first)
                }
                guard let scalar = UnicodeScalar(scalarValue) else { throw error("Invalid Unicode escape") }
                output.append(contentsOf: String(scalar).utf8)
            default: throw error("Unknown string escape")
            }
        }
        throw error("Unterminated string")
    }

    mutating func parseHexQuad() throws -> UInt16 {
        guard index + 4 <= bytes.count else { throw error("Short Unicode escape") }
        var value: UInt16 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            index += 1
            let digit: UInt16
            switch byte {
            case 48...57: digit = UInt16(byte - 48)
            case 65...70: digit = UInt16(byte - 55)
            case 97...102: digit = UInt16(byte - 87)
            default: throw error("Invalid Unicode escape")
            }
            value = value * 16 + digit
        }
        return value
    }

    mutating func parseNumber() throws -> JSONValue {
        let start = index
        consumeIf(45)
        guard index < bytes.count else { throw error("Incomplete number") }
        if bytes[index] == 48 {
            index += 1
            if index < bytes.count, (48...57).contains(bytes[index]) {
                throw error("Leading zero in number")
            }
        } else if (49...57).contains(bytes[index]) {
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        } else {
            throw error("Expected a digit")
        }
        if consumeIf(46) {
            guard index < bytes.count, (48...57).contains(bytes[index]) else { throw error("Expected a fractional digit") }
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
            index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            guard index < bytes.count, (48...57).contains(bytes[index]) else { throw error("Expected an exponent digit") }
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        }
        let literal = String(decoding: bytes[start..<index], as: UTF8.self)
        guard let decimal = exactDecimal(fromInvariantString: literal) else {
            throw JSONParseError(message: "Number at byte \(start) is not exactly representable as Decimal.")
        }
        return .number(decimal)
    }

    mutating func consume(_ literal: String) throws {
        let literalBytes = Array(literal.utf8)
        guard index + literalBytes.count <= bytes.count,
              Array(bytes[index..<(index + literalBytes.count)]) == literalBytes else {
            throw error("Expected '\(literal)'")
        }
        index += literalBytes.count
    }

    @discardableResult
    mutating func consumeIf(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    func error(_ message: String) -> JSONParseError {
        JSONParseError(message: "\(message) at byte \(index).")
    }
}
