import Foundation
import Testing
@testable import SkillsPackCore

@Suite struct InstallerTests {
    /// A local git repo with two skills, committed.
    func makeRepo(in home: TempHome) throws -> URL {
        let repo = home.url.appending(path: "repo")
        try home.skill("one", in: repo.appending(path: "skills"))
        try home.skill("two", in: repo.appending(path: "skills"))
        try home.write("extra", to: repo.appending(path: "skills/one/notes.md"))
        try git(repo, ["init", "-q", "-b", "main"])
        try git(repo, ["add", "."])
        try git(repo, ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init"])
        return repo
    }

    func git(_ repo: URL, _ arguments: [String]) throws {
        try Shell.git(["-C", repo.path] + arguments)
    }

    @Test func fetchInstallUpdateAndDeleteLink() throws {
        let home = try TempHome()
        let paths = home.paths
        let repo = try makeRepo(in: home)
        let installer = Installer(paths: paths)

        let fetched = try installer.fetch(SourceRef(repo: repo.path))
        #expect(fetched.skills.map(\.name) == ["one", "two"])
        #expect(fetched.skills.first?.path == "skills/one")

        let one = try #require(fetched.skills.first)
        try installer.install(one, from: fetched, agents: [.claude, .pi])
        installer.discard(fetched)
        #expect(home.read(paths.claudeSkills.appending(path: "one/notes.md")) == "extra")
        #expect(FileManager.default.fileExists(atPath: paths.piSkills.appending(path: "one/SKILL.md").path))
        #expect(!FileManager.default.fileExists(atPath: paths.codexSkills.appending(path: "one").path))
        #expect(!FileManager.default.fileExists(atPath: paths.claudeSkills.appending(path: "one/.git").path))
        let record = try #require(installer.sources()["one"])
        #expect(record.source.path == "skills/one")
        #expect(record.commit?.count == 40)

        // A new commit upstream shows up as an update.
        try home.write("changed", to: repo.appending(path: "skills/one/notes.md"))
        try git(repo, ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qam", "change"])
        let skill = try #require(Scanner(paths: paths).scan().first { $0.name == "one" })
        let refetched = try installer.fetch(record.source)
        #expect(installer.hasUpdate(skill, in: refetched, record: record))
        #expect(try installer.update(skill, from: refetched, record: record) == 2)
        #expect(home.read(paths.claudeSkills.appending(path: "one/notes.md")) == "changed")
        #expect(!installer.hasUpdate(skill, in: refetched, record: record))
        installer.discard(refetched)

        // Deleting a symlinked copy removes only the link.
        let target = try home.skill("linked", in: home.url.appending(path: "dev"))
        try FileManager.default.createDirectory(at: paths.codexSkills, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: paths.codexSkills.appending(path: "linked"), withDestinationURL: target)
        let linked = try #require(Scanner(paths: paths).scan().first { $0.name == "linked" })
        try installer.delete(linked)
        #expect(!FileManager.default.fileExists(atPath: paths.codexSkills.appending(path: "linked").path))
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "SKILL.md").path))
    }

    @Test func fetchSubpathAndMissingPath() throws {
        let home = try TempHome()
        let repo = try makeRepo(in: home)
        let installer = Installer(paths: home.paths)
        let fetched = try installer.fetch(SourceRef(repo: repo.path, path: "skills/two"))
        #expect(fetched.skills.map(\.name) == ["two"])
        installer.discard(fetched)
        #expect(throws: InstallerError.self) { try installer.fetch(SourceRef(repo: repo.path, path: "nope")) }
    }

    @Test func copyToAnotherAgent() throws {
        let home = try TempHome()
        try home.skill("solo", in: home.paths.claudeSkills)
        let skill = try #require(Scanner(paths: home.paths).scan().first)
        try Installer(paths: home.paths).copy(skill, to: .codex)
        let again = try #require(Scanner(paths: home.paths).scan().first)
        #expect(again.installations(for: .codex).count == 1)
    }

    @Test func readsSkillLockSources() throws {
        let home = try TempHome()
        try home.write(#"{"version": 3, "skills": {"tdd": {"sourceUrl": "https://github.com/mattpocock/skills.git", "skillPath": "skills/engineering/tdd/SKILL.md"}}}"#, to: home.paths.skillLock)
        let record = try #require(Installer(paths: home.paths).sources()["tdd"])
        #expect(record.source == SourceRef(repo: "https://github.com/mattpocock/skills.git", path: "skills/engineering/tdd"))
    }

    @Test func rejectsUnsafeNames() {
        #expect(throws: InstallerError.self) { try Installer.validate(name: "../evil") }
        #expect(throws: InstallerError.self) { try Installer.validate(name: ".hidden") }
        #expect(throws: Never.self) { try Installer.validate(name: "good-name_1.2") }
    }
}

