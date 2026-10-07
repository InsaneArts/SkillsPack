import CryptoKit
import Foundation

/// Where a skill comes from: a git repo, an optional ref, and the skill's folder inside the repo.
public struct SourceRef: Codable, Sendable, Hashable {
    public var repo: String
    public var ref: String?
    public var path: String?

    public init(repo: String, ref: String? = nil, path: String? = nil) {
        self.repo = repo
        self.ref = ref
        self.path = path
    }

    /// Accepts `owner/repo`, GitHub repo, tree and blob URLs, and any other git URL or local path.
    public static func parse(_ input: String) -> SourceRef? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }

        let parts = text.split(separator: "/").map(String.init)
        if parts.count == 2, !text.contains(":"), !text.hasPrefix("."), !text.hasPrefix("/"),
           parts.allSatisfy({ $0.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } }) {
            return SourceRef(repo: "https://github.com/\(parts[0])/\(parts[1]).git")
        }

        if let url = URL(string: text), url.host == "github.com" {
            let segments = url.path.split(separator: "/").map(String.init)
            guard segments.count >= 2 else { return nil }
            var name = segments[1]
            if name.hasSuffix(".git") { name.removeLast(4) }
            var source = SourceRef(repo: "https://github.com/\(segments[0])/\(name).git")
            if segments.count >= 4, segments[2] == "tree" || segments[2] == "blob" {
                source.ref = segments[3]
                var rest = Array(segments.dropFirst(4))
                if rest.last == "SKILL.md" { rest.removeLast() }
                source.path = rest.isEmpty ? nil : rest.joined(separator: "/")
            }
            return source
        }

        if text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("git@")
            || text.hasPrefix("ssh://") || text.hasPrefix("file://") || text.hasPrefix("/") {
            return SourceRef(repo: text)
        }
        return nil
    }

    /// A short form for display, like `owner/repo` or `owner/repo/path`.
    public var display: String {
        var repo = self.repo
        for prefix in ["https://github.com/", "git@github.com:"] where repo.hasPrefix(prefix) {
            repo = String(repo.dropFirst(prefix.count))
        }
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        return [repo, path].compactMap { $0 }.joined(separator: "/")
    }
}

public struct SourceRecord: Codable, Sendable, Hashable {
    public var source: SourceRef
    public var commit: String?
    public var installedAt: Date?
}

/// A skill found in a fetched repo.
public struct FoundSkill: Sendable, Identifiable, Hashable {
    public let name: String
    public let description: String
    public let dir: URL
    /// The folder's path inside the repo.
    public let path: String

    public var id: String { path }
}

/// A shallow clone of a source, ready to install from.
public struct Fetched: Sendable {
    public let source: SourceRef
    public let checkout: URL
    public let commit: String
    public let skills: [FoundSkill]
}

public struct InstallerError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }

    public init(message: String) { self.message = message }
}

public struct Installer: Sendable {
    let paths: Paths

    public init(paths: Paths) { self.paths = paths }

    var manifestURL: URL { paths.appSupport.appending(path: "sources.json") }

    // MARK: Sources

    /// Known sources by skill name: SkillsPack's own records, then the `npx skills` lock file.
    public func sources() -> [String: SourceRecord] {
        var result: [String: SourceRecord] = [:]
        if let lock = try? JSON(contentsOf: paths.skillLock) {
            for member in lock["skills"]?.members ?? [] {
                guard let url = member.value["sourceUrl"]?.stringValue else { continue }
                let skillPath = member.value["skillPath"]?.stringValue.map { ($0 as NSString).deletingLastPathComponent }
                result[member.key] = SourceRecord(source: SourceRef(repo: url, path: skillPath?.isEmpty == true ? nil : skillPath))
            }
        }
        result.merge(manifest()) { _, own in own }
        return result
    }

