import Foundation

/// A JSON value that keeps numbers as their original lexeme, so decimals are read without loss (§8.1).
public enum JSONValue: Sendable {
    case object(JSONObject)
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    public var typeName: String {
        switch self {
        case .object: "object"
        case .array: "array"
        case .string: "string"
        case .number: "number"
        case .bool: "boolean"
        case .null: "null"
        }
    }
}

/// Ordered JSON object.
public struct JSONObject: Sendable {
    public private(set) var keys: [String] = []
    private var storage: [String: JSONValue] = [:]

    public init() {}

    public init(_ pairs: [(String, JSONValue)]) {
        for (k, v) in pairs { self[k] = v }
    }

    public subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set {
            if storage[key] == nil, newValue != nil { keys.append(key) }
            if newValue == nil { keys.removeAll { $0 == key } }
            storage[key] = newValue
        }
    }

    public func has(_ key: String) -> Bool { storage[key] != nil }
}

public struct JSONSyntaxError: Error, CustomStringConvertible, Sendable {
    public var offset: Int
    public var message: String
    public var description: String { "Invalid JSON at byte \(offset): \(message)" }
}

// MARK: - Parser

public enum JSONParser {
    public static func parse(_ data: Data) throws -> JSONValue {
        try data.withUnsafeBytes { raw in
            var parser = Parser(bytes: raw.bindMemory(to: UInt8.self))
            // Skip a UTF-8 byte order mark.
            if parser.bytes.count >= 3, parser.bytes[0] == 0xEF, parser.bytes[1] == 0xBB, parser.bytes[2] == 0xBF { parser.index = 3 }
            parser.skipWhitespace()
            let value = try parser.parseValue(depth: 0)
            parser.skipWhitespace()
            guard parser.index == parser.bytes.count else { throw parser.error("unexpected trailing characters") }
            return value
        }
    }

    private struct Parser {
        let bytes: UnsafeBufferPointer<UInt8>
        var index = 0

        init(bytes: UnsafeBufferPointer<UInt8>) { self.bytes = bytes }

        func error(_ message: String) -> JSONSyntaxError { JSONSyntaxError(offset: index, message: message) }

        mutating func skipWhitespace() {
            while index < bytes.count {
                switch bytes[index] {
                case 0x20, 0x09, 0x0A, 0x0D: index += 1
                default: return
                }
            }
        }

        mutating func expect(_ literal: StaticString) throws {
            let count = literal.utf8CodeUnitCount
            guard index + count <= bytes.count else { throw error("unexpected end of input") }
            let ptr = literal.utf8Start
            for i in 0..<count where bytes[index + i] != ptr[i] { throw error("invalid literal") }
            index += count
        }

        mutating func parseValue(depth: Int) throws -> JSONValue {
            guard depth < 512 else { throw error("nesting too deep") }
            guard index < bytes.count else { throw error("unexpected end of input") }
            switch bytes[index] {
            case UInt8(ascii: "{"): return .object(try parseObject(depth: depth))
            case UInt8(ascii: "["): return .array(try parseArray(depth: depth))
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            default: return .number(try parseNumber())
            }
        }