@Suite struct UsageTests {
    func count(_ log: UsageScanner.Log, _ lines: [String]) -> [String: Usage] {
        UsageScanner.count(log, in: Data(lines.joined(separator: "\n").utf8))
    }

    @Test func claude() {
        let counts = count(.claude, [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"tdd"}}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"mattpocock-skills:tdd"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":"<command-message>bro</command-message>\n<command-name>/bro</command-name>"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>"}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"log says <command-name>/bro</command-name>"}]}}"#,
        ])
        #expect(counts["tdd"] == Usage(byUser: 0, byAgent: 1))
        #expect(counts["mattpocock-skills:tdd"]?.byAgent == 1)
        #expect(counts["bro"] == Usage(byUser: 1, byAgent: 0))
        #expect(counts["model"] == nil)
    }

    @Test func codex() {
        let counts = count(.codex, [
            #"{"type":"response_item","payload":{"type":"message","role":"developer","content":"skills: /h/.codex/skills/tdd/SKILL.md /h/.codex/skills/pr/SKILL.md"}}"#,
            #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"sed -n 1,200p /h/.agents/skills/tdd/SKILL.md\"}"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"run $grill-with-docs please, costs $5"}]}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>$HOME</environment_context>"}]}}"#,
            #"{"type":"compacted","payload":{"replacement_history":[{"type":"message","role":"user","content":[{"type":"input_text","text":"$grill-with-docs"}]},{"type":"function_call","arguments":"/h/s/tdd/SKILL.md"}]}}"#,
        ])
        #expect(counts["tdd"] == Usage(byUser: 0, byAgent: 1))
        #expect(counts["pr"] == nil)
        #expect(counts["grill-with-docs"] == Usage(byUser: 1, byAgent: 0))
        #expect(counts["HOME"] == nil)
    }

    @Test func pi() {
        let counts = count(.pi, [
            #"{"type":"message","message":{"role":"assistant","content":[{"type":"toolCall","name":"read","arguments":{"path":"/h/.pi/agent/skills/diagnose/SKILL.md"}}]}}"#,
            #"{"type":"message","message":{"role":"assistant","content":[{"type":"toolCall","name":"read","arguments":{"path":"/h/code/README.md"}}]}}"#,
            #"{"type":"message","message":{"role":"user","content":[{"type":"text","text":"<skill name=\"diagnose\" location=\"/h/x/SKILL.md\">"}]}}"#,
            #"{"type":"message","message":{"role":"toolResult","content":[{"type":"text","text":"<skill name=\"diagnose\" location=\"/h/x/SKILL.md\">"}]}}"#,
        ])
        #expect(counts["diagnose"] == Usage(byUser: 1, byAgent: 1))
        #expect(counts.count == 1)
    }

    @Test func cacheSkipsUnchangedFiles() throws {
        let home = try TempHome()
        let log = home.paths.claudeSessions.appending(path: "p/s.jsonl")
        try home.write(#"{"name":"Skill","input":{"skill":"tdd"}}"# + "\n", to: log)
        let scanner = UsageScanner(paths: home.paths)
        #expect(scanner.scan()["tdd"]?.byAgent == 1)
        #expect(scanner.scan()["tdd"]?.byAgent == 1)
        try home.write(#"{"name":"Skill","input":{"skill":"tdd"}}"# + "\n" + #"{"name":"Skill","input":{"skill":"tdd"}}"# + "\n", to: log)
        #expect(scanner.scan()["tdd"]?.byAgent == 2)
    }
}
