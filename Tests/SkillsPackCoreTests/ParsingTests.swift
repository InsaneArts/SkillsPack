import Foundation
import Testing
@testable import SkillsPackCore

@Suite struct JSONTests {
    let sample = """
    {
      "permissions": {
        "allow": [
          "Bash(git status)",
          "Skill"
        ]
      },
      "model": "opus",
      "count": 1.5e3,
      "nothing": null,
      "empty": {},
      "list": [],
      "text": "quote \\" slash / tab \\t ünïcode ✓",
      "enabledPlugins": {
        "a@b": true
      }
    }

    """

    @Test func roundTripKeepsBytes() throws {
        let value = try JSON(parsing: sample)
        #expect(value.rendered() + "\n" == sample)
    }

    @Test func setKeepsOrderAndAppendsNewKeys() throws {
        var value = try JSON(parsing: sample)
        value.set("model", .string("sonnet"))
        value.set("skillOverrides", .object([.init(key: "bro", value: .string("off"))]))
        #expect(value.members.map(\.key) == ["permissions", "model", "count", "nothing", "empty", "list", "text", "enabledPlugins", "skillOverrides"])
        value.set("skillOverrides", nil)
        value.set("model", .string("opus"))
        #expect(value.rendered() + "\n" == sample)
    }

    @Test func unicodeEscapesAndSurrogates() throws {
        let value = try JSON(parsing: #"{"a": "é😀"}"#)
        #expect(value["a"]?.stringValue == "é😀")
    }

    @Test func rejectsBrokenJSON() {
        #expect(throws: JSONError.self) { try JSON(parsing: #"{"a": }"#) }
    }

    /// The real files SkillsPack edits must survive a read and write unchanged.
    @Test(arguments: [".claude/settings.json", ".pi/agent/settings.json"])
    func realSettingsRoundTrip(_ path: String) throws {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let text = try String(contentsOf: url, encoding: .utf8)
        let file = JSONFile(url: url)
        let (value, indent, newline) = try file.read()
        #expect(value.rendered(indent: indent) + (newline ? "\n" : "") == text)
    }
}

@Suite struct FrontmatterTests {
    @Test func plainAndQuotedValues() {
        let fields = Frontmatter.parse("---\nname: tdd\ndescription: \"Test: first\"\ndisable-model-invocation: true\n---\nbody")
        #expect(fields["name"] == "tdd")
        #expect(fields["description"] == "Test: first")
        #expect(fields["disable-model-invocation"] == "true")
    }

    @Test func foldedValue() {
        let fields = Frontmatter.parse("---\nname: x\ndescription: >\n  First line\n  second line.\nlicense: MIT\n---\n")
        #expect(fields["description"] == "First line second line.")
        #expect(fields["license"] == "MIT")
    }

    @Test func quotedValueOverSeveralLines() {
        let fields = Frontmatter.parse("---\nname: rust-router\ndescription: \"CRITICAL: Use for Rust.\nTriggers on: cargo, \\\"crate\\\".\"\nversion: 2\n---\n")
        #expect(fields["description"] == "CRITICAL: Use for Rust. Triggers on: cargo, \"crate\".")
        #expect(fields["version"] == "2")
        #expect(fields["Triggers on"] == nil)
    }

    @Test func noFrontmatter() {
        #expect(Frontmatter.parse("# Title\nname: nope").isEmpty)
    }
}

@Suite struct SourceRefTests {
    @Test func shorthand() {
        #expect(SourceRef.parse("tornikegomareli/Skills") == SourceRef(repo: "https://github.com/tornikegomareli/Skills.git"))
    }

    @Test func treeURL() {
        let source = SourceRef.parse("https://github.com/mattpocock/skills/tree/main/skills/engineering/tdd/")
        #expect(source == SourceRef(repo: "https://github.com/mattpocock/skills.git", ref: "main", path: "skills/engineering/tdd"))
        #expect(source?.display == "mattpocock/skills/skills/engineering/tdd")
    }

    @Test func blobURLToSkillFile() {
        let source = SourceRef.parse("https://github.com/dmmulroy/skills/blob/main/bro/SKILL.md")
        #expect(source == SourceRef(repo: "https://github.com/dmmulroy/skills.git", ref: "main", path: "bro"))
    }

    @Test func otherGitURLs() {
        #expect(SourceRef.parse("https://gitlab.com/a/b.git")?.repo == "https://gitlab.com/a/b.git")
        #expect(SourceRef.parse("git@github.com:a/b.git")?.repo == "git@github.com:a/b.git")
        #expect(SourceRef.parse("not a url") == nil)
    }
}

@Suite struct CodexConfigTests {
    let original = """
    model = "gpt-5"

    [projects."/Users/me/app"]
    trust_level = "trusted"

    """

    @Test func appendAndRemoveRestoresText() throws {
        var config = CodexConfig(text: original)
        try config.appendDisabled(name: "tdd")
        #expect(config.text == original + "\n[[skills.config]]\nname = \"tdd\"\nenabled = false\n")
        #expect(config.blocks == [CodexConfig.Block(lines: 5..<8, path: nil, name: "tdd", enabled: false)])
        config.removeBlocks { $0.name == "tdd" }
        #expect(config.text == original)
    }

    @Test func readsBlocksCodexWrites() {
        let config = CodexConfig(text: "[[skills.config]]\npath = \"/a/b/SKILL.md\"\nenabled = false\n\n[other]\nx = 1\n")
        #expect(config.blocks.first?.path == "/a/b/SKILL.md")
        #expect(config.blocks.first?.enabled == false)
    }

    @Test func refusesConflictingSkillsTable() {
        var config = CodexConfig(text: "[skills]\nbundled = true\n")
        #expect(throws: (any Error).self) { try config.appendDisabled(name: "x") }
    }
}
