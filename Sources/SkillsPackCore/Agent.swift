import Foundation

public enum Agent: String, CaseIterable, Sendable, Codable {
    case claude, codex, pi

    public var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .pi: "pi"
        }
    }
}

public enum AgentState: Sendable, Equatable {
    case notInstalled, on, off
}

/// Every path SkillsPack reads or writes. Tests pass a temporary home.
public struct Paths: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func at(_ path: String) -> URL { home.appending(path: path) }

    public var claudeSkills: URL { at(".claude/skills") }
    public var claudeSettings: URL { at(".claude/settings.json") }
    public var claudePlugins: URL { at(".claude/plugins/installed_plugins.json") }
    public var claudeSessions: URL { at(".claude/projects") }
    public var codexSkills: URL { at(".codex/skills") }
    public var codexConfig: URL { at(".codex/config.toml") }
    public var codexSessions: [URL] { [at(".codex/sessions"), at(".codex/archived_sessions")] }
    public var sharedSkills: URL { at(".agents/skills") }
    public var skillLock: URL { at(".agents/.skill-lock.json") }
    public var piAgent: URL { at(".pi/agent") }
    public var piSkills: URL { at(".pi/agent/skills") }
    public var piSettings: URL { at(".pi/agent/settings.json") }
    public var piSessions: URL { at(".pi/agent/sessions") }
    public var appSupport: URL { at("Library/Application Support/SkillsPack") }

    /// Where SkillsPack puts a new skill for each agent.
    public func installDir(for agent: Agent) -> URL {
        switch agent {
        case .claude: claudeSkills
        case .codex: codexSkills
        case .pi: piSkills
        }
    }
}
