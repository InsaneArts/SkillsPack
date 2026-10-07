import Foundation
import SkillsPackCore

/// App state. Every file operation runs off the main thread, then the store reloads from disk.
@MainActor @Observable
final class SkillStore {
    let paths = Paths()
    private(set) var skills: [Skill] = []
    private(set) var snapshot = Switches.Snapshot.empty
    private(set) var usage: [String: Usage] = [:]
    private(set) var sources: [String: SourceRecord] = [:]
    private(set) var updates: Set<String> = []
    private(set) var issues: [HealthIssue] = []
    private(set) var repos: [String] = []
    private(set) var isCountingUsage = false
    private(set) var isCheckingUpdates = false
    var message: String?
    var error: String?

    private var switches: Switches { Switches(paths: paths) }

    init() {
        Task { await checkDaily() }
    }

    func reload() async {
        let paths = paths
        let (skills, snapshot, sources, issues, repos) = await Task.detached(priority: .userInitiated) {
            let skills = Scanner(paths: paths).scan()
            let installer = Installer(paths: paths)
            return (skills, Switches(paths: paths).snapshot(), installer.sources(), Health(paths: paths).issues(in: skills), installer.trackedRepos())
        }.value
        self.skills = skills
        self.snapshot = snapshot
        self.sources = sources
        self.issues = issues
        self.repos = repos
    }

