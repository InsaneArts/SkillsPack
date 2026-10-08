import Foundation
import Testing
@testable import SkillsPackCore

@Suite struct ScannerTests {
    @Test func findsSkillsAcrossAgentsSymlinksAndPlugins() throws {
        let home = try TempHome()
        let paths = home.paths
        try home.skill("alpha", in: paths.claudeSkills)
        try home.skill("alpha", in: paths.codexSkills)
        try home.skill("beta", in: paths.sharedSkills)
        let elsewhere = try home.skill("gamma", in: home.url.appending(path: "dev"))
        try FileManager.default.createDirectory(at: paths.piSkills, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: paths.piSkills.appending(path: "gamma"), withDestinationURL: elsewhere)
        try home.skill("system-one", in: paths.codexSkills.appending(path: ".system"))
        let plugin = home.url.appending(path: "plugin-cache/demo/1.0.0")
        try home.skill("nested", in: plugin.appending(path: "skills/engineering"))
        try home.write(#"{"version": 2, "plugins": {"demo@market": [{"installPath": "\#(plugin.path)", "version": "1.0.0"}]}}"#, to: paths.claudePlugins)

        let skills = Scanner(paths: paths).scan()
        let byName = Dictionary(uniqueKeysWithValues: skills.map { ($0.name, $0) })

        #expect(Set(byName.keys) == ["alpha", "beta", "gamma", "system-one", "demo:nested"])
        #expect(byName["alpha"]?.installations.count == 2)
        #expect(Set(byName["beta"]?.installations.first?.root.agents ?? []) == [.codex, .pi])
        #expect(byName["gamma"]?.installations.first?.isSymlink == true)
        #expect(byName["system-one"]?.isDeletable == false)
        #expect(byName["demo:nested"]?.pluginID == "demo@market")
        #expect(byName["demo:nested"]?.baseName == "nested")
    }

    @Test func skipsDisabledPlugins() throws {
        let home = try TempHome()
        let plugin = home.url.appending(path: "p")
        try home.skill("one", in: plugin.appending(path: "skills"))
        try home.write(#"{"plugins": {"p@m": [{"installPath": "\#(plugin.path)", "version": "1"}]}}"#, to: home.paths.claudePlugins)
        try home.write(#"{"enabledPlugins": {"p@m": false}}"#, to: home.paths.claudeSettings)
        #expect(Scanner(paths: home.paths).scan().isEmpty)
    }
}

@Suite struct SwitchesTests {
    @Test func claudeOverrideRoundTrip() throws {
        let home = try TempHome()
        let paths = home.paths
        try home.skill("bro", in: paths.claudeSkills)
        let original = "{\n  \"model\": \"opus\",\n  \"skillOverrides\": {\n    \"other\": \"name-only\"\n  }\n}\n"
        try home.write(original, to: paths.claudeSettings)
        let skill = try #require(Scanner(paths: paths).scan().first)
        let switches = Switches(paths: paths)

        try switches.setEnabled(false, skill: skill, agent: .claude)
        #expect(home.read(paths.claudeSettings).contains("\"bro\": \"off\""))
        #expect(switches.state(of: skill, for: .claude, in: switches.snapshot()) == .off)

        try switches.setEnabled(true, skill: skill, agent: .claude)
        #expect(home.read(paths.claudeSettings) == original)
        #expect(switches.state(of: skill, for: .claude, in: switches.snapshot()) == .on)
    }

    @Test func claudeRemovesEmptyOverrides() throws {
        let home = try TempHome()
        try home.skill("bro", in: home.paths.claudeSkills)
        try home.write("{\n  \"model\": \"opus\"\n}\n", to: home.paths.claudeSettings)
        let skill = try #require(Scanner(paths: home.paths).scan().first)
        let switches = Switches(paths: home.paths)
        try switches.setEnabled(false, skill: skill, agent: .claude)
        try switches.setEnabled(true, skill: skill, agent: .claude)
        #expect(home.read(home.paths.claudeSettings) == "{\n  \"model\": \"opus\"\n}\n")
    }

    @Test func codexByNameAndByPath() throws {
        let home = try TempHome()
        let paths = home.paths
        let dir = try home.skill("tdd", in: paths.sharedSkills)
        let original = "model = \"gpt-5\"\n"
        try home.write(original, to: paths.codexConfig)
        let skill = try #require(Scanner(paths: paths).scan().first)
        let switches = Switches(paths: paths)

        try switches.setEnabled(false, skill: skill, agent: .codex)
        #expect(switches.state(of: skill, for: .codex, in: switches.snapshot()) == .off)
        #expect(switches.state(of: skill, for: .pi, in: switches.snapshot()) == .on)
        try switches.setEnabled(true, skill: skill, agent: .codex)
        #expect(home.read(paths.codexConfig) == original)

        // A block Codex itself wrote by path also counts, and turning on removes it.
        try home.write(original + "\n[[skills.config]]\npath = \"\(dir.path)/SKILL.md\"\nenabled = false\n", to: paths.codexConfig)
        #expect(switches.state(of: skill, for: .codex, in: switches.snapshot()) == .off)
        try switches.setEnabled(true, skill: skill, agent: .codex)
        #expect(home.read(paths.codexConfig) == original)
    }

    @Test func piUsesTheLinkPath() throws {
        let home = try TempHome()
        let paths = home.paths
        let target = try home.skill("linked", in: home.url.appending(path: "dev"))
        try FileManager.default.createDirectory(at: paths.piSkills, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: paths.piSkills.appending(path: "linked"), withDestinationURL: target)
        let original = "{\n  \"theme\": \"dark\"\n}\n"
        try home.write(original, to: paths.piSettings)
        let skill = try #require(Scanner(paths: paths).scan().first)
        let switches = Switches(paths: paths)

        try switches.setEnabled(false, skill: skill, agent: .pi)
        #expect(home.read(paths.piSettings).contains("\"-\(paths.piSkills.path)/linked/SKILL.md\""))
        #expect(switches.state(of: skill, for: .pi, in: switches.snapshot()) == .off)
        try switches.setEnabled(true, skill: skill, agent: .pi)
        #expect(home.read(paths.piSettings) == original)
    }

    @Test func piReadsRelativeEntriesFromPiConfig() throws {
        let home = try TempHome()
        try home.skill("rel", in: home.paths.piSkills)
        try home.write(#"{"skills": ["-skills/rel/SKILL.md"]}"#, to: home.paths.piSettings)
        let skill = try #require(Scanner(paths: home.paths).scan().first)
        let switches = Switches(paths: home.paths)
        #expect(switches.state(of: skill, for: .pi, in: switches.snapshot()) == .off)
        try switches.setEnabled(true, skill: skill, agent: .pi)
        #expect(switches.state(of: skill, for: .pi, in: switches.snapshot()) == .on)
    }

    @Test func batchOffAndOnRestoresEveryFile() throws {
        let home = try TempHome()
        let paths = home.paths
        for name in ["one", "two", "three"] {
            try home.skill(name, in: paths.claudeSkills)
            try home.skill(name, in: paths.codexSkills)
            try home.skill(name, in: paths.piSkills)
        }
        let claude = "{\n  \"model\": \"opus\"\n}\n"
        let codex = "model = \"gpt-5\"\n\n[projects.\"/x\"]\ntrust_level = \"trusted\"\n"
        let pi = "{\n  \"theme\": \"dark\"\n}\n"
        try home.write(claude, to: paths.claudeSettings)
        try home.write(codex, to: paths.codexConfig)
        try home.write(pi, to: paths.piSettings)
        let skills = Scanner(paths: paths).scan()
        let switches = Switches(paths: paths)

        for agent in Agent.allCases { try switches.setEnabled(false, skills: skills, agent: agent) }
        let snapshot = switches.snapshot()
        #expect(skills.allSatisfy { skill in Agent.allCases.allSatisfy { switches.state(of: skill, for: $0, in: snapshot) == .off } })

        for agent in Agent.allCases { try switches.setEnabled(true, skills: skills, agent: agent) }
        #expect(home.read(paths.claudeSettings) == claude)
        #expect(home.read(paths.codexConfig) == codex)
        #expect(home.read(paths.piSettings) == pi)
    }

    @Test func backupIsWrittenBeforeChanges() throws {
        let home = try TempHome()
        try home.skill("bro", in: home.paths.claudeSkills)
        try home.write("{}\n", to: home.paths.claudeSettings)
        let skill = try #require(Scanner(paths: home.paths).scan().first)
        try Switches(paths: home.paths).setEnabled(false, skill: skill, agent: .claude)
        let backups = try FileManager.default.contentsOfDirectory(atPath: home.paths.appSupport.appending(path: "backups").path)
        #expect(backups.count == 1)
        #expect(backups.first?.hasPrefix("claude-settings.json-") == true)
    }
}
