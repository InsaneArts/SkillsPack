import Foundation

public struct HealthIssue: Sendable, Identifiable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// A symlink in a skills folder whose target is gone.
        case brokenLink(URL)
        /// A skill in a folder no agent reads, and where it belongs.
        case strayFolder(URL, destination: URL)
        /// Copies of one skill with different content. The newest copy wins.
        case differentCopies(newest: URL, others: [URL])
    }

    public let kind: Kind
    public let title: String
    public let detail: String

    public var id: String { title + detail }
}

/// Finds problems in the skill folders and fixes them.
public struct Health: Sendable {
    let paths: Paths

    public init(paths: Paths) { self.paths = paths }

    /// Folders that look like skill folders but no agent reads.
    var strayFolders: [(from: URL, to: URL)] {
        [(paths.home.appending(path: ".pi/skills"), paths.piSkills)]
    }

    public func issues(in skills: [Skill]) -> [HealthIssue] {
        brokenLinks() + strays() + differentCopies(in: skills)
    }

    func brokenLinks() -> [HealthIssue] {
        let fm = FileManager.default
        var issues: [HealthIssue] = []
        for root in Scanner(paths: paths).roots() where root.isWritable {
            for name in (try? fm.contentsOfDirectory(atPath: root.url.path)) ?? [] {
                let link = root.url.appending(path: name)
                guard let target = try? fm.destinationOfSymbolicLink(atPath: link.path),
                      !fm.fileExists(atPath: link.path) else { continue }
                issues.append(HealthIssue(
                    kind: .brokenLink(link),
                    title: "Broken link: \(name)",
                    detail: "\(Self.display(link, home: paths.home)) points to \(target), which does not exist."))
            }
        }
        return issues
    }

    func strays() -> [HealthIssue] {
        let fm = FileManager.default
        var issues: [HealthIssue] = []
        for (from, to) in strayFolders {
            for name in ((try? fm.contentsOfDirectory(atPath: from.path)) ?? []).sorted() where !name.hasPrefix(".") {
                let dir = from.appending(path: name)
                guard fm.fileExists(atPath: dir.appending(path: "SKILL.md").path) else { continue }
                let destination = to.appending(path: name)
                let exists = fm.fileExists(atPath: destination.path)
                issues.append(HealthIssue(
                    kind: .strayFolder(dir, destination: destination),
                    title: "Not loaded: \(name)",
                    detail: "No agent reads \(Self.display(from, home: paths.home)). "
                        + (exists ? "A copy is already in \(Self.display(to, home: paths.home)), so Fix moves this one to the Trash."
                                  : "Fix moves it to \(Self.display(to, home: paths.home)).")))
            }
        }
        return issues
    }

    func differentCopies(in skills: [Skill]) -> [HealthIssue] {
        var issues: [HealthIssue] = []
        for skill in skills {
            let copies = skill.installations.filter { $0.root.isWritable && !$0.isSymlink }
            guard copies.count > 1, Set(copies.map { Installer.contentHash($0.dir) }).count > 1 else { continue }
            let sorted = copies.sorted { Self.modified($0.skillFile) > Self.modified($1.skillFile) }
            issues.append(HealthIssue(
                kind: .differentCopies(newest: sorted[0].dir, others: sorted.dropFirst().map(\.dir)),
                title: "Copies differ: \(skill.name)",
                detail: "The \(copies.count) copies are not the same. Fix copies the newest one, in \(Self.display(sorted[0].dir, home: paths.home)), over the others."))
        }
        return issues
    }

    public func fix(_ issue: HealthIssue) throws {
        let fm = FileManager.default
        switch issue.kind {
        case .brokenLink(let link):
            try fm.removeItem(at: link)
        case .strayFolder(let dir, let destination):
            if fm.fileExists(atPath: destination.path) {
                try fm.trashItem(at: dir, resultingItemURL: nil)
            } else {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: dir, to: destination)
            }
        case .differentCopies(let newest, let others):
            for other in others { try Installer.replace(other, with: newest) }
        }
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    static func display(_ url: URL, home: URL) -> String {
        url.path.hasPrefix(home.path) ? "~" + url.path.dropFirst(home.path.count) : url.path
    }
}

/// An estimate of what a skill costs every session: agents load each skill's name and description.
public enum ContextCost {
    /// About 4 characters per token, plus a few tokens of list formatting. Skills only you can call cost nothing.
    public static func tokens(for skill: Skill) -> Int {
        skill.userInvocableOnly ? 0 : (skill.baseName.count + skill.description.count) / 4 + 4
    }
}
