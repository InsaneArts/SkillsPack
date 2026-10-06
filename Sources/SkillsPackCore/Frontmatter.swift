import Foundation

/// Reads the top-level `key: value` pairs of a SKILL.md frontmatter block.
/// Handles quoted values and folded (`>`) or literal (`|`) multi-line values.
enum Frontmatter {
    static func parse(_ text: String) -> [String: String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : String($0)
        }[...]
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        lines.removeFirst()

        var fields: [String: String] = [:]
        while let line = lines.popFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let first = line.first, first != " ", first != "\t", first != "#",
                  let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            if let quote = value.first, quote == "\"" || quote == "'", !closes(value, quote) {
                // A quoted value can continue on the next lines, indented or not.
                var parts = [value]
                while let next = lines.popFirst() {
                    parts.append(next.trimmingCharacters(in: .whitespaces))
                    if closes(next.trimmingCharacters(in: .whitespaces), quote, isContinuation: true) { break }
                }
                value = parts.joined(separator: " ")
            } else if [">", "|", ">-", "|-", ">+", "|+", ""].contains(value) {
                var parts: [String] = []
                while let next = lines.first, next.first == " " || next.first == "\t" || next.isEmpty {
                    if next.trimmingCharacters(in: .whitespaces) == "---" { break }
                    parts.append(next.trimmingCharacters(in: .whitespaces))
                    lines.removeFirst()
                }
                value = parts.filter { !$0.isEmpty }.joined(separator: " ")
            }
            fields[key] = unquote(value)
        }
        return fields
    }

    /// True when a quoted value ends with its closing quote. The opening quote alone does not count.
    static func closes(_ text: String, _ quote: Character, isContinuation: Bool = false) -> Bool {
        guard text.last == quote, text.count >= (isContinuation ? 1 : 2) else { return false }
        let beforeQuote = text.dropLast()
        if quote == "\"" {
            let backslashes = beforeQuote.reversed().prefix { $0 == "\\" }.count
            return backslashes % 2 == 0
        }
        return true
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else {
            return value
        }
        let inner = String(value.dropFirst().dropLast())
        if first == "'" { return inner.replacingOccurrences(of: "''", with: "'") }
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
}
