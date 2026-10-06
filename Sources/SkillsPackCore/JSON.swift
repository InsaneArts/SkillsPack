import Foundation

/// A JSON value that keeps object key order and number text, so rewriting
/// an agent's settings file changes only the key SkillsPack edits.
public indirect enum JSON: Equatable, Sendable {
    case object([Member])
    case array([JSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    public struct Member: Equatable, Sendable {
        public var key: String
        public var value: JSON
    }

    public subscript(key: String) -> JSON? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    /// Sets a key in place, appends a new key at the end, or removes it when `value` is nil.
    public mutating func set(_ key: String, _ value: JSON?) {
        guard case .object(var members) = self else { return }
        if let index = members.firstIndex(where: { $0.key == key }) {
            if let value { members[index].value = value } else { members.remove(at: index) }
        } else if let value {
            members.append(Member(key: key, value: value))
        }
        self = .object(members)
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var members: [Member] {
        if case .object(let m) = self { return m }
        return []
    }

    public var elements: [JSON] {
        if case .array(let a) = self { return a }
        return []
    }
}

// MARK: - Parsing

public struct JSONError: Error, CustomStringConvertible {
    public let description: String
}

extension JSON {
    public init(parsing text: String) throws {
        var parser = Parser(bytes: Array(text.utf8))
        self = try parser.parseDocument()
    }

    public init(contentsOf url: URL) throws {
        try self.init(parsing: try String(contentsOf: url, encoding: .utf8))
    }
}

private struct Parser {
    let bytes: [UInt8]
    var i = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func parseDocument() throws -> JSON {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard i == bytes.count else { throw error("unexpected text after JSON value") }
        return value
    }

    func error(_ message: String) -> JSONError { JSONError(description: "\(message) at byte \(i)") }

    mutating func skipWhitespace() {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }

    mutating func expect(_ byte: UInt8) throws {
        guard i < bytes.count, bytes[i] == byte else { throw error("expected '\(Character(UnicodeScalar(byte)))'") }
        i += 1
    }

    mutating func parseValue() throws -> JSON {
        guard i < bytes.count else { throw error("unexpected end") }
        switch bytes[i] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try parseLiteral("true"); return .bool(true)
        case UInt8(ascii: "f"): try parseLiteral("false"); return .bool(false)
        case UInt8(ascii: "n"): try parseLiteral("null"); return .null
        default: return try parseNumber()
        }
    }

    mutating func parseLiteral(_ word: String) throws {
        for byte in word.utf8 { try expect(byte) }
    }

    mutating func parseObject() throws -> JSON {
        try expect(UInt8(ascii: "{"))
        var members: [JSON.Member] = []
        skipWhitespace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(members) }
        while true {
            skipWhitespace()
            let key = try parseString()
            skipWhitespace()
            try expect(UInt8(ascii: ":"))
            skipWhitespace()
            members.append(JSON.Member(key: key, value: try parseValue()))
            skipWhitespace()
            guard i < bytes.count else { throw error("unexpected end in object") }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            try expect(UInt8(ascii: "}"))
            return .object(members)
        }
    }

    mutating func parseArray() throws -> JSON {
        try expect(UInt8(ascii: "["))
        var elements: [JSON] = []
        skipWhitespace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(elements) }
        while true {
            skipWhitespace()
            elements.append(try parseValue())
            skipWhitespace()
            guard i < bytes.count else { throw error("unexpected end in array") }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            try expect(UInt8(ascii: "]"))
            return .array(elements)
        }
    }

    mutating func parseNumber() throws -> JSON {
        let start = i
        while i < bytes.count, "+-0123456789.eE".utf8.contains(bytes[i]) { i += 1 }
        guard i > start else { throw error("unexpected character") }
        return .number(String(decoding: bytes[start..<i], as: UTF8.self))
    }

    mutating func parseString() throws -> String {
        try expect(UInt8(ascii: "\""))
        var out: [UInt8] = []
        while i < bytes.count {
            let byte = bytes[i]
            i += 1
            switch byte {
            case UInt8(ascii: "\""):
                return String(decoding: out, as: UTF8.self)
            case UInt8(ascii: "\\"):
                guard i < bytes.count else { throw error("unexpected end in string") }
                let escaped = bytes[i]
                i += 1
                switch escaped {
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try parseHex4()
                    if (0xD800...0xDBFF).contains(scalar), i + 1 < bytes.count,
                       bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") {
                        i += 2
                        let low = try parseHex4()
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let unicode = Unicode.Scalar(scalar) else { throw error("invalid unicode escape") }
                    out.append(contentsOf: Array(String(Character(unicode)).utf8))
                default: out.append(escaped)
                }
            default:
                out.append(byte)
            }
        }
        throw error("unterminated string")
    }

    mutating func parseHex4() throws -> UInt32 {
        guard i + 4 <= bytes.count, let value = UInt32(String(decoding: bytes[i..<i + 4], as: UTF8.self), radix: 16) else {
            throw error("invalid unicode escape")
        }
        i += 4
        return value
    }
}

// MARK: - Writing

extension JSON {
    /// Renders like `JSON.stringify(value, null, indent)`.
    public func rendered(indent: String = "  ") -> String {
        var out = ""
        write(to: &out, indent: indent, level: 0)
        return out
    }

    private func write(to out: inout String, indent: String, level: Int) {
        let pad = String(repeating: indent, count: level)
        let innerPad = pad + indent
        switch self {
        case .object(let members):
            guard !members.isEmpty else { out += "{}"; return }
            out += "{\n"
            for (index, member) in members.enumerated() {
                out += innerPad + JSON.quote(member.key) + ": "
                member.value.write(to: &out, indent: indent, level: level + 1)
                out += index < members.count - 1 ? ",\n" : "\n"
            }
            out += pad + "}"
        case .array(let elements):
            guard !elements.isEmpty else { out += "[]"; return }
            out += "[\n"
            for (index, element) in elements.enumerated() {
                out += innerPad
                element.write(to: &out, indent: indent, level: level + 1)
                out += index < elements.count - 1 ? ",\n" : "\n"
            }
            out += pad + "]"
        case .string(let s): out += JSON.quote(s)
        case .number(let n): out += n
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}

/// Reads a JSON settings file and writes it back in the same style.
struct JSONFile {
    let url: URL

    func read() throws -> (value: JSON, indent: String, trailingNewline: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (.object([]), "  ", true) }
        let text = try String(contentsOf: url, encoding: .utf8)
        return (try JSON(parsing: text), Self.indent(of: text), text.hasSuffix("\n"))
    }

    func write(_ value: JSON, indent: String, trailingNewline: Bool) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = value.rendered(indent: indent) + (trailingNewline ? "\n" : "")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func indent(of text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst() {
            let lead = line.prefix { $0 == " " || $0 == "\t" }
            if !lead.isEmpty { return String(lead) }
        }
        return "  "
    }
}
