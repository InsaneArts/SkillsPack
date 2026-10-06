import Foundation

/// Reads and writes each agent's own on/off switch for skills:
/// - Claude: `skillOverrides` in `~/.claude/settings.json` (`"name": "off"`).
/// - Codex: `[[skills.config]]` blocks in `~/.codex/config.toml` (`enabled = false`).
/// - pi: `-<path>/SKILL.md` entries in the `skills` array of `~/.pi/agent/settings.json`.
public struct Switches: Sendable {
    let paths: Paths

    public init(paths: Paths) { self.paths = paths }

    /// A snapshot of all three switch files.
    public struct Snapshot: Sendable {
        var claudeOff: Set<String> = []
        var codexBlocks: [CodexConfig.Block] = []
        var piEntries: [String] = []

        public static let empty = Snapshot()
    }

    public func snapshot() -> Snapshot {
        var snapshot = Snapshot()
        if let settings = try? JSON(contentsOf: paths.claudeSettings) {
            snapshot.claudeOff = Set(settings["skillOverrides"]?.members.filter { $0.value.stringValue == "off" }.map(\.key) ?? [])
        }
        if let text = try? String(contentsOf: paths.codexConfig, encoding: .utf8) {
            snapshot.codexBlocks = CodexConfig(text: text).blocks
        }
        if let settings = try? JSON(contentsOf: paths.piSettings) {
            snapshot.piEntries = settings["skills"]?.elements.compactMap(\.stringValue) ?? []
        }
        return snapshot
    }

    public func state(of skill: Skill, for agent: Agent, in snapshot: Snapshot) -> AgentState {
        let installations = skill.installations(for: agent)
        guard !installations.isEmpty else { return .notInstalled }
        switch agent {
        case .claude:
            return snapshot.claudeOff.contains(skill.name) ? .off : .on
        case .codex:
            let off = snapshot.codexBlocks.contains { $0.enabled == false && codexBlock($0, matches: skill) }
            return off ? .off : .on
        case .pi:
            let off = installations.allSatisfy { installation in
                snapshot.piEntries.contains { isExclusion($0) && piEntry($0, matches: installation) }
            }
            return off ? .off : .on
        }
    }

    public func setEnabled(_ enabled: Bool, skill: Skill, agent: Agent) throws {
        switch agent {
        case .claude: try setClaude(enabled, skill: skill)
        case .codex: try setCodex(enabled, skill: skill)
        case .pi: try setPi(enabled, skill: skill)
        }
    }

    /// Removes every switch entry for a skill, used after it is deleted.
    public func clear(skill: Skill) throws {
        for agent in Agent.allCases where !skill.installations(for: agent).isEmpty {
            try setEnabled(true, skill: skill, agent: agent)
        }
    }

    // MARK: Claude

    func setClaude(_ enabled: Bool, skill: Skill) throws {
        let file = JSONFile(url: paths.claudeSettings)
        let (value, indent, newline) = try file.read()
        var settings = value
        var overrides = settings["skillOverrides"] ?? .object([])
        let isOff = overrides[skill.name]?.stringValue == "off"
        guard isOff == enabled else { return } // already in the wanted state
        overrides.set(skill.name, enabled ? nil : .string("off"))
        settings.set("skillOverrides", overrides.members.isEmpty ? nil : overrides)
        try Backup(paths: paths).save(paths.claudeSettings, label: "claude")
        try file.write(settings, indent: indent, trailingNewline: newline)
    }

    // MARK: Codex

    func codexBlock(_ block: CodexConfig.Block, matches skill: Skill) -> Bool {
        if block.name == skill.name { return true }
        guard let path = block.path else { return false }
        let target = canonical(path)
        return skill.installations(for: .codex).contains { canonical($0.skillFile.path) == target }
    }

