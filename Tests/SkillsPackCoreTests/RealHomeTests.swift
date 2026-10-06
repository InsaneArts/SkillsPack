import Foundation
import Testing
@testable import SkillsPackCore

/// Read-only checks against this machine's real agent folders.
/// Run with `SKILLSPACK_REAL_HOME=1 swift test --filter RealHomeTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SKILLSPACK_REAL_HOME"] == "1"))
struct RealHomeTests {
    let paths = Paths()

    @Test func scanAndStates() {
        let skills = Scanner(paths: paths).scan()
        let switches = Switches(paths: paths)
        let snapshot = switches.snapshot()
        #expect(!skills.isEmpty)
        for agent in Agent.allCases {
            let states = skills.map { switches.state(of: $0, for: agent, in: snapshot) }
            print("\(agent.title): on \(states.filter { $0 == .on }.count), off \(states.filter { $0 == .off }.count)")
        }
        print("skills: \(skills.count), plugin skills: \(skills.filter { $0.pluginID != nil }.count), sources: \(Installer(paths: paths).sources().count)")
    }

    @Test func usageScan() {
        let start = Date()
        let usage = UsageScanner(paths: paths).scan()
        print(String(format: "usage scan: %.1fs, %d names", Date().timeIntervalSince(start), usage.count))
        let installed = Set(Scanner(paths: paths).scan().map(\.name))
        for (name, count) in usage.filter({ installed.contains($0.key) }).sorted(by: { $0.value.total > $1.value.total }).prefix(12) {
            print("  \(name): you \(count.byUser), agent \(count.byAgent)")
        }
    }
}
