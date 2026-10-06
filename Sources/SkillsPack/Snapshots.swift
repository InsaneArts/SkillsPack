#if DEBUG
import AppKit
import SwiftUI

/// Debug only: `swift run SkillsPack --snapshot <dir>` renders each screen with real data to PNG files, then quits.
@MainActor
enum Snapshots {
    static func render(to dir: URL) async {
        let store = SkillStore()
        await store.reload()
        await store.countUsage()
        let detail = CommandLine.arguments.last.flatMap { name in store.skills.first { $0.name == name }?.name } ?? "product-thinking"
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, route) in [("list", Route.list), ("detail", .detail(detail)), ("install", .install)] {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let host = NSHostingView(rootView: RootView(route: route).environment(store).frame(width: 480, height: 640)
                    .background(Color(nsColor: .windowBackgroundColor)))
                host.frame = NSRect(x: 0, y: 0, width: 480, height: 640)
                host.appearance = NSAppearance(named: appearance)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                window.backgroundColor = appearance == .aqua ? .white : NSColor(white: 0.12, alpha: 1)
                try? await Task.sleep(for: .milliseconds(800))
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appending(path: "\(name)-\(suffix).png"))
            }
        }
        print("Snapshots written to \(dir.path)")
        exit(0)
    }
}
#endif