    func manifest() -> [String: SourceRecord] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: SourceRecord].self, from: data)) ?? [:]
    }

    func saveManifest(_ manifest: [String: SourceRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    func record(_ name: String, _ record: SourceRecord?) throws {
        var manifest = manifest()
        manifest[name] = record
        try saveManifest(manifest)
    }

    // MARK: Tracked repos

    var reposURL: URL { paths.appSupport.appending(path: "repos.json") }

    /// Repos that `matchSources` searches for skills with no known source.
    public func trackedRepos() -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(contentsOf: reposURL))) ?? []
    }

    public func saveTrackedRepos(_ repos: [String]) throws {
        try FileManager.default.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
        try JSONEncoder().encode(repos).write(to: reposURL, options: .atomic)
    }

    /// Links each skill with no known source to a skill of the same name in the given repos.
    /// The first repo that has the name wins. Returns the names that got a source.
    public func matchSources(in repos: [SourceRef], for skills: [Skill]) throws -> [String] {
        var known = sources()
        var manifest = manifest()
        var matched: [String] = []
        for repo in repos {
            let fetched = try fetch(repo)
            defer { discard(fetched) }
            for skill in skills where known[skill.name] == nil && skill.isDeletable {
                guard let found = fetched.skills.first(where: { $0.name == skill.baseName }) else { continue }
                var source = repo
                source.path = found.path.isEmpty ? nil : found.path
                let record = SourceRecord(source: source, commit: nil, installedAt: nil)
                known[skill.name] = record
                manifest[skill.name] = record
                matched.append(skill.name)
            }
        }
        try saveManifest(manifest)
        return matched
    }

    // MARK: Fetch

    public func fetch(_ source: SourceRef) throws -> Fetched {
        let checkout = FileManager.default.temporaryDirectory.appending(path: "SkillsPack-\(UUID().uuidString)")
        do {
            try Shell.git(["clone", "--depth", "1", "--quiet"] + (source.ref.map { ["--branch", $0] } ?? []) + [source.repo, checkout.path])
        } catch {
            // The ref may be a commit, which `--branch` does not accept.
            guard let ref = source.ref else { throw error }
            try? FileManager.default.removeItem(at: checkout)
            try Shell.git(["clone", "--depth", "1", "--quiet", source.repo, checkout.path])
            try Shell.git(["-C", checkout.path, "fetch", "--depth", "1", "--quiet", "origin", ref])
            try Shell.git(["-C", checkout.path, "checkout", "--quiet", "FETCH_HEAD"])
        }
        let commit = try Shell.git(["-C", checkout.path, "rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let base = source.path.map { checkout.appending(path: $0) } ?? checkout
        guard FileManager.default.fileExists(atPath: base.path) else {
            throw InstallerError(message: "\(source.path ?? "") does not exist in \(source.display).")
        }
        let skills = Self.discover(in: base, checkout: checkout)
        guard !skills.isEmpty else { throw InstallerError(message: "No SKILL.md found in \(source.display).") }
        return Fetched(source: source, checkout: checkout, commit: commit, skills: skills)
    }

    /// Deletes the temporary clone.
    public func discard(_ fetched: Fetched) {
        try? FileManager.default.removeItem(at: fetched.checkout)
    }

    static func discover(in base: URL, checkout: URL) -> [FoundSkill] {
        let fm = FileManager.default
        var dirs: [URL] = []
        if fm.fileExists(atPath: base.appending(path: "SKILL.md").path) {
            dirs = [base]
        } else if let walker = fm.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in walker {
                let name = url.lastPathComponent
                if name == ".git" || name == "node_modules" { walker.skipDescendants(); continue }
                if fm.fileExists(atPath: url.appending(path: "SKILL.md").path) {
                    dirs.append(url)
                    walker.skipDescendants()
                }
            }
        }
        let root = checkout.resolvingSymlinksInPath().path
        return dirs.sorted { $0.path < $1.path }.map { dir in
            let fields = Frontmatter.parse((try? String(contentsOf: dir.appending(path: "SKILL.md"), encoding: .utf8)) ?? "")
            let full = dir.resolvingSymlinksInPath().path
            let path = full.hasPrefix(root) ? String(full.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : dir.lastPathComponent
            return FoundSkill(
                name: fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? dir.lastPathComponent,
                description: fields["description"] ?? "",
                dir: dir,
                path: path)
        }
    }

    // MARK: Install

    /// Copies a fetched skill into each agent's skills folder and records its source.
    public func install(_ skill: FoundSkill, from fetched: Fetched, agents: Set<Agent>) throws {
        try Self.validate(name: skill.name)
        for agent in Agent.allCases where agents.contains(agent) {
            try Self.replace(paths.installDir(for: agent).appending(path: skill.name), with: skill.dir)
        }
        var source = fetched.source
        source.path = skill.path.isEmpty ? nil : skill.path
        try record(skill.name, SourceRecord(source: source, commit: fetched.commit, installedAt: Date()))
    }

    /// Copies an installed skill into another agent's skills folder.
    public func copy(_ skill: Skill, to agent: Agent) throws {
        guard let from = skill.installations.first else { return }
        try Self.validate(name: skill.baseName)
        try Self.replace(paths.installDir(for: agent).appending(path: skill.baseName), with: from.resolvedDir)
    }

    /// Moves every writable copy to the Trash. Symlinks are removed, never their targets.
    public func delete(_ skill: Skill) throws {
        let fm = FileManager.default
        for installation in skill.installations where installation.root.isWritable {
            if installation.isSymlink {
                try fm.removeItem(at: installation.dir)
            } else {
                try fm.trashItem(at: installation.dir, resultingItemURL: nil)
            }
        }
        try record(skill.name, nil)
    }

    // MARK: Update

    /// True when the copy in the source differs from the installed copy.
    public func hasUpdate(_ skill: Skill, in fetched: Fetched, record: SourceRecord) -> Bool {
        guard let found = Self.match(skill, in: fetched, record: record),
              let installed = skill.installations.first(where: { $0.root.isWritable && !$0.isSymlink }) else { return false }
        return Self.contentHash(found.dir) != Self.contentHash(installed.dir)
    }

    /// Replaces every writable, non-symlink copy with the fetched version. Returns the number of copies updated.
    @discardableResult
    public func update(_ skill: Skill, from fetched: Fetched, record: SourceRecord) throws -> Int {
        guard let found = Self.match(skill, in: fetched, record: record) else {
            throw InstallerError(message: "\(skill.name) is no longer in \(record.source.display).")
        }
        var count = 0
        for installation in skill.installations where installation.root.isWritable && !installation.isSymlink {
            try Self.replace(installation.dir, with: found.dir)
            count += 1
        }
        var updated = record
        updated.commit = fetched.commit
        updated.installedAt = Date()
        try self.record(skill.name, updated)
        return count
    }

    static func match(_ skill: Skill, in fetched: Fetched, record: SourceRecord) -> FoundSkill? {
        fetched.skills.first { $0.path == (record.source.path ?? "") }
            ?? fetched.skills.first { $0.name == skill.baseName }
    }

    // MARK: Claude plugins

    /// Refreshes the plugin's marketplace, then updates the plugin with Claude's own CLI.
    public func updatePlugin(_ id: String) throws -> String {
        let candidates = [".local/bin/claude"].map { paths.home.appending(path: $0).path } + ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        guard let claude = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw InstallerError(message: "Could not find the claude command.")
        }
        if let marketplace = id.split(separator: "@").last, id.contains("@") {
            _ = try? Shell.run(claude, ["plugin", "marketplace", "update", String(marketplace)])
        }
        return try Shell.run(claude, ["plugin", "update", id])
    }

    // MARK: Helpers

    static func validate(name: String) throws {
        let allowed = name.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) }
        guard !name.isEmpty, allowed, !name.hasPrefix(".") else {
            throw InstallerError(message: "\"\(name)\" is not a valid skill folder name.")
        }
    }

    /// Replaces `destination` with a copy of `source`, without the `.git` folder.
    static func replace(_ destination: URL, with source: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appending(path: ".skillspack-\(UUID().uuidString)")
        try fm.copyItem(at: source.resolvingSymlinksInPath(), to: staging)
        try? fm.removeItem(at: staging.appending(path: ".git"))
        if (try? destination.checkResourceIsReachable()) == true || (try? fm.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: staging, to: destination)
    }

    /// A hash of every file's relative path and bytes, ignoring `.git` and `.DS_Store`.
    static func contentHash(_ dir: URL) -> String {
        let fm = FileManager.default
        let base = dir.resolvingSymlinksInPath()
        guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { return "" }
        var files: [(String, URL)] = []
        for case let url as URL in walker {
            if url.lastPathComponent == ".git" { walker.skipDescendants(); continue }
            guard url.lastPathComponent != ".DS_Store",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            files.append((String(url.path.dropFirst(base.path.count)), url))
        }
        var hasher = SHA256()
        for (relative, url) in files.sorted(by: { $0.0 < $1.0 }) {
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: (try? Data(contentsOf: url)) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum Shell {
    @discardableResult
    static func git(_ arguments: [String]) throws -> String {
        try run("/usr/bin/git", arguments)
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        // One pipe for both streams, so a chatty stderr cannot fill up and block the process.
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallerError(message: message.isEmpty ? "\(executable) failed" : message)
        }
        return text
    }
}