        mutating func parseObject(depth: Int) throws -> JSONObject {
            index += 1
            var object = JSONObject()
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return object }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw error("expected property name") }
                let key = try parseString()
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw error("expected ':'") }
                index += 1
                skipWhitespace()
                object[key] = try parseValue(depth: depth + 1)
                skipWhitespace()
                guard index < bytes.count else { throw error("unexpected end of input") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return object }
                throw error("expected ',' or '}'")
            }
        }

        mutating func parseArray(depth: Int) throws -> [JSONValue] {
            index += 1
            var array: [JSONValue] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return array }
            while true {
                skipWhitespace()
                array.append(try parseValue(depth: depth + 1))
                skipWhitespace()
                guard index < bytes.count else { throw error("unexpected end of input") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return array }
                throw error("expected ',' or ']'")
            }
        }

        mutating func parseNumber() throws -> String {
            let start = index
            while index < bytes.count, Self.isNumberByte(bytes[index]) { index += 1 }
            let lexeme = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self)
            guard !lexeme.isEmpty, DecimalMath.isNumberLexeme(lexeme) else {
                index = start
                throw error("invalid value")
            }
            return lexeme
        }

        static func isNumberByte(_ b: UInt8) -> Bool {
            (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x2B || b == 0x2E || b == 0x65 || b == 0x45
        }

        mutating func parseHex4() throws -> UInt32 {
            guard index + 4 <= bytes.count else { throw error("bad unicode escape") }
            var value: UInt32 = 0
            for _ in 0..<4 {
                let b = bytes[index]
                let digit: UInt32
                switch b {
                case 0x30...0x39: digit = UInt32(b - 0x30)
                case 0x41...0x46: digit = UInt32(b - 0x41 + 10)
                case 0x61...0x66: digit = UInt32(b - 0x61 + 10)
                default: throw error("bad unicode escape")
                }
                value = value * 16 + digit
                index += 1
            }
            return value
        }

        mutating func parseString() throws -> String {
            index += 1 // opening quote
            var scalars: [UInt8] = []
            var runStart = index
            while index < bytes.count {
                let b = bytes[index]
                if b == UInt8(ascii: "\"") {
                    scalars.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[runStart..<index]))
                    index += 1
                    return String(decoding: scalars, as: UTF8.self)
                }
                if b < 0x20 { throw error("control character in string") }
                if b == UInt8(ascii: "\\") {
                    scalars.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[runStart..<index]))
                    index += 1
                    guard index < bytes.count else { throw error("unexpected end of input") }
                    let e = bytes[index]
                    index += 1
                    switch e {
                    case UInt8(ascii: "\""): scalars.append(0x22)
                    case UInt8(ascii: "\\"): scalars.append(0x5C)
                    case UInt8(ascii: "/"): scalars.append(0x2F)
                    case UInt8(ascii: "b"): scalars.append(0x08)
                    case UInt8(ascii: "f"): scalars.append(0x0C)
                    case UInt8(ascii: "n"): scalars.append(0x0A)
                    case UInt8(ascii: "r"): scalars.append(0x0D)
                    case UInt8(ascii: "t"): scalars.append(0x09)
                    case UInt8(ascii: "u"):
                        var code = try parseHex4()
                        if (0xD800...0xDBFF).contains(code) {
                            guard index + 6 <= bytes.count, bytes[index] == 0x5C, bytes[index + 1] == UInt8(ascii: "u") else {
                                throw error("unpaired surrogate")
                            }
                            index += 2
                            let low = try parseHex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw error("unpaired surrogate") }
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        } else if (0xDC00...0xDFFF).contains(code) {
                            throw error("unpaired surrogate")
                        }
                        guard let scalar = Unicode.Scalar(code) else { throw error("bad unicode escape") }
                        scalars.append(contentsOf: Array(String(Character(scalar)).utf8))
                    default:
                        throw error("bad escape")
                    }
                    runStart = index
                    continue
                }
                index += 1
            }
            throw error("unterminated string")
        }
    }
}

// MARK: - Writer

public enum JSONWriter {
    public static func write(_ value: JSONValue, pretty: Bool = true) -> Data {
        var out = ""
        out.reserveCapacity(1 << 16)
        append(value, to: &out, indent: 0, pretty: pretty)
        if pretty { out.append("\n") }
        return Data(out.utf8)
    }

    private static func append(_ value: JSONValue, to out: inout String, indent: Int, pretty: Bool) {
        let newline = pretty ? "\n" : ""
        let pad = pretty ? String(repeating: "  ", count: indent + 1) : ""
        let closePad = pretty ? String(repeating: "  ", count: indent) : ""
        switch value {
        case .null: out.append("null")
        case .bool(let b): out.append(b ? "true" : "false")
        case .number(let n): out.append(n)
        case .string(let s): appendString(s, to: &out)
        case .array(let items):
            if items.isEmpty { out.append("[]"); return }
            out.append("[" + newline)
            for (i, item) in items.enumerated() {
                out.append(pad)
                append(item, to: &out, indent: indent + 1, pretty: pretty)
                out.append(i < items.count - 1 ? "," + newline : newline)
            }
            out.append(closePad + "]")
        case .object(let object):
            if object.keys.isEmpty { out.append("{}"); return }
            out.append("{" + newline)
            for (i, key) in object.keys.enumerated() {
                out.append(pad)
                appendString(key, to: &out)
                out.append(pretty ? ": " : ":")
                append(object[key] ?? .null, to: &out, indent: indent + 1, pretty: pretty)
                out.append(i < object.keys.count - 1 ? "," + newline : newline)
            }
            out.append(closePad + "}")
        }
    }

    private static func appendString(_ s: String, to out: inout String) {
        out.append("\"")
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out.append("\\\"")
            case "\\": out.append("\\\\")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            case "\u{08}": out.append("\\b")
            case "\u{0C}": out.append("\\f")
            default:
                if scalar.value < 0x20 {
                    out.append(String(format: "\\u%04x", scalar.value))
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out.append("\"")
    }
}
