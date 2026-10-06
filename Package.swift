// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SkillsPack",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SkillsPackCore"),
        .executableTarget(name: "SkillsPack", dependencies: ["SkillsPackCore"]),
        .testTarget(name: "SkillsPackCoreTests", dependencies: ["SkillsPackCore"]),
    ]
)
