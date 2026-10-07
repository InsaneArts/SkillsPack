import Foundation

public struct Usage: Codable, Sendable, Equatable {
    public var byUser = 0
    public var byAgent = 0
    public var lastUsed: Date?
    /// Uses in sessions from the last 90 days. Computed on each scan, not cached.
    public var recent = 0

    /// `recent` stays out of the cache, so it never goes stale.
    enum CodingKeys: String, CodingKey { case byUser, byAgent, lastUsed }

    public init(byUser: Int = 0, byAgent: Int = 0, lastUsed: Date? = nil, recent: Int = 0) {
        self.byUser = byUser
        self.byAgent = byAgent
        self.lastUsed = lastUsed
        self.recent = recent
    }

    public var total: Int { byUser + byAgent }

    mutating func add(_ other: Usage) {
        byUser += other.byUser
        byAgent += other.byAgent
        if let date = other.lastUsed, date > (lastUsed ?? .distantPast) { lastUsed = date }
    }
}

/// Counts skill use in Claude, Codex, and pi session logs.
/// Counts per file are cached, so only new or changed logs are read again.
public struct UsageScanner: Sendable {
    let paths: Paths

    public init(paths: Paths) { self.paths = paths }

    enum Log: String, Codable { case claude, codex, pi }

    struct FileEntry: Codable {
        var size: Int
        var modified: Double
        var counts: [String: Usage]
    }

    var cacheURL: URL { paths.appSupport.appending(path: "usage-cache.json") }

    public func scan() -> [String: Usage] {
        let cache = (try? JSONDecoder().decode([String: FileEntry].self, from: Data(contentsOf: cacheURL))) ?? [:]
        var entries: [String: FileEntry] = [:]
        for (log, url) in logFiles() {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            if let cached = cache[url.path], cached.size == size, cached.modified == modified {
                entries[url.path] = cached
                continue
            }
            guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { continue }
            var counts = Self.count(log, in: data)
            for name in counts.keys { counts[name]?.lastUsed = Date(timeIntervalSince1970: modified) }
            entries[url.path] = FileEntry(size: size, modified: modified, counts: counts)
        }
        try? FileManager.default.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: cacheURL, options: .atomic)

        // A log's modification date is when its session last ran.
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600).timeIntervalSince1970
        var totals: [String: Usage] = [:]
        for entry in entries.values {
            for (name, usage) in entry.counts {
                totals[name, default: Usage()].add(usage)
                if entry.modified >= cutoff { totals[name, default: Usage()].recent += usage.total }
            }
        }
        return totals
    }

    func logFiles() -> [(Log, URL)] {
        var files: [(Log, URL)] = []
        func walk(_ dir: URL, _ log: Log) {
            guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return }
            for case let url as URL in walker where url.pathExtension == "jsonl" { files.append((log, url)) }
        }
        walk(paths.claudeSessions, .claude)
        paths.codexSessions.forEach { walk($0, .codex) }
        walk(paths.piSessions, .pi)
        return files
    }

    // MARK: Counting

    static func count(_ log: Log, in data: Data) -> [String: Usage] {
        var counts: [String: Usage] = [:]
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            let text = Bytes(base: base, count: raw.count)
            switch log {
            case .claude: countClaude(text, into: &counts)
            case .codex: countCodex(text, into: &counts)
            case .pi: countPi(text, into: &counts)
            }
        }
        return counts
    }

    /// Claude: the `Skill` tool call, and a user message that starts with `<command-message>`.
    static func countClaude(_ text: Bytes, into counts: inout [String: Usage]) {
        text.forEach(#""name":"Skill","input":{"skill":""#) { end in
            if let name = text.name(from: end, until: "\"") { counts[name, default: Usage()].byAgent += 1 }
        }
        for opener in [#""content":"<command-message>"#, #""text":"<command-message>"#] {
            text.forEach(opener) { end in
                let line = text.line(around: end)
                guard let start = text.find("<command-name>/", in: end..<min(line.upperBound, end + 400)),
                      let name = text.name(from: start + "<command-name>/".utf8.count, until: "<") else { return }
                counts[name, default: Usage()].byUser += 1
            }
        }
    }

    /// Codex: a tool call that reads `<skill>/SKILL.md`, and `$skill` in a user message.
    /// Only top-level `response_item` lines count. Compacted lines repeat old history and are skipped.
    static func countCodex(_ text: Bytes, into counts: inout [String: Usage]) {
        let injected = ["<environment_context>", "AGENTS.md", "<permissions", "<user_instructions>"]
        text.forEachLine { line in
            let head = line.lowerBound..<min(line.upperBound, line.lowerBound + 200)
            if text.find(#""type":"response_item","payload":{"type":"function_call""#, in: head) != nil {
                text.forEach("/SKILL.md", in: line) { end in
                    if let name = text.lastPathComponent(before: end - "/SKILL.md".utf8.count) {
                        counts[name, default: Usage()].byAgent += 1
                    }
                }
            } else if text.find(#""type":"response_item""#, in: head) != nil, text.find(#""role":"user""#, in: head) != nil {
                guard !injected.contains(where: { text.find($0, in: line) != nil }) else { return }
                var names = Set<String>()
                text.forEachByte(UInt8(ascii: "$"), in: line) { index in
                    if let name = text.name(from: index + 1, until: nil), name.first?.isLetter == true { names.insert(name) }
                }
                for name in names { counts[name, default: Usage()].byUser += 1 }
            }
        }
    }

    /// pi: a `read` call on `<skill>/SKILL.md`, and the `<skill name="...">` block a `/skill:name` command expands to.
    static func countPi(_ text: Bytes, into counts: inout [String: Usage]) {
        text.forEach(#""name":"read","arguments":{"path":""#) { end in
            guard let close = text.find("\"", in: end..<min(text.count, end + 1024)) else { return }
            let suffix = "/SKILL.md"
            guard close - end > suffix.utf8.count, text.find(suffix, in: (close - suffix.utf8.count)..<close) != nil,
                  let name = text.lastPathComponent(before: close - suffix.utf8.count) else { return }
            counts[name, default: Usage()].byAgent += 1
        }
        var checkedLine: Range<Int>?
        var isUser = false
        text.forEach(#"<skill name=\""#) { end in
            if checkedLine?.contains(end) != true {
                let line = text.line(around: end)
                checkedLine = line
                isUser = text.find(#""role":"user""#, in: line.lowerBound..<min(line.upperBound, line.lowerBound + 300)) != nil
            }
            guard isUser, let name = text.name(from: end, until: "\\") else { return }
            counts[name, default: Usage()].byUser += 1
        }
    }
}

