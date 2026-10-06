import Foundation
@testable import SkillsPackCore

/// A throwaway home folder with helpers to lay out skills.
struct TempHome {
    let url: URL
    var paths: Paths { Paths(home: url) }

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "SkillsPackTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func skill(_ name: String, in dir: URL, description: String = "Does things.") throws -> URL {
        let folder = dir.appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: \(description)\n---\n\nBody of \(name).\n"
            .write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        return folder
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
}
