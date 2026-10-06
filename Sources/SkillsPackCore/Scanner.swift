import Foundation

/// A folder that one or more agents read skills from.
public struct SkillRoot: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// An agent's own skills folder, or `~/.agents/skills`. SkillsPack may change files here.
        case user
        /// Skills that ship with Codex.
        case system
        /// Skills from an installed Claude plugin.
        case plugin(id: String, version: String)
    }

    public let url: URL
    public let agents: Set<Agent>
    public let kind: Kind

    public var isWritable: Bool { kind == .user }
}

/// One copy of a skill in one root.
public struct Installation: Sendable, Hashable, Identifiable {
    public let root: SkillRoot
    /// The folder inside the root. It is a symlink when `isSymlink` is true.
    public let dir: URL
    public let isSymlink: Bool

    public var id: String { dir.path }
    public var skillFile: URL { dir.appending(path: "SKILL.md") }
    public var resolvedDir: URL { dir.resolvingSymlinksInPath() }
}

public struct Skill: Sendable, Identifiable, Hashable {
    /// The name agents know the skill by. Claude plugin skills are `plugin:skill`.
    public let name: String
    public let description: String
    public let userInvocableOnly: Bool
    public var installations: [Installation]

    public var id: String { name }

    /// The name without a plugin prefix, used as a folder name.
    public var baseName: String { String(name.split(separator: ":").last ?? Substring(name)) }

    public func installations(for agent: Agent) -> [Installation] {
        installations.filter { $0.root.agents.contains(agent) }
    }

    public var pluginID: String? {
        for installation in installations {
            if case .plugin(let id, _) = installation.root.kind { return id }
        }
        return nil
    }

    public var isDeletable: Bool { installations.contains { $0.root.isWritable } }
}

public struct Scanner: Sendable {
    let paths: Paths

    public init(paths: Paths) { self.paths = paths }

    public func roots() -> [SkillRoot] {
        var roots = [
            SkillRoot(url: paths.claudeSkills, agents: [.claude], kind: .user),
            SkillRoot(url: paths.codexSkills, agents: [.codex], kind: .user),
            SkillRoot(url: paths.codexSkills.appending(path: ".system"), agents: [.codex], kind: .system),
            SkillRoot(url: paths.sharedSkills, agents: [.codex, .pi], kind: .user),
            SkillRoot(url: paths.piSkills, agents: [.pi], kind: .user),
        ]
        roots += pluginRoots()
        return roots
    }

    /// Skills from Claude plugins that are installed and not turned off.
    func pluginRoots() -> [SkillRoot] {
        guard let installed = try? JSON(contentsOf: paths.claudePlugins) else { return [] }
        let enabled = (try? JSON(contentsOf: paths.claudeSettings))?["enabledPlugins"]
        var roots: [SkillRoot] = []
        for member in installed["plugins"]?.members ?? [] {
            if enabled?[member.key]?.boolValue == false { continue }
            guard let entry = member.value.elements.first,
                  let installPath = entry["installPath"]?.stringValue else { continue }
            let version = entry["version"]?.stringValue ?? ""
            roots.append(SkillRoot(
                url: URL(filePath: installPath).appending(path: "skills"),
                agents: [.claude],
                kind: .plugin(id: member.key, version: version)))
        }
        return roots
    }

    public func scan() -> [Skill] {
        var byName: [String: Skill] = [:]
        var order: [String] = []
        for root in roots() {
            for found in skillDirs(in: root) {
                let fields = Frontmatter.parse((try? String(contentsOf: found.dir.appending(path: "SKILL.md"), encoding: .utf8)) ?? "")
                var name = fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? found.dir.lastPathComponent
                if case .plugin(let id, _) = root.kind {
                    name = "\(id.split(separator: "@").first ?? "")" + ":" + name
                }
                let installation = Installation(root: root, dir: found.dir, isSymlink: found.isSymlink)
                if byName[name] == nil {
                    order.append(name)
                    byName[name] = Skill(
                        name: name,
                        description: fields["description"] ?? "",
                        userInvocableOnly: fields["disable-model-invocation"] == "true",
                        installations: [installation])
                } else {
                    byName[name]?.installations.append(installation)
                }
            }
        }
        return order.compactMap { byName[$0] }
    }

    /// Skill folders in a root. Plugin roots are searched recursively, other roots one level deep.
    func skillDirs(in root: SkillRoot) -> [(dir: URL, isSymlink: Bool)] {
        let fm = FileManager.default
        if case .plugin = root.kind {
            guard let walker = fm.enumerator(at: root.url, includingPropertiesForKeys: nil) else { return [] }
            var result: [(URL, Bool)] = []
            for case let url as URL in walker where url.lastPathComponent == "SKILL.md" {
                result.append((url.deletingLastPathComponent(), false))
            }
            return result.sorted { $0.0.path < $1.0.path }
        }
        // Paths are built from the root's own path (not the resolved one), because pi matches
        // its switch entries against the path it found the skill at.
        guard let names = try? fm.contentsOfDirectory(atPath: root.url.path) else { return [] }
        return names
            .filter { !$0.hasPrefix(".") }
            .sorted()
            .map { root.url.appending(path: $0) }
            .filter { fm.fileExists(atPath: $0.appending(path: "SKILL.md").path) }
            .map { ($0, (try? fm.destinationOfSymbolicLink(atPath: $0.path)) != nil) }
    }
}