/// Fast byte search over a memory-mapped log file.
struct Bytes {
    let base: UnsafePointer<UInt8>
    let count: Int

    func find(_ needle: String, in range: Range<Int>) -> Int? {
        let bytes = Array(needle.utf8)
        guard range.lowerBound >= 0, range.upperBound <= count, range.count >= bytes.count else { return nil }
        let found = bytes.withUnsafeBytes { n in
            memmem(base + range.lowerBound, range.count, n.baseAddress, n.count)
        }
        guard let found else { return nil }
        return UnsafeRawPointer(found) - UnsafeRawPointer(base)
    }

    /// Calls `body` with the index just after each match.
    func forEach(_ needle: String, in range: Range<Int>? = nil, _ body: (Int) -> Void) {
        let length = needle.utf8.count
        let range = range ?? 0..<count
        var position = range.lowerBound
        while let index = find(needle, in: position..<range.upperBound) {
            body(index + length)
            position = index + length
        }
    }

    func forEachLine(_ body: (Range<Int>) -> Void) {
        var start = 0
        while start < count {
            var end = count
            if let found = memchr(base + start, 0x0A, count - start) {
                end = UnsafeRawPointer(found) - UnsafeRawPointer(base)
            }
            body(start..<end)
            start = end + 1
        }
    }

    func forEachByte(_ byte: UInt8, in range: Range<Int>, _ body: (Int) -> Void) {
        var index = range.lowerBound
        while index < range.upperBound {
            guard let found = memchr(base + index, Int32(byte), range.upperBound - index) else { return }
            let position = UnsafeRawPointer(found) - UnsafeRawPointer(base)
            body(position)
            index = position + 1
        }
    }

    func line(around index: Int) -> Range<Int> {
        var start = min(index, count)
        while start > 0, base[start - 1] != 0x0A { start -= 1 }
        var end = index
        if end < count, let found = memchr(base + end, 0x0A, count - end) {
            end = UnsafeRawPointer(found) - UnsafeRawPointer(base)
        } else {
            end = count
        }
        return start..<end
    }

    /// Reads a skill name at `index`: letters, digits, `-`, `_`, `.`, and `:`.
    /// With a terminator, the name must end exactly there.
    func name(from index: Int, until terminator: Character?) -> String? {
        var end = index
        while end < count, end - index < 128 {
            let byte = base[end]
            let isNameByte = (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x30 && byte <= 0x39)
                || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_") || byte == UInt8(ascii: ".") || byte == UInt8(ascii: ":")
            guard isNameByte else { break }
            end += 1
        }
        guard end > index else { return nil }
        if let terminator {
            guard end < count, base[end] == terminator.asciiValue else { return nil }
        }
        var name = String(decoding: UnsafeBufferPointer(start: base + index, count: end - index), as: UTF8.self)
        while name.hasSuffix(".") || name.hasSuffix(":") { name.removeLast() }
        return name.isEmpty ? nil : name
    }

    /// The folder name before `/` at `index`, as in `.../<name>/SKILL.md`.
    func lastPathComponent(before index: Int) -> String? {
        var start = index
        while start > 0, base[start - 1] != UInt8(ascii: "/"), base[start - 1] != UInt8(ascii: "\""), index - start < 128 {
            start -= 1
        }
        guard start < index, start > 0, base[start - 1] == UInt8(ascii: "/") else { return nil }
        return name(from: start, until: "/")
    }
}