    func setCodex(_ enabled: Bool, skill: Skill) throws {
        let text = (try? String(contentsOf: paths.codexConfig, encoding: .utf8)) ?? ""
        var config = CodexConfig(text: text)
        config.removeBlocks { codexBlock($0, matches: skill) }
        if !enabled { try config.appendDisabled(name: skill.name) }
        guard config.text != text else { return }
        try Backup(paths: paths).save(paths.codexConfig, label: "codex")
        try FileManager.default.createDirectory(at: paths.codexConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try config.text.write(to: paths.codexConfig, atomically: true, encoding: .utf8)
    }

    // MARK: pi

    func isExclusion(_ entry: String) -> Bool { entry.hasPrefix("-") || entry.hasPrefix("!") }

    /// pi matches entries against the path it found the skill at, without resolving symlinks.
    /// `pi config` writes paths relative to the skill folder's root or to `~/.pi/agent`.
    func piEntry(_ entry: String, matches installation: Installation) -> Bool {
        var target = entry
        if let first = target.first, "-!+".contains(first) { target.removeFirst() }
        let candidates: [URL]
        if target.hasPrefix("/") {
            candidates = [URL(filePath: target)]
        } else if target.hasPrefix("~/") {
            candidates = [paths.home.appending(path: String(target.dropFirst(2)))]
        } else {
            candidates = [paths.piAgent.appending(path: target), installation.root.url.appending(path: target)]
        }
        let file = installation.skillFile.standardizedFileURL.path
        let dir = installation.dir.standardizedFileURL.path
        return candidates.contains {
            let path = $0.standardizedFileURL.path
            return path == file || path == dir
        }
    }

    func setPi(_ enabled: Bool, skill: Skill) throws {
        let installations = skill.installations(for: .pi)
        let file = JSONFile(url: paths.piSettings)
        let (value, indent, newline) = try file.read()
        var settings = value
        let entries = settings["skills"]?.elements ?? []
        var kept = entries.filter { element in
            guard let entry = element.stringValue else { return true }
            return !installations.contains { piEntry(entry, matches: $0) }
        }
        if !enabled {
            kept += installations.map { .string("-" + $0.skillFile.path) }
        }
        guard kept != entries else { return }
        settings.set("skills", kept.isEmpty ? nil : .array(kept))
        try Backup(paths: paths).save(paths.piSettings, label: "pi")
        try file.write(settings, indent: indent, trailingNewline: newline)
    }

    func canonical(_ path: String) -> String {
        URL(filePath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

/// Text-level editing of `[[skills.config]]` blocks in Codex's `config.toml`.
/// Everything else in the file stays as it is.
struct CodexConfig {
    struct Block: Sendable, Equatable {
        var lines: Range<Int>
        var path: String?
        var name: String?
        var enabled: Bool?
    }

    private(set) var lines: [String]

    init(text: String) {
        lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
    }

    var text: String { lines.joined(separator: "\n") }

    var blocks: [Block] {
        var result: [Block] = []
        var index = 0
        while index < lines.count {
            guard lines[index].trimmingCharacters(in: .whitespaces) == "[[skills.config]]" else { index += 1; continue }
            var block = Block(lines: index..<index + 1)
            var end = index + 1
            while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                let parts = lines[end].split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    switch parts[0] {
                    case "path": block.path = Self.unquote(parts[1])
                    case "name": block.name = Self.unquote(parts[1])
                    case "enabled": block.enabled = parts[1].hasPrefix("true") ? true : parts[1].hasPrefix("false") ? false : nil
                    default: break
                    }
                }
                end += 1
            }
            // Trailing blank lines belong to the gap before the next table, not to this block.
            while end > index + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
            block.lines = index..<end
            result.append(block)
            index = end
        }
        return result
    }

    mutating func removeBlocks(where shouldRemove: (Block) -> Bool) {
        for block in blocks.reversed() where shouldRemove(block) {
            var range = block.lines
            // Remove the blank line that separated this block from the one above.
            if range.lowerBound > 0, lines[range.lowerBound - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                range = (range.lowerBound - 1)..<range.upperBound
            }
            lines.removeSubrange(range)
        }
    }

    mutating func appendDisabled(name: String) throws {
        // A `[skills]` table or inline `skills.config` array would conflict with `[[skills.config]]`.
        if lines.contains(where: {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line == "[skills]" || line.hasPrefix("skills.config") || line.hasPrefix("skills =")
        }) {
            throw JSONError(description: "config.toml defines skills in a form SkillsPack does not edit. Change it by hand.")
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        if !lines.isEmpty { lines.append("") }
        lines += ["[[skills.config]]", "name = \(Self.quote(name))", "enabled = false", ""]
    }

    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func unquote(_ value: String) -> String {
        var value = value
        if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else { return value }
        let inner = String(value.dropFirst().dropLast())
        return first == "'" ? inner : inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
}

/// Copies a config file before SkillsPack changes it. Keeps the 20 newest copies per file.
struct Backup {
    let paths: Paths

    func save(_ file: URL, label: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return }
        let dir = paths.appSupport.appending(path: "backups")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let prefix = "\(label)-\(file.lastPathComponent)-"
        try fm.copyItem(at: file, to: dir.appending(path: prefix + formatter.string(from: Date())))
        let old = (try fm.contentsOfDirectory(atPath: dir.path)).filter { $0.hasPrefix(prefix) }.sorted().dropLast(20)
        for name in old { try? fm.removeItem(at: dir.appending(path: name)) }
    }
}
