// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SkillsPack",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Self-updates, signed with EdDSA, from appcast.xml in this repo.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(name: "SkillsPackCore"),
        .executableTarget(
            name: "SkillsPack",
            dependencies: ["SkillsPackCore", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Resources/AgentLogos")]),
        .testTarget(name: "SkillsPackCoreTests", dependencies: ["SkillsPackCore"]),
    ]
)