    /// Checks for updates once a day while the app runs.
    private func checkDaily() async {
        let key = "lastUpdateCheck"
        while true {
            let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
            if Date().timeIntervalSince(last) > 24 * 3600 {
                await reload()
                await checkUpdates(quiet: true)
                UserDefaults.standard.set(Date(), forKey: key)
            }
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    /// Estimated tokens the agent loads every session for the skills that are on.
    func contextTokens(for agent: Agent) -> (tokens: Int, skills: Int) {
        let on = skills.filter { state($0, agent) == .on }
        return (on.reduce(0) { $0 + ContextCost.tokens(for: $1) }, on.count)
    }

    /// Skills that are on somewhere and were not used in the last 90 days.
    var unusedSkills: [Skill] {
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        return skills.filter { skill in
            Agent.allCases.contains { state(skill, $0) == .on }
                && (usage(of: skill).lastUsed ?? .distantPast) < cutoff
                && ContextCost.tokens(for: skill) > 0
        }
        .sorted { ContextCost.tokens(for: $0) > ContextCost.tokens(for: $1) }
    }

    func countUsage() async {
        guard !isCountingUsage else { return }
        isCountingUsage = true
        let paths = paths
        usage = await Task.detached(priority: .userInitiated) { UsageScanner(paths: paths).scan() }.value
        isCountingUsage = false
    }

    func state(_ skill: Skill, _ agent: Agent) -> AgentState {
        switches.state(of: skill, for: agent, in: snapshot)
    }

    func usage(of skill: Skill) -> Usage { usage[skill.name] ?? Usage() }

    // MARK: Actions

    /// On turns off, off turns on, and a missing skill is copied into that agent's folder.
    func toggle(_ skill: Skill, _ agent: Agent) async {
        switch state(skill, agent) {
        case .on:
            await run("Turned off \(skill.name) in \(agent.title).") { try Switches(paths: $0).setEnabled(false, skill: skill, agent: agent) }
        case .off:
            await run("Turned on \(skill.name) in \(agent.title).") { try Switches(paths: $0).setEnabled(true, skill: skill, agent: agent) }
        case .notInstalled:
            await run("Installed \(skill.baseName) for \(agent.title).") { try Installer(paths: $0).copy(skill, to: agent) }
        }
    }

    func turnOffEverywhere(_ skills: [Skill]) async {
        let targets = skills.flatMap { skill in Agent.allCases.filter { state(skill, $0) == .on }.map { (skill, $0) } }
        await run("Turned off \(skills.count == 1 ? skills[0].name : "\(skills.count) skills") everywhere.") { paths in
            let switches = Switches(paths: paths)
            for (skill, agent) in targets { try switches.setEnabled(false, skill: skill, agent: agent) }
        }
    }

    func fix(_ issues: [HealthIssue]) async {
        await run(issues.count == 1 ? "Fixed: \(issues[0].title)." : "Fixed \(issues.count) problems.") { paths in
            let health = Health(paths: paths)
            for issue in issues { try health.fix(issue) }
        }
    }

    func addRepo(_ input: String) async {
        guard SourceRef.parse(input) != nil else {
            error = "Enter a GitHub URL, owner/repo, or a git URL."
            return
        }
        let repos = repos + [input.trimmingCharacters(in: .whitespacesAndNewlines)]
        await run("Added \(input).") { try Installer(paths: $0).saveTrackedRepos(repos) }
    }

    func removeRepo(_ repo: String) async {
        let repos = repos.filter { $0 != repo }
        await run("Removed \(repo).") { try Installer(paths: $0).saveTrackedRepos(repos) }
    }

    /// Links skills with no source to same-named skills in the tracked repos.
    func matchSources() async {
        let refs = repos.compactMap(SourceRef.parse)
        let skills = skills
        let paths = paths
        do {
            let matched = try await Task.detached(priority: .userInitiated) {
                try Installer(paths: paths).matchSources(in: refs, for: skills)
            }.value
            message = matched.isEmpty ? "No new matches in your repos." : "Linked \(matched.count) skills to a source. Check for updates to compare them."
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        await reload()
    }

    func delete(_ skill: Skill) async {
        await run("Deleted \(skill.name). Folders are in the Trash.") { paths in
            try Installer(paths: paths).delete(skill)
            try Switches(paths: paths).clear(skill: skill)
        }
        updates.remove(skill.name)
    }

    func update(_ skill: Skill) async {
        if let plugin = skill.pluginID {
            await run("Updated the \(plugin) plugin.") { _ = try Installer(paths: $0).updatePlugin(plugin) }
            return
        }
        guard let record = sources[skill.name] else { return }
        await run("Updated \(skill.name).") { paths in
            let installer = Installer(paths: paths)
            var repo = record.source
            repo.path = nil
            let fetched = try installer.fetch(repo)
            defer { installer.discard(fetched) }
            try installer.update(skill, from: fetched, record: record)
        }
        if error == nil { updates.remove(skill.name) }
    }

    /// Clones each known source once and compares it with the installed copies.
    func checkUpdates(quiet: Bool = false) async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        let candidates = skills.compactMap { skill in sources[skill.name].map { (skill, $0) } }.filter { $0.0.isDeletable }
        let paths = paths
        let (found, failures) = await Task.detached(priority: .userInitiated) {
            let installer = Installer(paths: paths)
            var fetched: [SourceRef: Fetched] = [:]
            var failed: [SourceRef: String] = [:]
            var found = Set<String>()
            for (skill, record) in candidates {
                var repo = record.source
                repo.path = nil
                if failed[repo] != nil { continue }
                do {
                    if fetched[repo] == nil { fetched[repo] = try installer.fetch(repo) }
                    if let copy = fetched[repo], installer.hasUpdate(skill, in: copy, record: record) { found.insert(skill.name) }
                } catch {
                    failed[repo] = error.localizedDescription
                }
            }
            fetched.values.forEach(installer.discard)
            return (found, failed.map { "\($0.key.display): \($0.value)" })
        }.value
        updates = found
        isCheckingUpdates = false
        if quiet { return }
        message = found.isEmpty ? "All \(candidates.count) skills with a known source are up to date." : "\(found.count) updates available."
        error = failures.isEmpty ? nil : "Could not check " + failures.joined(separator: "; ")
    }

    // MARK: Install from URL

    func fetch(_ input: String) async throws -> Fetched {
        guard let source = SourceRef.parse(input) else {
            throw InstallerError(message: "Enter a GitHub URL, owner/repo, or a git URL.")
        }
        let paths = paths
        return try await Task.detached(priority: .userInitiated) { try Installer(paths: paths).fetch(source) }.value
    }

    func install(_ skills: [FoundSkill], from fetched: Fetched, agents: Set<Agent>) async {
        let names = skills.map(\.name).joined(separator: ", ")
        await run("Installed \(names) for \(agents.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: ", ")).") { paths in
            let installer = Installer(paths: paths)
            for skill in skills { try installer.install(skill, from: fetched, agents: agents) }
        }
    }

    func discard(_ fetched: Fetched) {
        let paths = paths
        Task.detached { Installer(paths: paths).discard(fetched) }
    }

    private func run(_ success: String, _ work: @escaping @Sendable (Paths) throws -> Void) async {
        let paths = paths
        do {
            try await Task.detached(priority: .userInitiated) { try work(paths) }.value
            message = success
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        await reload()
    }
}
