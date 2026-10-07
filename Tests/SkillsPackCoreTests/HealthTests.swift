import Foundation
import Testing
@testable import SkillsPackCore

@Suite struct HealthTests {
    @Test func brokenLinkIsFoundAndRemoved() throws {
        let home = try TempHome()
        try FileManager.default.createDirectory(at: home.paths.claudeSkills, withIntermediateDirectories: true)
        let link = home.paths.claudeSkills.appending(path: "gone")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/nowhere/gone")
        let health = Health(paths: home.paths)
        let issues = health.issues(in: [])
        #expect(issues.map(\.title) == ["Broken link: gone"])
        try health.fix(issues[0])
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == nil)
        #expect(health.issues(in: []).isEmpty)
    }

    @Test func strayPiFolderMovesToTheFolderPiReads() throws {
        let home = try TempHome()
        try home.skill("lost", in: home.url.appending(path: ".pi/skills"))
        let health = Health(paths: home.paths)
        let issues = health.issues(in: [])
        #expect(issues.map(\.title) == ["Not loaded: lost"])
        try health.fix(issues[0])
        #expect(FileManager.default.fileExists(atPath: home.paths.piSkills.appending(path: "lost/SKILL.md").path))
        #expect(health.issues(in: []).isEmpty)
    }

    @Test func differentCopiesAreMadeEqualToTheNewest() throws {
        let home = try TempHome()
        let old = try home.skill("tdd", in: home.paths.codexSkills, description: "Old.")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old.appending(path: "SKILL.md").path)
        try home.skill("tdd", in: home.paths.claudeSkills, description: "New.")
        let health = Health(paths: home.paths)
        let issues = health.issues(in: Scanner(paths: home.paths).scan())
        #expect(issues.map(\.title) == ["Copies differ: tdd"])
        try health.fix(issues[0])
        #expect(home.read(old.appending(path: "SKILL.md")).contains("New."))
        #expect(health.issues(in: Scanner(paths: home.paths).scan()).isEmpty)
    }

    @Test func contextCost() throws {
        let home = try TempHome()
        try home.skill("abcd", in: home.paths.claudeSkills, description: String(repeating: "x", count: 396))
        let skill = try #require(Scanner(paths: home.paths).scan().first)
        #expect(ContextCost.tokens(for: skill) == 104)
    }

    @Test func matchSourcesLinksSkillsByName() throws {
        let home = try TempHome()
        let repo = try InstallerTests().makeRepo(in: home)
        try home.skill("two", in: home.paths.claudeSkills)
        try home.skill("other", in: home.paths.claudeSkills)
        let installer = Installer(paths: home.paths)
        let matched = try installer.matchSources(in: [SourceRef(repo: repo.path)], for: Scanner(paths: home.paths).scan())
        #expect(matched == ["two"])
        #expect(installer.sources()["two"]?.source.path == "skills/two")
        #expect(installer.sources()["other"] == nil)

        try installer.saveTrackedRepos(["owner/repo"])
        #expect(installer.trackedRepos() == ["owner/repo"])
    }
}
